// テストの道具: 偽物のブラウザ・要求の組み立て(docs/design/pdf-lambda.md 7.1)
import { createHash } from 'node:crypto';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { S3Client } from '@aws-sdk/client-s3';
import config from '../config.json';
import { BrowserLike, Deps, PageLike, PdfRequest, RequestLike, rendererId } from '../src/handler';

export const BUCKET = 'n-bato-pdf-test';
export const CANARY = 'CANARY-7f3a9c-氏名の目印';

export const fakePdf = (pages: number, padBytes = 0): Buffer =>
  Buffer.from(
    `%PDF-1.4\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n2 0 obj << /Type /Pages /Kids [] /Count ${pages} >> endobj\n` +
      `${Array.from({ length: Math.min(pages, 5) }, (_, i) => `${i + 3} 0 obj << /Type /Page /Parent 2 0 R >> endobj\n`).join('')}` +
      `${'%'.repeat(padBytes)}\n%%EOF\n`,
    'latin1',
  );

export const htmlWith = (body: string): string => `<!doctype html><html><head><meta charset="utf-8"><style>body{font-family:serif}</style></head><body>${body}</body></html>`;

export const requestFor = (html: string, over: Partial<PdfRequest> = {}): PdfRequest => {
  const bytes = Buffer.from(html, 'utf8');
  const inputKey = createHash('sha256').update(`key:${html}`).digest('hex');
  return {
    protocol: 1,
    request_id: 'pdf-12-a1',
    input_key: inputKey,
    input: { bucket: BUCKET, key: `v1/in/12-${inputKey}.html`, sha256: createHash('sha256').update(bytes).digest('hex'), bytes: bytes.length },
    output_prefix: `v1/out/${inputKey}/`,
    options: { format: 'A4', print_background: true, prefer_css_page_size: true },
    limits: { max_pages: 300, max_output_bytes: 52428800 },
    deadline_at: Date.now() + 600_000,
    ...over,
  };
};

export type FakeBrowserOptions = {
  pdf?: Buffer;
  requests?: string[]; // setContent のときに出る要求の URL
  setContent?: () => Promise<void>;
  createPDFStream?: () => Promise<ReadableStream<Uint8Array>>;
  closeHangs?: boolean;
};

export class FakeBrowser implements BrowserLike {
  connected = true;
  closed = false;
  jsEnabled: boolean | null = null;
  interception: boolean | null = null;
  pdfOptions: Record<string, unknown> | null = null;
  aborted: string[] = [];
  continued: string[] = [];
  killed: NodeJS.Signals[] = [];

  constructor(private readonly opts: FakeBrowserOptions = {}) {}

  async newPage(): Promise<PageLike> {
    let onRequest: ((r: RequestLike) => void) | null = null;
    const self = this;
    return {
      async setJavaScriptEnabled(v: boolean) {
        self.jsEnabled = v;
      },
      async setRequestInterception(v: boolean) {
        self.interception = v;
      },
      on(_event: 'request', handler: (r: RequestLike) => void) {
        onRequest = handler;
        return this;
      },
      async setContent() {
        for (const url of self.opts.requests ?? []) {
          onRequest?.({
            url: () => url,
            abort: async () => void self.aborted.push(url),
            continue: async () => void self.continued.push(url),
          });
        }
        if (self.opts.setContent) await self.opts.setContent();
      },
      async createPDFStream(options: Record<string, unknown>) {
        self.pdfOptions = options;
        if (self.opts.createPDFStream) return self.opts.createPDFStream();
        const pdf = self.opts.pdf ?? fakePdf(2);
        return new ReadableStream<Uint8Array>({
          start(controller) {
            for (let i = 0; i < pdf.length; i += 65536) controller.enqueue(new Uint8Array(pdf.subarray(i, i + 65536)));
            controller.close();
          },
        });
      },
      async close() {},
    };
  }

  async close(): Promise<void> {
    if (this.opts.closeHangs) return new Promise(() => undefined);
    this.closed = true;
  }

  process() {
    return { pid: undefined, kill: (s?: NodeJS.Signals) => (this.killed.push(s ?? 'SIGTERM'), true) };
  }
}

export const makeDeps = (s3: S3Client, browser: FakeBrowser | (() => Promise<BrowserLike>), over: Partial<Deps> = {}) => {
  const logs: string[] = [];
  const tmpRoot = mkdtempSync(join(tmpdir(), 'pdf-test-'));
  const launches: unknown[] = [];
  const deps: Deps = {
    config: { ...config },
    env: { PDF_BUCKET: BUCKET, CHROMIUM_PATH: '/opt/chromium/chrome-headless-shell', AWS_SECRET_ACCESS_KEY: 'must-not-leak', PATH: '/usr/bin' },
    now: () => Date.now(),
    log: (l) => logs.push(l),
    tmpRoot,
    renderer: { build: 'test', chromium: '158', puppeteer: '25.19.0', font_digest: 'abc', renderer_id: rendererId('test', 'abc') },
    coverage: [[0x20, 0x7e], [0x3040, 0x30ff], [0x4e00, 0x9fff]],
    s3: () => s3,
    launch: async (o) => {
      launches.push(o);
      return typeof browser === 'function' ? browser() : browser;
    },
    ...over,
  };
  return { deps, logs, tmpRoot, launches };
};

export const context = (remainingMs = 85_000) => ({ getRemainingTimeInMillis: () => remainingMs, memoryLimitInMB: '1024' });
