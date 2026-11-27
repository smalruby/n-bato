// イメージを作るときに 1 回だけ流す(Dockerfile)。作り手の名前と、フォントの digest を build.json に書く(docs/design/pdf-lambda.md 2.2)。
// font_digest = フォントの各ファイルの SHA-256(名前の順)をつないだものの SHA-256。
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const [fontsDir, chromiumVersionFile, out] = process.argv.slice(2);
if (!fontsDir || !chromiumVersionFile || !out) throw new Error('usage: write-build-meta <fonts dir> <chromium version file> <out>');
const fonts = readdirSync(fontsDir).filter((n) => /\.(ttc|ttf|otf)$/.test(n)).sort();
if (fonts.length === 0) throw new Error('no fonts');
const digest = createHash('sha256');
for (const f of fonts) digest.update(`${f}\0${createHash('sha256').update(readFileSync(join(fontsDir, f))).digest('hex')}\n`);
const puppeteer = JSON.parse(readFileSync(join(process.cwd(), 'node_modules/puppeteer-core/package.json'), 'utf8')) as { version: string };
const chromium = readFileSync(chromiumVersionFile, 'utf8').trim();
const build = process.env.RENDERER_BUILD || 'local';
writeFileSync(out, `${JSON.stringify({ build, chromium, puppeteer: puppeteer.version, font_digest: digest.digest('hex').slice(0, 16) })}\n`);
