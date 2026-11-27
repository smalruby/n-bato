// n-bato の印刷用 HTML を A4 の PDF にする Lambda(#22、docs/design/pdf-lambda.md、ADR-0037)。
//
// Rails のジョブが同期(RequestResponse)で呼ぶ。HTML と PDF は S3 を通し、要求と応答は参照だけの JSON(schema/*.v1.json)。
// - やり直さない(やり直すのはジョブだけ。中の S3 の SDK の回数だけ許す。4.4)
// - 分かっている失敗は例外にせず status: "error" で返す。いちばん外で包み、予想していない例外は INTERNAL(種類の名前だけ)
// - ログに中身を書かない(1 行の JSON に、数とコードだけ。2.4)
// - 呼び出しごとに /tmp/r-<uuid> を作り、ブラウザも毎回立ち上げて最後に消す(4.3)
import { createHash, randomUUID } from 'node:crypto';
import { createReadStream, createWriteStream, existsSync, readFileSync, readdirSync, rmSync, statfsSync, statSync } from 'node:fs';
import { mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { Readable, Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { GetObjectCommand, HeadObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { NodeHttpHandler } from '@smithy/node-http-handler';
import Ajv from 'ajv';
import config from '../config.json';
import requestSchema from '../schema/request.v1.json';
import responseSchema from '../schema/response.v1.json';
import { ERROR_CODES, ErrorCode, RenderError, errorKind } from './errors';
import { chromiumFlags } from './flags';
import { Coverage, loadCoverage, missingGlyphs } from './glyphs';
import { MemorySampler } from './memory';
import { countPdfPages } from './pdf';

export type Config = typeof config;

export type RendererInfo = { build: string; chromium: string; puppeteer: string; font_digest: string; renderer_id: string };

export type PdfRequest = {
  protocol: 1;
  request_id: string;
  input_key: string;
  input: { bucket: string; key: string; sha256: string; bytes: number };
  output_prefix: string;
  options: { format: 'A4'; print_background: boolean; prefer_css_page_size: boolean };
  limits: { max_pages: number; max_output_bytes: number };
  deadline_at: number;
};

export type Metrics = {
  cold_start: boolean;
  duration_ms: number;
  launch_ms: number;
  render_ms: number;
  upload_ms: number;
  peak_rss_mb: number;
  memory_limit_mb: number | null;
  tmp_free_mb: number | null;
  blocked_requests: number;
  missing_glyphs: number;
  missing_codepoints: string[];
};

export type PdfResponse = {
  protocol: 1;
  request_id: string | null;
  status: 'ok' | 'error';
  reused?: boolean;
  output?: { bucket: string; key: string; bytes: number; pages: number };
  error?: { code: ErrorCode; retryable: boolean; detail: string };
  metrics: Metrics;
  renderer: RendererInfo;
};

// puppeteer の型の、ここで使う分だけ(テストでは偽物を入れる)
export type PageLike = {
  setJavaScriptEnabled(enabled: boolean): Promise<void>;
  setRequestInterception(value: boolean): Promise<void>;
  on(event: 'request', handler: (req: RequestLike) => void): unknown;
  setContent(html: string, options: { waitUntil: 'load'; timeout: number }): Promise<void>;
  createPDFStream(options: Record<string, unknown>): Promise<ReadableStream<Uint8Array>>;
  pdf?(options: Record<string, unknown>): Promise<Uint8Array>;
  close(): Promise<void>;
};
export type RequestLike = { url(): string; abort(): Promise<void>; continue(): Promise<void>; isInterceptResolutionHandled?(): boolean };
export type BrowserLike = {
  newPage(): Promise<PageLike>;
  close(): Promise<void>;
  process(): { pid?: number; kill(signal?: NodeJS.Signals): boolean } | null;
  connected?: boolean;
};
export type LaunchOptions = { executablePath: string; args: string[]; userDataDir: string; env: NodeJS.ProcessEnv; timeout: number };

export type Deps = {
  config: Config;
  env: NodeJS.ProcessEnv;
  now: () => number;
  log: (line: string) => void;
  tmpRoot: string;
  renderer: RendererInfo;
  coverage: Coverage | null;
  s3: (opts: { requestTimeoutMs: number; maxAttempts: number }) => S3Client;
  launch: (opts: LaunchOptions) => Promise<BrowserLike>;
};

export type LambdaContext = { getRemainingTimeInMillis(): number; memoryLimitInMB?: string | number };

const ajv = new Ajv({ allErrors: false, strict: true });
const validateRequest = ajv.compile(requestSchema);
export const validateResponse = ajv.compile(responseSchema);

const MB = 1024 * 1024;
let warm = false;

// ---- 作り手(イメージを作るときに build.json に書く。renderer_id = SHA-256(build \0 font_digest) の先頭 16 文字) ----

export const rendererId = (build: string, fontDigest: string): string =>
  createHash('sha256').update(`${build}\0${fontDigest}`).digest('hex').slice(0, 16);

export const loadRenderer = (path = '/var/task/build.json'): RendererInfo => {
  let meta = { build: 'dev', chromium: 'unknown', puppeteer: 'unknown', font_digest: 'none' };
  try {
    meta = { ...meta, ...JSON.parse(readFileSync(path, 'utf8')) };
  } catch {
    // 手元のテスト。イメージには必ずある(Dockerfile)
  }
  return { ...meta, renderer_id: rendererId(meta.build, meta.font_digest) };
};

// ---- S3 の時間切れと回数(残り時間から決める。4.3) ----

export const s3Budget = (remainingMs: number): { requestTimeoutMs: number; maxAttempts: number } =>
  remainingMs >= 40_000 ? { requestTimeoutMs: 10_000, maxAttempts: 3 } : { requestTimeoutMs: Math.max(1_000, remainingMs - 5_000), maxAttempts: 1 };

const defaultS3 = (env: NodeJS.ProcessEnv) => (opts: { requestTimeoutMs: number; maxAttempts: number }) =>
  new S3Client({
    maxAttempts: opts.maxAttempts,
    requestHandler: new NodeHttpHandler({ connectionTimeout: Math.min(5_000, opts.requestTimeoutMs), requestTimeout: opts.requestTimeoutMs }),
    // 手元のコンテナの試験(MinIO)のときだけ。本番の関数には付けない(CDK)
    ...(env.S3_ENDPOINT ? { endpoint: env.S3_ENDPOINT, forcePathStyle: true } : {}),
  });

const defaultLaunch = async (opts: LaunchOptions): Promise<BrowserLike> => {
  const puppeteer = await import('puppeteer-core');
  return (await puppeteer.launch({
    executablePath: opts.executablePath,
    args: opts.args,
    ignoreDefaultArgs: true,
    userDataDir: opts.userDataDir,
    env: opts.env,
    pipe: true, // WebSocket を使わない(100MiB の maxPayload に当たらない。4.1)
    headless: 'shell',
    timeout: opts.timeout,
    protocolTimeout: 60_000,
    handleSIGINT: false,
    handleSIGTERM: false,
    handleSIGHUP: false,
  })) as unknown as BrowserLike;
};

// ---- いちばん外: 何があっても応答の形で返す ----

export const createHandler = (deps: Deps) => async (event: unknown, context: LambdaContext): Promise<PdfResponse> => {
  const started = deps.now();
  const coldStart = !warm;
  warm = true;
  const sampler = new MemorySampler(deps.config.memory_sample_interval_ms);
  sampler.start();
  const metrics: Metrics = {
    cold_start: coldStart,
    duration_ms: 0,
    launch_ms: 0,
    render_ms: 0,
    upload_ms: 0,
    peak_rss_mb: 0,
    memory_limit_mb: context.memoryLimitInMB ? Number(context.memoryLimitInMB) : null,
    tmp_free_mb: null,
    blocked_requests: 0,
    missing_glyphs: 0,
    missing_codepoints: [],
  };
  const requestId = typeof (event as { request_id?: unknown })?.request_id === 'string' ? String((event as { request_id: string }).request_id).slice(0, 64) : null;
  const inputKey = typeof (event as { input_key?: unknown })?.input_key === 'string' ? String((event as { input_key: string }).input_key) : '';
  let response: PdfResponse;
  try {
    const result = await render(event, context, deps, metrics, sampler);
    response = { protocol: 1, request_id: requestId, status: 'ok', reused: result.reused, output: result.output, metrics, renderer: deps.renderer };
  } catch (e) {
    const code: ErrorCode = e instanceof RenderError ? e.code : 'INTERNAL';
    const detail = (e instanceof RenderError ? e.detail : errorKind(e)).slice(0, 200);
    response = { protocol: 1, request_id: requestId, status: 'error', error: { code, retryable: ERROR_CODES[code], detail }, metrics, renderer: deps.renderer };
  }
  const peak = sampler.stop();
  metrics.peak_rss_mb = Math.round(peak.totalMb);
  metrics.duration_ms = Math.max(0, Math.round(deps.now() - started));
  deps.log(logLine(response, inputKey, peak, deps.env));
  return response;
};

// 1 行の JSON(Embedded Metric Format を兼ねる)。要求の JSON・HTML・URL・例外の文は出さない
const logLine = (r: PdfResponse, inputKey: string, peak: ReturnType<MemorySampler['stop']>, env: NodeJS.ProcessEnv): string => {
  const line: Record<string, unknown> = {
    _aws: {
      Timestamp: Date.now(),
      CloudWatchMetrics: [
        {
          Namespace: 'NBato/PdfRenderer',
          Dimensions: [[]],
          Metrics: [
            { Name: 'PeakRssMb', Unit: 'Megabytes' },
            { Name: 'DurationMs', Unit: 'Milliseconds' },
            { Name: 'Pages', Unit: 'Count' },
            { Name: 'MissingGlyphs', Unit: 'Count' },
          ],
        },
      ],
    },
    request_id: r.request_id,
    input_key: /^[0-9a-f]{64}$/.test(inputKey) ? inputKey.slice(0, 12) : null,
    status: r.status,
    code: r.error?.code ?? null,
    reused: r.reused ?? false,
    PeakRssMb: r.metrics.peak_rss_mb,
    DurationMs: r.metrics.duration_ms,
    Pages: r.output?.pages ?? 0,
    MissingGlyphs: r.metrics.missing_glyphs,
    bytes: r.output?.bytes ?? 0,
    cold_start: r.metrics.cold_start,
    launch_ms: r.metrics.launch_ms,
    render_ms: r.metrics.render_ms,
    upload_ms: r.metrics.upload_ms,
    blocked_requests: r.metrics.blocked_requests,
    tmp_free_mb: r.metrics.tmp_free_mb,
    level: r.status === 'ok' ? (r.metrics.missing_glyphs > 0 ? 'warn' : 'info') : 'error',
  };
  // 実験(4.10 の ④)のときだけ、測り方ごとの山を並べる(数だけ)
  if (env.PDF_EXPERIMENT === '1') {
    line.experiment = {
      node_rss_mb: Math.round(peak.nodeRssMb),
      chromium_rss_mb: Math.round(peak.chromiumRssMb),
      heap_used_mb: Math.round(peak.heapUsedMb),
      total_mb: Math.round(peak.totalMb),
      error_detail: r.error?.detail ?? null,
      dev_shm_mb: devShmMb(),
    };
  }
  return JSON.stringify(line);
};

// ---- 中身 ----

const checkRequest = (event: unknown, deps: Deps): PdfRequest => {
  if (!event || typeof event !== 'object') throw new RenderError('INVALID_REQUEST', 'not an object');
  const protocol = (event as { protocol?: unknown }).protocol;
  if (protocol !== 1) throw new RenderError('UNSUPPORTED_PROTOCOL', `protocol ${typeof protocol === 'number' ? protocol : typeof protocol}`);
  if (!validateRequest(event)) {
    const err = validateRequest.errors?.[0];
    throw new RenderError('INVALID_REQUEST', `${err?.instancePath || '/'} ${err?.keyword ?? ''}`.trim());
  }
  const req = event as PdfRequest;
  const bucket = deps.env.PDF_BUCKET;
  if (!bucket || req.input.bucket !== bucket) throw new RenderError('INVALID_REQUEST', 'bucket');
  if (!req.input.key.endsWith(`-${req.input_key}.html`)) throw new RenderError('INVALID_REQUEST', 'input.key');
  if (req.output_prefix !== `v1/out/${req.input_key}/`) throw new RenderError('INVALID_REQUEST', 'output_prefix');
  return req;
};

const tmpFreeMb = (root: string): number | null => {
  try {
    const s = statfsSync(root);
    return Math.floor((s.bavail * s.bsize) / MB);
  } catch {
    return null;
  }
};

// 空きが少なければ、前の呼び出しの残り(/tmp/r-*)を消す(4.3)
const ensureTmp = (deps: Deps, metrics: Metrics): void => {
  metrics.tmp_free_mb = tmpFreeMb(deps.tmpRoot);
  if (metrics.tmp_free_mb !== null && metrics.tmp_free_mb < deps.config.tmp_min_free_mb) {
    for (const name of readdirSync(deps.tmpRoot)) {
      if (name.startsWith('r-')) rmSync(join(deps.tmpRoot, name), { recursive: true, force: true });
    }
    metrics.tmp_free_mb = tmpFreeMb(deps.tmpRoot);
  }
};

const devShmMb = (): number | null => {
  try {
    const st = statfsSync('/dev/shm');
    return Math.floor((st.blocks * st.bsize) / MB);
  } catch {
    return null;
  }
};

const s3Status = (e: unknown): number | undefined => (e as { $metadata?: { httpStatusCode?: number } })?.$metadata?.httpStatusCode;

const readInput = async (s3: S3Client, req: PdfRequest, maxBytes: number): Promise<Buffer> => {
  let body: Readable;
  try {
    const res = await s3.send(new GetObjectCommand({ Bucket: req.input.bucket, Key: req.input.key }));
    if (typeof res.ContentLength === 'number' && res.ContentLength > maxBytes) throw new RenderError('INPUT_TOO_LARGE', 'content-length');
    body = res.Body as Readable;
  } catch (e) {
    if (e instanceof RenderError) throw e;
    const name = errorKind(e);
    if (name === 'NoSuchKey' || s3Status(e) === 404) throw new RenderError('INPUT_NOT_FOUND', 'NoSuchKey');
    throw new RenderError('S3_ERROR', `GetObject ${name}`);
  }
  const chunks: Buffer[] = [];
  let size = 0;
  try {
    for await (const chunk of body) {
      size += (chunk as Buffer).length;
      if (size > maxBytes) {
        body.destroy();
        throw new RenderError('INPUT_TOO_LARGE', 'body');
      }
      chunks.push(chunk as Buffer);
    }
  } catch (e) {
    if (e instanceof RenderError) throw e;
    throw new RenderError('S3_ERROR', `GetObject body ${errorKind(e)}`);
  }
  const html = Buffer.concat(chunks);
  if (html.length !== req.input.bytes) throw new RenderError('INPUT_CHECKSUM_MISMATCH', 'bytes');
  if (createHash('sha256').update(html).digest('hex') !== req.input.sha256) throw new RenderError('INPUT_CHECKSUM_MISMATCH', 'sha256');
  return html;
};

const withTimeout = async <T>(p: Promise<T>, ms: number, onTimeout: () => RenderError): Promise<T> => {
  let timer: NodeJS.Timeout | undefined;
  try {
    return await Promise.race([
      p,
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(onTimeout()), ms);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
};

// ブラウザが落ちた・つながりが切れたときの例外を BROWSER_CRASHED に
const crashed = (e: unknown, browser: BrowserLike | null): boolean => {
  const name = errorKind(e);
  const msg = e instanceof Error ? e.message : '';
  return browser?.connected === false || name === 'TargetCloseError' || /Target closed|Session closed|Connection closed|Protocol error/i.test(msg);
};

// ページ → ブラウザの順に閉じ、5 秒で閉じなければプロセスグループごと SIGKILL(4.3)
export const closeBrowser = async (browser: BrowserLike | null, page: PageLike | null, timeoutMs: number): Promise<void> => {
  if (!browser) return;
  const proc = browser.process();
  const closing = (async () => {
    try {
      await page?.close();
    } catch {
      // 落ちたあと
    }
    await browser.close();
  })();
  let closed = false;
  try {
    await withTimeout(closing, timeoutMs, () => new RenderError('INTERNAL', 'close timeout'));
    closed = true;
  } catch {
    closed = false;
  }
  if (closed || !proc) return;
  try {
    // puppeteer は Linux で Chromium を別のプロセスグループ(detached)で起こすので、グループごと止める
    if (proc.pid) process.kill(-proc.pid, 'SIGKILL');
    else proc.kill('SIGKILL');
  } catch {
    try {
      proc.kill('SIGKILL');
    } catch {
      // もう無い
    }
  }
};

const render = async (
  event: unknown,
  context: LambdaContext,
  deps: Deps,
  metrics: Metrics,
  sampler: MemorySampler,
): Promise<{ reused: boolean; output: NonNullable<PdfResponse['output']> }> => {
  const req = checkRequest(event, deps);
  if (deps.now() > req.deadline_at) throw new RenderError('DEADLINE_EXCEEDED', 'before start');
  const cfg = deps.config;
  const maxPages = Math.min(req.limits.max_pages, cfg.max_pages);
  const maxOutput = Math.min(req.limits.max_output_bytes, cfg.max_output_bytes);

  ensureTmp(deps, metrics);
  const work = await mkdtemp(join(deps.tmpRoot, `r-${randomUUID()}-`));
  let browser: BrowserLike | null = null;
  let page: PageLike | null = null;
  try {
    const s3 = deps.s3(s3Budget(context.getRemainingTimeInMillis()));
    const html = await readInput(s3, req, cfg.max_input_bytes);
    const htmlText = html.toString('utf8');
    const glyphs = missingGlyphs(htmlText, deps.coverage, cfg.max_missing_codepoints);
    metrics.missing_glyphs = glyphs.count;
    metrics.missing_codepoints = glyphs.codepoints;

    // ブラウザ(毎回まっさらに。TMPDIR と user-data-dir を呼び出しの場所の下に)
    const launchStarted = deps.now();
    try {
      browser = await deps.launch({
        executablePath: deps.env.CHROMIUM_PATH ?? '/opt/chromium/chromium',
        args: chromiumFlags(deps.env),
        userDataDir: join(work, 'profile'),
        env: { ...chromiumEnv(deps.env), TMPDIR: work, HOME: work },
        timeout: 20_000,
      });
    } catch (e) {
      // 実験のときだけ、立ち上がらなかった理由の文を出す(HTML を読む前なので中身は入らない)
      if (deps.env.PDF_EXPERIMENT === '1') deps.log(JSON.stringify({ experiment_launch_error: String((e as Error)?.message).slice(0, 1500) }));
      throw new RenderError('BROWSER_LAUNCH_FAILED', errorKind(e));
    }
    sampler.watchGroup(browser.process()?.pid);
    metrics.launch_ms = Math.round(deps.now() - launchStarted);

    const renderStarted = deps.now();
    const pdfPath = join(work, 'out.pdf');
    try {
      page = await browser.newPage();
      await page.setJavaScriptEnabled(false);
      await page.setRequestInterception(true);
      page.on('request', (r) => {
        if (r.isInterceptResolutionHandled?.()) return;
        const url = r.url();
        if (url.startsWith('data:') || url === 'about:blank') {
          r.continue().catch(() => undefined);
        } else {
          metrics.blocked_requests += 1;
          r.abort().catch(() => undefined);
        }
      });
      await withTimeout(page.setContent(htmlText, { waitUntil: 'load', timeout: cfg.set_content_timeout_ms }), cfg.set_content_timeout_ms + 1_000, () => new RenderError('RENDER_TIMEOUT', 'setContent'));

      const pdfTimeout = Math.min(context.getRemainingTimeInMillis() - cfg.pdf_reserve_ms, cfg.pdf_timeout_max_ms);
      if (pdfTimeout <= 0) throw new RenderError('RENDER_TIMEOUT', 'no time left');
      const p = page;
      const writePdf = async (): Promise<void> => {
        // 上限 + 1 ページまでしか組まない(301 ページ目があれば TOO_MANY_PAGES。300 を超える大きな表で時間とメモリを使わない)
        const pdfOptions = {
          format: req.options.format,
          printBackground: req.options.print_background,
          preferCSSPageSize: req.options.prefer_css_page_size,
          pageRanges: `1-${maxPages + 1}`,
          timeout: pdfTimeout,
        };
        // 実験 ②(4.10)のときだけ、PDF を一度に受け取る(page.pdf())。本番はいつもストリーム
        if (deps.env.PDF_EXPERIMENT === '1' && deps.env.PDF_RECEIVE === 'buffer' && p.pdf) {
          const buf = await p.pdf(pdfOptions);
          if (buf.length > maxOutput) throw new RenderError('OUTPUT_TOO_LARGE', 'buffer');
          await pipeline(Readable.from([Buffer.from(buf)]), createWriteStream(pdfPath, { mode: 0o600 }));
          return;
        }
        const stream = await p.createPDFStream(pdfOptions);
        let written = 0;
        const limit = new Transform({
          transform(chunk: Buffer, _enc, cb) {
            written += chunk.length;
            if (written > maxOutput) cb(new RenderError('OUTPUT_TOO_LARGE', 'stream'));
            else cb(null, chunk);
          },
        });
        await pipeline(Readable.fromWeb(stream as unknown as import('node:stream/web').ReadableStream), limit, createWriteStream(pdfPath, { mode: 0o600 }));
      };
      await withTimeout(writePdf(), pdfTimeout, () => new RenderError('RENDER_TIMEOUT', 'pdf'));
    } catch (e) {
      if (e instanceof RenderError) throw e;
      if (errorKind(e) === 'TimeoutError') throw new RenderError('RENDER_TIMEOUT', 'TimeoutError');
      if (crashed(e, browser)) throw new RenderError('BROWSER_CRASHED', errorKind(e));
      throw e;
    }
    metrics.render_ms = Math.round(deps.now() - renderStarted);
    await closeBrowser(browser, page, cfg.close_timeout_ms);
    browser = null;
    page = null;

    const bytes = statSync(pdfPath).size;
    if (bytes === 0) throw new RenderError('BROWSER_CRASHED', 'empty pdf');
    const pages = await countPdfPages(pdfPath);
    if (pages > maxPages) throw new RenderError('TOO_MANY_PAGES', `>${maxPages}`);
    if (pages < 1) throw new RenderError('INTERNAL', 'no pages');

    // 出力は条件つき(If-None-Match: *)。412 = もうある → ある方を返す(4.5)
    const uploadStarted = deps.now();
    const key = `${req.output_prefix}${deps.renderer.renderer_id}.pdf`;
    const sha256 = await fileSha256(pdfPath);
    const upload = deps.s3(s3Budget(context.getRemainingTimeInMillis()));
    let reused = false;
    let outBytes = bytes;
    try {
      await upload.send(
        new PutObjectCommand({
          Bucket: req.input.bucket,
          Key: key,
          Body: createReadStream(pdfPath),
          ContentLength: bytes,
          ContentType: 'application/pdf',
          IfNoneMatch: '*',
          ChecksumSHA256: Buffer.from(sha256, 'hex').toString('base64'),
        }),
      );
    } catch (e) {
      const status = s3Status(e);
      if (status === 412 || errorKind(e) === 'PreconditionFailed') {
        reused = true;
        try {
          const head = await upload.send(new HeadObjectCommand({ Bucket: req.input.bucket, Key: key }));
          outBytes = head.ContentLength ?? bytes;
        } catch (he) {
          throw new RenderError('S3_ERROR', `HeadObject ${errorKind(he)}`);
        }
      } else {
        throw new RenderError('S3_ERROR', `PutObject ${status ?? ''} ${errorKind(e)}`.replace(/\s+/g, ' ').trim());
      }
    }
    metrics.upload_ms = Math.round(deps.now() - uploadStarted);
    return { reused, output: { bucket: req.input.bucket, key, bytes: outBytes, pages } };
  } finally {
    await closeBrowser(browser, page, cfg.close_timeout_ms);
    await rm(work, { recursive: true, force: true });
  }
};

const fileSha256 = async (path: string): Promise<string> => {
  const hash = createHash('sha256');
  await pipeline(createReadStream(path), hash);
  return hash.digest('hex');
};

// Chromium に渡す環境変数。鍵(AWS_*)は渡さない
export const chromiumEnv = (env: NodeJS.ProcessEnv): NodeJS.ProcessEnv => {
  const keep = ['PATH', 'LD_LIBRARY_PATH', 'FONTCONFIG_PATH', 'FONTCONFIG_FILE', 'LANG', 'TZ'];
  const out: NodeJS.ProcessEnv = {};
  for (const k of keep) if (env[k] !== undefined) out[k] = env[k];
  return out;
};

// ---- Lambda の入口 ----

const coveragePath = '/var/task/fonts/coverage.txt';

export const handler = createHandler({
  config,
  env: process.env,
  now: () => Date.now(),
  log: (line) => process.stdout.write(`${line}\n`),
  tmpRoot: process.env.PDF_TMP_ROOT ?? '/tmp',
  renderer: loadRenderer(),
  coverage: existsSync(coveragePath) ? loadCoverage(coveragePath) : null,
  s3: defaultS3(process.env),
  launch: defaultLaunch,
});
