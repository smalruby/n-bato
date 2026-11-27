#!/usr/bin/env bash
# Chromium が立ち上がらないときの切り分け、その 2(#22)。CI の ubuntu の上でじかに。
#   bench/debug-launch2.sh <イメージ>
set -uo pipefail
IMAGE=${1:-n-bato-pdf-renderer:dev}
URL='data:text/html,<p>ok</p>'
sudo apt-get install -y -qq gdb >/dev/null 2>&1
rm -rf /tmp/cr /tmp/cr-fonts && mkdir -p /tmp/cr && id=$(docker create "$IMAGE") && docker cp "$id:/opt/chromium/." /tmp/cr/ && docker cp "$id:/var/task/fonts" /tmp/cr-fonts && docker rm "$id" >/dev/null
echo "=== 比べ: Playwright の chromium-headless-shell(同じ ubuntu の上)"
npx --yes playwright@1 install chromium-headless-shell >/dev/null 2>&1
hs=$(find ~/.cache/ms-playwright -type f \( -name headless_shell -o -name chrome-headless-shell \) 2>/dev/null | head -1)
echo "headless_shell: $hs"
t0=$SECONDS; timeout 25 "$hs" --no-sandbox --dump-dom "$URL" 2>&1 | tail -3; echo "終わり: $? ($((SECONDS - t0)) 秒)"
echo "=== Playwright の headless_shell を、@sparticuz と同じ旗で"
t0=$SECONDS; timeout 25 "$hs" --headless --no-sandbox --no-zygote --in-process-gpu --use-gl=angle --use-angle=swiftshader --user-data-dir=/tmp/p0 --dump-dom "$URL" 2>&1 | tail -3; echo "終わり: $? ($((SECONDS - t0)) 秒)"
echo "=== @sparticuz の Chromium(ubuntu の上でじかに)"
export LD_LIBRARY_PATH=/tmp/cr/lib:/tmp/cr
t0=$SECONDS; timeout 25 /tmp/cr/chromium --headless --no-sandbox --no-zygote --user-data-dir=/tmp/p1 --dump-dom "$URL" 2>&1 | tail -3; echo "終わり: $? ($((SECONDS - t0)) 秒)"
echo "=== 止まったところのスタック(10 秒後)"
/tmp/cr/chromium --headless --no-sandbox --no-zygote --single-process --user-data-dir=/tmp/p2 --dump-dom "$URL" > /tmp/o.txt 2>&1 &
pid=$!; sleep 10
sudo gdb -p "$pid" -batch -ex "set pagination off" -ex "thread apply all bt 8" > /tmp/gdb.txt 2>/dev/null
grep -E "^Thread" /tmp/gdb.txt | cut -c1-120
echo "--- 1〜10 番のスレッド"
awk '/^Thread [0-9]+ /{n=$2} n<=10' /tmp/gdb.txt | grep -E "^Thread|^#" | cut -c1-200
echo "--- 開いているもの"
ls -l /proc/$pid/fd 2>/dev/null | awk '{print $NF}' | sort | uniq -c | sort -rn | head -20
kill -9 "$pid" 2>/dev/null
echo "=== ldd で見つからないもの"
ldd /tmp/cr/chromium | grep -i "not found"
echo "=== ファイル"
ls -la /tmp/cr | head -30
