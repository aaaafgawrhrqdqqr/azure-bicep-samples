# 構築手順書（初めての人向け）

この手順書どおりに進めると、次の状態になります。

- Azure に、**インターネットから直接アクセスできない Foundry** ができる
- GitHub の `agents/` フォルダーにあるエージェント定義を変更して保存（push）するだけで、
  **自動的に Foundry のエージェントが更新される**

所要時間は全体で **1〜1.5 時間** ほどです（そのうち 20 分ほどは Azure の構築待ち）。

---

## 0. 全体の流れ

```
手順 1  事前準備を確認する                      … 5 分
手順 2  GitHub に空のリポジトリを作る             … 5 分
手順 3  Runner 用のトークン（PAT）を作る          … 5 分
手順 4  Azure の準備スクリプトを実行する          … 10 分
手順 5  GitHub に設定値を登録する                … 10 分
手順 6  コードを GitHub に送る（push）            … 5 分
手順 7  自動で構築される様子を確認する            … 20〜30 分（待ち時間あり）
手順 8  エージェントを変更して、自動反映を試す    … 10 分
```

**順番が大事です。** 手順 5（設定値の登録）より前に手順 6（push）をすると、
設定値がない状態で自動構築が始まって失敗します。必ず番号順に進めてください。

### 用語の説明

| 用語 | 意味 |
|---|---|
| リポジトリ | GitHub 上のフォルダーのようなもの。コードと変更履歴を保存する |
| push（プッシュ） | 自分の PC のコードを GitHub に送ること |
| ワークフロー | GitHub Actions で自動実行される処理。`.github/workflows/` の YAML ファイルに書いてある |
| Runner（ランナー） | ワークフローを実際に実行するコンピューター |
| PAT | Personal Access Token。GitHub の操作を許可する「合い鍵」のような文字列 |
| OIDC | GitHub と Azure の間で、パスワードを使わずに信頼関係を作る仕組み |
| Managed Identity | Azure のリソースに付ける「Azure 専用の身分証」。パスワード不要で Azure にサインインできる |
| Private Endpoint | Azure のサービスに、VNet の中からだけ届く入口を作る仕組み |

---

## 手順 1. 事前準備を確認する

次の 4 つがそろっているか確認してください。

### 1-1. GitHub のアカウント

https://github.com にサインインできれば OK です。Free プランで構いません。

### 1-2. Azure のサブスクリプションと権限

このサブスクリプションで **所有者（Owner）** の権限が必要です
（準備スクリプトの中で、権限の割り当てを行うため）。

確認方法：
1. https://portal.azure.com を開く
2. 上の検索欄に「サブスクリプション」と入力して開く
3. 使うサブスクリプションをクリック
4. 左メニューの **アクセス制御 (IAM)** → **自分のアクセスを表示**
5. 「所有者」が表示されていれば OK

> 個人で作ったサブスクリプションなら、通常は所有者になっています。
> 会社のサブスクリプションで「共同作成者」しかない場合は、管理者に相談してください。

### 1-3. Git

PowerShell を開いて、次を入力します。

```powershell
git --version
```

`git version 2.xx.x` のように表示されれば OK です。
表示されない場合は https://git-scm.com からインストールしてください。

### 1-4. このフォルダー

`C:\work\foundry-private-cicd` に、次のファイルがあることを確認します。

```
.github\workflows\infra.yml
.github\workflows\agents.yml
agents\helpdesk-agent.yaml
infra\base.bicep
infra\main.bicep
runner\Dockerfile
runner\entrypoint.sh
scripts\（Python ファイルなど）
```

---

## 手順 2. GitHub に空のリポジトリを作る

1. https://github.com/new を開く
2. 次のように入力する

   | 項目 | 入力する値 |
   |---|---|
   | Owner | 自分のユーザー名（または Organization） |
   | Repository name | `foundry-private-cicd`（好きな名前で OK） |
   | Visibility | **Private**（必ず Private にする） |
   | Add a README file | **チェックしない**（空のまま作る） |
   | .gitignore / license | **None のまま** |

3. **Create repository** を押す

作成後の画面の URL を控えてください。

```
https://github.com/<Owner>/<Repository name>
```

この **Owner** と **Repository name** は、このあと何度も使います。

> **なぜ Private が必須？**
> この構成では、Azure の VNet の中でワークフローを実行します。
> Public にすると、他人が送ったプル リクエストのコードが VNet の中で実行されるおそれがあります。

---

## 手順 3. Runner 用のトークン（PAT）を作る

Azure の中の Runner が GitHub に「ジョブはありますか？」と問い合わせたり、
自分を Runner として登録したりするために使います。

1. GitHub の右上の自分のアイコン → **Settings**
2. 左メニューの一番下 → **Developer settings**
3. **Personal access tokens** → **Fine-grained tokens**
4. **Generate new token** を押す
5. 次のように入力する

   | 項目 | 入力する値 |
   |---|---|
   | Token name | `foundry-runner`（分かりやすい名前） |
   | Expiration | `90 days` など（期限が来たら作り直す） |
   | Repository access | **Only select repositories** → 手順 2 で作ったリポジトリを選ぶ |

6. **Permissions** の **Repository permissions** で、次の 3 つだけを設定する

   | 権限 | 設定 |
   |---|---|
   | Actions | **Read-only** |
   | Administration | **Read and write** |
   | Metadata | **Read-only**（自動で設定される） |

7. 一番下の **Generate token** を押す
8. 表示された `github_pat_...` で始まる文字列を **コピーしてメモ帳などに一時保存** する

> **この画面を閉じると、トークンは二度と表示されません。** 必ずコピーしてください。
> トークンはパスワードと同じです。人に見せたり、ファイルに保存してコミットしたりしないでください。

---

## 手順 4. Azure の準備スクリプトを実行する

Azure の中に、次のものを作ります。
- リソースグループ（今回作るものをまとめて入れる箱）
- GitHub がパスワードなしで Azure にサインインするための ID（OIDC 用の Managed Identity）
- その ID への権限

### 4-1. Cloud Shell を開く

1. https://portal.azure.com を開く
2. 画面上部の **`>_`** のアイコン（Cloud Shell）を押す
3. 初回は「Bash」か「PowerShell」かを聞かれるので **Bash** を選ぶ
4. 初回はストレージの設定を聞かれるので、**ストレージ アカウントは不要（No storage account required）** を選び、
   サブスクリプションを選んで **適用** を押す
5. 画面下に黒い画面（ターミナル）が出て、`$` が表示されれば準備完了

> Cloud Shell の上部の表示が「PowerShell」になっている場合は、「Bash に切り替える」を押してください。

### 4-2. 正しいサブスクリプションが選ばれているか確認する

```bash
az account show --query "{name:name, id:id}" -o table
```

使いたいサブスクリプションの名前が表示されれば OK です。違う場合は次で切り替えます。

```bash
az account list -o table
az account set --subscription "<使いたいサブスクリプションの名前か ID>"
```

### 4-3. 使うリージョンでモデルが使えるか確認する

この構成は **東日本（japaneast）** で `gpt-5-mini` を使う設定になっています。使えるか確認します。

```bash
az cognitiveservices model list --location japaneast \
  --query "[?model.name=='gpt-5-mini'].{version:model.version, sku:join(',', model.skus[].name)}" -o table
```

- `2025-08-07` と `GlobalStandard` が表示されれば OK
- 何も表示されない場合は、別のリージョンやモデルを使う必要があります。この時点で相談してください

### 4-4. 準備スクリプトをアップロードする

1. Cloud Shell の上部メニューの **ファイルの管理**（または **アップロード/ダウンロード** のアイコン）→ **アップロード**
2. 自分の PC の `C:\work\foundry-private-cicd\scripts\bootstrap.sh` を選ぶ
3. アップロードが終わったら、次で確認する

```bash
ls -l bootstrap.sh
```

`bootstrap.sh` が表示されれば OK です。

### 4-5. 準備スクリプトを実行する

`<Owner>` と `<Repository name>` を、手順 2 で控えた値に置き換えて実行します
（`<` と `>` は消してください）。

```bash
GH_OWNER=<Owner> GH_REPO=<Repository name> bash bootstrap.sh
```

例：
```bash
GH_OWNER=taro-yamada GH_REPO=foundry-private-cicd bash bootstrap.sh
```

1〜3 分ほどで終わり、最後に次のような表示が出ます。

```
完了しました。GitHub のリポジトリ → Settings → Secrets and variables → Actions の
「Variables」に次を登録してください。

  AZURE_CLIENT_ID        = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  AZURE_TENANT_ID        = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  AZURE_SUBSCRIPTION_ID  = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  AZURE_RESOURCE_GROUP   = rg-foundry-private-cicd
  AZURE_LOCATION         = japaneast
```

**この 5 行をメモ帳にコピーしておきます。**（これらは秘密情報ではありません）

#### うまくいかないとき

| 表示されたエラー | 対処 |
|---|---|
| `AuthorizationFailed` / `does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/write'` | 所有者の権限がありません（手順 1-2 を確認） |
| `PrincipalNotFound` / `Cannot find user or service principal` | 作った ID の反映待ちです。1〜2 分待って、同じコマンドをもう一度実行してください（何度実行しても問題ありません） |
| `GH_OWNER を指定してください` | コマンドの `GH_OWNER=...` の部分が抜けています |

---

## 手順 5. GitHub に設定値を登録する

ワークフローが Azure にサインインするための情報を、GitHub に登録します。

### 5-1. Variables（変数）を 5 つ登録する

1. 手順 2 で作ったリポジトリを開く
2. 上部のタブの **Settings**（歯車）
3. 左メニューの **Secrets and variables** → **Actions**
4. **Variables** タブを選ぶ
5. **New repository variable** を押し、Name と Value を入力して **Add variable**
6. これを 5 回繰り返す

| Name | Value |
|---|---|
| `AZURE_CLIENT_ID` | 手順 4-5 で表示された値 |
| `AZURE_TENANT_ID` | 手順 4-5 で表示された値 |
| `AZURE_SUBSCRIPTION_ID` | 手順 4-5 で表示された値 |
| `AZURE_RESOURCE_GROUP` | `rg-foundry-private-cicd` |
| `AZURE_LOCATION` | `japaneast` |

> Name は **大文字・アンダースコアまで完全に同じ** にしてください。1 文字でも違うとワークフローが失敗します。

### 5-2. Secret（秘密の値）を 1 つ登録する

1. 同じ画面で **Secrets** タブを選ぶ
2. **New repository secret** を押す
3. 次を入力して **Add secret**

| Name | Secret |
|---|---|
| `RUNNER_GITHUB_PAT` | 手順 3 で作ったトークン（`github_pat_...`） |

> Secrets に登録した値は、登録後は誰も（自分も）見られません。ログにも `***` と表示されます。
> メモ帳に一時保存したトークンは、ここまで終わったら削除してください。

### 5-3. 登録内容を確認する

- Variables タブに 5 つ並んでいる
- Secrets タブに `RUNNER_GITHUB_PAT` がある

---

## 手順 6. コードを GitHub に送る（push）

PC の **PowerShell** を開き、次を 1 行ずつ実行します。
`<Owner>` と `<Repository name>` は自分の値に置き換えてください。

```powershell
cd C:\work\foundry-private-cicd

# Git の管理を始める（ブランチ名は main）
git init -b main

# 初めて Git を使う場合だけ、名前とメールを設定する（コミットに記録される）
git config user.name "自分の名前"
git config user.email "GitHub に登録しているメールアドレス"

# すべてのファイルを登録して、保存（コミット）する
git add .
git commit -m "初回: Foundry 閉域 CI/CD 一式"

# 送り先（GitHub のリポジトリ）を設定して、送る
git remote add origin https://github.com/<Owner>/<Repository name>.git
git push -u origin main
```

`git push` を実行すると、初回はブラウザーが開いて **GitHub へのサインイン** を求められます。
サインインして許可すると、送信が完了します。

確認：ブラウザーでリポジトリを開き、ファイルが表示されていれば成功です。

---

## 手順 7. 自動で構築される様子を確認する

push した瞬間に、ワークフローが自動で動き始めます。

### 7-1. Actions の画面を開く

リポジトリの上部タブの **Actions** を開くと、2 つのワークフローが動いています。

| ワークフロー | 状態 | 説明 |
|---|---|---|
| **infra** | 🟡 実行中 | Azure に VNet、Foundry、Runner などを作っている（**15〜20 分**） |
| **agents** | 🟡 待機中 | `validate` はすぐ ✅ になる。`deploy` は「**Waiting for a runner to pick up this job...**」と表示されたまま待つ |

> **agents の deploy が待機中なのは正常です。** deploy を実行する Runner は、
> infra ワークフローがこれから作るので、まだ存在しないためです。
> infra が終わって Runner ができると、自動的に実行が始まります。

### 7-2. infra の進み具合を見る

1. **infra** をクリック → **deploy** をクリック
2. 各ステップの進み具合とログが見られる

| ステップ | 内容 | 時間の目安 |
|---|---|---|
| Azure にサインイン（OIDC） | パスワードなしで Azure にサインイン | 数秒 |
| ACR を作る | イメージの置き場を作る | 1 分 |
| Runner イメージを作って push | Runner のコンテナーを作る | 3〜5 分 |
| Foundry と Runner を作る | 本体を作る | 10〜15 分 |

全部 ✅ になったら、画面下の **Summary** にデプロイ結果（Foundry の名前、エンドポイントなど）が表示されます。

### 7-3. agents が自動で動く

infra が終わると、1 分ほどで次が起きます。

1. Azure の中で Runner（Container Apps ジョブ）が起動する
2. 待機していた agents の **deploy** が動き始める
3. 「エージェントを反映」→「動作確認」のステップが実行される

「動作確認」のログに、次のような内容が出れば **すべて成功** です。

```
--- helpdesk-agent ---
Q: パスワードを忘れたときはどうすればいいですか？
A: （エージェントの回答）

動作確認 OK
```

> infra の完了をきっかけに、agents がもう 1 回自動で実行されることがあります。正常な動きです。

### 7-4. Azure 側でも確認する（任意）

1. Azure Portal で **リソースグループ** → `rg-foundry-private-cicd` を開く
2. 次のようなリソースが並んでいる

| 種類 | 名前の例 |
|---|---|
| Foundry | `fdy-aif-xxxxxxxx` |
| 仮想ネットワーク | `fdy-vnet` |
| プライベート エンドポイント | `pe-fdy-aif-xxxxxxxx` |
| プライベート DNS ゾーン × 3 | `privatelink.….azure.com` |
| Container Apps 環境 | `fdy-cae` |
| Container Apps ジョブ | `fdy-job-gh-runner` |
| コンテナー レジストリ | `acrxxxxxxxx` |
| マネージド ID | `id-github-infra`、`fdy-id-runner` |

3. **Container Apps ジョブ**（`fdy-job-gh-runner`）→ 左メニューの **実行履歴** を開くと、
   Runner が起動して終了した記録が見られます

4. **Foundry**（`fdy-aif-…`）→ 左メニューの **ネットワーク** を開くと、
   公開アクセスが **無効** になっていることが確認できます

> Foundry ポータル（ai.azure.com）でエージェントを見ようとしても、公開アクセスが無効なので見られません。
> これは「閉域になっている」証拠です。見たい場合は README の「Foundry ポータルでの確認」を参照してください。

---

## 手順 8. エージェントを変更して、自動反映を試す

ここからが普段の使い方です。

### 8-1. GitHub の画面で直接変更する（いちばん簡単）

1. リポジトリで `agents/helpdesk-agent.yaml` を開く
2. 右上の鉛筆アイコン（Edit this file）を押す
3. `instructions:` の中身を書き換える（例：「必ず最後に『他にご不明点はありますか？』と添えてください。」を追加）
4. 右上の **Commit changes...** を押す
5. 「Commit directly to the main branch」を選んで **Commit changes**
6. **Actions** タブを開くと、agents ワークフローが自動で動き出す
7. 1〜3 分で完了し、「動作確認」のログで変更が反映された回答を確認できる

### 8-2. レビューを挟む方法（チームで使う場合のおすすめ）

5 の手順で **Create a new branch for this commit and start a pull request** を選ぶと、

1. プル リクエストが作られ、**validate**（定義の書き方のチェック）だけが動く
2. 内容を確認して **Merge pull request** を押す
3. main に入った時点で **deploy** が動き、Foundry に反映される

という流れになり、「レビューを通ったものだけが本番に入る」運用ができます。

### 8-3. エージェントを増やす

`agents/` フォルダーに新しい YAML ファイルを追加するだけです。
`helpdesk-agent.yaml` をコピーして、`name` を別の名前に変えてください。

---

## うまくいかないとき（よくあるエラー）

| どこで | エラーの例 | 原因と対処 |
|---|---|---|
| infra「Azure にサインイン」 | `AADSTS700213` / `AADSTS70021: No matching federated identity record found for presented assertion subject 'repo:…'` | GitHub が送ってきた身分証明（subject）が Azure の登録と一致しない。**下の「subject が一致しないとき」を参照** |
| infra「Azure にサインイン」 | `Login failed ... client-id` | Variables の Name の打ち間違い、または値の貼り間違い（手順 5-1） |
| infra「ACR を作る」など | `AuthorizationFailed` | 権限の反映待ち。数分待って、Actions → infra → **Re-run all jobs** |
| infra「Foundry と Runner を作る」 | `InsufficientQuota` / `quota` | モデルの容量（クォータ）が足りない。`infra/main.bicep` の `modelCapacity` を小さくする（例: 10 → 5） |
| infra「Foundry と Runner を作る」 | `FlagMustBeSetForRestore` / `already exists in deleted state` | 以前削除した Foundry が「論理削除」状態で残っている。下の「後片付け」の purge を実行 |
| agents「deploy」 | ずっと「Waiting for a runner」 | ① infra が成功しているか確認 ② Secret `RUNNER_GITHUB_PAT` の値と権限（手順 3）を確認 ③ PAT の期限切れ |
| agents「エージェントを反映」 | `PermissionDenied` / `401` / `403` | 権限の反映待ち（最大 10 分ほど）。少し待って **Re-run jobs** |
| agents「エージェントを反映」 | 名前解決や接続のエラー | Private DNS の設定が反映されていない。infra をもう一度実行する |
| agents「動作確認」 | `DeploymentNotFound` | YAML の `model` が `infra/main.bicep` の `modelName` と違う |

ログの見方：Actions → 失敗したワークフロー → 赤い ❌ のジョブ → 赤いステップを開くと、エラーの詳細が見られます。

### subject が一致しないとき（`AADSTS700213`）

GitHub が Azure に渡す身分証明（subject）は、リポジトリによって次の 2 つの形式があります。

| 形式 | 例 |
|---|---|
| 従来の形式 | `repo:taro/foundry-private-cicd:ref:refs/heads/main` |
| ID 付きの新しい形式 | `repo:taro@12345678/foundry-private-cicd@987654321:ref:refs/heads/main` |

bootstrap.sh は従来の形式で登録しています。新しい形式が送られてきた場合は、次の手順で追加します。

1. 失敗したログのエラー文から、`presented assertion subject '` と `'` の間の文字列をコピーする
   （ログの少し上の `subject claim - ` の後ろにも同じ文字列があります）
2. Cloud Shell で、`<コピーした文字列>` を置き換えて実行する

   ```bash
   az identity federated-credential create \
     --name github-main-ids \
     --identity-name id-github-infra \
     --resource-group rg-foundry-private-cicd \
     --issuer "https://token.actions.githubusercontent.com" \
     --subject "<コピーした文字列>" \
     --audiences "api://AzureADTokenExchange"
   ```

3. 1 分ほど待ってから、Actions → infra → **Re-run all jobs** を押す

> 最初から両方の形式を登録しておくこともできます。bootstrap.sh を実行するときに
> `GH_OIDC_SUBJECT="<新しい形式の文字列>"` を一緒に指定してください。

---

## 後片付け（検証が終わったら）

Azure の費用を止めるには、リソースグループごと削除します。

### 1. リソースグループを削除する

Cloud Shell で実行します（10 分ほどかかります）。

```bash
az group delete --name rg-foundry-private-cicd --yes
```

### 2. Foundry を完全に削除する（purge）

Foundry は削除しても 48 時間ほど「論理削除」の状態で残り、同じ名前で作り直せません。
同じ構成をもう一度作る予定があるなら、完全に削除しておきます。

```bash
# 論理削除された Foundry の一覧
az cognitiveservices account list-deleted -o table

# 完全に削除（名前と場所は上の一覧の値）
az cognitiveservices account purge \
  --name <Foundryの名前> \
  --resource-group rg-foundry-private-cicd \
  --location japaneast
```

### 3. GitHub 側を片付ける

- 手順 3 で作った PAT を削除する（Settings → Developer settings → Fine-grained tokens → 削除）
- リポジトリが不要なら削除する（リポジトリの Settings → 一番下の Delete this repository）

### もう一度作り直すとき

リソースグループを削除すると、手順 4 で作った「GitHub 用の ID」も一緒に消えます。
作り直すときは **手順 4 から** やり直し、手順 5-1 の `AZURE_CLIENT_ID` を新しい値に更新してから、
Actions → infra → **Run workflow** を押してください。
