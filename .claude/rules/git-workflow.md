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
- Project 5 の Status は autopilot と同じに動かす: Sprint Backlog → In Progress(AI Status: Understanding → Implementing → Self-Reviewing)→ Review(🙋 HITL、人がレビュー)→ DoD(Playwright で確かめる)→ 人がマージ。
- マージは人がする。AI はマージしない。
