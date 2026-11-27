#!/usr/bin/env bash
# Chromium が立ち上がらないときの切り分け(#22)。CI(x86_64 の ubuntu)で流す。中身は空の data: のページだけ。
#   bench/debug-launch.sh [イメージ]
set -uo pipefail
cd "$(dirname "$0")/.."
IMAGE=${1:-n-bato-pdf-renderer:dev}
URL='data:text/html,<p>ok</p>'
try() {
  local name=$1; shift
  echo "=== $name"
  local t0=$SECONDS
  timeout 40 "$@" > /tmp/dbg.out 2>&1
  echo "--- 終わり: $? ($((SECONDS - t0)) 秒)"
  tail -n 15 /tmp/dbg.out | cut -c1-300
}
# 1. @sparticuz/chromium の勧めどおり(実行のときに /tmp へ展開・その包みの旗)。Lambda の素のイメージで
cat > /tmp/sp.js <<'JS'
const { spawnSync } = require('child_process');
(async () => {
  const c = (await import('/w/node_modules/@sparticuz/chromium/build/index.js')).default;
  const exe = await c.executablePath();
  const r = spawnSync(exe, [...c.args, '--user-data-dir=/tmp/p', '--dump-dom', process.argv[2]], { encoding: 'utf8', timeout: 30000 });
  console.log('status', r.status, r.signal, 'out', (r.stdout || '').slice(0, 200), 'err', (r.stderr || '').slice(-1500));
})();
JS
try upstream docker run --rm -v "$PWD:/w:ro" -v /tmp/sp.js:/sp.js:ro -e AWS_EXECUTION_ENV=AWS_Lambda_nodejs22.x --entrypoint node public.ecr.aws/lambda/nodejs:22 /sp.js "$URL"
# 2. このイメージ(/opt/chromium)。制限なし
base=(--no-sandbox --no-zygote --user-data-dir=/tmp/p --enable-logging=stderr --v=0)
try image-plain docker run --rm --entrypoint /opt/chromium/chromium "$IMAGE" --headless "${base[@]}" --dump-dom "$URL"
try image-shell-swiftshader docker run --rm --entrypoint /opt/chromium/chromium "$IMAGE" "--headless=shell" "${base[@]}" --in-process-gpu --use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader --dump-dom "$URL"
try image-single docker run --rm --entrypoint /opt/chromium/chromium "$IMAGE" --headless "${base[@]}" --single-process --disable-gpu --dump-dom "$URL"
try image-no-fontconfig docker run --rm -e FONTCONFIG_FILE=/nonexistent --entrypoint /opt/chromium/chromium "$IMAGE" --headless "${base[@]}" --dump-dom "$URL"
# 3. 外(ubuntu の上)で strace。どこで止まるか
rm -rf /tmp/cr && mkdir -p /tmp/cr && id=$(docker create "$IMAGE") && docker cp "$id:/opt/chromium/." /tmp/cr/ && docker cp "$id:/var/task/fonts" /tmp/cr-fonts && docker rm "$id" >/dev/null
sed 's#/var/task/fonts#/tmp/cr-fonts#' /tmp/cr-fonts/fonts.conf > /tmp/cr-fonts/host.conf
try host-strace env LD_LIBRARY_PATH=/tmp/cr/lib:/tmp/cr FONTCONFIG_FILE=/tmp/cr-fonts/host.conf strace -f -tt -o /tmp/strace.txt /tmp/cr/chromium --headless "${base[@]}" --dump-dom "$URL"
echo "=== strace の終わりのほう(futex と epoll を除く)"
grep -v -E 'futex|epoll_wait|restart_syscall' /tmp/strace.txt | tail -n 80 | cut -c1-250
echo "=== strace で開けなかったもの"
grep -E 'ENOENT|EACCES|EPERM' /tmp/strace.txt | grep -v -E '\.(so|pak)' | awk '{$1="";$2="";print}' | sort | uniq -c | sort -rn | head -40 | cut -c1-250
