# 本番へのデプロイ

決めたことは開発QAボード 第6回・第8回・第9回(Issue #13)と ADR-0036。**Mac は ghcr.io のトークンを持たない**(第9回 `r9-ghcr`: `actions-only`)。デプロイもバックアップからの戻しも Actions から起こす。ここには、仕組みと、人が一度だけすることと、AI が毎回することを書く。

## 仕組み

| 何を | いつもの道 | 予備の道 |
|---|---|---|
| アプリ(Kamal) | GitHub Actions「Deploy」(`.github/workflows/deploy.yml`)。開発の Claude が `gh workflow run` で起動 | Actions が止まっているときだけ、Mac から期限の短いトークンで(「Actions が止まっているとき」) |
| バックアップからの戻し(`bin/prod-restore`) | GitHub Actions「Restore」(`.github/workflows/restore.yml`)。開発の Claude がユーザーに確かめて起動し、**理事長の承認のあと**に流れる | 〃 |
| AWS の部品(CDK の NBatoStack) | 「Deploy Infra」(`.github/workflows/deploy-infra.yml`)。main に `infra/` の変更が入ったときか手で起動し、**理事長の承認のあと**に反映 | Mac から `cd infra && npx cdk deploy` |
| CDK の差分 | 「CI - Infra」(`.github/workflows/ci-infra.yml`)。`infra/` を変えた PR と main への push で、`cdk diff` をジョブの要約に出す | Mac から `cd infra && npx cdk diff` |

- **イメージ**は ghcr.io に公開で置く(`ghcr.io/smalruby/n-bato:<コミット>`)。鍵は入れない(鍵はサーバーで起動するときに渡す)。Kamal はコミットを git clone してから作るので、コミットしていないファイルは入らない。`.dockerignore` も鍵と実データを外す。
- **秘密**は `.kamal/secrets` が `bin/kamal-secret` で読む。同じ名前の環境変数があればそれ(Actions)、無ければ `$NBATO_SECRETS_DIR` のファイル(Mac)。名前とファイルの対応は `bin/kamal-secret` の表だけに書く。
- **止めるスイッチ**: リポジトリの変数 `DEPLOY_FREEZE` が `true` のとき、Deploy も Deploy Infra も出さない(両方に効かせる。開発QAボード 第8回 8-14)。CDK だけ急ぐときの切り方は「AI が毎回すること」の「CDK だけ急いで反映するとき」。
- **重ならないように**: Deploy は 1 つずつ(concurrency `deploy-production`、走っているものは打ち切らない)。サーバーの側でも Kamal のロックを取るので、`bin/prod-runner`・`bin/prod-restore` が流れている間は失敗する(`bin/kamal lock status` で確かめる)。Deploy Infra も 1 つずつ(`infra-deploy-production`)。
- **出すのは CI が通った main だけ**。Deploy の preflight が、そのコミットの CI(`ci.yml`、main への push)が成功していることを確かめる。
- **ghcr.io へのログイン**: Kamal は、イメージを置くときも、サーバーで取ってくるときも `docker login` する(公開のイメージでも、Kamal 2.12 にはサーバーでのログインを飛ばす設定がない)。Actions はそのジョブの `GITHUB_TOKEN`(ジョブが終われば使えなくなる)で入り、終わったら `bin/kamal registry logout --skip-local` でサーバーから外す。Mac はトークンを持たない(第9回 `r9-ghcr`)。`bin/kamal-secret` は `KAMAL_REGISTRY_*` を環境変数からだけ読み、無ければ空にする(置き場所のファイルは読まない)。
  - **Mac でもトークンなしで動くもの**: `bin/kamal app exec --reuse`(`bin/prod-backup`・`bin/prod-runner`)・`bin/kamal lock`・`app logs`・`app stop`/`start`。イメージを取ってこないので、ログインしない(Kamal 2.12 の `lib/kamal/cli/app.rb` で、`docker login` するのは `--reuse` の無い `exec` だけ)。
  - **トークンが要るもの**: `deploy`・`redeploy`・`setup`・`build`・`registry login`、`--reuse` の無い `app exec`(新しいコンテナを起こす。`bin/prod-restore` の置き換え)。前の 5 つは `.kamal/hooks/pre-connect` がつなぐ前に止め、Actions を案内する。`--reuse` の無い `app exec` はフックでは見分けられないので、サーバーの `docker login` で失敗する。

### Environment と、そこに置くもの(名前だけ。値はここにも記録にも書かない)

| 置き場所 | 名前 | 中身 |
|---|---|---|
| Environment `production`(Deployment branches: main だけ。承認者なし) | Secrets `RAILS_MASTER_KEY` `ANTHROPIC_API_KEY` `SMTP_USERNAME` `SMTP_PASSWORD` `NBATO_MAIL_FROM` `NBATO_BACKUP_BUCKET` `NBATO_BACKUP_AWS_ACCESS_KEY_ID` `NBATO_BACKUP_AWS_SECRET_ACCESS_KEY` | Mac の秘密の置き場所と同じ値(原本は Mac) |
| 〃 | Secret `NBATO_SSH_PRIVATE_KEY` | **Actions だけの** SSH の秘密鍵(Mac の `n-bato-deploy` とは別) |
| 〃 | Variable `NBATO_SSH_KNOWN_HOSTS` | サーバーのホスト鍵の行(公開してよいもの) |
| Environment `production-infra`(main だけ。**承認者: 理事長**) | Secret `AWS_CDK_DEPLOY_ROLE_ARN` | CDK の出力 `CdkDeployRoleArn` |
| Environment `production-restore`(main だけ。**承認者: 理事長**) | (何も置かない) | Restore の承認だけに使う。秘密は承認のあとのジョブが `production` から読む |
| リポジトリ | Secret `AWS_CDK_DIFF_ROLE_ARN` | CDK の出力 `CdkDiffRoleArn` |
| リポジトリ | Secret `AWS_GITHUB_OIDC_PROVIDER_ARN`(無くてよい) | アカウントにすでに GitHub の OIDC プロバイダがあるときだけ、その ARN |
| リポジトリ | Variable `DEPLOY_FREEZE` | `true` で止める。それ以外(無いときも)は出してよい |

- ghcr.io のトークンは置かない(Actions の `GITHUB_TOKEN` を使う)。
- 役割の ARN を Secrets にするのは、AWS のアカウント番号を公開のログに出さないため(`mask-aws-account-id` も付ける)。
- Environment を分けるのは、承認者の設定が Environment ごとだから。アプリのデプロイは承認なし(第6回 r6-trigger)、CDK の反映は承認あり(r6-cdk)。分け方は開発QAボード 第8回 8-11 で決めた(`split`)。戻しは承認あり(第9回 r9-ghcr)だが、アプリの秘密を 2 か所に置かないよう、承認だけの `production-restore` と、秘密のある `production` の 2 つのジョブに分けた。

### AWS の役割(OIDC。`infra/lib/n-bato-stack.ts`)

| 役割 | 使えるジョブ(OIDC の sub) | できること |
|---|---|---|
| `n-bato-github-cdk-diff` | `repo:smalruby/n-bato:pull_request`、`repo:smalruby/n-bato:ref:refs/heads/main` | NBatoStack のテンプレートを読む、bootstrap の版を読む。**それだけ**(バケットの中身は読めない) |
| `n-bato-github-cdk-deploy` | `repo:smalruby/n-bato:environment:production-infra` | CDK の bootstrap の役割(`cdk-hnb659fds-*-role-<アカウント>-<リージョン>`)を引き受ける。それだけ |

フォークからの PR には OIDC のトークンが出ないので、差分の役割はフォークからは使えない。

## 初めに一度だけ(人と AI)

順番どおりに行う。**本番・外への操作**と書いたものは、その都度ユーザーに確かめてから行う(`.claude/rules/session-roles.md`)。秘密の値は画面にも記録にも出さない(`gh secret set` は標準入力から読ませる)。

1. **OIDC の役割を作る(本番・外への操作。Mac から cdk deploy)**
   1. 同じ AWS アカウントに GitHub の OIDC プロバイダ(`token.actions.githubusercontent.com`)がすでにあるか確かめる: `aws iam list-open-id-connect-providers`。あれば、以下の cdk のコマンドに `-c githubOidcProviderArn=<その ARN>` を付け、手順 4 で `AWS_GITHUB_OIDC_PROVIDER_ARN` にも入れる(付けたり外したりしない。外すとスタックがプロバイダを作ろうとして失敗する)。
   2. `cd infra && npx cdk diff` で、足されるのが OIDC のプロバイダ・役割 2 つ・その権限だけであることを確かめる。
   3. `npx cdk deploy`。出力の `CdkDiffRoleArn` と `CdkDeployRoleArn` を控える(手元だけ)。
2. **Environment を 3 つ作る(外への操作。GitHub の設定。開発QAボード 第8回 8-11・第9回 r9-ghcr)**
   - `production`(アプリの Deploy): Deployment branches は `main` だけ。承認者は付けない。
   - `production-infra`(Deploy Infra の反映): Deployment branches は `main` だけ。Required reviewers は理事長。
   - `production-restore`(Restore の承認): Deployment branches は `main` だけ。Required reviewers は理事長。秘密は置かない。
   - 作るのは人に確かめてから(AI が勝手に作らない)。画面(Settings → Environments)でも、gh でもよい。gh なら(n-bato のトークンは Administration を書ける):
     ```bash
     export GH_TOKEN=$(cat ~/.private/n-bato-dev.pat)
     R=smalruby/n-bato
     # production: main だけ、承認者なし
     gh api -X PUT "repos/$R/environments/production" --input - \
       <<<'{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
     gh api -X POST "repos/$R/environments/production/deployment-branch-policies" -f name=main -f type=branch

     # production-infra: main だけ、承認者は理事長(<ログイン> は理事長の GitHub のログイン名)
     REVIEWER_ID=$(gh api "users/<ログイン>" --jq .id)
     gh api -X PUT "repos/$R/environments/production-infra" --input - \
       <<<"{\"reviewers\":[{\"type\":\"User\",\"id\":${REVIEWER_ID}}],\"prevent_self_review\":false,\"deployment_branch_policy\":{\"protected_branches\":false,\"custom_branch_policies\":true}}"
     gh api -X POST "repos/$R/environments/production-infra/deployment-branch-policies" -f name=main -f type=branch

     # production-restore: main だけ、承認者は理事長(Restore の承認だけ。秘密は置かない)
     gh api -X PUT "repos/$R/environments/production-restore" --input - \
       <<<"{\"reviewers\":[{\"type\":\"User\",\"id\":${REVIEWER_ID}}],\"prevent_self_review\":false,\"deployment_branch_policy\":{\"protected_branches\":false,\"custom_branch_policies\":true}}"
     gh api -X POST "repos/$R/environments/production-restore/deployment-branch-policies" -f name=main -f type=branch

     # 確かめる(承認者があるのは production-infra と production-restore、どれも main だけ)
     gh api "repos/$R/environments" --jq '.environments[] | {name, rules: [.protection_rules[].type]}'
     gh api "repos/$R/environments/production/deployment-branch-policies" --jq '[.branch_policies[].name]'
     gh api "repos/$R/environments/production-infra/deployment-branch-policies" --jq '[.branch_policies[].name]'
     gh api "repos/$R/environments/production-restore/deployment-branch-policies" --jq '[.branch_policies[].name]'
     ```
   - `prevent_self_review` は `false` にする。Deploy Infra は main へのマージで起き、Restore は AI が理事長のトークンで起こすので、どちらも理事長が「起こした人」になるため。`true` にすると、理事長が承認できなくなる。
   - 承認は理事長が GitHub の画面で行う。AI は承認しない(下の「AWS の部品を変える」)。AI が使う n-bato のトークンは理事長のものなので、**Deployments の書き込みの権限を付けない**(付けると、承認の API を AI が呼べてしまい、承認者の設定が決まりだけになる)。トークンの権限を絞るときも、これを外したままにする。
3. **Actions だけの SSH の鍵を作って、サーバーに登録する(本番の操作)**
   ```bash
   # 作る(Mac の秘密の置き場所に。パスフレーズなし、Actions が使うため)
   ssh-keygen -t ed25519 -N '' -C 'n-bato-actions' -f "$NBATO_SECRETS_DIR/n-bato-actions"
   chmod 600 "$NBATO_SECRETS_DIR/n-bato-actions"
   # サーバーに足す(Mac の鍵で入る)。restrict でポート転送・エージェント転送・端末を止める
   { printf 'restrict '; cat "$NBATO_SECRETS_DIR/n-bato-actions.pub"; } \
     | ssh -i "$NBATO_SECRETS_DIR/n-bato-deploy" -l ubuntu n-bato.smalruby.app 'umask 077; cat >> ~/.ssh/authorized_keys'
   ```
   - Actions から入れなくするときは、サーバーの `~/.ssh/authorized_keys` から `n-bato-actions` の行を消す(Mac の鍵はそのまま使える)。
   - サーバーを作り直す(CDK で置き換わる)と、この行は消える。そのときはもう一度足す。
   - 長く使う鍵を置かない仕組み(使い捨ての証明書など)は #25。
4. **Secrets と変数を入れる(外への操作。値は出さない)**
   ```bash
   export GH_TOKEN=$(cat ~/.private/n-bato-dev.pat) R=smalruby/n-bato
   # アプリの秘密: bin/kamal-secret が Mac の置き場所から読む(対応表は 1 か所だけ)
   for name in RAILS_MASTER_KEY ANTHROPIC_API_KEY SMTP_USERNAME SMTP_PASSWORD NBATO_MAIL_FROM \
               NBATO_BACKUP_BUCKET NBATO_BACKUP_AWS_ACCESS_KEY_ID NBATO_BACKUP_AWS_SECRET_ACCESS_KEY; do
     bin/kamal-secret "$name" | gh secret set "$name" --env production --repo "$R"
   done
   # SSH は Actions だけの鍵(bin/kamal-secret の NBATO_SSH_PRIVATE_KEY は Mac の鍵なので使わない)
   gh secret set NBATO_SSH_PRIVATE_KEY --env production --repo "$R" < "$NBATO_SECRETS_DIR/n-bato-actions"
   # ホスト鍵: Mac がすでに信じている行を写す(つなぎ直して取るより確か)
   ssh-keygen -F n-bato.smalruby.app | grep -v '^#' | gh variable set NBATO_SSH_KNOWN_HOSTS --env production --repo "$R"
   # 役割の ARN(手順 1 の出力)
   gh secret set AWS_CDK_DIFF_ROLE_ARN --repo "$R"                       # 聞かれたら貼る
   gh secret set AWS_CDK_DEPLOY_ROLE_ARN --env production-infra --repo "$R"
   ```
   - `ssh-keygen -F` の行がハッシュされていても、そのまま使える。
   - 鍵を変えたときは、Mac の置き場所(原本)を直してから、同じコマンドで入れ直す。
5. **Mac に ghcr.io のトークンは置かない**(開発QAボード 第9回 `r9-ghcr`)。Actions が止まっているときだけ、下の「Actions が止まっているとき」の手順で、その都度作って消す。
6. **はじめての Deploy(本番の操作)**
   1. AI が `gh workflow run deploy.yml --ref main` で起動する(下の「AI が毎回すること」)。
   2. パッケージ `ghcr.io/smalruby/n-bato` ができたら、公開にする前に、中に鍵が無いことを確かめる(AI):
      ```bash
      docker run --rm --platform linux/amd64 --entrypoint sh ghcr.io/smalruby/n-bato:<コミット> -c \
        'cd /rails; for f in config/master.key config/credentials/production.key .env .kamal data notes storage/production.sqlite3; do [ -e "$f" ] && echo "ある: $f"; done; env | cut -d= -f1 | sort'
      ```
      「ある:」が 1 行も出ず、環境変数の名前に鍵(`RAILS_MASTER_KEY`・`*_KEY`・`*_PASSWORD` など)が無いこと。
   3. 人がパッケージの設定(Package settings → Danger Zone → Change visibility)で **Public** にする(外への操作)。org の設定で公開のパッケージが許されていないときは、そこも直す。
   4. 前の版(`localhost:5555/n-bato`)には `bin/kamal rollback` で戻れない(イメージの名前が変わったため)。戻すときは、前のコミットを Deploy し直す。
7. **あとかたづけ(急がない)**: Mac の一時的なレジストリ(`kamal-docker-registry` のコンテナ)は使わなくなる。`docker rm -f kamal-docker-registry` で消してよい。

## AI が毎回すること

### アプリを出す

1. 出してよい時かを確かめる(`.claude/rules/session-roles.md`: 運用のスクリプトが使うモデル・属性が変わる、データの形が変わるマイグレーションを含む、なら前もって連絡帳で知らせる)。
2. main のそのコミットの CI が通っていることを確かめる: `GH_TOKEN=$(cat ~/.private/n-bato-dev.pat) gh run list --workflow ci.yml --branch main --limit 1`
3. 起動する:
   ```bash
   export GH_TOKEN=$(cat ~/.private/n-bato-dev.pat)
   gh workflow run deploy.yml --ref main --repo smalruby/n-bato
   gh run list --workflow deploy.yml --limit 1 --repo smalruby/n-bato   # 番号を見て
   gh run watch <番号> --repo smalruby/n-bato --exit-status
   ```
4. 終わったら https://n-bato.smalruby.app/up を確かめ、連絡帳に書く。

### バックアップから戻す(Restore)

戻すと、そのバックアップのあとの変更はすべて消える。**ユーザーに確かめてから**起こす(本番の DB への書き込み)。

1. 戻す名前を確かめる: `NBATO_SECRETS_DIR=... bin/prod-backup --list`(Mac。トークンは要らない)。
2. ユーザーに、戻す名前と消える範囲を伝えて確かめる。
3. 起動する:
   ```bash
   export GH_TOKEN=$(cat ~/.private/n-bato-dev.pat)
   gh workflow run restore.yml --ref main --repo smalruby/n-bato -f backup=production-YYYYMMDD-HHMMSS.sqlite3
   gh run list --workflow restore.yml --limit 1 --repo smalruby/n-bato   # 番号を見て
   ```
4. **理事長が GitHub の画面で承認する**(Environment `production-restore`。AI は承認しない)。承認のあと、`bin/prod-restore` が流れる(ロック → いまの状態も写す → 止める → 置き換える → 起動 → /up)。
5. `gh run watch <番号> --repo smalruby/n-bato --exit-status` で終わりを待ち、要約(名前と /up)を確かめて、連絡帳に書く。
- `DEPLOY_FREEZE` では止まらない(戻しは、止めている時期にも使う逃げ道のため)。Deploy とは同じ順番待ちに並ぶ。

止まったとき:
- 「DEPLOY_FREEZE が true」: 止めている時期。人に聞く(スイッチを勝手に外さない)。
- 「CI が通っていません」: CI が終わるのを待つか、直す。
- Kamal のロック: 運用のスクリプトが流れているかもしれない。`bin/kamal lock status`(Mac)で確かめ、運用に聞く。

### 止めるスイッチ

```bash
GH_TOKEN=$(cat ~/.private/n-bato-dev.pat) gh variable set DEPLOY_FREEZE --body true  --repo smalruby/n-bato   # 止める
GH_TOKEN=$(cat ~/.private/n-bato-dev.pat) gh variable set DEPLOY_FREEZE --body false --repo smalruby/n-bato   # 戻す
```

入れる・外すのは、人が決めたときだけ。

### CDK だけ急いで反映するとき(止めるスイッチが入っている間)

`DEPLOY_FREEZE` はアプリの Deploy にも Deploy Infra にも効く(開発QAボード 第8回 8-14)。CDK だけ急いで直したいときは、人が決めてから、スイッチを一時的に切る。

1. 人に確かめる。切っている間はアプリの Deploy も出せてしまうので、その間 AI は Deploy を起動しない。
2. 切る: `GH_TOKEN=$(cat ~/.private/n-bato-dev.pat) gh variable set DEPLOY_FREEZE --body false --repo smalruby/n-bato`
3. Deploy Infra を起こす: `GH_TOKEN=$(cat ~/.private/n-bato-dev.pat) gh workflow run deploy-infra.yml --ref main --repo smalruby/n-bato`(main に入ったときにスイッチで止まった Run は、これで流し直す)。差分を見て、理事長が承認する。
4. 反映のジョブ(「本番に反映する」)が始まったら、すぐ戻す: `... gh variable set DEPLOY_FREEZE --body true ...`。反映のジョブは始めにスイッチを見るので、承認の前に戻すと承認のあとで止まる。承認しないで止めるときも、戻す。

### AWS の部品を変える

1. `infra/` を変えた PR(または main へのコミット)で、CI - Infra の要約の差分を読む。
2. main に入ると Deploy Infra が走り、差分があれば `production-infra` の承認を待つ。理事長に、要約の差分を見て承認してもらう(AI は承認しない)。
3. 差分に削除・置き換えがあると、Deploy Infra は止まる。人が差分を読み、よければ Mac から `cd infra && npx cdk deploy` する(本番の操作)。

## Actions が止まっているとき(Mac からの予備の道)

GitHub Actions が使えないときだけ使う。Mac には ghcr.io のトークンを置かないので、その都度、理事長が期限の短いトークンを作り、終わったら消す(開発QAボード 第9回 `r9-ghcr`)。

1. **理事長がトークンを作る(外への操作)**: GitHub の Settings → Developer settings → Personal access tokens → **Tokens (classic)**。権限は **`write:packages` だけ**(`read:packages` は付いてくる)、期限は **7 日**。ghcr.io は fine-grained のトークンを受け付けないため classic にする。
2. **環境変数で渡して、Mac から操作する**(ファイルに書かない。履歴に残らないよう `read -s` で読む):
   ```bash
   read -rs KAMAL_REGISTRY_PASSWORD && export KAMAL_REGISTRY_PASSWORD   # トークンを貼る(画面に出ない)
   export KAMAL_REGISTRY_USERNAME=<理事長の GitHub のログイン名>
   export NBATO_SECRETS_DIR=...                                          # 秘密の置き場所(CLAUDE.local.md)
   bin/kamal deploy                                   # デプロイ。`DEPLOY_FREEZE` は効かないので、止めている時期かを自分で確かめる
   bin/prod-restore production-YYYYMMDD-HHMMSS.sqlite3   # 戻し(理事長に確かめてから。名前を入れ直す)
   ```
   - `config/deploy.yml` と `.kamal/secrets` は Actions と同じ。違うのは、秘密が `$NBATO_SECRETS_DIR` のファイルから来ることと、SSH の鍵が `n-bato-deploy` であること。
   - イメージは Mac で作って ghcr.io に置く(Apple シリコンでも amd64 で作る。`builder.arch`)。
3. **サーバーと Mac から外す**: `bin/kamal registry logout`(サーバーと手元の両方)。`unset KAMAL_REGISTRY_PASSWORD KAMAL_REGISTRY_USERNAME`。
4. **理事長がトークンを GitHub で消す**(期限を待たない)。
