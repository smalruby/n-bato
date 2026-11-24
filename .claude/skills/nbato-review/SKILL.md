---
name: nbato-review
description: n-bato の PR を、別の批判的なレビュアーとして規約(.claude/rules・ADR・デザインシステム)に照らしてレビューし、指摘を Must / Question / FYI に分けて直せるものは直し、残りだけを 1 つのまとめコメントで人に渡す。人が番号で返事をしたら(例「Q1はOK, FYI1は修正して」)、`address` でその番号のものだけに対応する。PR のレビューを頼まれたとき、PR をレビューに出す前に使う。
argument-hint: "<PR 番号> | address <PR 番号>"
---

# nbato-review — PR の敵対的レビューと、返事への対応

smalruby3-editor の autopilot のレビュー(`tools/autopilot/prompts/autopilot-review.md`・`autopilot-address-review.md`)を n-bato に合わせたもの。

- `/nbato-review <PR 番号>` … **レビュー**(手順 A)。直せるものは直し、まとめコメントを 1 つ出し、人のレビューへ回す。
- `/nbato-review address <PR 番号>` … **返事への対応**(手順 B)。人が番号で触れた指摘だけに対応する。

人が見るのは「残ったもの」だけにする。指摘を載せるだけで終わらせず、決まった扱い(下の表)で、できるだけこのレビューの中で直す。

## 前提

- **ほかのスキルを呼ばない。** `/code-review`・`/security-review`・`/simplify` などの、エージェントをいくつも立てるスキルやワークフローは使わない。差分は自分の目で読む(トークンを使いすぎ、許可の確認で止まるため。autopilot の #893 と同じ)。
- **トークン**: リポジトリの操作(PR・Issue・コメント・ラベル)は `GH_TOKEN=$(cat ~/.private/n-bato-dev.pat) gh ...`。Project 5 の書き換えは、いつもの gh のログイン(`GH_TOKEN` を付けない)で行う。いつものログインには n-bato のリポジトリの権限が無く、PAT には org の Project を書く権限が無い(`CLAUDE.local.md`「GitHub」)。
- **外に出る操作**(開発QAボード 第8回 8-10): このスキルを呼んだこと(人が呼ぶ・AI が流れの中で呼ぶ)を、その PR の中の操作の確かめとみなす。中身は、その PR へのコメント・ラベル・Ready・PR のブランチへの push と、PR の Issue の子の Issue を作ること。ほかの PR・`main` には push しない。マージはスキルではしない(マージしてよいかは `.claude/rules/git-workflow.md` の決まりで、流れの側が決める)。
- **団体の情報を書かない**: コメント・Issue・コミットは公開。氏名・住所・金額・内部の予定・非公開のリンク・鍵の値を書かない(`.claude/rules/session-roles.md`)。出す本文(まとめコメント・子の Issue・返事)は、出す前に必ず `bin/check-private --text pr-comment.md < <本文のファイル>` に通す(標準入力を読む)。見つかったら直してから出す。
- 作業は、その PR のブランチの worktree で行う(`.claude/rules/git-workflow.md`)。無ければ `bin/setup-worktree <名前> <PR のブランチ>` で作る。

```bash
REPO=smalruby/n-bato
PR=<PR 番号>
gh_repo() { GH_TOKEN=$(cat ~/.private/n-bato-dev.pat) gh "$@"; }
ISSUE=$(gh_repo pr view "$PR" --repo "$REPO" --json body -q .body | grep -oE '(Closes|Fixes|Refs) #[0-9]+' | head -1 | grep -oE '[0-9]+')
mkdir -p tmp
```

## 手順 A: レビュー

### A1. 読む

1. 差分と PR の本文・会話: `gh_repo pr diff "$PR" --repo "$REPO"`、`gh_repo pr view "$PR" --repo "$REPO" --json title,body,comments,reviews`。
2. **いつも読む**: `CLAUDE.md`、`.claude/rules/*.md`(とくに `code-style.md`)。
3. **触ったところで読む**:

| 触ったファイル | 読むもの |
|---|---|
| `app/models/`・`db/migrate/` | `docs/data-model.md`、ADR-0002〜0007、業務ごとの ADR(0026・0029〜0031 など) |
| `app/controllers/`・`config/routes.rb` | ADR-0008、ADR-0033 |
| `app/views/`・`app/javascript/`・`app/assets/`・`docs/design-system/` | `docs/design-system/README.md`、ADR-0012・0013・0033 |
| `test/` | ADR-0025 |
| `config/procedures/` | 定款で確かめたか(CLAUDE.md「画面の決まり」。条文の番号を推測で書かない) |
| `infra/`・`config/deploy.yml`・`.kamal/`・`bin/prod-*` | ADR-0024・0035、`.claude/rules/session-roles.md` |

### A2. 敵対的にレビューする

差分を「直す前提で疑う」目で読む。とくに次を見る(番号は `.claude/rules/code-style.md` の節):

- **規約からの逸脱**(`code-style.md`・ADR・デザインシステム)。新しく書いたところが、いまの書き方からずれていないか。
- **イベントの決まり**: 新しいイベントの操作した人の列が名詞 + -er か、人が画面で行う出来事の `by:` が必須か(第8回 8-5)。イベントに日時が 1 つだけか・`created_at`/`updated_at` が無いか、`app/` からイベントを `update`・`destroy` していないか、作るのが `event_of ... entry:` の入口だけか、入口が 1 つのトランザクションで操作履歴の名前(`Audit.label!`/`Audit.final!`)まで付けているか、長いイベントのいまの状態を入口の外で書き換えていないか(`model:verify` に照合を足したか)。**[Must]**
- **台帳**: モデルを足したのに `docs/data-model.md` に無い。**[Must]**(テストも落ちる)
- **コントローラー**: 7 つの基本のアクションの外のアクション・ルートを**新しく**足していないか(出来事は入れ子の `resource ... only: :create`。開発QAボード 第8回 8-1)。コントローラーにロジック(業務の確かめ・書き込み)が入っていないか。コントローラーで `Audit.label!`・`Audit.final!` を**新しく**呼んでいないか(操作履歴の名前は入口で付ける。第8回 8-4)。**[Must]**
- **画面**: 見直し票とデザインシステムに無い UI を作っていないか(ADR-0012)。保存ボタンを置いていないか(自動保存。作る画面 new の動詞のボタンだけは例外。第8回 8-2)。色・文字の大きさ・余白がトークン(`var(--…)`)か `nb-` の部品か(並べ方の Tailwind のユーティリティはよい。第8回 8-7)。新しい画面が `nb-` の部品か。元に戻せない操作と消す操作が `confirm-twice` か(ブラウザのダイアログを使わない。第8回 8-3)、元に戻せない操作が `Audit.final!` か。詳しい画面にパンくず、PDF・外のリンクが別のタブ(ADR-0033)か。
- **正確さ**: 境目(年度の 4/1・3/31、締めた年度、監査の役割)、nil、空の文字と nil の違い(NOT NULL の列)、トランザクションの抜け、元に戻すとの食い違い、退行。
- **セキュリティと秘密**: 団体の情報・鍵の値が差分・PR の本文・コメントに入っていたら **[Must]**。認可(監査の役割は閲覧だけ)、入力の確かめ、Brakeman の警告を理由なく消していないか。
- **テスト**: 直接のテストがあるか。外に出る呼び出し(Claude API・Slack・S3・Chrome)を偽物で差し替えているか。テストのデータが架空か。移した業務のファイルのカバレッジが 100% か(ADR-0025。要るときは `COVERAGE=1 bin/rails test`)。
- **重複・複雑さ・効率**: 同じことを 2 か所に書いていないか、N+1、要らない層(サービスオブジェクトなど)。
- **ドキュメントの揃い**: ADR・台帳・デザインシステム・`CLAUDE.md` のコマンド・`config/procedures/` の更新漏れ。
- **🧱 infra**: Issue が `🧱 infra` なのに `infra/` などの外を変えている、本文が `Closes #`(`Refs #` にする)。**[Must]**
- 「いまは動くが、壊れやすい・将来壊れる」作り。

### A3. 分ける(影響の大きさで)

| 分類 | 定義 | 例 |
|---|---|---|
| **Must** | リリースの前に必ず直す。セキュリティの問題・考え漏れ(はっきりした不具合・退行)・規約の決まり(イベント・台帳・7 つのアクション・団体の情報)を破るもの | nil で落ちる、鍵や団体の情報が入っている、イベントを `update` している |
| **Question** | 直したほうがよいが動く。人との相談が要ることがある。めったに起きないが困ることがある | 名前・設計の妥当さ、まれな競合、将来の広げ方 |
| **FYI** | 動き・安全には影響しない改善(重複・冗長・整理の余地・小さな食い違い) | もっと短く書ける、使われなくなったコードや文 |

分類は「直すかどうか」ではなく、**影響の大きさ**で決める。

指摘は 1 件ずつコメントにしない。手元にメモを集める(番号は A6 で機械的に振るので、自分で付けない):

```json
{"category":"Must","location":"app/models/a.rb:10","text":"<何が問題か>","handling":"<どう扱ったか>"}
```

### A4. 扱う(分類ごとの決まり)

| 分類 | 扱い | `handling` に書くこと |
|---|---|---|
| **Must** | **必ず自分で直す** | `修正済み(<sha>)` |
| **Question** | **基本は自分で直す**。よほど大変・効果が小さいと考えて見送るときは、**follow-up の Issue(PR の Issue の子の Issue)を作る**。仕様・方針の選択が人にしかできないもの(どちらの動きにするか、何を残すか)だけは直さずに人に渡す | `修正済み(<sha>)` / `見送り: <理由>。#<番号> で対応` / `人間の判断に委ねる: <選んでほしいこと>` |
| **FYI** | **簡単なら自分で直す**。ただし ①振る舞いが変わる(使う人・呼ぶ側から見える動きや出力が変わる)②設定の値が増える(env・設定・URL のパラメーターなど)③infra(`infra/`・`config/deploy.yml`・`.kamal/`)の変更が要る、のどれかに当たるものは直さない。確かめたことの共有だけのものも直さない | `修正済み(<sha>)` / `見送り: <理由>` / `見送り: 情報共有のみ` |

- 仕様・方針の選択が要る **Must 級**の指摘(直し方そのものが割れる)は、直さずに `人間の判断に委ねる: …` にし、出口の報告でも目立たせる。
- 画面の変更が要る指摘は、直さずに `人間の判断に委ねる: 見直し票で決める` にする(ADR-0012。小さな崩れ・誤字は直してよい)。

**直すとき**: PR のブランチで直し、`bin/rails test`・`bin/standardrb`・`bin/brakeman --no-pager` を通してから、意味のまとまりごとにコミットする(日本語、末尾に `Co-Authored-By:`。pre-commit で `bin/check-private` が動く)。全部直してから push する。

**follow-up の Issue の作り方**(Question を見送るとき):

```bash
# 同じものがあれば作らない
gh_repo issue list --repo "$REPO" --state open --search "<要点> in:title" --json number,title
url=$(gh_repo issue create --repo "$REPO" --title "<題>" \
  --body "<何が問題か・どう直すか・なぜこの PR で見送ったか>"$'\n\n'"Follow-up of #$ISSUE (PR #$PR のレビューの指摘)")
num=$(basename "$url")
dbid=$(gh_repo api "repos/$REPO/issues/$num" --jq .id)
gh_repo api --method POST "repos/$REPO/issues/$ISSUE/sub_issues" -F sub_issue_id="$dbid"
```

- Project 5 には載せない・担当を付けない(載せるかは人が決める)。infra の変更が要るものは `--label "🧱 infra"` を付け、本文に「`infra/` などだけ・前と互換のある変更だけ」「PR は `Refs #<番号>`」と書く。

### A5. 1 つのまとめコメントにする

直したものを push したあとで、**すべての指摘(0 件でも)を 1 つのコメント**にする。本文は `bin/review-findings`(`lib/review_findings.rb`、テストは `test/lib/review_findings_test.rb`)で作る:

- 1 行目に印 `<!-- nbato-review-findings round=N -->`、2 行目に件数(`指摘 N 件(Must a / Question b / FYI c)`)。別の要約のコメントは出さない。
- Must → Question → FYI の見出しごとに `- **[M1]** \`file:line\` 内容 — 扱い`。
- 番号は分類ごとの連番。同じ PR の 2 回目からは**前の回の続き**から振る(1 回目が Q2 までなら 2 回目は Q3 から)。

```bash
gh_repo api "repos/$REPO/issues/$PR/comments" --paginate | jq -s add > tmp/review-comments-$PR.json
# tmp/review-findings-$PR.json に A3 のメモの配列を書いてから:
bin/review-findings render tmp/review-comments-$PR.json tmp/review-findings-$PR.json tmp/review-findings-$PR.md
# 出す前に団体の情報が無いかを調べる(見つかったら直してから出す)
bin/check-private --text pr-comment.md < tmp/review-findings-$PR.md
```

- `POST` と出たら: `gh_repo pr comment "$PR" --repo "$REPO" --body-file tmp/review-findings-$PR.md`
- `PATCH <id>` と出たら: `gh_repo api -X PATCH "repos/$REPO/issues/comments/<id>" -F body=@tmp/review-findings-$PR.md`
- **二重に出さない**: このレビューのまとめコメントをもう出していて(途中で止まったやり直しなど)、そのあとに人のコメントが無ければ、新しい回にせず `REVIEW_ROUND=<N> bin/review-findings render ...` でその回を書き換える。
- **見送った Question・FYI**(「見送り: …」)は、まとめコメントとは別に、親の EPIC の Issue(無ければ PR の Issue)に「見送った指摘(PR #N)」としてコメントする(`.claude/rules/git-workflow.md`)。本文は同じく `bin/check-private --text` に通す。

### A6. 人のレビューへ回す

```bash
gh_repo pr ready "$PR" --repo "$REPO"
gh_repo pr edit "$PR" --repo "$REPO" --add-label "🙋 HITL"
ISSUE_URL="https://github.com/$REPO/issues/$ISSUE"
gh project item-edit 5 --owner smalruby --url "$ISSUE_URL" --field "Status" --value "Review"
gh project item-edit 5 --owner smalruby --url "$ISSUE_URL" --field "AI Status" --clear
```

- Project の 2 行は、いつもの gh のログイン(`GH_TOKEN` を付けない)。Issue が Project に無ければ、書き換えずに報告で伝える。
- 最後に、人に短く報告する: PR の URL、件数(Must a 件を直した / Question b 件 / FYI c 件)、人に渡したもの(`人間の判断に委ねる`)の番号と問い、作った follow-up の Issue。

## 手順 B: 返事への対応(`address`)

人がまとめコメントへ番号で返事をした(PR のコメントか、レビュー)ときに使う。**人が番号で触れた指摘だけ**に対応する。触れなかった指摘は「レビューのときの扱いでよい」と読み、決まり(A4)をもう一度当てない(見送った理由をやり直したり、人の返事より決まりを優先したりしないため)。

### B1. 読む

```bash
gh_repo pr diff "$PR" --repo "$REPO"
gh_repo api "repos/$REPO/issues/$PR/comments" --paginate | jq -s add > tmp/review-comments-$PR.json
gh_repo api "repos/$REPO/pulls/$PR/reviews" --paginate | jq -s add > tmp/review-reviews-$PR.json
gh_repo api "repos/$REPO/pulls/$PR/comments" --paginate | jq -s add > tmp/review-inline-$PR.json
```

直すことになったときのために、A1 と同じものを読んでおく。

### B2. どの返事に対応するかを決める

- 対象は、**いちばん新しいまとめコメントより後の、人(自分の bot・Claude 以外)の返事**(PR のコメント・レビューの本文・行のコメント)。前の `address` が対応した返事は、その対応のまとめ(B4)の印 `<!-- nbato-review-address handled=<コメントやレビューの ID,…> -->` で分かるので、もう一度対応しない。
- 対応する返事が 1 件も無ければ、何もしない(コードにもコメントにも触らない)で、人にそう伝える。
- 返事の本文(古い順)を `tmp/review-replies-$PR.json` に配列で書き、番号ごとの対応を出す:

```bash
bin/review-findings plan tmp/review-comments-$PR.json tmp/review-replies-$PR.json
```

| action | 意味 | 対応 |
|---|---|---|
| `no-change` | 「OK」「そのままで」「直さなくていい」 | 何もしない |
| `fix` | 「修正して」「直して」 | **直す**(FYI でも、言われたら直す) |
| `reply` | 質問・代案 | 返事をし、要るなら直す |

- 番号の表記のゆれ(`Q1`・`q1`・`Question1`、`M1`・`Must1`、`FYI1`・`F1`、全角の数字)は `plan` が受ける。引用の行(`>`)は読まない。同じ番号が何度も出たら後のものを使う。
- **番号の無い指示**(「ここを Z に直して」「テストを足して」): 直す頼みなら直す。質問なら返事をする(要ればコードも変える)。意図がはっきりしない・いくつにも読めるときは、直さずに人に聞く。

### B3. 対応する

- 直すものは、A4 の「直すとき」と同じに直してコミットし、push する。
- 人が「直して」と言ったのに、よほど大変などでこの PR では直せないときは、黙って見送らず、A4 の手順で follow-up の Issue を作り、人に確かめる(人の指示に反するため)。
- 仕様・方針の選択が人にしかできないものは、論点を書いて人に聞く。

### B4. 対応のまとめを 1 つ残す

PR に 1 つのコメントで残す。1 行目に、対応した返事の ID の印を書く:

```
<!-- nbato-review-address handled=<コメントやレビューの ID,…> -->
🤖 返事への対応: 指摘 N 件(直した a 件 / 返事 b 件 / 直さない c 件)
- Q1: 直さない(OK とのこと)
- FYI1: 修正済み(<sha>)
- M2: 返事: …
```

- 直すものが無ければ(すべて「そのままで」など)コミットしない。
- 終わったら、A6 と同じに `🙋 HITL` を付けて Status を Review にし(AI Status は消す)、人に報告する。
