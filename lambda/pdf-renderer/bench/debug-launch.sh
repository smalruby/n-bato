#!/usr/bin/env bash
# Chromium が立ち上がらないときの切り分け(#22)。CI(x86_64 の ubuntu)で流す。中身は空の data: のページだけ。
# @sparticuz/chromium の版ごとに、包みの勧めどおり(Lambda の素のイメージ・実行のときに /tmp へ展開・包みの旗)で立ち上げて比べる。
#   bench/debug-launch.sh [版 …]
set -uo pipefail
versions=("${@:-158.0.0 153.0.0 147.0.2 143.0.4}")
read -r -a versions <<< "${versions[*]}"
cat > /tmp/sp.js <<'JS'
const { spawnSync } = require('child_process');
const { createRequire } = require('module');
const { pathToFileURL } = require('url');
(async () => {
  const m = await import(pathToFileURL(createRequire(process.argv[2] + '/').resolve('@sparticuz/chromium')).href);
  const c = m.default ?? m;
  const exe = await c.executablePath();
  for (const [name, extra] of [
    ['dump-dom', ['--dump-dom', 'data:text/html,<p>ok</p>']],
    ['print-to-pdf', ['--print-to-pdf=/tmp/o.pdf', '--no-pdf-header-footer', 'data:text/html,<p>ok</p>']],
    ['dump-dom-single', ['--single-process', '--dump-dom', 'data:text/html,<p>ok</p>']],
    ['dump-dom-verbose', ['--enable-logging=stderr', '--v=1', '--dump-dom', 'about:blank']],
  ]) {
    const t0 = Date.now();
    const r = spawnSync(exe, [...c.args, '--user-data-dir=/tmp/p-' + name, ...extra], { encoding: 'utf8', timeout: 25000 });
    console.log(`${name}: status=${r.status} signal=${r.signal} ${Date.now() - t0}ms out=${JSON.stringify((r.stdout || '').slice(0, 80))} err=${JSON.stringify((r.stderr || '').slice(name.endsWith('verbose') ? -3000 : -400))}`);
  }
})();
JS
for v in "${versions[@]}"; do
  echo "=== @sparticuz/chromium $v"
  d=/tmp/sp-$v; rm -rf "$d"; mkdir -p "$d"
  (cd "$d" && npm init -y >/dev/null && npm i --no-audit --no-fund --silent "@sparticuz/chromium@$v" >/dev/null)
  timeout 120 docker run --rm -v "$d:/w:ro" -v /tmp/sp.js:/sp.js:ro -e AWS_EXECUTION_ENV=AWS_Lambda_nodejs22.x --entrypoint node public.ecr.aws/lambda/nodejs:22 /sp.js /w 2>&1 | grep -v -E 'Pulling|Already exists|Digest|Status:|Unable to find|Pull complete|Download|Verifying|Waiting' | cut -c1-600
done
