// イメージを作るときに 1 回だけ流す(Dockerfile)。@sparticuz/chromium の圧縮した Chromium を取り出し、/opt/chromium に写す。
// 動くときに /tmp へ展開しない(立ち上がりが速くなり、/tmp を使わない。docs/design/pdf-lambda.md 1.2)。
// 写すもの: chromium の本体、swiftshader の .so(Chromium が自分の場所から読む)、Amazon Linux 2023 用の .so(lib/)。
// 包みのフォント(Open Sans)と fonts.conf は写さない(フォントは本番の Rails と同じ Noto を /var/task/fonts に置く)。
import { cpSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const main = async (): Promise<void> => {
  const dest = process.argv[2];
  if (!dest) throw new Error('usage: extract-chromium <dest>');
  if (!process.env.AWS_EXECUTION_ENV) throw new Error('AWS_EXECUTION_ENV を付けて流す(Amazon Linux 2023 用の .so も取り出すため)');
  const chromium = (await import('@sparticuz/chromium')).default;
  const exe = await chromium.executablePath();
  mkdirSync(join(dest, 'lib'), { recursive: true });
  cpSync(exe, join(dest, 'chromium'));
  for (const name of readdirSync(tmpdir())) {
    if (/\.(so(\.\d+)*|json)$/.test(name)) cpSync(join(tmpdir(), name), join(dest, name));
  }
  cpSync(join(tmpdir(), 'al2023', 'lib'), join(dest, 'lib'), { recursive: true });
  // 包みの exports が package.json を出さないので、場所を直に読む
  const pkg = JSON.parse(readFileSync(join(process.cwd(), 'node_modules/@sparticuz/chromium/package.json'), 'utf8')) as { version: string };
  writeFileSync(join(dest, 'version.txt'), `${pkg.version}\n`);
};

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
