// 手元のコンテナで Lambda に近づけて動かし、測る(docs/design/pdf-lambda.md 4.10・7.2)。AWS は使わない。
//
//   node out/bench/run.js --label B-1024 --memory 1024 [--add "旗 …"] [--remove "旗 …"] [--shm] 入力の HTML …
//
// - S3 は adobe/s3mock(コンテナ pdf-s3、網 pdf-bench。MinIO は公開のイメージが無くなった)。HTML を置き、Lambda のコンテナを 1 つの入力ごとに立ち上げ直して呼ぶ(冷えた立ち上がり)。
// - Lambda のコンテナは読むだけのファイル・/tmp 1GB(tmpfs)・/dev/shm なし(--ipc=none。--shm で 64MB を付ける)・メモリの上限・
//   Lambda と同じでない利用者(993:990)。
// - メモリの山は cgroup の memory.peak(コンテナまるごと。REPORT の Max Memory Used に当たる)と、関数の中で測った値(4.2)。
// - 結果は out/results.tsv に 1 行ずつ足す。PDF は out/pdf/<label>/ に置き、pdfinfo・pdffonts で見る。
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { CreateBucketCommand, GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';

const IMAGE = process.env.PDF_IMAGE ?? 'n-bato-pdf-renderer:dev';
const NET = 'pdf-bench';
const BUCKET = 'n-bato-pdf-bench';
const S3_USER = 'benchuser';
const S3_PASS = 'benchpass-not-secret';
const OUT = join(__dirname, '..', '..', 'bench', 'out');

const args = process.argv.slice(2);
const opt = (name: string, def = ''): string => {
  const i = args.indexOf(`--${name}`);
  if (i < 0) return def;
  const v = args[i + 1];
  args.splice(i, 2);
  return v;
};
const flag = (name: string): boolean => {
  const i = args.indexOf(`--${name}`);
  if (i < 0) return false;
  args.splice(i, 1);
  return true;
};

const label = opt('label', 'run');
const memory = Number(opt('memory', '1024'));
const add = opt('add');
const remove = opt('remove');
// Lambda は 1,769MB で vCPU 1 つ分(メモリに比べて CPU も配られる)。既定はそれに合わせる
const cpus = opt('cpus', Math.max(0.2, memory / 1769).toFixed(2));
const tmpMb = Number(opt('tmp', '1024'));
const receive = opt('receive', 'stream');
const shm = flag('shm');
const inputs = args;

const sh = (cmd: string, a: string[], allowFail = false): string => {
  const r = spawnSync(cmd, a, { encoding: 'utf8' });
  if (r.status !== 0 && !allowFail) throw new Error(`${cmd} ${a.join(' ')}: ${r.stderr}`);
  return (r.stdout ?? '').trim();
};

const ensureS3 = async (): Promise<S3Client> => {
  sh('docker', ['network', 'create', NET], true);
  if (!sh('docker', ['ps', '-q', '-f', 'name=^pdf-s3$'])) {
    sh('docker', ['rm', '-f', 'pdf-s3'], true);
    sh('docker', ['run', '-d', '--name', 'pdf-s3', '--network', NET, '-p', '127.0.0.1:9100:9090', '-e', `COM_ADOBE_TESTING_S3MOCK_STORE_INITIAL_BUCKETS=${BUCKET}`, 'adobe/s3mock']);
  }
  const s3 = new S3Client({ endpoint: 'http://127.0.0.1:9100', forcePathStyle: true, region: 'us-east-1', credentials: { accessKeyId: S3_USER, secretAccessKey: S3_PASS } });
  for (let i = 0; i < 60; i += 1) {
    try {
      await s3.send(new CreateBucketCommand({ Bucket: BUCKET }));
      return s3;
    } catch (e) {
      const n = (e as Error).name;
      if (n === 'BucketAlreadyOwnedByYou' || n === 'BucketAlreadyExists') return s3;
      await new Promise((r) => setTimeout(r, 1000));
    }
  }
  throw new Error('S3 の代わりが立ち上がらない');
};

const invoke = async (body: unknown): Promise<{ res: unknown; ms: number }> => {
  const started = Date.now();
  for (let i = 0; i < 60; i += 1) {
    try {
      const r = await fetch('http://127.0.0.1:9000/2015-03-31/functions/function/invocations', { method: 'POST', body: JSON.stringify(body), signal: AbortSignal.timeout(150_000) });
      const text = await r.text();
      return { res: JSON.parse(text), ms: Date.now() - started };
    } catch (e) {
      // 立ち上がりの直後はつながらない・すぐ切れる(fetch は TypeError)。時間切れ(TimeoutError)は待たない
      if ((e as Error).name === 'TypeError' && Date.now() - started < 30_000) {
        await new Promise((r) => setTimeout(r, 500));
        continue;
      }
      return { res: { invoke_error: (e as Error).name }, ms: Date.now() - started };
    }
  }
  throw new Error('Lambda のコンテナにつながらない');
};

const pdfFonts = (path: string): string => {
  const out = sh('pdffonts', [path], true).split('\n').slice(2);
  const names = new Set(out.map((l) => l.split(/\s+/)[0].replace(/^[A-Z]{6}\+/, '')).filter(Boolean));
  return [...names].join(',');
};

const main = async (): Promise<void> => {
  mkdirSync(join(OUT, 'pdf', label), { recursive: true });
  const results = join(OUT, 'results.tsv');
  if (!existsSync(results)) {
    writeFileSync(results, ['label', 'input', 'memory_mb', 'cpus', 'tmp_mb', 'receive', 'add', 'remove', 'shm', 'dev_shm_mb', 'tmp_free_mb', 'status', 'code', 'detail', 'pages', 'pdfinfo_pages', 'bytes', 'cgroup_peak_mb', 'fn_peak_mb', 'node_rss_mb', 'chromium_rss_mb', 'heap_used_mb', 'oom_killed', 'invoke_ms', 'launch_ms', 'render_ms', 'upload_ms', 'missing_glyphs', 'blocked', 'fonts'].join('\t') + '\n');
  }
  const s3 = await ensureS3();
  for (const input of inputs) {
    const name = basename(input, '.html');
    const html = readFileSync(input);
    const inputKey = createHash('sha256').update(randomBytes(16)).update(html).digest('hex');
    const key = `v1/in/1-${inputKey}.html`;
    await s3.send(new PutObjectCommand({ Bucket: BUCKET, Key: key, Body: html }));
    const container = `pdf-lambda-${process.pid}`;
    sh('docker', ['rm', '-f', container], true);
    const runArgs = [
      'run', '-d', '--name', container, '--network', NET, '-p', '127.0.0.1:9000:8080', '--platform', 'linux/amd64',
      '--read-only', '--tmpfs', `/tmp:size=${tmpMb}m`, ...(shm ? ['--shm-size', '64m'] : ['--ipc', 'none']),
      '--user', '993:990', `--memory=${memory}m`, `--memory-swap=${memory}m`, `--cpus=${cpus}`,
      '-e', 'HOME=/tmp', '-e', 'TMPDIR=/tmp', '-e', `PDF_BUCKET=${BUCKET}`, '-e', 'S3_ENDPOINT=http://pdf-s3:9090',
      '-e', `AWS_ACCESS_KEY_ID=${S3_USER}`, '-e', `AWS_SECRET_ACCESS_KEY=${S3_PASS}`, '-e', 'AWS_REGION=us-east-1',
      '-e', `AWS_LAMBDA_FUNCTION_MEMORY_SIZE=${memory}`, '-e', 'AWS_LAMBDA_FUNCTION_TIMEOUT=90',
      '-e', 'PDF_EXPERIMENT=1', '-e', `PDF_FLAGS_ADD=${add}`, '-e', `PDF_FLAGS_REMOVE=${remove}`, '-e', `PDF_RECEIVE=${receive}`,
      IMAGE,
    ];
    sh('docker', runArgs);
    const request = {
      protocol: 1,
      request_id: 'pdf-1-a1',
      input_key: inputKey,
      input: { bucket: BUCKET, key, sha256: createHash('sha256').update(html).digest('hex'), bytes: Math.min(html.length, 10485760) },
      output_prefix: `v1/out/${inputKey}/`,
      options: { format: 'A4', print_background: true, prefer_css_page_size: true },
      limits: { max_pages: 25, max_output_bytes: 52428800 },
      deadline_at: Date.now() + 600_000,
    };
    const { res, ms } = await invoke(request);
    const peakBytes = Number(sh('docker', ['exec', container, 'cat', '/sys/fs/cgroup/memory.peak'], true) || 0);
    const oom = sh('docker', ['inspect', '-f', '{{.State.OOMKilled}}', container], true);
    const logs = sh('docker', ['logs', container], true);
    const line = logs.split('\n').reverse().find((l) => l.startsWith('{"_aws"'));
    const exp = line ? (JSON.parse(line) as { experiment?: Record<string, number> }).experiment ?? {} : {};
    const r = res as { status?: string; error?: { code: string; detail: string }; output?: { key: string; pages: number; bytes: number }; metrics?: Record<string, number>; errorType?: string; invoke_error?: string };
    let pdfinfoPages = '';
    let fonts = '';
    if (r.status === 'ok' && r.output) {
      const obj = await s3.send(new GetObjectCommand({ Bucket: BUCKET, Key: r.output.key }));
      const pdfPath = join(OUT, 'pdf', label, `${name}.pdf`);
      writeFileSync(pdfPath, Buffer.from(await obj.Body!.transformToByteArray()));
      pdfinfoPages = (/Pages:\s+(\d+)/.exec(sh('pdfinfo', [pdfPath], true)) ?? [])[1] ?? '';
      fonts = pdfFonts(pdfPath);
    }
    writeFileSync(join(OUT, 'pdf', label, `${name}.log`), logs.split('\n').slice(-200).join('\n'));
    sh('docker', ['rm', '-f', container], true);
    const m = r.metrics ?? {};
    const row = [
      label, name, memory, cpus, tmpMb, receive, add, remove, shm, exp.dev_shm_mb ?? '', m.tmp_free_mb ?? '', r.status ?? (r.errorType ? `fn:${r.errorType}` : r.invoke_error ? `invoke:${r.invoke_error}` : '?'),
      r.error?.code ?? '', r.error?.detail ?? '', r.output?.pages ?? '', pdfinfoPages, r.output?.bytes ?? '',
      Math.round(peakBytes / 1024 / 1024), m.peak_rss_mb ?? '', exp.node_rss_mb ?? '', exp.chromium_rss_mb ?? '', exp.heap_used_mb ?? '', oom, ms,
      m.launch_ms ?? '', m.render_ms ?? '', m.upload_ms ?? '', m.missing_glyphs ?? '', m.blocked_requests ?? '', fonts,
    ];
    appendFileSync(results, row.join('\t') + '\n');
    console.log(row.join('\t'));
  }
};

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
