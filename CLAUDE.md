# n-bato — AI エージェント向け指示

NPO 法人の事務を何でも引き受ける「スーパー事務員」アプリ(Rails 8)。名前は NPO butler を縮めた「Nばと」。英字の表記は **n-bato**(ハイフン付き)、Ruby のモジュール名は `NBato`。日本語では「N(エヌ)ばと」と書き、画面(HTML)では `<ruby>N<rt>エヌ</rt></ruby>ばと` とルビを振る。概要と段階(P1〜P3)は `README.md`。

## このセッションの役割

このリポジトリの Claude のセッションは **開発とデプロイだけ** をする。事務・運用は別のセッションで行う(`.claude/rules/session-roles.md`)。

## 最初に読むもの

1. `README.md` — 目的と進め方
2. `notes/journal/` の最新ファイル — 前回までの作業記録と次にやること(git 管理外。無ければ作る)
3. `CLAUDE.local.md` — 手元専用の指示(実データの場所など。git 管理外。無ければ無視)
4. `docs/adr/README.md` — 設計の決定の記録(ADR、日本語の MADR)。設計で迷ったら先に読む
5. `docs/data-model.md` — データモデルの台帳(リソースとイベント、用語辞書)

## 開発コマンド

```bash
bin/setup --skip-server        # 依存の導入と DB 準備
bin/rails test                 # テスト(必ず通してからコミット)
bin/rubocop                    # スタイル(rubocop-rails-omakase)
bin/brakeman --no-pager        # セキュリティ静的解析
bin/dev                        # 開発サーバ(http://localhost:3000)
bin/rails kaikeiou:import[PATH]        # 会計王 SIWAKE ファイル(またはディレクトリ)の取り込み
bin/rails ledger:summary               # 年度ごとの集計
bin/rails 'ledger:opening[2017,100:12000 106:345000]'  # 期首残高(数字は例)
bin/rails 'organization:load[data/organization.yml]'   # 法人情報(例: config/organization.example.yml)
bin/rails 'data:load[data/records.yml]'                 # 会員・役員・事業報告書
EMAIL=... PASSWORD=... NAME=... bin/rails users:create
bin/rails server -p 3100 -d            # 開発サーバ(画面の確認は Playwright でスクリーンショット)
RAILS_MASTER_KEY=$(cat config/master.key) docker compose up -d --build   # 手元の Docker(http://localhost:3200)
NBATO_SECRETS_DIR=... bin/kamal deploy                 # 本番(https://n-bato.smalruby.app、Lightsail)。秘密の置き場所は CLAUDE.local.md
NBATO_SECRETS_DIR=... bin/prod-runner script.rb        # 手元の Ruby のファイルを本番の rails runner で実行(運用のセッション用)
(cd infra && npx cdk diff)                             # 本番の AWS の部品(NBatoStack)。deploy は人に確かめてから
```

## Claude Code が経理担当をするとき

Claude Code が、アプリの代わりに仕訳を提案することもできる(API キーが無い環境でも使える)。API キーは `.env` の `ANTHROPIC_API_KEY`(git 管理外。`docker compose` が読む)。

1. `bin/rails 'bookkeeper:prompt[証憑ID]'` で指示文・科目表・過去の仕訳・添付ファイルの場所を見る(Docker のときは `docker compose exec web ...`、添付は `docker compose cp` で取り出す)
2. 添付(写真・PDF)を読み、表示された JSON Schema の形で答えを作る。読み取れないことは questions に書き、推測で埋めない
3. `bin/rails 'bookkeeper:import[証憑ID,答え.json]'` で提案として登録する。**承認(記帳)は人が画面で行う。Claude Code は承認しない**

## 画面の決まり(デザインシステム)

- **UI・UX を変える順番(2026-11-20 ユーザー指定)**: ① 変更案を artifact で人間に見せ、選んでもらって合意を取る → ② `docs/design-system/` に書く → ③ 実装する。実装してから相談しない。デザインシステムに書いていない UI は作らない(画面ごとにばらばらになるのを防ぐため)。小さな不具合の修正(崩れ・誤字)はこの限りでない。
  - 見直し票とデザインシステムの原本(artifact)の場所は `CLAUDE.local.md`。

- 原本は `docs/design-system/`(README・tokens.json・components.css)。色・寸法は `var(--…)` のトークンだけを使い、新しい画面は `nb-` の部品で作る。古い `.btn`・`.card`・`.data-table` は移行用にトークンで描き直してある。
- `tokens.json` か `components.css` を直したら `bin/rails design:tokens`(`app/assets/tailwind/nbato.css` を作り直す)。CSS は `bin/rails tailwindcss:build`(開発サーバーを `bin/rails s` だけで動かすと自動では作り直されない)。
- **保存ボタンを置かない。** 入力欄は `data-controller="autosave"` の中に置き、`data-url` に PATCH(JSON)の送り先を書く。コントローラは `include AutosaveResponse` と `respond_to { format.json { autosave_response(record) } }`。
- **操作履歴は自動で残る**(`ApplicationRecord` の `Audited`)。リクエスト 1 回が 1 つの操作。履歴に出す文は `Audit.label!("…")`、元に戻せない操作(承認・提出・決議の反映・登記)は `Audit.final!("…")`。記録しない模型は `self.audited = false`。
- **元に戻す・やり直す**を出す画面は、コントローラで `undoable_screen`。範囲は `audit_scope`(既定はコントローラ名)。右ペインに `history_panel`。
- 元に戻せない操作のボタンは `confirm-twice`(2 回押し、ダイアログを出さない)。
- 年に一度の手続きは `config/procedures/*.yml` に手順・説明・根拠の条文を書く(画面は ProceduresController)。条文は利用団体の定款(場所は `CLAUDE.local.md`)で確かめてから書く。推測で条文番号を書かない。
- ダークモードは画面の移行が済むまで `data-theme="dark"` のときだけ。

## 設計の決まり(ADR)

- データモデルはイミュータブルデータモデルが土台(ADR-0002〜0008)。イベントは日時 1 つ・追加だけ。作るのは名前空間の中の名詞のクラスの入口(例 `JournalProposal::Approval.approve!`)だけ。コントローラーは 7 つの基本のアクションで、出来事は create。
- モデルを足したら `docs/data-model.md` に足す。いまの状態の照合は `bin/rails model:verify`。
- 設計の大事な決定は `docs/adr/` に日本語の MADR で足す(`TEMPLATE.md`)。

## 構成の要点

- `app/models/kaikeiou/` 会計王 SIWAKE 形式。`app/models/ledger/` 帳簿の集計と計算書類の行。`app/models/bookkeeper/` Claude による仕訳提案。`app/models/compliance/` 期限の一覧。
- 所轄庁向けの書類は `app/views/filings/`・`app/views/statements/`(印刷用レイアウト `layouts/print`、全角数字)。PDF は `PdfRenderer`(Ferrum + Chrome)。
- 書面決議は `Resolution`(コントローラでは `::Resolution` と書く。Rails の helper モジュールと名前がぶつかるため)。

## 進め方

- いまはブートストラップ期。**トピックブランチは作らず `main` に直接コミット** する。コミットは意味のまとまりごとに分け、テストが通る状態でコミットする。
- コミットメッセージは日本語でよい。末尾に `Co-Authored-By:` を付ける。
- **作業記録(ジャーナル)** は `notes/journal/YYYY-MM-DD.md` に追記していく(git 管理外)。書くこと: やったこと、決めたこと(理由も)、確認した結果(数値)、詰まったこと、次にやること。セッションの終わりに必ず更新する。
- push・GitHub リポジトリの作成など外部に出る操作は、ユーザーの確認を取ってから行う。

## 公開リポジトリとしての注意(コミットするもの・手元だけのもの)

このリポジトリは公開する。**利用団体に特化した情報は、コミットせず手元(git 管理外)だけで管理する**(2026-11-23 ユーザー決定)。

| 区分 | 例 | 置き場所 |
|---|---|---|
| コミットしてよい | アプリのコード、一般的な手順(`config/procedures/`)、デザインシステム、架空のデータのテスト | リポジトリ |
| コミットしてよい(出どころを書く) | 公的機関が公開している情報(所轄庁の名前・窓口の住所と電話、様式の番号など) | リポジトリ。使うところにコメントで「公開情報であること・出どころ」を書く |
| **手元だけ** | 利用団体の会員・役員・関係者の氏名・住所・連絡先 | `data/`(実データ)、`CLAUDE.local.md` |
| **手元だけ** | 金額(仕訳・残高・決算の数字)、通帳・証憑 | `data/`、`storage/`(アプリのデータ) |
| **手元だけ** | 団体の内部の情報(決めたこと・作業記録・会議・提出の状況)、非公開のリンク(artifact・Google ドライブ・Slack のワークスペース)、手元の作業領域の場所 | `notes/`、`CLAUDE.local.md` |
| **手元だけ** | 鍵(`config/master.key`、`.env`) | リポジトリの直下(git 管理外) |

- `CLAUDE.md`(公開)には一般的な決まりだけを書き、団体に特化したことは `CLAUDE.local.md`(手元)に書いて、ここから参照する。迷ったら手元に置く。
- コードや画面の文に団体の情報が要るときは、法人情報(`organization:load`)や `data/` から読む。コードに直接書かない。
- テスト・fixture・seed・例(`*.example.yml`)は架空のデータで作る。実データでしか確かめられないことは、結果の数値だけを `notes/` に書く。
- **コミットの前に `bin/check-private` を通す**(pre-commit フックで自動。入れるのは `bin/check-private --install-hook`)。CI でも、いまのファイルと履歴のすべてのコミットを調べる(`scan_private`)。
  - **広く拾う(安全側に倒す)**: 鍵の形、電話番号、郵便番号、メールアドレス(`example.com` などの例示用は除く)、都道府県名、「市区町村+番地」の住所、全角スペースで区切った氏名。
  - **許すのは** `config/check_private_allow.yml` に載せたものだけ。載せてよいのは架空の例と公的機関の公開情報で、ファイルを限り、理由と出どころを書く。会員・役員・関係者の情報は、どんな理由でも載せない。
  - **手元だけで調べる語**(会員・役員の氏名、実際の金額、非公開のリンクなど)は `.private-patterns`(git 管理外、1 行 1 つの正規表現)に書く。団体の情報が増えたら足す。

## ドメインの約束ごと

- 会計は NPO 法人会計基準に沿う。事業年度は 4/1〜3/31。`fiscal_year` は開始年(2024 年度 = 2024-04-01〜2025-03-31)で表す。
- 帳簿の正は当面「会計王」。このアプリは会計王の仕訳形式 **SIWAKE 3.00.00** で読み書きする(`app/models/kaikeiou/`)。
  - CP932、CRLF。1 行目は `//SFD FMTNAME="SIWAKE" ...` のヘッダ、2 行目は列名、3 行目以降が 1 行 1 仕訳(借方・貸方とも 1 科目)。
  - 文字列は `"` で囲み、数値は囲まない。読み込んだファイルを書き出すと、元と同じバイト列になることをテストで保証する。
  - 日付は和暦 `"H.36/04/15"`。会計王は令和以降も平成のまま数える(H.36 = 2024 年)。
  - 科目名には桁合わせの空白(半角・全角)が入る(`"現      金"`)。表示や照合には空白を除いた名前を使い、書き出しには元の名前を使う。
- 科目の区分は科目コードの範囲で決める(`Account.category_for_code`)。部門 111〜119 = ①〜⑨事業、900 = 管理部門、0 = 部門なし。
- AI は承認なしに帳簿へ記帳しない(P1 の後半で実装)。仕訳には元の証憑、AI の根拠、承認者と日時を残す。
- Claude API のモデルは `claude-opus-5-5` を既定にする。
