# n-bato(N(エヌ)ばと)

NPO 法人の事務を何でも引き受ける「スーパー事務員」アプリ。名前は **NPO butler** を縮めた「Nばと」から。日本語では「N(エヌ)ばと」と書き、画面では N に「エヌ」のルビを振る。

最初の利用団体は NPO法人Rubyプログラミング少年団。

## 方針

- 会計と書類は AI(Claude)が作り、人(理事長・監事)が確認して承認する。
- 帳簿は、承認した仕訳を会計王の仕訳形式(SIWAKE 3.00.00)で書き出して会計王に取り込む。当面は会計王を正とする。
- 期限のある事務(事業報告書等の提出、役員の任期、総会の決議、登記)を管理し、書類まで作る。

## 進め方

| 段階 | 内容 |
|------|------|
| P1 | 会計の核: 証憑の取り込み、AI の仕訳提案と承認、会計王 SIWAKE 形式の入出力、決算書類(活動計算書・貸借対照表・財産目録・注記) |
| P2 | 提出と公告: 所轄庁への年次提出パック、貸借対照表の公告 |
| P3 | 会員・役員・書面決議(みなし決議)と議事録 |

いまは本番(Lightsail)で動かしていて、ログインするのは理事長 1 人。開発のタスクは GitHub の Issue と Projects で管理する(団体の事務は載せない。事務のやることは Nばとの「やること」で管理する)。

## できること(2026-11-20 時点)

| 区分 | 機能 |
|------|------|
| 会計 | 会計王 SIWAKE 形式の取り込み・書き出し(バイト単位で往復一致)、仕訳の入力、年度ごとの活動計算書・貸借対照表・財産目録・注記(HTML/PDF)、総勘定元帳、通帳・現金の残高照合、期首残高 |
| AI 仕訳 | 証憑(写真・PDF・説明)を登録 → Claude が科目表と過去の仕訳を見て仕訳を提案 → 人が直して承認 → 記帳(承認者・日時を残す) |
| 提出 | 事業報告書の作成(前年度から下書き、事業費は活動計算書から自動)、所轄庁への提出書類一式を 1 つの PDF に |
| 会員・役員 | 年度ごとの会員資格、役員の任期(満了後も次の選任までは伸長)、住所などは暗号化 |
| 決議 | 総会・理事会の書面決議(みなし決議)。同意の記録、提案書・同意書・議事録、成立後に役員選任・互選・決算承認を記録へ反映 |
| 期限 | ホームに「やること・期限」(提出・通常総会・役員改選・登記・貸借対照表の公告) |

## 開発

```bash
bin/setup --skip-server   # 依存の導入と DB の準備
bin/dev                   # http://localhost:3000
bin/rails test            # テスト
bin/standardrb && bin/brakeman --no-pager
```

AI エージェント(Claude Code)向けの決まりは `CLAUDE.md` と `.claude/rules/`、設計の決定は `docs/adr/`、画面の決まりは `docs/design-system/`、データモデルは `docs/data-model.md`。

## 手元の Docker で動かす

```bash
RAILS_MASTER_KEY=$(cat config/master.key) docker compose up -d --build
# http://localhost:3200
RAILS_MASTER_KEY=$(cat config/master.key) docker compose exec web bin/rails users:create  # EMAIL / PASSWORD / NAME を環境変数で
```

PDF はコンテナ内の Chromium と Noto CJK フォントで作る。データは volume `n-bato-storage` に残る。

## 技術構成

Rails 8 / SQLite / Solid Queue / Hotwire / Tailwind CSS。本番は Kamal で AWS Lightsail に載せる(`config/deploy.yml`)。AWS の部品(サーバー・S3 のバックアップ・SES)は CDK(`infra/`)。毎晩、データを S3 に送る(`NightlyBackupJob`)。デプロイは GitHub Actions から(予備は Mac から)。人が一度だけすることと AI が毎回することは `docs/deploy.md`。

## 個人情報について

**会員の個人情報や実際の仕訳データはリポジトリに入れない。** テストには架空のデータを使う。コミットの前と CI で `bin/check-private` が、鍵や個人情報らしい形をファイルと履歴の両方で調べる。

## ライセンス

MIT(`LICENSE`)。
