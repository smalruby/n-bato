// PDF のページ数を数える。Chromium(Skia)の PDF は、ページのオブジェクトを "/Type /Page" で書く(オブジェクトストリームに入れない)。
// まず "/Type /Pages" の "/Count N" を探し(いちばん大きい値が全体)、無ければ "/Type /Page" を数える。
// 実験とテスト(bin/pdf-golden の pdfinfo)で、数え方が合うことを確かめる。
import { createReadStream } from 'node:fs';

export const countPdfPages = async (path: string): Promise<number> => {
  let maxCount = 0;
  let pageObjects = 0;
  let carry = '';
  for await (const chunk of createReadStream(path, { encoding: 'latin1', highWaterMark: 1 << 20 })) {
    const text = carry + (chunk as string);
    for (const m of text.matchAll(/\/Type\s*\/Pages\b[^>]*?\/Count\s+(\d+)|\/Count\s+(\d+)[^>]*?\/Type\s*\/Pages\b/g)) {
      maxCount = Math.max(maxCount, Number(m[1] ?? m[2]));
    }
    // 前の塊で数え終えたもの(末尾が carry の中で終わるもの)は数えない
    for (const m of text.matchAll(/\/Type\s*\/Page(?![a-zA-Z])/g)) {
      if (m.index + m[0].length > carry.length) pageObjects += 1;
    }
    carry = text.slice(-256);
  }
  return maxCount > 0 ? maxCount : pageObjects;
};
