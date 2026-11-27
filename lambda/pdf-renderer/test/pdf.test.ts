import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { countPdfPages } from '../src/pdf';
import { fakePdf } from './helpers';

const write = (buf: Buffer): string => {
  const p = join(mkdtempSync(join(tmpdir(), 'pdf-count-')), 'a.pdf');
  writeFileSync(p, buf);
  return p;
};

test('/Type /Pages の /Count を読む', async () => {
  expect(await countPdfPages(write(fakePdf(7)))).toBe(7);
  expect(await countPdfPages(write(fakePdf(301)))).toBe(301);
});

test('/Count が無ければ /Type /Page を数える(塊の境目をまたいでも二重に数えない)', async () => {
  const obj = '<< /Type /Page /Parent 2 0 R >>\n';
  const pad = 'x'.repeat((1 << 20) - 10); // 1MB の塊の境目に掛かるように
  const p = write(Buffer.from(`%PDF-1.4\n${pad}${obj}${obj}${obj}`, 'latin1'));
  expect(await countPdfPages(p)).toBe(3);
});
