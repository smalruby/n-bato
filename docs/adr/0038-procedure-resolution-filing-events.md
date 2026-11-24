---
status: 提案中
date: 2026-11-25
decision-makers: Claude(理事長の確かめ待ち)
---

# 手続き・決議・提出の作り替え(手順の状態の変化・事業報告の節目・同意の取消・議案の反映)

移す順(ADR-0002): 会計 → 会員 → やること・依頼 → **手続き・決議・提出**・登記(登記は ADR-0031 で済み)。Issue #16(EPIC #5)。画面は変えない(ADR-0012。変えるなら見直し票から)。型は ADR-0034(やること・依頼)。

## 状況と問題

* 手続きの手順(ProcedureStep)は、済みにした・対象外にした・済みを取り消したを、1 行の status・completed_on の書き換えで持っていた。
* 事業報告(AnnualReport)の承認・提出・公告・出し直しが要る・出し直した の日付は、列の書き換えだった。書くのは事業報告の画面・手順の効き目・決議の反映・締めた年度の変更の 4 か所に散らばっていた。
* 同意(Consent)は「取り消す」で行ごと消していた。決議の議案(ResolutionItem)の「記録に反映した」は applied_on の書き換えで、元に戻せない操作にもなっていなかった(CLAUDE.md では決議の反映は元に戻せない操作)。
* コントローラーに complete・reopen・skip・apply_item・consents#destroy の独自のアクションがあった。

## 判断の基準

* 出来事(いつ誰が済みにしたか・提出した日をいつ記録したか・同意を取り消したか・議案を反映したか)が残ること
* 画面と使い方を変えないこと。手順の「元に戻せます」・事業報告の画面の日付の欄は、いまどおり
* 運用のスクリプトが読む列(手順の status・completed_on、事業報告の日付、議案の applied_on)を、同じ名前で読めること

## 検討した選択肢

* 手順: 済みにした・対象外にした・取り消したを 3 つのイベントに分ける / 1 つのイベント `ProcedureStep::StatusChange`(変えたあとの状態)にする(採用)
* 事業報告の日付: 節目ごとに 5 つのイベント(承認・提出・公告・出し直しが要る・出し直した)と、直すための取消のイベント / 1 つのイベント `AnnualReport::Milestone`(種類と日付。空なら消した)にする(採用)
* 同意の「取り消す」: いまどおり消す(打ち間違いの訂正として操作履歴に残す)/ 取消のイベントを足す(採用)
* 締めた年度を直したときの「出し直しが要る」: 自分の範囲の操作に分ける / 直した操作に入れる(採用)

## 決定

* **手続き**(ProcedureRun・LE): 始めるのは `ProcedureRun.start!(kind:, period:)`(もう始めてあればその手続き。二度押しでも 1 つ)。いまの状態(済んだ数・次にやること)は手順から毎回決まるので、列は持たない。
* **手順**(ProcedureStep・LE): 状態の変化は `ProcedureStep::StatusChange.change!(手順, status:, on:, reason:, by:)`(日時 changed_at、中身の日付 completed_on)。status は done・skipped・open の 3 つ。
  * 3 つは 1 つの軸で、持つ列も同じなので 1 つのイベントにした(ADR-0034 のやることと同じ)。順は id(済んだ日は人が入れる過去の日なので、順には使わない)。
  * 保存する状態(status・completed_on)は列のまま持ち、最後の変化から決まる(ADR-0005)。入口だけが書き換え、**直接書き換えると検証で止まる**。画面の 6 つの状態(未着手・進行中・待ち・期限切れ・記録から済み)は、いまどおり毎回計算する。
  * 確かめたこと(checks)・メモは作業の中身で、ふつうに直してよい(ADR-0006)。返事を待つもののチェックも同じ(本当の同意は決議の Consent に残る)。
  * 済みにした手順の効き目(提出・公告・出し直し・年度を締める)は、同じ操作の中で記録する。もう締めてある年度なら締め直さない。
  * 返事がそろっているか(blocked_reason)は、いまどおり画面が確かめる(運用のスクリプトからは、これまでの complete! と同じく確かめずに済みにできる)。
  * final の手順を済みにするのは元に戻せない操作、取り消せない。ほかは元に戻せる(いまどおり)。
* **事業報告**(AnnualReport・LE): 節目は `AnnualReport::Milestone.record!(事業報告, 種類, on:, automatic:, by:)`(日時 recorded_at、日付 dated_on)。種類は approved・submitted・bs_published・resubmit_needed・resubmitted。
  * 事業報告の画面では日付の欄を自由に直せる・消せる(画面を変えない)。5 つに分けると「直す・消す」のたびに取消のイベントが要るので、変えたあとの日付を持つ 1 つのイベントにし、空なら「消した」とした。
  * いまの状態(approved_on・submitted_on・bs_published_on・resubmit_needed_on・resubmitted_on)は列のまま持ち、種類ごとの最後の記録から決まる。直接書き換えると検証で止まる。提出書の日付(letter_date)・公告の場所などは中身。
  * 事業報告の画面は、日付の欄が変わっていたときだけ節目を記録する(同じ日付なら記録しない)。
* **決議**(Resolution・LE): 成立した日は、取り消していない同意から毎回決まる(列は持たない)。`resolution.consents` は取り消していない同意だけ、`all_consents` は取り消したものも。
  * **同意**(Consent・E。日付 consented_on): `Consent.record!`。取り消していない同意は 1 人 1 つ(検証。一意の索引は、取り消したあとに記録し直せるよう外し、`model:verify` で確かめる)。
  * **同意の取消**(Consent::Cancellation・E。日時 cancelled_at): `Consent::Cancellation.cancel!`。画面の「取り消す」はこれ。同意の記録は消さない。
  * **議案の反映**(ResolutionItem::Application・E。日付 applied_on): `ResolutionItem::Application.apply!`。役員の任期・登記の事由・事業報告の承認(節目)を作る。外に効く出来事なので **元に戻せない操作** にした(CLAUDE.md の決まりに合わせた。決議の画面には元に戻すが無いので、見た目は変わらない)。議案(ResolutionItem)は決議の中身(R)。
  * **同意を記録した(取り消したものも)・議案を反映した決議は消せない**。反映した議案も消せない。出来事を消さないため(ADR-0007)。これまでは消せた。
* **決まりで付ける節目**: 締めた年度を直したときの「出し直しが要る」は automatic。開くたびに付く決まり(ADR-0034 の自動で済み)とちがい、人が直した操作の結果なので、**直した操作に入れる**(範囲を分けない)。直したのを元に戻すと印も外れる。包んだ操作の名前は変えない。GET で状態を変えるものは、この範囲には無い。
* **入口の共通**(ADR-0034 のレビューの教え):
  * 入口(change!・record!・start!・Consent.record!・cancel!・apply!)は、操作の外(rake・運用のスクリプト)で呼ばれても 1 つの操作にまとめる。
  * 入口は transaction(requires_new: true)。途中で失敗したら、外のトランザクションの中でも途中までの変更を残さない(議案の反映の互選が途中で失敗したときなど)。
  * 二度押し: 古い記録を読んでいても、一意の索引(RecordNotUnique)でも、500 にせず「もう…してあります」。手順の二度押しは、もう一方が先に作った手順の記録を読み直して、同じ状態なら何もしない。
  * 同じ状態なら何もせず(nil)、画面は「元に戻せます」と言わずに「もう済みにしてあります」などと出す。
  * 元に戻す・やり直すのあと、触った手順・事業報告のいまの状態をイベントと照合し、食い違えば Conflict(`Audit.check_states!`。持ち主は audit_state_owner)。
* **コントローラー**(ADR-0008): `POST /procedures/:id/steps/:key/status_changes`(status)、`POST /resolutions/:id/consents/:id/cancellation`、`POST /resolutions/:id/items/:id/application`。complete・reopen・skip・apply_item・consents#destroy は無くした。元に戻すの範囲(audit_scope)はもとのまま。
* **移し方**(マイグレーション 20261125100000): いまの列からイベントを作る(open でない手順に 1 つ、事業報告の日付の入った列ごとに 1 つ、反映した議案に 1 つ)。おかしな行はそろえる(決まった値でない状態は open、済み・対象外で日付の無いものは更新した日(日本時間)、open で日付の残ったものは日付を消す)。議案の applied_on、同意の created_at・updated_at の列は消す。これまでの操作のうち、手続き・手順・事業報告・決議・議案・同意に触れたもの(作成・変更・削除)は、元に戻せない操作にした。形の合わない操作が残っていても、元に戻す・やり直すは Conflict で止める(StatementInvalid も。ADR-0034 で共通にした)。

### 結果

* 良い: 誰がいつ手順を済みにしたか、提出日をいつ・どこから記録したか、同意を取り消したか、いつ議案を反映したかが残る。独自のアクションが無くなった。`model:verify` で手順・事業報告・同意の食い違いが分かる。
* 悪い: 運用のスクリプトの書き方が変わる(手順を済みにする・事業報告の日付を入れる・同意・反映)。対応は運用との連絡帳(notes/ops-dev/0007、git 管理外)に「旧 → 新」で書いた。移す前の、これらに触れた操作は元に戻せなくなる。同意を記録した決議は消せなくなった。

### 確かめ方

`test/models/procedure_resolution_events_test.rb`、`test/integration/procedure_resolution_events_test.rb`、`test/migrations/create_procedure_and_resolution_events_test.rb`、`test/models/event_rules_test.rb`、`bin/rails model:verify`、`bin/rails test:system`(架空のデータの画面)。

## 補足

* 台帳の「待」のうち、この範囲に入れたのは ProgramActivity(事業報告の中身。R のまま 済)。ArticleVersion(定款の版)・ProgramProfile(定款の事業)は定款の、FiscalPeriod(年度を締める)は会計の範囲なので、ここでは移さない。定款の変更を議案として反映するようになったら、ArticleVersion を決議の反映につなぐ。
* 理事長に確かめてほしいこと: 同意を記録した決議を消せなくしたこと、議案の反映を元に戻せない操作にしたこと、事業報告の日付を 1 つのイベント(節目)にまとめたこと。
