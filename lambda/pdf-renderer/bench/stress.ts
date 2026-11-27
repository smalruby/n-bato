// ストレスの HTML を作る(docs/design/pdf-lambda.md 7.3)。中身はすべて作り物(架空の科目・摘要・ノイズの画像)。
//   node out/bench/stress.js <出力のディレクトリ>
import { deflateSync } from 'node:zlib';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const head = (extra = '') => `<!doctype html><html lang="ja"><head><meta charset="utf-8"><style>
@page { size: A4; margin: 15mm; }
body { font-family: "Noto Serif CJK JP", serif; font-size: 10pt; line-height: 1.5; margin: 0; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #000; padding: 1px 4px; }
thead { display: table-header-group; }
.page { break-after: page; }
.amount { text-align: right; }
${extra}</style></head><body>`;
const tail = '</body></html>';

// 1 ページに収まる表(40 行)を n ページぶん。ページの数がちょうど n になる
const ledgerPages = (n: number): string => {
  const parts = [head()];
  for (let p = 1; p <= n; p += 1) {
    parts.push(`<section class="page"><h2>総勘定元帳(見本) ${p} / ${n}</h2><table><thead><tr><th>日付</th><th>相手の科目</th><th>摘要</th><th>借方</th><th>貸方</th><th>残高</th></tr></thead><tbody>`);
    for (let r = 0; r < 40; r += 1) {
      const i = p * 40 + r;
      parts.push(`<tr><td>2026/${String((i % 12) + 1).padStart(2, '0')}/${String((i % 28) + 1).padStart(2, '0')}</td><td>消耗品費</td><td>見本の摘要 ${i}</td><td class="amount">${(i * 37) % 100000}</td><td class="amount"></td><td class="amount">${(i * 91) % 1000000}</td></tr>`);
    }
    parts.push('</tbody></table></section>');
  }
  parts.push(tail);
  return parts.join('');
};

// 区切りの無い長い表(見出しがページごとにくり返されるか)。1,000 行で 24 ページほど
const longTable = (rows: number): string => {
  const parts = [head(), '<h1>長い表(見本)</h1><table><thead><tr><th>番号</th><th>科目</th><th>摘要</th><th>金額</th></tr></thead><tbody>'];
  for (let i = 1; i <= rows; i += 1) parts.push(`<tr><td>${i}</td><td>旅費交通費</td><td>見本の摘要 ${'長い文'.repeat(i % 7)}</td><td class="amount">${i * 13}</td></tr>`);
  parts.push('</tbody></table>', tail);
  return parts.join('');
};

// 改ページを避ける塊が 1 ページより長いとき・長い名前・1 つのセルの長い文
const awkward = (): string => {
  const long = '特定非営利活動法人見本架空プログラミング教育推進協議会'.repeat(6);
  return (
    head('.keep { break-inside: avoid; border: 1px solid #000; }') +
    `<h1>${long}</h1>` +
    `<div class="keep">${'<p>改ページを避けたい長い塊の見本の文です。</p>'.repeat(120)}</div>` +
    `<table><tr><th>役職</th><td>${'代表理事兼事務局長兼会計担当'.repeat(10)}</td></tr><tr><th>摘要</th><td>${'とても長い摘要の文。'.repeat(400)}</td></tr></table>` +
    tail
  );
};

// 外字・旧字・記号(フォントに無い字が混ざるか)
const glyphs = (): string =>
  head() +
  '<h1>字の見本</h1><p>①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳ ０１２３４５６７８９ ㈱㈲㍿ 〒 ※ 〃</p>' +
  '<p>髙橋 﨑 德 邊 邉 齋 齊 𠮷 𡈽 葛󠄀 辻󠄀 鷗 剝 頰</p><p>𪚲 𩸽 🎌 ♨</p>' +
  tail;

// ノイズの PNG(圧縮が効かない。中身は乱数)
const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
const crc32 = (buf: Buffer): number => {
  let c = 0xffffffff;
  for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};
const chunk = (type: string, data: Buffer): Buffer => {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
};
let seed = 12345;
const rand = (): number => {
  seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  return seed & 0xff;
};
const noisePng = (w: number, h: number): Buffer => {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;
  ihdr[9] = 2; // RGB
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y += 1) {
    raw[y * (w * 3 + 1)] = 0;
    for (let x = 0; x < w * 3; x += 1) raw[y * (w * 3 + 1) + 1 + x] = rand();
  }
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw, { level: 0 })), chunk('IEND', Buffer.alloc(0))]);
};

// data: の画像を count 枚(合わせて約 totalBytes)
const images = (count: number, totalBytes: number): string => {
  const per = Math.floor((totalBytes / count) * 0.74); // base64 で 4/3 になる
  const side = Math.floor(Math.sqrt(per / 3));
  const parts = [head('img { width: 80mm; display: block; margin: 2mm 0; }'), '<h1>画像の見本</h1>'];
  for (let i = 0; i < count; i += 1) parts.push(`<img alt="" src="data:image/png;base64,${noisePng(side, side).toString('base64')}">`);
  parts.push(tail);
  return parts.join('');
};

// PDF が大きくなるもの: ページごとに違うフィルタをかけた画像(Chromium が高い解像度の絵にして埋める)。40 ページで 50MB を超えた
const hugePdf = (pages: number): string => {
  const img = noisePng(700, 700).toString('base64');
  const parts = [head(`.f { width: 180mm; height: 250mm; background-image: url(data:image/png;base64,${img}); background-size: cover; }`)];
  for (let p = 0; p < pages; p += 1) parts.push(`<section class="page"><div class="f" style="filter: hue-rotate(${p * 7}deg) blur(0.4px) saturate(${1 + p / 50})"></div></section>`);
  parts.push(tail);
  return parts.join('');
};

const main = (): void => {
  const out = process.argv[2] ?? 'out/stress';
  mkdirSync(out, { recursive: true });
  const files: Record<string, string> = {
    // 1 回に作るのは 25 ページまで(2026-11-27 理事長。それより多い書類はジョブを分ける。いまは無い)
    'stress-ledger-25': ledgerPages(25),
    'stress-ledger-26': ledgerPages(26),
    'stress-long-table': longTable(1000),
    'stress-awkward': awkward(),
    'stress-glyphs': glyphs(),
    'stress-images-9mb': images(20, 9 * 1024 * 1024),
    'stress-images-11mb': images(20, 11 * 1024 * 1024 + 200 * 1024),
    'stress-huge-pdf': hugePdf(25),
  };
  for (const [name, html] of Object.entries(files)) {
    writeFileSync(join(out, `${name}.html`), html);
    console.log(`${name}\t${Buffer.byteLength(html)}`);
  }
};

main();
