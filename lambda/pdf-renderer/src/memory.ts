// メモリの山を測る(docs/design/pdf-lambda.md 4.2)。正は Lambda の REPORT の Max Memory Used。
// ここでは 100 ミリ秒ごとに、Node と Chromium のプロセスグループの各プロセスの PSS を足し、その最大を取る。
// PSS(/proc/<pid>/smaps_rollup)は共有のページを使うプロセスの数で割るので、足しても重ならない。
// VmRSS を足すと共有のページを何度も数え、コンテナの山(cgroup の memory.peak)より 300MB ほど大きく出た(P1 の実験 ④、2026-11-27)。
// smaps_rollup が読めないとき(古いカーネル)は VmRSS。heapUsed は使わない(過去の不具合: JS のヒープだけを見ていた)。
// Linux でないとき(テスト)は Node の RSS だけ。
import { readdirSync, readFileSync } from 'node:fs';

const KB = 1024;

export const pssKb = (pid: number | 'self'): number => {
  try {
    const m = /^Pss:\s+(\d+)\s+kB/m.exec(readFileSync(`/proc/${pid}/smaps_rollup`, 'utf8'));
    if (m) return Number(m[1]);
  } catch {
    // 読めないときは VmRSS
  }
  return vmRssKb(pid);
};

export const vmRssKb = (pid: number | 'self'): number => {
  try {
    const m = /VmRSS:\s+(\d+)\s+kB/.exec(readFileSync(`/proc/${pid}/status`, 'utf8'));
    return m ? Number(m[1]) : 0;
  } catch {
    return 0;
  }
};

// /proc/<pid>/stat の 5 つ目(pgrp)。comm に空白や括弧が入りうるので、最後の ")" のあとから数える
export const pgrpOf = (stat: string): number | null => {
  const rest = stat.slice(stat.lastIndexOf(')') + 2).split(' ');
  const pgrp = Number(rest[2]);
  return Number.isInteger(pgrp) ? pgrp : null;
};

export const groupPids = (pgrp: number): number[] => {
  let entries: string[];
  try {
    entries = readdirSync('/proc');
  } catch {
    return [];
  }
  const pids: number[] = [];
  for (const e of entries) {
    if (!/^\d+$/.test(e)) continue;
    try {
      if (pgrpOf(readFileSync(`/proc/${e}/stat`, 'utf8')) === pgrp) pids.push(Number(e));
    } catch {
      // 読む間に終わったプロセス
    }
  }
  return pids;
};

export type MemorySample = { totalMb: number; nodeRssMb: number; chromiumRssMb: number; heapUsedMb: number };

export class MemorySampler {
  peak: MemorySample = { totalMb: 0, nodeRssMb: 0, chromiumRssMb: 0, heapUsedMb: 0 };
  private timer: NodeJS.Timeout | null = null;
  private pgrp: number | null = null;

  constructor(private readonly intervalMs: number) {}

  start(): void {
    this.sample();
    this.timer = setInterval(() => this.sample(), this.intervalMs);
    this.timer.unref();
  }

  watchGroup(pgrp: number | null | undefined): void {
    this.pgrp = pgrp ?? null;
    this.sample();
  }

  sample(): void {
    const mu = process.memoryUsage();
    const chromiumKb = this.pgrp ? groupPids(this.pgrp).reduce((sum, pid) => sum + pssKb(pid), 0) : 0;
    const nodeKb = pssKb('self') || mu.rss / KB;
    const s: MemorySample = {
      nodeRssMb: nodeKb / KB,
      chromiumRssMb: chromiumKb / KB,
      heapUsedMb: mu.heapUsed / KB / KB,
      totalMb: nodeKb / KB + chromiumKb / KB,
    };
    this.peak = {
      totalMb: Math.max(this.peak.totalMb, s.totalMb),
      nodeRssMb: Math.max(this.peak.nodeRssMb, s.nodeRssMb),
      chromiumRssMb: Math.max(this.peak.chromiumRssMb, s.chromiumRssMb),
      heapUsedMb: Math.max(this.peak.heapUsedMb, s.heapUsedMb),
    };
  }

  stop(): MemorySample {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    this.sample();
    return this.peak;
  }
}
