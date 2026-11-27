#!/usr/bin/env bash
# 架空のデータの環境(bin/demo、http://localhost:3300)から、PDF にする 6 つの書類の印刷用 HTML を取り出す(実験と見比べの入力。#22)。
#   lambda/pdf-renderer/bench/fetch-demo-html.sh [出力のディレクトリ(既定 bench/out/docs)]
# 実データの開発サーバー(:3000)には向けない。
set -euo pipefail
cd "$(dirname "$0")"
root=$(cd ../../.. && pwd)
out=${1:-out/docs}
base=${NBATO_DEMO_URL:-http://localhost:3300}
case "$base" in http://localhost:3300*|http://127.0.0.1:3300*) ;; *) echo "架空のデータの環境(:3300)だけに向ける" >&2; exit 1 ;; esac
mkdir -p "$out"
jar=$(mktemp); trap 'rm -f "$jar"' EXIT
token=$(curl -sf -c "$jar" "$base/session/new" | sed -n 's/.*name="authenticity_token" value="\([^"]*\)".*/\1/p' | head -1)
curl -sf -b "$jar" -c "$jar" -o /dev/null --data-urlencode "authenticity_token=$token" --data-urlencode "email_address=ai@example.com" \
  --data-urlencode "password=$(cat "$root/tmp/demo_password")" "$base/session"
get() { # 名前 パス
  if curl -sf -b "$jar" -o "$out/$1.html" "$base$2"; then echo "ok   $1"; else echo "skip $1 ($2)"; rm -f "$out/$1.html"; fi
}
year=$(cd "$root" && NBATO_DEMO=1 bin/rails runner -e development 'print AnnualReport.order(:fiscal_year).last&.fiscal_year' 2>/dev/null | tail -1)
fy=$(cd "$root" && NBATO_DEMO=1 bin/rails runner -e development 'print FiscalPeriod.order(:year).last&.year rescue print Date.current.year' 2>/dev/null | tail -1)
for d in letter business_report activity notes balance_sheet inventory officer_roster member_roster; do get "filing-$d" "/annual_reports/$year/documents/$d.html"; done
get "filing-pack" "/annual_reports/$year/pack.html"
for k in activity balance_sheet inventory notes; do get "statement-$k" "/fiscal_years/$fy/statements/$k.html"; done
get "ledgers" "/fiscal_years/$fy/ledgers.html"
code=$(cd "$root" && NBATO_DEMO=1 bin/rails runner -e development "print Account.in_year($fy).order(:code).first&.code" 2>/dev/null | tail -1)
get "ledger-$code" "/fiscal_years/$fy/ledgers/$code.html"
for id in $(cd "$root" && NBATO_DEMO=1 bin/rails runner -e development 'print Resolution.pluck(:id).join(" ")' 2>/dev/null | tail -1); do
  for d in proposal consent_form minutes; do get "resolution-$id-$d" "/resolutions/$id/documents/$d.html"; done
done
for id in $(cd "$root" && NBATO_DEMO=1 bin/rails runner -e development 'print RegistrationFiling.pluck(:id).join(" ")' 2>/dev/null | tail -1); do
  for d in cover mutual_election articles; do get "registration-$id-$d" "/registration_filings/$id/documents/$d.html"; done
done
get "filing-samples" "/filing_samples.html"
