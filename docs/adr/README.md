# 設計の決定の記録(ADR)

日本語の MADR で書く(ADR-0001)。新しく書くときは `TEMPLATE.md` を写し、番号を 1 つ進める。要る節だけ使ってよい。状態は 提案中 → 採用 / 却下、覆したら「ADR-NNNN で置き換え」、やめたら「廃止」。

| 番号 | 題 | 状態 |
|---|---|---|
| [0001](0001-adr-in-japanese-madr.md) | ADR を日本語の MADR で残す | 採用 |
| [0002](0002-immutable-data-model.md) | イミュータブルデータモデルを土台にする | 採用 |
| [0003](0003-event-rules-by-design-and-tests.md) | イベントの決まりは、設計とテストで守る | 採用 |
| [0004](0004-event-entry-points.md) | イベントを作る入口 | 採用 |
| [0005](0005-current-state-in-long-term-events.md) | いまの状態は長いイベントだけが持ち、作り直して照合する | 採用 |
| [0006](0006-resource-changes.md) | リソースを変えるとき: 業務の変更はイベント、打ち間違いの訂正は操作履歴 | 採用 |
| [0007](0007-corrections-and-undo.md) | 訂正と「元に戻す」 | 採用 |
| [0008](0008-controllers-and-hotwire.md) | コントローラーは 7 つの基本のアクションだけ、出来事は create | 採用 |
| [0009](0009-public-repository-and-private-data.md) | 公開するリポジトリと、手元だけに置く情報 | 採用 |
| [0010](0010-passkeys.md) | パスキーでのログイン(パスワードと併用、ドメインごと) | 採用 |
| [0011](0011-ruby-4.md) | Ruby 4.0 を使う | 採用 |
| [0012](0012-ui-change-process.md) | 画面の変更は、見直し票で合意 → デザインシステム → 実装 | 採用 |
| [0013](0013-sheet-operations.md) | 表(シート)の操作 — 見直し票 第1回 | 採用 |
| [0014](0014-working-year-and-past-years.md) | 作業する年度と、過去の年度の扱い — 見直し票 第2回 | 採用 |
| [0015](0015-year-colors-and-closing.md) | 年度の色、年度更新と締め、変更の記録 — 見直し票 第3回 | 採用 |
| [0016](0016-year-datasets.md) | 年度のデータの束(データセット)と、締めた時点の正 — 見直し票 第5回 | 採用 |
| [0017](0017-icons.md) | アイコン — 見直し票 第6回 | 採用 |
| [0018](0018-roles-and-per-year-attributes.md) | 年度ごとの持ち方・監査の役割・AI に聞く — 見直し票 第7回・第8回 | 採用 |
| [0019](0019-todos-and-requests.md) | やることと依頼 — 見直し票 第9回 | 採用 |
| [0020](0020-slack.md) | Slack との連携 — 見直し票 第10回・第11回 | 採用 |
| [0021](0021-member-applications.md) | 入会申込の受け箱 — 見直し票 第11回 | 採用 |
| [0022](0022-navigation-and-todo-counts.md) | 左のメニューと、やることの件数 — 見直し票 第12回 | 採用 |
| [0023](0023-articles-and-programs.md) | 定款と事業のページ — 見直し票 第13回 | 採用 |
| [0024](0024-development-and-operation.md) | 開発と運用の大きな方針 | 採用 |
| [0025](0025-backend-coverage.md) | バックエンドの自動テストのカバレッジを 100% にする | 採用 |
| [0026](0026-journal-entry-cancellation.md) | 記帳した仕訳の取消 | 採用 |
| [0027](0027-filing-destinations.md) | 提出先を法人ごとに設定し、確認済みのものだけを書類に使う | 採用 |
| [0028](0028-ai-web-search-for-destinations.md) | 提出先の窓口を AI に Web で調べてもらう | 採用 |
| [0029](0029-person-address-and-name-history.md) | 会員の住所・氏名を、日付つきの出来事で持つ — 見直し票 第20回 | 採用 |
| [0030](0030-member-domain-events.md) | 会員の作り替え(入会・会員資格・役員の任期) — 見直し票 第20回 | 採用 |
| [0031](0031-registration-filings.md) | 登記の申請を 1 件ずつ記録し、申請書の文と添付書類を作る — 見直し票 第20回 | 採用 |
| [0032](0032-filing-destination-list.md) | 提出先の一覧: 行のボタン・連絡先の列・足し方 — 見直し票 第18回・第19回 | 採用 |
| [0033](0033-no-browser-back.md) | ブラウザの「戻る」を使わなくてよい画面(パンくず・PDF は別のタブ) — 見直し票 第21回 | 採用 |

関係するもの: データモデルの台帳 `docs/data-model.md`、デザインシステム `docs/design-system/`。

0013 以降は、見直し票(画面の変更の案に人が答える票)の回ごとに、検討した選択肢・決定・理由をまとめたもの。正確な記録ではなく、あとで迷わないための要約。理由が答えに書かれていないものは「推測」と書いた。
