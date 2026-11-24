---
status: 採用
date: 2026-11-24
decision-makers: 理事長(ユーザー)・Claude
---

# 本番へのデプロイは GitHub Actions から、AI が起動する(イメージは ghcr.io、秘密は Environment、CDK は承認のあと) — 開発QAボード 第6回

## 状況と問題

これまで本番へのデプロイは Mac から `bin/kamal deploy` で行い、イメージは Mac の一時的なレジストリ(localhost:5555)から SSH でサーバーへ送っていた。CDK(`infra/`)の反映も Mac から。Mac にしか秘密が無く、デプロイが人と Mac の都合に縛られる。GitHub Actions からデプロイできるようにするには、イメージの置き場所、起動のしかた、秘密の渡し方、サーバーに入る鍵、AWS への入り方を決める必要がある(Issue #13)。

## 判断の基準

* 鍵が漏れたときの害を小さくする(用途ごとに分け、長く使う鍵を増やさない。ADR-0035)
* 避けたい時期に勝手に走らない(止めるスイッチ)。データを壊しうる変更は人が見る
* Mac からの道を予備として残し、2 つの道で設定(秘密の読み方)を二重に持たない
* staging(#26)・Merge Queue での自動デプロイ(#24)・使い捨ての SSH の仕組み(#25)を、あとから足せる形にする

## 検討した選択肢

第6回の 5 問(Issue #13 の「判断待ち」「決まったこと」に全文)。

* r6-registry: **ghcr.io に公開** / ghcr.io に非公開
* r6-trigger: **いまは手で起動、PR の形になったら自動** / いまから自動 / 毎回承認
* r6-secrets: **GitHub の Environment「production」の Secrets** / AWS Secrets Manager / Mac から出さない
* r6-ssh: **Actions だけの鍵** / Mac と同じ鍵
* r6-cdk: **差分は自動、反映は承認のあと** / Mac からだけ

## 決定

5 問とも AI のおすすめ(太字)を採用。理事長のひとこと: ゆくゆくは Merge Queue で main に入ったら自動でデプロイ(ローリングデプロイなので、いつでも気にせず出す)。SSH は、ゆくゆくは使い捨ての仕組みにする。CDK は smalruby3-editor の Actions と同じ形にし、名前は staging / production(stg / prod と書かない)。

### 形

* **アプリ**: `.github/workflows/deploy.yml`(workflow_dispatch)。開発の Claude が `gh workflow run deploy.yml --ref main` で起動する。preflight で「main であること」「`DEPLOY_FREEZE` が true でないこと」「そのコミットの CI(ci.yml)が通ったこと」を確かめ、Environment `production` のジョブで `bin/kamal deploy`。concurrency で 1 つずつ、サーバーの側でも Kamal のロック。
* **イメージ**: `ghcr.io/smalruby/n-bato`(公開)。Kamal は git clone から作るので、コミットしたものしか入らない。Actions は `GITHUB_TOKEN`(`packages: write`)で置く。
  * Kamal 2.12 は、外のレジストリを使うと、サーバーでも必ず `docker login` する(飛ばす設定がない)。そのため Actions はジョブの `GITHUB_TOKEN` でログインし、終わったら `kamal registry logout --skip-local` で外す。Mac は `ghcr.env` のトークン(classic、`write:packages` だけ)。公開にしても、Kamal を通す限りログインは要る。公開にする良さは、鍵の無いイメージを誰でも確かめられることと、将来ほかの道(staging など)からも取れること。
* **秘密**: `.kamal/secrets` は `bin/kamal-secret NAME` だけを呼ぶ。同じ名前の環境変数があればそれ(Actions。Environment の Secrets を env で渡す)、無ければ `$NBATO_SECRETS_DIR` のファイル(Mac)。名前とファイルの対応はこのスクリプトの表 1 か所だけ。SSH の鍵も `ssh.key_data` で秘密として読むので、Actions はファイルを書かない。
* **SSH**: Actions だけの鍵(`NBATO_SSH_PRIVATE_KEY`)。サーバーの `authorized_keys` に `restrict` を付けて足す。ホスト鍵は Environment の変数 `NBATO_SSH_KNOWN_HOSTS` で固定し、知らない鍵ならつながない。
* **CDK**: スタックに GitHub の OIDC プロバイダと役割 2 つを足す。
  * `n-bato-github-cdk-diff`: PR と main への push から。NBatoStack のテンプレートと bootstrap の版を読むだけ(ReadOnlyAccess は使わない。バックアップの中身を読めてしまうため)。「CI - Infra」が `cdk diff --method template` を要約に出す。
  * `n-bato-github-cdk-deploy`: Environment `production-infra` のジョブからだけ。CDK の bootstrap の役割を引き受けることしかできない。「Deploy Infra」は main に infra/ の変更が入ったとき(か手で)差分を出し、承認者(理事長)の承認のあと `cdk deploy`。削除・置き換えを含む差分(`--fail-on destructive`)は Actions では出さず、人が読んで Mac から出す。
* **Environment を 2 つ**: `production`(アプリ。main だけ、承認なし。秘密)と `production-infra`(CDK。main だけ、承認あり)。GitHub の承認者は Environment ごとにしか付けられず、1 つにまとめるとアプリのデプロイも毎回承認になり、r6-trigger(毎回の承認はしない)と合わないため。staging を足すときは `staging` / `staging-infra`。
* **止めるスイッチ**: リポジトリの変数 `DEPLOY_FREEZE`。true のとき Deploy も Deploy Infra も出さない。入れる・外すのは人が決めたときだけ。

### 結果

* 良い: Mac が無くてもデプロイでき、起動の記録が Actions に残る。AWS には長く使う鍵を置かない。CDK の反映の前に、人が差分を見る。Mac の道も同じ設定で動く。
* 悪い: 秘密の置き場所が 2 つ(Mac が原本、Environment は写し)になり、鍵を変えたときは両方を直す(`docs/deploy.md` の手順 4 を流し直す)。Actions の SSH の鍵は長く使う鍵のまま(#25 で見直す)。Mac からの操作にも ghcr.io のトークンが要るようになった。イメージの名前が変わったので、それより前の版には `kamal rollback` で戻れない。

### 確かめ方

* `infra/test/n-bato-stack.test.ts`: 役割の信頼の条件(リポジトリ・sub)と、できることの一覧。
* `actionlint` でワークフローを確かめる。
* はじめての Deploy のあと、イメージの中に鍵が無いことを確かめてから公開にする(`docs/deploy.md` 手順 6)。

## 補足

* 人が一度だけすること・AI が毎回することは `docs/deploy.md`。
* 関係: ADR-0024(開発と運用の大きな方針)、ADR-0035(用途ごとに IAM を分ける)、`.claude/rules/session-roles.md`(デプロイの決まり)。Issue #13(この決定)、#24(Merge Queue)、#25(使い捨ての SSH)、#26(staging)。
* 参考: smalruby3-editor の `.github/workflows/ci-infra.yml`・`deploy-infra-stg.yml`(OIDC、concurrency、削除・置き換えで止める安全装置)。
