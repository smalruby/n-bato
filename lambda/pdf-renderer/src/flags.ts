// Chromium の起動の旗(docs/design/pdf-lambda.md 3.2・4.1)。
// puppeteer の既定の旗は使わず(ignoreDefaultArgs: true)、ここの一覧だけで起こす。一覧そのものを test/flags.test.ts で固定する。
// もとは puppeteer-core 25.19.0 の既定と @sparticuz/chromium 158.0.0 の chromium.args。
// 外したもの: --disable-web-security・--allow-running-insecure-content(通信の禁止を弱めるため)、
//   --enable-automation・--auto-open-devtools-for-tabs など、PDF に要らないもの。
// メモリに効く旗(--disable-dev-shm-usage・--js-flags・--single-process)は実験 ①(4.10)で決めた。結果は docs/design/pdf-lambda.md 4.10。
export const CHROMIUM_FLAGS: readonly string[] = Object.freeze([
  // puppeteer-core の既定から
  '--allow-pre-commit-input',
  '--disable-background-networking',
  '--disable-background-timer-throttling',
  '--disable-backgrounding-occluded-windows',
  '--disable-breakpad',
  '--disable-client-side-phishing-detection',
  '--disable-component-extensions-with-background-pages',
  '--disable-component-update',
  '--disable-crash-reporter',
  '--disable-default-apps',
  '--disable-dev-shm-usage',
  '--disable-extensions',
  '--disable-hang-monitor',
  '--disable-infobars',
  '--disable-ipc-flooding-protection',
  '--disable-popup-blocking',
  '--disable-prompt-on-repost',
  '--disable-renderer-backgrounding',
  '--disable-search-engine-choice-screen',
  '--disable-sync',
  '--export-tagged-pdf',
  '--force-color-profile=srgb',
  '--generate-pdf-document-outline',
  '--metrics-recording-only',
  '--no-first-run',
  '--password-store=basic',
  '--use-mock-keychain',
  '--hide-scrollbars',
  '--mute-audio',
  // @sparticuz/chromium の chromium.args から(Lambda で動かすため)
  '--disable-domain-reliability',
  '--disable-print-preview',
  '--disk-cache-size=33554432',
  '--no-default-browser-check',
  '--no-pings',
  '--font-render-hinting=none',
  '--disable-features=AudioServiceOutOfProcess,IsolateOrigins,site-per-process,Translate,MediaRouter,OptimizationHints',
  '--ignore-gpu-blocklist',
  '--in-process-gpu',
  '--disable-webgl',
  '--disable-setuid-sandbox',
  '--disable-site-isolation-trials',
  '--headless',
  '--no-sandbox',
  '--no-zygote',
]);

// 決して付けない旗(通信の禁止を弱める・中を見せる)。テストで、一覧に無いことを確かめる
export const FORBIDDEN_FLAGS: readonly string[] = Object.freeze([
  '--disable-web-security',
  '--allow-running-insecure-content',
  '--remote-debugging-port',
  '--remote-allow-origins',
  '--enable-automation',
  '--allow-file-access-from-files',
]);

// 実験のとき(PDF_EXPERIMENT=1)だけ、環境変数で旗を足し引きする(本番では読まない)
export const chromiumFlags = (env: NodeJS.ProcessEnv = process.env): string[] => {
  const flags = [...CHROMIUM_FLAGS];
  if (env.PDF_EXPERIMENT !== '1') return flags;
  const remove = (env.PDF_FLAGS_REMOVE ?? '').split(/\s+/).filter(Boolean);
  const add = (env.PDF_FLAGS_ADD ?? '').split(/\s+/).filter(Boolean);
  const kept = flags.filter((f) => !remove.some((r) => f === r || f.startsWith(`${r}=`)));
  const out = [...kept, ...add];
  for (const f of out) {
    if (FORBIDDEN_FLAGS.some((x) => f === x || f.startsWith(`${x}=`))) throw new Error('forbidden flag in experiment');
  }
  return out;
};
