// Lambda の中のテスト(docs/design/pdf-lambda.md 7.1)。S3 は aws-sdk-client-mock、ブラウザは偽物。
import { readdirSync } from 'node:fs';
import { Readable } from 'node:stream';
import { GetObjectCommand, HeadObjectCommand, PutObjectCommand, S3Client, S3ServiceException } from '@aws-sdk/client-s3';
import { sdkStreamMixin } from '@smithy/util-stream';
import { mockClient } from 'aws-sdk-client-mock';
import { createHandler, s3Budget, validateResponse, chromiumEnv, PdfResponse } from '../src/handler';
import { BUCKET, CANARY, FakeBrowser, context, fakePdf, htmlWith, makeDeps, requestFor } from './helpers';

const s3Mock = mockClient(S3Client);
const s3 = new S3Client({ region: 'ap-northeast-1' });

const body = (html: string) => sdkStreamMixin(Readable.from([Buffer.from(html, 'utf8')]));

const s3Error = (name: string, status: number) =>
  new S3ServiceException({ name, $fault: status >= 500 ? 'server' : 'client', $metadata: { httpStatusCode: status }, message: `${name} ${CANARY}` });

const html = htmlWith(`<h1>貸借対照表</h1><p>${CANARY}</p>`);

beforeEach(() => {
  s3Mock.reset();
  s3Mock.on(GetObjectCommand).callsFake(() => ({ Body: body(html), ContentLength: Buffer.byteLength(html) }));
  s3Mock.on(PutObjectCommand).resolves({});
});

const run = async (event: unknown, browser = new FakeBrowser(), over = {}, remaining = 85_000) => {
  const t = makeDeps(s3, browser, over);
  const res = await createHandler(t.deps)(event, context(remaining));
  return { res, ...t, browser };
};

const expectValid = (res: PdfResponse) => {
  const ok = validateResponse(res);
  if (!ok) throw new Error(JSON.stringify(validateResponse.errors));
};

const expectNoLeak = (res: PdfResponse, logs: string[]) => {
  const all = JSON.stringify(res) + logs.join('\n');
  expect(all).not.toContain('CANARY');
  expect(all).not.toContain('must-not-leak');
  expect(all).not.toContain('貸借対照表');
};

describe('うまくいくとき', () => {
  test('PDF を条件つきで置き、形どおりの応答を返す', async () => {
    const { res, logs, tmpRoot, browser, launches } = await run(requestFor(html));
    expectValid(res);
    expect(res.status).toBe('ok');
    expect(res.reused).toBe(false);
    const req = requestFor(html);
    expect(res.output).toEqual({ bucket: BUCKET, key: `${req.output_prefix}${res.renderer.renderer_id}.pdf`, bytes: fakePdf(2).length, pages: 2 });
    const put = s3Mock.commandCalls(PutObjectCommand)[0].args[0].input;
    expect(put.IfNoneMatch).toBe('*');
    expect(put.ChecksumSHA256).toMatch(/^[A-Za-z0-9+/]{43}=$/);
    expect(put.ContentType).toBe('application/pdf');
    expect(browser.jsEnabled).toBe(false);
    expect(browser.interception).toBe(true);
    expect(browser.closed).toBe(true);
    expect(browser.pdfOptions).toMatchObject({ format: 'A4', printBackground: true, preferCSSPageSize: true, pageRanges: '1-26' });
    expect(readdirSync(tmpRoot)).toEqual([]);
    expect(logs).toHaveLength(1);
    expect(JSON.parse(logs[0])).toMatchObject({ status: 'ok', Pages: 2, request_id: 'pdf-12-a1', input_key: req.input_key.slice(0, 12) });
    const env = (launches[0] as { env: NodeJS.ProcessEnv }).env;
    expect(env.AWS_SECRET_ACCESS_KEY).toBeUndefined();
    expectNoLeak(res, logs);
  });

  test('data: と about:blank のほかの要求はすべて止め、数だけを返す', async () => {
    const browser = new FakeBrowser({
      requests: ['data:image/png;base64,AAAA', 'about:blank', 'http://169.254.169.254/latest/meta-data/', 'http://127.0.0.1:9001/2018-06-01/runtime/invocation/next', 'https://example.com/a.css', 'file:///etc/passwd'],
    });
    const { res, logs } = await run(requestFor(html), browser);
    expect(res.metrics.blocked_requests).toBe(4);
    expect(browser.continued).toEqual(['data:image/png;base64,AAAA', 'about:blank']);
    expect(JSON.stringify(res) + logs.join()).not.toContain('169.254');
  });

  test('出力がもうある(412)ときは、ある方を返す', async () => {
    s3Mock.on(PutObjectCommand).rejects(s3Error('PreconditionFailed', 412));
    s3Mock.on(HeadObjectCommand).resolves({ ContentLength: 999 });
    const { res } = await run(requestFor(html));
    expectValid(res);
    expect(res.status).toBe('ok');
    expect(res.reused).toBe(true);
    expect(res.output?.bytes).toBe(999);
  });

  test('フォントに無い字を数える(数と U+ だけ)', async () => {
    const h = htmlWith('<p>漢字と&#x20B9F;と&#55356;と𠮷</p><p title="属性の字は数えない Ω">A</p>');
    s3Mock.on(GetObjectCommand).callsFake(() => ({ Body: body(h) }));
    const { res, logs } = await run(requestFor(h));
    expect(res.metrics.missing_codepoints).toEqual(['U+D83C', 'U+20B9F', 'U+20BB7']);
    expect(res.metrics.missing_glyphs).toBe(3);
    expect(JSON.parse(logs[0]).level).toBe('warn');
  });
});

describe('要求が悪い', () => {
  test.each([
    ['版が違う', { protocol: 2 }, 'UNSUPPORTED_PROTOCOL'],
    ['バケットが違う', { input: { ...requestFor(html).input, bucket: 'other-bucket' } }, 'INVALID_REQUEST'],
    ['キーの形が違う', { input: { ...requestFor(html).input, key: 'v1/in/../../etc' } }, 'INVALID_REQUEST'],
    ['出力の場所が違う', { output_prefix: `v1/out/${'0'.repeat(64)}/` }, 'INVALID_REQUEST'],
    ['知らない項目', { extra: 1 }, 'INVALID_REQUEST'],
    ['期限切れ', { deadline_at: Date.now() - 1 }, 'DEADLINE_EXCEEDED'],
  ])('%s', async (_name, over, code) => {
    const { res, logs } = await run({ ...requestFor(html), ...over });
    expectValid(res);
    expect(res.status).toBe('error');
    expect(res.error?.code).toBe(code);
    expect(res.error?.retryable).toBe(false);
    expect(s3Mock.commandCalls(GetObjectCommand)).toHaveLength(0);
    expectNoLeak(res, logs);
  });

  test('オブジェクトでない', async () => {
    const { res } = await run('hello');
    expectValid(res);
    expect(res.error?.code).toBe('INVALID_REQUEST');
    expect(res.request_id).toBeNull();
  });
});

describe('入力', () => {
  test('無い → INPUT_NOT_FOUND(やり直してよい)', async () => {
    s3Mock.on(GetObjectCommand).rejects(s3Error('NoSuchKey', 404));
    const { res, logs } = await run(requestFor(html));
    expect(res.error).toMatchObject({ code: 'INPUT_NOT_FOUND', retryable: true });
    expectNoLeak(res, logs);
  });

  test('ハッシュが違う → INPUT_CHECKSUM_MISMATCH', async () => {
    const req = requestFor(html);
    const { res } = await run({ ...req, input: { ...req.input, sha256: 'f'.repeat(64) } });
    expect(res.error?.code).toBe('INPUT_CHECKSUM_MISMATCH');
  });

  test('大きすぎる → INPUT_TOO_LARGE', async () => {
    s3Mock.on(GetObjectCommand).callsFake(() => ({ Body: body(html), ContentLength: 11 * 1024 * 1024 }));
    const { res } = await run(requestFor(html));
    expect(res.error).toMatchObject({ code: 'INPUT_TOO_LARGE', retryable: false });
  });

  test('S3 のほかの失敗 → いつも S3_ERROR', async () => {
    s3Mock.on(GetObjectCommand).rejects(s3Error('InternalError', 500));
    const { res, logs } = await run(requestFor(html));
    expect(res.error).toMatchObject({ code: 'S3_ERROR', retryable: true });
    expectNoLeak(res, logs);
  });
});

describe('組版', () => {
  test('26 ページ → TOO_MANY_PAGES(出力を置かない)', async () => {
    const { res } = await run(requestFor(html), new FakeBrowser({ pdf: fakePdf(26) }));
    expect(res.error).toMatchObject({ code: 'TOO_MANY_PAGES', retryable: false });
    expect(s3Mock.commandCalls(PutObjectCommand)).toHaveLength(0);
  });

  test('要求の上限のほうが小さければ、それに従う', async () => {
    const req = requestFor(html, { limits: { max_pages: 1, max_output_bytes: 52428800 } });
    const browser = new FakeBrowser({ pdf: fakePdf(2) });
    const { res } = await run(req, browser);
    expect(res.error?.code).toBe('TOO_MANY_PAGES');
    expect(browser.pdfOptions?.pageRanges).toBe('1-2');
  });

  test('PDF が大きすぎる → OUTPUT_TOO_LARGE(ストリームの途中で止める)', async () => {
    const req = requestFor(html, { limits: { max_pages: 25, max_output_bytes: 1000 } });
    const { res, tmpRoot } = await run(req, new FakeBrowser({ pdf: fakePdf(2, 200_000) }));
    expect(res.error).toMatchObject({ code: 'OUTPUT_TOO_LARGE', retryable: false });
    expect(readdirSync(tmpRoot)).toEqual([]);
  });

  test('setContent が終わらない → RENDER_TIMEOUT、ブラウザを閉じ、/tmp/r-* を残さない', async () => {
    const browser = new FakeBrowser({ setContent: () => new Promise(() => undefined) });
    const t = makeDeps(s3, browser);
    t.deps.config = { ...t.deps.config, set_content_timeout_ms: 50 };
    const res = await createHandler(t.deps)(requestFor(html), context());
    expect(res.error).toMatchObject({ code: 'RENDER_TIMEOUT', retryable: true });
    expect(browser.closed).toBe(true);
    expect(readdirSync(t.tmpRoot)).toEqual([]);
  });

  test('PDF のストリームが終わらない → RENDER_TIMEOUT(残り時間 − 20 秒)', async () => {
    const browser = new FakeBrowser({ createPDFStream: async () => new ReadableStream<Uint8Array>({ start() {} }) });
    const { res } = await run(requestFor(html), browser, {}, 20_100);
    expect(res.error?.code).toBe('RENDER_TIMEOUT');
  });

  test('残り時間が 20 秒を切っていたら組まない', async () => {
    const browser = new FakeBrowser();
    const { res } = await run(requestFor(html), browser, {}, 19_000);
    expect(res.error?.code).toBe('RENDER_TIMEOUT');
    expect(browser.pdfOptions).toBeNull();
  });

  test('ブラウザが落ちた → BROWSER_CRASHED', async () => {
    const browser = new FakeBrowser({
      setContent: async () => {
        browser.connected = false;
        const e = new Error(`Protocol error: Target closed ${CANARY}`);
        e.name = 'TargetCloseError';
        throw e;
      },
    });
    const { res, logs } = await run(requestFor(html), browser);
    expect(res.error).toMatchObject({ code: 'BROWSER_CRASHED', retryable: true, detail: 'TargetCloseError' });
    expectNoLeak(res, logs);
  });

  test('ブラウザが立ち上がらない → BROWSER_LAUNCH_FAILED', async () => {
    const { res } = await run(requestFor(html), new FakeBrowser(), {
      launch: async () => {
        throw new Error(`spawn ENOENT ${CANARY}`);
      },
    });
    expect(res.error).toMatchObject({ code: 'BROWSER_LAUNCH_FAILED', retryable: true, detail: 'Error' });
  });

  test('閉じるのに 5 秒かかるときは SIGKILL で止める', async () => {
    const browser = new FakeBrowser({ closeHangs: true });
    const t = makeDeps(s3, browser);
    t.deps.config = { ...t.deps.config, close_timeout_ms: 30 };
    const res = await createHandler(t.deps)(requestFor(html), context());
    expect(res.status).toBe('ok');
    expect(browser.killed).toContain('SIGKILL');
  });
});

describe('出力', () => {
  test('409(DELETE とぶつかった)→ S3_ERROR(やり直してよい)', async () => {
    s3Mock.on(PutObjectCommand).rejects(s3Error('ConditionalRequestConflict', 409));
    const { res, logs } = await run(requestFor(html));
    expect(res.error).toMatchObject({ code: 'S3_ERROR', retryable: true });
    expect(res.error?.detail).toBe('PutObject 409 ConditionalRequestConflict');
    expectNoLeak(res, logs);
  });

  test('412 のあとの HEAD が失敗 → S3_ERROR', async () => {
    s3Mock.on(PutObjectCommand).rejects(s3Error('PreconditionFailed', 412));
    s3Mock.on(HeadObjectCommand).rejects(s3Error('Forbidden', 403));
    const { res } = await run(requestFor(html));
    expect(res.error?.code).toBe('S3_ERROR');
  });
});

describe('包みの外に例外を出さない', () => {
  test('予想していない例外は INTERNAL、detail は種類の名前だけ', async () => {
    const browser = new FakeBrowser({
      setContent: async () => {
        throw new TypeError(`boom ${CANARY}`);
      },
    });
    const { res, logs } = await run(requestFor(html), browser);
    expectValid(res);
    expect(res.error).toEqual({ code: 'INTERNAL', retryable: false, detail: 'TypeError' });
    expectNoLeak(res, logs);
  });
});

describe('S3 の時間切れと回数', () => {
  test('残り 40 秒以上なら 10 秒・3 回、少なければ 残り − 5 秒・1 回', () => {
    expect(s3Budget(85_000)).toEqual({ requestTimeoutMs: 10_000, maxAttempts: 3 });
    expect(s3Budget(40_000)).toEqual({ requestTimeoutMs: 10_000, maxAttempts: 3 });
    expect(s3Budget(30_000)).toEqual({ requestTimeoutMs: 25_000, maxAttempts: 1 });
    expect(s3Budget(3_000)).toEqual({ requestTimeoutMs: 1_000, maxAttempts: 1 });
  });
});

describe('Chromium に渡す環境変数', () => {
  test('鍵を渡さない', () => {
    const env = chromiumEnv({ PATH: '/bin', AWS_ACCESS_KEY_ID: 'x', AWS_SECRET_ACCESS_KEY: 'y', AWS_SESSION_TOKEN: 'z', FONTCONFIG_FILE: '/f', AWS_LAMBDA_RUNTIME_API: '127.0.0.1:9001' });
    expect(env).toEqual({ PATH: '/bin', FONTCONFIG_FILE: '/f' });
  });
});
