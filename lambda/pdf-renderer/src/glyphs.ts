// 豆腐(□)を見つける(docs/design/pdf-lambda.md 4.9)。
// イメージを作るときに fc-query で書き出した、フォントが持つ字の範囲(coverage.txt。"20-7e a0 3000-30ff …" の形)を読み、
// HTML の文の字のうち、どのフォントにも無い字の種類を数える。返すのは数と U+XXXX だけ(どの文の字かは返さない)。
import { readFileSync } from 'node:fs';

export type Coverage = Array<[number, number]>; // 並べた [始め, 終わり](両端を含む)

export const parseCoverage = (text: string): Coverage => {
  const ranges: Coverage = [];
  for (const token of text.split(/\s+/).filter(Boolean)) {
    const m = /^([0-9a-fA-F]+)(?:-([0-9a-fA-F]+))?$/.exec(token);
    if (!m) throw new Error('bad coverage token');
    const a = parseInt(m[1], 16);
    const b = m[2] ? parseInt(m[2], 16) : a;
    ranges.push([a, b]);
  }
  ranges.sort((x, y) => x[0] - y[0]);
  const merged: Coverage = [];
  for (const r of ranges) {
    const last = merged[merged.length - 1];
    if (last && r[0] <= last[1] + 1) last[1] = Math.max(last[1], r[1]);
    else merged.push([r[0], r[1]]);
  }
  return merged;
};

export const loadCoverage = (path: string): Coverage | null => {
  try {
    return parseCoverage(readFileSync(path, 'utf8'));
  } catch {
    return null;
  }
};

export const covers = (coverage: Coverage, cp: number): boolean => {
  let lo = 0;
  let hi = coverage.length - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    const [a, b] = coverage[mid];
    if (cp < a) hi = mid - 1;
    else if (cp > b) lo = mid + 1;
    else return true;
  }
  return false;
};

const NAMED: Record<string, string> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };

// タグ・<style>・<script>・コメントを除いた文(属性の値は数えない)
export const textOf = (html: string): string =>
  html
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .replace(/<(style|script|title)\b[\s\S]*?<\/\1\s*>/gi, ' ')
    .replace(/<[^>]*>/g, ' ')
    .replace(/&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/g, (all, ref: string) => {
      if (ref[0] === '#') {
        const cp = ref[1] === 'x' || ref[1] === 'X' ? parseInt(ref.slice(2), 16) : parseInt(ref.slice(1), 10);
        return cp >= 0 && cp <= 0x10ffff ? String.fromCodePoint(cp) : ' ';
      }
      return NAMED[ref] ?? all;
    });

// 数えない字: 空白・改行・制御文字・異体字セレクタ・幅のない結合子など(字形を持たない)
const ignored = (cp: number): boolean =>
  cp <= 0x20 ||
  (cp >= 0x7f && cp <= 0xa0) ||
  (cp >= 0x200b && cp <= 0x200f) ||
  (cp >= 0x2028 && cp <= 0x202e) ||
  cp === 0x2060 ||
  cp === 0x3000 ||
  cp === 0xfeff ||
  (cp >= 0xfe00 && cp <= 0xfe0f) ||
  (cp >= 0xe0100 && cp <= 0xe01ef);

export const missingGlyphs = (html: string, coverage: Coverage | null, max: number): { count: number; codepoints: string[] } => {
  if (!coverage) return { count: 0, codepoints: [] };
  const missing = new Set<number>();
  for (const ch of textOf(html)) {
    const cp = ch.codePointAt(0)!;
    if (!ignored(cp) && !covers(coverage, cp)) missing.add(cp);
  }
  const sorted = [...missing].sort((a, b) => a - b);
  return {
    count: sorted.length,
    codepoints: sorted.slice(0, max).map((cp) => `U+${cp.toString(16).toUpperCase().padStart(4, '0')}`),
  };
};
