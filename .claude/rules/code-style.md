# コードの書き方(いまの実装から起こした決まり)

いまのコードがそろってしている書き方を、決まりとして書き起こしたもの(2026-11-24)。コードがそろっていなかったところは開発QAボード 第8回(2026-11-25、Issue #28)で決めてもらい、その答えを決まりとして書いた(項目に「開発QAボード 第8回 8-N」と書いたもの)。まだ決まっていないところは **要確認** と書き、人に決めてもらう。決まったら、ここを直す。

レビュー(スキル `nbato-review`)は、この文書と ADR・デザインシステムに照らして行う。迷ったら ADR(`docs/adr/`)が正。

## 1. データモデル(イミュータブルデータモデル)

出どころ: ADR-0002〜0007、`docs/data-model.md`、`app/models/concerns/event_record.rb`、`test/models/event_rules_test.rb`。

- **リソースとイベントを分ける。** 「〜する」を付けて自然ならイベント(承認・取消・住所の変更)、不自然ならリソース(人・科目・提出先)。始まりと終わりのある出来事は長いイベント(LE: 証憑・入会・登記の申請)。分類はモデルごとに台帳 `docs/data-model.md` に書く。**モデルを足したら台帳に足す**(`test/models/data_model_ledger_test.rb` が確かめる)。
- **イベントは日時を 1 つだけ持ち、追加するだけ。**
  - `include EventRecord` と `event_of :<日時の列>, entry: :<入口>` を書く(例 `app/models/journal_proposal/approval.rb`)。
  - 表に `created_at`・`updated_at` を付けない(マイグレーションでも `t.timestamps` を書かない)。
  - 列の名前は出来事の名前: 日時なら `_at`(`approved_at`・`cancelled_at`)、日付なら `_on`(`moved_on`・`submitted_on`)。人が日付を入れる出来事は `_on`、ボタンを押した時の出来事は `_at`。
  - `app/` からイベントを `update`・`destroy` しない。作るのは入口だけ。マイグレーションと保守のタスク(`db/`・`lib/tasks/`)からは直してよく、直したら理由を ADR か notes に残す(ADR-0003)。
  - 守り方は readonly? やトリガーではなく、テスト(ADR-0003)。
- **入口は、名前空間の中の名詞のクラスのクラスメソッド 1 つ**(ADR-0004)。
  - クラスはリソースの名前空間に出来事の名詞: `JournalProposal::Approval`、`Person::AddressChange`、`RegistrationFiling::Submission`。
  - メソッドは出来事に合う英語の動詞 + `!`: `approve!`・`reject!`・`withdraw!`・`cancel!`・`submit!`・`confirm!`。合う動詞が無ければ `record!`(`Person::AddressChange.record!`・`RegistrationFiling::Correction.record!`)。
  - 引数の形: 1 つ目に対象(位置引数)、操作した人は `by:`、日時は `at: Time.current`(日付の出来事は `moved_on:` など列の名前)、ほかはキーワード(例 `JournalEntry::Cancellation.cancel!(entry, by:, reason:, at: Time.current)`)。
  - **操作した人(開発QAボード 第8回 8-5)**: 新しいイベントの列は、出来事の名詞 + -er(`approver`・`rejecter`・`canceller`)。いまの列(`recorded_by`・`changed_by` など)は改名しない(マイグレーションと運用への連絡が要るため)。`by:` は、人が画面で行う出来事なら必須(`by:` と書き、既定の値を付けない)。AI や rake からも起きる出来事なら省ける(`by: nil`)。
  - 中身の順: ①確かめる(だめなら日本語の文で `raise ArgumentError`)→ ②`transaction do` → ③`create!` → ④関係するイベント・長いイベントのいまの状態 → ⑤操作履歴の名前(`Audit.label!` / `Audit.final!`)→ ⑥作ったイベントを返す。
  - クラスの先頭のコメントに、何の出来事か・日時の列・元に戻せるか・ADR を書く(例 `app/models/journal_entry/cancellation.rb`)。
- **いまの状態は長いイベントだけが持つ**(ADR-0005)。詳細のイベントから決まる状態(`Voucher#derived_status`)は、入口の中(`advance_status!` など)だけで書き換え、`app/models/model_verification.rb` に照合を足す(`bin/rails model:verify`、CI でも流す)。リソースに状態の列を持たせない。
  - 状態の絞り込みは、詳細のイベントの有無の副問い合わせで書く(例 `JournalProposal.pending`)。
- **リソースを変えるとき**: 業務の変更(転居・改姓・退会・就任)はイベント、打ち間違いの訂正はその場で直して操作履歴に残す(ADR-0006)。どちらかは台帳に項目ごとに書く。
- **訂正と元に戻す**: イベントは消さない。取り消しは取り消しのイベント(`JournalEntry::Cancellation`・`Person::ChangeCancellation`)を足す。記帳したあとの仕訳は、取消 + 正しい仕訳で直す(ADR-0007・0026)。
- どちらがなくても成り立つもの同士(人と年度、人と役)は交差エンティティで結ぶ(`Membership`・`OfficerTerm`。ADR-0002)。
- 年度ごとに変わる項目は、ID を共通にして年度ごとの記録に持つ(`YearRecords`。`Person` → `PersonYear`)。年度ごとのデータセット(科目・部門)は `YearlyDataset`(ADR-0016・0018)。
- 個人情報の列は `encrypts` する(`Person`・`PersonYear`・`MemberApplication`・`AuditChange`)。

**要確認**

- 入口が 1 つのクラスに 2 つあるもの: `JournalProposal.propose!` と `repropose!`。`propose!` だけ対象をキーワード(`voucher:`)で受ける。
- 台帳で「移行: 待」のモデル(`JournalEntry`・`Membership`・`ProcedureStep` など)は、まだこの決まりに沿っていない。直すのは移す順(ADR-0002 の補足)のとき。

## 2. コントローラーとルート

出どころ: ADR-0008・0033、`config/routes.rb`、`app/controllers/journal_proposals/approvals_controller.rb`。

- **7 つの基本のアクションだけ。出来事は、その出来事の「作る」**: 承認は `POST /journal_proposals/:id/approval` → `JournalProposals::ApprovalsController#create`。ルートは入れ子の `resource :approval, only: :create, module: :journal_proposals`(1 対 1 の出来事)か `resources :corrections, only: :create`(何度も起きる出来事)。
- コントローラーがするのは 3 つだけ: ①パラメーターを確かめる、②イベントの入口(リソースなら `save`)を呼ぶ、③画面に渡す変数を用意する。業務の確かめはモデルに書く。
- 入口の `ArgumentError`(日本語の文)と `ActiveRecord::RecordInvalid` を `rescue` して、`redirect_to ..., alert: e.message` で返す。うまくいったら `notice:` に過去形の文(「記録しました」)。送ったあとは別の画面に移る(PRG。ADR-0033)。
- クラスの先頭に、何の出来事か・ADR を 1 行で書く(「AI の提案の承認(イベントを作る)。docs/adr/0008: …」)。
- 一覧の `index` は、絞り込みのクエリを覚える(`remember_list_url`)。詳しい画面にはパンくず(`crumbs`)を付ける(ADR-0033)。
- 監査の役割は閲覧だけ。`ApplicationController#read_only_for_auditor` が GET 以外を止める。止めないコントローラーは `READ_ONLY_ALLOWED` に足す。
- 締めた年度を変えるときは理由を書いてもらう(`ClosedYearGuard#closed_year_reason_ok?`、モデルでは `Audit.reason!`・`FiscalPeriod.changed_after_close!`)。
- **7 つの外のアクション(開発QAボード 第8回 8-1)**: 新しく足すのは禁止(レビューで Must)。いま残っているもの(`vouchers#propose`・`reject`、`registration_filings#include`・`exclude`、`fiscal_periods#start_next`・`reopen`、`people#apply_to_years`・`accounts#apply_to_years`、`undo#undo`・`redo`、`assistant#perform`、`passkeys` の `*_options`・`verify*` など)は、その業務をイミュータブルデータモデルに移すときに一緒に直す。モデルを移し終えた入会は、`member_applications/approval`・`rejection` の create に直した(#36)。
- **操作履歴の名前を付ける場所(開発QAボード 第8回 8-4)**: `Audit.label!`・`Audit.final!` は入口(モデル)で呼ぶ。rake や AI から同じ出来事を起こしても、同じ名前が付くようにするため(ADR-0004)。いまコントローラーで付けているところ(`journal_entries`・`people`・`accounts`・`fiscal_periods`・`procedure_steps`・`filing_destinations`・`passkeys` など)は、その業務を移すときに入口へ移す。新しくコントローラーで付けるのは、レビューで Must。

**要確認**

- 監査の役割の確かめを、`read_only_for_auditor` のほかにコントローラーでもしているところがある(`People::AddressChangesController` など 11 か所)。

## 3. 画面(ビュー・Hotwire・自動保存)

出どころ: CLAUDE.md「画面の決まり」、ADR-0008・0012・0013・0033、`docs/design-system/README.md`、`app/javascript/controllers/`。

- **保存ボタンを置かない。** 入力欄は `data-controller="autosave"` の中に置き、`data-url` に PATCH(JSON)の送り先を書く。コントローラーは `include AutosaveResponse` と `respond_to { format.json { autosave_response(record) } }`(`app/controllers/concerns/autosave_response.rb`)。
  - **例外: 作る画面(new)(開発QAボード 第8回 8-2)**: 必須の項目がそろうまで行を作れないので、送るボタンを残してよい。文字は動詞にする(「作る」「登録する」。「保存」としない)。直す画面(edit)は自動保存にする。いま保存ボタンの残る画面(`organizations/edit`・`journal_entries/_form`・`people/_form`・`accounts/edit`・`vouchers/_form`・`annual_reports/_form`・`resolutions/_form`・`registration_filings/show`)は、見直し票で画面ごとに合意を取ってから移す(#39)。
- 動きは Stimulus のコントローラー(`app/javascript/controllers/*_controller.js`、名前はハイフンつき: `confirm-twice`・`row-detail`・`year-switch`)。JavaScript は importmap(ビルドしない)。
- **元に戻せない操作と消す操作のボタンは `confirm-twice`**(2 回押し、ダイアログを出さない。`data-armed-label="もう一度押すと…(元に戻せません)"`)。危ないボタンは `nb-btn nb-btn--danger`。ブラウザのダイアログ(`turbo_confirm`・`data-confirm`)は使わない(開発QAボード 第8回 8-3)。残っていた 3 つ(`journal_entries/show`・`vouchers/show`・`siwake_imports/show`)は #37 で替えた。結合テストでは `assert_confirm_twice` で確かめる。
- **画面の書き換え(開発QAボード 第8回 8-8)**: いまは、出来事は送ったあと別の画面に移る(PRG)、入力は自動保存の JSON。画面の一部だけを書き換える必要のある画面ができたら Turbo Stream を使う(ジョブの進み具合の知らせ #23 の Action Cable で使う見込み。ADR-0008)。
- PDF と外のサイトへのリンクは別のタブ(`new_tab_link_to`、文字の後ろに「↗」)。帳票は `layouts/print`(明朝・全角数字・黒一色)、PDF は `PdfRenderer`。
- アイコンは `icon(role)`(`app/helpers/icon_helper.rb`、Lucide。ADR-0017)。
- 画面の説明(右ペインの「使い方」)は `config/help/` の YAML、年に一度の手続きは `config/procedures/*.yml`(条文は定款で確かめてから書く。推測で条文の番号を書かない)。
- 待つ表示(AI の作業中など)は `auto-reload`(残りの秒数を出し、決まった間隔で読み込み直す。デザインシステム「待つ表示」)。

## 4. 操作履歴と元に戻す

出どころ: CLAUDE.md「画面の決まり」、`app/models/concerns/audited.rb`・`app/models/audit.rb`・`app/controllers/application_controller.rb`。

- 操作履歴は自動で残る(`ApplicationRecord` が `include Audited`)。リクエスト 1 回が 1 つの操作(`ApplicationController#record_operation`)。rake などでは 1 件ごとに操作を作る。
- 履歴に出す文は `Audit.label!("…")`(過去形・日本語。「登記の申請を始めた(…)」)。元に戻せない操作(承認・取消・提出・決議の反映・登記・住所の変更)は `Audit.final!("…")`。締めた年度の変更の理由は `Audit.reason!`。
- 記録しないモデルは `self.audited = false`。履歴に残さずに書くとき(写しの列の同期など)は `Audit.without { … }`(`YearRecords#sync_latest!`)。
- 元に戻す・やり直すを出す画面は、コントローラーで `undoable_screen`。範囲は `audit_scope`(既定はコントローラーの名前。入れ子のコントローラーは親の画面の名前を返す: `People::AddressChangesController#audit_scope = "people"`)。右ペインに `history_panel`。
- 履歴の年度の分け方は `Audited#audit_fiscal_year`(年度の列か、日付の列 `AUDIT_DATE_COLUMNS`)。新しい日付の列で年度を決めるなら、ここに足す。

## 5. デザインシステム

出どころ: ADR-0012、CLAUDE.md「画面の決まり」、`docs/design-system/`。

- **UI を変える順番: ①見直し票(artifact)で案を見せて合意 → ②`docs/design-system/` に書く → ③実装。** 実装してから相談しない。デザインシステムに書いていない UI は作らない。小さな不具合(崩れ・誤字)の修正はこの限りでない。実装のコミットに見直し票の回の番号を書く(「(見直し第21回)」)。
- 色・寸法は `var(--…)` のトークンだけ。新しい画面は `nb-` の部品(`nb-btn`・`nb-sheet`・`nb-field` など。一覧は README「コンポーネント」)。
- **Tailwind のユーティリティ(開発QAボード 第8回 8-7)**: 並べ方のユーティリティ(`flex`・`grid`・`items-center`・`justify-between`・`gap-*`・`flex-wrap` など)は使ってよい。色・文字の大きさ・余白(`text-red-600`・`text-sm`・`mb-4`・`p-2` など)は、トークンか `nb-` の部品だけで決める。古い部品(`.btn`・`.card`・`.data-table`)の画面は、触るときに `nb-` の部品へ移す(まとめて移す EPIC は作らない)。
- `tokens.json`・`components.css` を直したら `bin/rails design:tokens`、CSS は `bin/rails tailwindcss:build`。
- 狭い幅(720px まで)は 1 列・本文を先に・右ペインを出さない(README「狭い幅」)。ダークモードは `data-theme="dark"` のときだけ。

**要確認**

- 帳票の `layouts/print` は色の値を直に書いている(`#f5f5f4`)。帳票はこのシステムの色を使わない(黒一色)ので、トークンにするか、帳票だけの例外とするか。

## 6. 名前と言葉

出どころ: CLAUDE.md、`docs/design-system/README.md`「言葉」・「名前」、`config/locales/models.ja.yml`。

- **コードは英語、画面・コメント・メッセージは日本語。** 画面の言葉は事務員の言葉(「レコード」ではなく「仕訳」「証憑」「会員」)。ボタンは動詞で終える(「承認して記帳」)、結果は過去形(「記帳しました」)。エラーは、何が起きたかとどうすればよいかを書き、謝らない(「取り消す理由を書いてください」)。
- 日付は画面では `2026/11/20`、帳票では和暦の全角(`Wareki`)。
- 製品名は英字で `n-bato`、Ruby で `NBato`、画面では `<ruby>N<rt>エヌ</rt></ruby>ばと`。
- 書面決議のモデルは、コントローラーでは `::Resolution` と書く(Rails の helper のモジュールとぶつかるため)。
- **モデルの日本語の名前は `config/locales/models.ja.yml`**(操作履歴の表示に使う。`model_name.human`)。クラスメソッド `self.model_name_label` には書かない(開発QAボード 第8回 8-6)。`model_name_label` は #38 で無くした(`test/models/model_names_test.rb` が確かめる)。

## 7. Ruby の書き方

出どころ: `.standard.yml`、`app/` 全体。

- 書き方の検査は **standardrb**(`standard` + `standard-rails`)。`bin/standardrb` で調べ、`bin/standardrb --fix` で直す。決まりは standard の既定のまま。外すときは `.standard.yml` にファイルを限って理由を書く(いまはイベントの表の `Rails/CreateTableWithTimestamps`、素の Ruby のスクリプトの `Rails/TimeZone`)。1 か所だけなら、その行に `# standard:disable <Cop> -- 理由`。
- 1 行で書けるメソッドは endless(`def cancelled? = cancellation.present?`、`app/` に 360 以上)。
- ブロックの引数が 1 つなら `it`(`list.find { it.fiscal_year == year }`)。`_1` は使わない。
- キーワード引数の省略形(`create!(person:, address:, by:)`)。
- サービスオブジェクト(`app/services`)を作らない。処理はモデル(イベントの入口・名前空間の中のクラス `Bookkeeper::ProposalGenerator`・`Requests::Organizer`)に書く(ADR-0004)。
- 外に出るもの(Claude API・Chrome・S3)は、差し替えられるように作る: 引数で受ける(`client: Bookkeeper::Client.new`)か、`PdfRenderer.engine` のような差し替え口。

## 8. テスト

出どころ: `test/`、ADR-0003・0025、`test/test_helper.rb`。

- minitest。テストの名前は日本語の文(`test "イベントのクラスがある"`)。画面とコントローラーは結合テスト(`test/integration/`、`sign_in`)で確かめる(`test/controllers/` は使っていない)。
- **データは架空のもの。** fixture は `users.yml` だけで、ほかはテストの中で作る(法人は `ensure_organization` の「テスト法人」、会計王のファイルは `test/fixtures/files/siwake_sample.txt`)。実データでしか確かめられないことは、数値だけを `notes/` に書く。
- **外に出ない。** Chrome は立ち上げず `PdfRenderer::Fake`(`test_helper.rb` で差し替え、渡した HTML を確かめる)。Claude API は `FakeClient`(`test/models/bookkeeper/proposal_generator_test.rb`)を `client:` で渡す。パスキーは `WebAuthn::FakeClient`。
- イベントの決まりは `test/models/event_rules_test.rb`、台帳は `data_model_ledger_test.rb`、いまの状態は `bin/rails model:verify`(CI では seed のあとに流す)。
- **バックエンドのカバレッジは 100%**(ADR-0025): `COVERAGE=1 bin/rails test`。対象はモデル・コントローラー・ジョブ・ヘルパー・`lib/`(ビュー・JavaScript・設定・マイグレーション・rake のタスクは外す)。実機が要るところだけ `# :nocov:` で囲み、理由を書く。イミュータブルデータモデルに移した業務から順に 100% にする。
- コミットの前に `bin/rails test`・`bin/standardrb`・`bin/brakeman --no-pager` を通す。

## 9. 公開リポジトリと団体の情報

出どころ: CLAUDE.md「公開リポジトリとしての注意」、ADR-0009、`.claude/rules/session-roles.md`、`bin/check-private`。

- 団体の情報(会員・役員の氏名・住所・連絡先、金額、内部の情報、非公開のリンク、鍵)は、コード・テスト・コミット・Issue・PR に入れない。コードに要るときは法人情報(`organization:load`)や `data/` から読む。
- `bin/check-private` をコミットの前に通す(pre-commit フック。CI はファイルと履歴のすべて)。許すのは `config/check_private_allow.yml` の架空の例と公的機関の公開情報だけ(ファイルを限り、理由と出どころを書く)。
- 公的機関の公開情報をコードに書くときは、使うところにコメントで「公開情報であること・出どころ」を書く。
- 秘密は `.kamal/secrets` に値を書かず、`NBATO_SECRETS_DIR` から読むだけ。本番が AWS を使う鍵は用途ごとに IAM ユーザー(ADR-0035)。

## 10. マイグレーション

出どころ: `db/migrate/20261123090000_split_journal_proposal_events.rb`・`20261124091000_create_member_application_events.rb`、ADR-0003。

- **データを捨てない。** 行の列をイベントに分けるときは、表を作ったあと、いまの行からイベントを SQL(`execute <<~SQL INSERT … SELECT …`)で作り(足りない日時は `COALESCE(reviewed_at, updated_at)` のように埋める)、それから古い列を消す。
- `up` と `down` を両方書き、`down` で元の列にデータを戻す。
- マイグレーションの中でモデルのクラスを使わず、SQL で書く(あとでモデルが変わっても流せるように)。
- 履歴の扱いが変わるときは、操作履歴も合わせる(例: 承認を元に戻せない操作にしたので `audit_operations.kind` を `final` にした)。
- 先頭のコメントに、何をなぜ分けるか・ADR を書く。
- データの形が変わるマイグレーションを含むデプロイは、前に運用との連絡帳で知らせる(`.claude/rules/session-roles.md`)。

## 11. コメント

- **コメントは日本語。** クラス・モジュールの先頭に、何のためのものか・ADR やデザインシステムの節・見直し票の回を書く(`app/models` と `app/controllers` の 7 割のファイル)。
- 「なぜ」を書く(「NOT NULL の列があるため」「マイグレーションや保守のタスクから直せるようにするため」)。推測で書いたことは「推測」と書く(ADR の 0013 以降)。
- Rails が作ったままのファイルの英語のコメントは、そのまま残してよい。

## 12. コミットと進め方

出どころ: CLAUDE.md「進め方」、`.claude/rules/git-workflow.md`・`decisions.md`、`git log`。

- コミットメッセージは日本語。1 行目に「何をしたか」と、要るなら括弧で理由や出どころ(「(見直し第21回)」「(issue #9 のときどき失敗するテスト)」「ADR-0026」)。本文に箇条書きで中身と理由。末尾に `Co-Authored-By:`。
- 意味のまとまりごとに分け、テストが通る状態でコミットする。書き方だけをそろえる自動修正は、別のコミットにする。
- 1 つの Issue が 1 つのブランチ(`<種類>/<説明>-<Issue 番号>`)と 1 つの PR。PR は Draft で作り、本文に `Closes #<番号>`(🧱 infra は `Refs #<番号>`)。自己レビュー(`nbato-review`)のあと、人が確かめることが残らず CI が通っていれば AI がマージしてよい(`git-workflow.md`)。
- push・外への送信は、ユーザーに確かめてから。ただし `/nbato-review` を呼んだことは、その PR の中の操作(コメント・ラベル・Ready・PR のブランチへの push・子の Issue)の確かめとみなす。`main` への push とマージはスキルではしない。出す本文は `bin/check-private --text` に通す(開発QAボード 第8回 8-10)。
- 人が決めることは開発QAボードで聞き、Issue に記録を積む(`decisions.md`)。設計の大事な決定は ADR に足す。
