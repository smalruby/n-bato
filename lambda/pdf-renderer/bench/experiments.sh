#!/usr/bin/env bash
# P1 の実験 ①〜⑤ を順に流す(docs/design/pdf-lambda.md 4.10)。x86_64 の Linux(GitHub Actions の ubuntu)で流す。
# Mac(arm64)の Docker は x86_64 を Rosetta でまねるが、その上では Chromium 158 が立ち上がらない(CPU を使わずに止まる。2026-11-27 に確かめた)。
#   bench/experiments.sh [①〜⑤ のうち流すもの(既定 all)]
# 前に: docker build -t n-bato-pdf-renderer:dev .、bench/fetch-demo-html.sh(架空のデータの 6 つの書類)、node out/bench/stress.js bench/out/stress
set -euo pipefail
cd "$(dirname "$0")/.."
which=${1:-all}
run() { node out/bench/run.js "$@"; }
docs=(bench/out/docs/*.html)
stress=(bench/out/stress/*.html)
heavy=(bench/out/stress/stress-ledger-300.html bench/out/stress/stress-long-table.html bench/out/stress/stress-images-9mb.html bench/out/stress/stress-huge-pdf.html bench/out/stress/stress-awkward.html bench/out/docs/filing-pack.html bench/out/docs/ledgers.html)

# 0 まず 1 つの書類で立ち上がるかを見る。だめなら Chromium のログを出して止める(すべての実験が同じ理由で落ちるのを待たない)
run --label e0-smoke --memory 1024 bench/out/docs/ledgers.html
if ! tail -n 1 bench/out/results.tsv | cut -f12 | grep -qx ok; then
  echo "立ち上がらない。Chromium のログ:" >&2
  cat bench/out/pdf/e0-smoke/ledgers.log >&2
  exit 1
fi

if [[ $which == all || $which == 1 ]]; then
  # ① Chromium の側のメモリの上限(第一の候補)。関数のメモリは 1024MB に固定
  run --label e1-base --memory 1024 "${heavy[@]}"
  run --label e1-no-disable-dev-shm --memory 1024 --remove --disable-dev-shm-usage "${heavy[@]}"
  run --label e1-no-disable-dev-shm-with-shm64 --memory 1024 --remove --disable-dev-shm-usage --shm "${heavy[@]}"
  run --label e1-js-heap-96 --memory 1024 --add --js-flags=--max-old-space-size=96 "${heavy[@]}"
  run --label e1-js-heap-2048 --memory 1024 --add --js-flags=--max-old-space-size=2048 "${heavy[@]}"
  run --label e1-single-process --memory 1024 --add --single-process "${heavy[@]}"
fi
if [[ $which == all || $which == 2 ]]; then
  # ② PDF の受け取り方(一度に / ストリーム)
  run --label e2-buffer --memory 1024 --receive buffer bench/out/stress/stress-huge-pdf.html bench/out/stress/stress-images-9mb.html bench/out/stress/stress-ledger-300.html
  run --label e2-stream --memory 1024 --receive stream bench/out/stress/stress-huge-pdf.html bench/out/stress/stress-images-9mb.html bench/out/stress/stress-ledger-300.html
fi
if [[ $which == all || $which == 3 ]]; then
  # ③ /tmp の大きさ(/dev/shm のあるなしは記録の dev_shm_mb)
  run --label e3-tmp-512 --memory 1024 --tmp 512 bench/out/stress/stress-huge-pdf.html bench/out/stress/stress-ledger-300.html
fi
if [[ $which == all || $which == 5 ]]; then
  # ⑤ 関数のメモリをどこまで下げられるか(すべての書類とストレス)。④ の測り方の並びは、どの行にもある
  for mem in 512 768 1024 1536; do
    run --label "e5-mem-$mem" --memory "$mem" "${docs[@]}" "${stress[@]}"
  done
fi
node out/bench/summary.js bench/out/results.tsv
