# worktree で並べて開発する

いくつかの Issue を並べて進めるときは、Issue ごとに git の worktree を作る(どんどん使ってよい)。

## 置き場所

- **本体の隣**に置く: `~/work/smalruby/n-bato-<名前>/`(smalruby3-editor と同じ)。
- 本体の中(`.claude/worktrees/` など)には置かない。`.claude/` 以下をコミットするときにじゃまになり、`.gitignore` に足すのも筋が悪い。

## 作る・片づける

```bash
bin/setup-worktree issue-15 refactor/todo-events-15   # 作って、手元だけのファイルをつなぐ
cd ../n-bato-issue-15
# …開発・テスト・コミット…
cd ../n-bato
git worktree remove ../n-bato-issue-15
git branch -d refactor/todo-events-15                 # マージ済みなら
```

- Claude Code の Agent(`isolation: "worktree"`)や EnterWorktree の worktree も、`.claude/settings.json` の WorktreeCreate / WorktreeRemove フック(`bin/claude-worktree`)で同じ場所・同じ作り方になる(ブランチは `topic/<名前>`)。Agent が終わっても worktree は自動では消えないので、マージのあとに上の手順で片づける。
- `bin/setup-worktree` は、`.private-patterns`・`CLAUDE.local.md`・`notes/`・`config/master.key` を本体へのリンクでつなぎ、DB を準備する。
- `data/`(実データ)と `storage/`(手元の DB)はつながない。worktree の DB は、その worktree の中に新しく作る。
- pre-commit のフック(`bin/check-private`)は本体と共通。`.private-patterns` がつながっていないと、手元だけの点検語で調べられない。

## ブランチと PR(autopilot の流れ)

- ブランチは `<種類>/<説明>-<Issue 番号>`(例: `refactor/todo-events-15`、`test/coverage-6`)。
- 1 つの Issue が 1 つのブランチと 1 つの PR。PR は main 向けの Draft で作り、本文に `Closes #<番号>` を書く(🧱 infra の Issue は `Refs #<番号>`)。
- Project 5 の Status は autopilot と同じに動かす: Sprint Backlog → In Progress(AI Status: Understanding → Implementing → Self-Reviewing)→ 自己レビュー(`.claude/skills/nbato-review`、Must / Question / FYI)→ マージ。人が確かめることが残れば Review(🙋 HITL)で人を待つ。
- **マージ(2026-11-24 理事長)**: 自己レビューのあと、人が確かめること(「人間の判断に委ねる」の指摘・人に決めてもらう設計の選択)が残っていない PR は、CI が通っていれば AI がマージしてよい。残っていれば Review(🙋 HITL)にして人を待つ。
- **見送った Q・FYI は EPIC に積む**: 自己レビューで直さなかった Question と FYI(「見送り: …」)は、その都度、親の EPIC の Issue にコメントする(EPIC が無い Issue は、その Issue に)。見出しは「見送った指摘(PR #N)」、1 件ずつ ID・場所・中身・見送った理由。
- **EPIC を閉じるとき**に、その EPIC(と子の Issue)に積んだ「見送った指摘」を拾い、開発QAボード(artifact)に 1 回分としてまとめて人に確かめてもらう。多くは AI の判断のままでよいが、そうでないこともあるため。答えは EPIC に書き写す(`decisions.md`)。EPIC を閉じるのは、その確かめが済んでから。EPIC の無い Issue の見送りは、次の EPIC を閉じるときの回に一緒に入れる。
