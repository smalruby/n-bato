// results.tsv を、ラベルごとの Markdown の表にする(GitHub Actions のまとめ・PR に貼る)。数だけ。
import { readFileSync } from 'node:fs';

const [file] = process.argv.slice(2);
const lines = readFileSync(file ?? 'bench/out/results.tsv', 'utf8').trim().split('\n');
const cols = lines[0].split('\t');
const rows = lines.slice(1).map((l) => Object.fromEntries(l.split('\t').map((v, i) => [cols[i], v])));
const byLabel = new Map<string, Record<string, string>[]>();
for (const r of rows) byLabel.set(r.label, [...(byLabel.get(r.label) ?? []), r]);

const num = (v: string): number => (v === '' ? NaN : Number(v));
const max = (rs: Record<string, string>[], k: string): string => {
  const ns = rs.map((r) => num(r[k])).filter((n) => !Number.isNaN(n));
  return ns.length ? String(Math.max(...ns)) : '';
};

console.log('## ラベルごと\n');
console.log('| ラベル | メモリ | CPU | 入力 | ok | 失敗(コード) | cgroup の山(最大 MB) | 関数の中の山(最大 MB) | heapUsed(最大) | 時間(最大 ms) | /dev/shm |');
console.log('|---|---|---|---|---|---|---|---|---|---|---|');
for (const [label, rs] of byLabel) {
  const ok = rs.filter((r) => r.status === 'ok').length;
  const fails = rs.filter((r) => r.status !== 'ok').map((r) => `${r.input}:${r.code || r.status}`).join(', ');
  console.log(`| ${label} | ${rs[0].memory_mb} | ${rs[0].cpus} | ${rs.length} | ${ok} | ${fails || '—'} | ${max(rs, 'cgroup_peak_mb')} | ${max(rs, 'fn_peak_mb')} | ${max(rs, 'heap_used_mb')} | ${max(rs, 'invoke_ms')} | ${rs[0].dev_shm_mb || 'なし'} |`);
}
console.log('\n## 行ごと\n');
const show = ['label', 'input', 'status', 'code', 'pages', 'pdfinfo_pages', 'bytes', 'cgroup_peak_mb', 'fn_peak_mb', 'node_rss_mb', 'chromium_rss_mb', 'heap_used_mb', 'oom_killed', 'invoke_ms', 'launch_ms', 'render_ms', 'missing_glyphs', 'fonts'];
console.log(`| ${show.join(' | ')} |`);
console.log(`|${show.map(() => '---').join('|')}|`);
for (const r of rows) console.log(`| ${show.map((k) => r[k] ?? '').join(' | ')} |`);
