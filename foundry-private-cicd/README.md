> ブログ「たいやきまんの技術備忘録」の記事「閉域の Microsoft Foundry に GitHub Actions でエージェントまでデプロイする」で使ったコード一式です。
> このフォルダーの中身を、新しいリポジトリのルートにそのまま置いて使います（`.github/workflows` もルートに置く）。
> 実機で動かしたあと、OIDC の subject の新しい形式への対応（`scripts/bootstrap.sh` の `GH_OIDC_SUBJECT`）と、手順書（`docs/setup-guide.md`）の追記を加えています。

# Foundry（閉域）へ GitHub Actions でエージェントまでデプロイする

Microsoft Foundry を **公開アクセスなし（Private Endpoint のみ）** で作り、
GitHub Actions から **インフラとプロンプト エージェントの定義** までを自動でデプロイする構成です。
GitHub は **Free プランのまま** 使えます。

## 全体像

```
┌──────────── GitHub ────────────┐
│ infra ワークフロー             │  標準の GitHub-hosted runner（無料枠）
│   └ Bicep で Azure を構築 ─────┼──► ARM（管理プレーン。公開エンドポイント）
│                                │
│ agents ワークフロー            │
│   ├ validate（定義の検証）     │  標準の GitHub-hosted runner（Azure に接続しない）
│   └ deploy ◄───ジョブを取りに来る── VNet 内の Self-hosted runner
└────────────────────────────────┘
                                         │
┌──────────────── Azure の VNet ─────────┼──────────────────────────┐
│ snet-aca: Container Apps 環境（受信口なし）                         │
│   └ Runner ジョブ（GitHub にジョブがあるときだけ起動、終わったら消える） │
│        │ Managed Identity で認証                                    │
│        ▼ Private DNS → Private Endpoint                             │
│ snet-pe : Foundry の Private Endpoint                               │
│            └ Foundry（公開アクセス無効）                            │
│                ├ プロジェクト proj-agents                           │
│                │   └ エージェント（agents/*.yaml の内容）           │
│                └ モデルのデプロイ（gpt-5-mini、従量課金）           │
└────────────────────────────────────────────────────────────────────┘
```

### 2 つの層に分けている理由

| 層 | 何をするか | どこで動くか | なぜそこか |
|---|---|---|---|
| インフラ層 | VNet、Foundry、モデル、Runner を作る | 標準の GitHub-hosted runner | Bicep のデプロイは ARM（管理プレーン）への操作で、ARM は公開エンドポイント。Foundry を閉じていても外から作れる。無料枠で動かせる |
| エージェント層 | エージェント定義の反映と動作確認 | VNet 内の Self-hosted runner | エージェントの作成はプロジェクトのエンドポイント（データ プレーン）への操作。公開アクセスを無効にしたので、Private Endpoint 経由でしか届かない |

この分け方で、「Runner がまだないので、Runner を作るパイプラインが動かない」という
**最初の鶏と卵の問題** も起きません（Runner 自体をインフラ層が作るため）。

### 認証の考え方

| 誰が | 何で認証するか | 持っている権限 |
|---|---|---|
| infra ワークフロー | **OIDC**（GitHub が発行するトークンを Entra ID が信頼する。シークレット不要） | リソースグループの共同作成者 + ロール割り当て |
| agents ワークフロー（deploy） | **Runner の Managed Identity** | Foundry プロジェクトの Foundry User だけ |

Foundry を操作できる資格情報は **GitHub には一切置いていません**。
Foundry に触れるのは「VNet の中で動いている Runner」だけです。
GitHub-hosted runner や他人の PC からは、仮にコードを改ざんされても Foundry に届きません。

## ファイル構成と中身

```
infra/base.bicep            ACR（Runner イメージの置き場）
infra/main.bicep            VNet、Private DNS、Foundry、Private Endpoint、Runner など本体
runner/Dockerfile           Runner のコンテナー イメージ
runner/entrypoint.sh        Runner の起動処理（登録 → ジョブ 1 件 → 終了）
agents/*.yaml               エージェント定義（1 ファイル = 1 エージェント）
scripts/agent_defs.py       定義の読み込みと検証
scripts/deploy_agents.py    定義を Foundry に反映
scripts/smoke_test.py       反映したエージェントに実際に質問して確認
scripts/bootstrap.sh        最初に 1 回だけ手で実行する準備
.github/workflows/infra.yml   インフラ層のワークフロー
.github/workflows/agents.yml  エージェント層のワークフロー
```

### infra/base.bicep

Runner のイメージを置く ACR（Basic）だけを作ります。
main.bicep の Runner ジョブがこのイメージを参照するため、
「ACR を作る → イメージを push → main.bicep」の順番にする必要があり、ファイルを分けています。
ACR は公開エンドポイントのままです。置くのは秘密情報を含まない Runner のイメージだけで、
pull は Managed Identity（パスワードなし）で行います。

### infra/main.bicep

| リソース | ポイント |
|---|---|
| VNet と 2 つのサブネット | `snet-aca` は Container Apps 用で `Microsoft.App/environments` に委任（/27 以上）。`snet-pe` は Private Endpoint 用 |
| Private DNS ゾーン × 3 | `privatelink.cognitiveservices.azure.com`、`privatelink.openai.azure.com`、`privatelink.services.ai.azure.com`。VNet にリンクし、Runner から Foundry の名前を引くと Private Endpoint の IP が返るようにする |
| Foundry（`kind: AIServices`） | `publicNetworkAccess: Disabled`、`networkAcls.defaultAction: Deny` で外からの入口を閉じる。`disableLocalAuth: true` で API キーを無効にし Entra ID 認証だけにする。`allowProjectManagement: true` でプロジェクトを作れるようにする |
| プロジェクト | エージェントを入れる箱。エンドポイントは `https://<名前>.services.ai.azure.com/api/projects/proj-agents` |
| モデルのデプロイ | `GlobalStandard`（使ったトークン分だけの従量課金。固定費なし）。デプロイ名がエージェント定義の `model` に対応する |
| Private Endpoint | `groupIds: ['account']` で Foundry につなぎ、3 つの DNS ゾーンに自動登録する |
| Runner 用 Managed Identity | ACR の **AcrPull** と、プロジェクトの **Foundry User**（旧名 Azure AI User）だけを持つ |
| Container Apps 環境 | VNet 統合、`internal: true`（受信口を作らない）、Consumption プロファイル（動いた分だけ課金） |
| Runner ジョブ | イベント駆動。KEDA の `github-runner` スケーラーが 30 秒ごとに GitHub のキューを見て、`foundry-private` ラベルのジョブがあれば Runner を起動する。待機中は 0 台 |

`allowedIpAddresses` に自分のグローバル IP を入れると、その IP からだけ Foundry ポータルを見られます
（空なら完全に閉じる）。検証中にポータルでエージェントを確認したいときに使い、終わったら空に戻してください。

### runner/Dockerfile と entrypoint.sh

Microsoft の公式チュートリアルのサンプルをもとに、次を追加・変更しています。

- **Python を追加**：エージェントの反映に使う
- **PAT を消してから Runner を起動**：公式サンプルのままだと、Runner 登録用の PAT が環境変数に残り、
  ワークフローのステップから読めてしまう。`unset` してから `exec` で Runner を起動するので、ステップからは見えない
- **ラベルを付けて `--ephemeral` で登録**：ジョブを 1 つ実行したら登録が消える（使い捨て）

### agents/*.yaml

```yaml
name: helpdesk-agent        # Foundry 上のエージェント名
model: gpt-5-mini           # モデルのデプロイ名
instructions: |             # システム プロンプト
  ...
smoke_test:
  input: "..."              # デプロイ後に送る質問
  expect_any: []            # 応答に含まれるべき語句（空なら応答があれば OK）
```

ファイルを追加すればエージェントが増えます。

### scripts/deploy_agents.py

`azure-ai-projects` 2.x の `project.agents.create_version()` に `PromptAgentDefinition` を渡して反映します。
反映のたびに **新しいバージョン** が作られ、古いバージョンも残ります（問題があれば戻せる）。
`--validate-only` を付けると Azure に接続せずに定義だけを検証します（プル リクエストで使用）。

### scripts/smoke_test.py

`project.get_openai_client(agent_name=...)` でエージェントに紐づいたクライアントを作り、
Responses API で実際に質問して、応答が返ること（と期待する語句）を確認します。
「定義は入ったが、モデル名の誤りや権限不足で動かない」を、デプロイの時点で見つけるためのものです。

### .github/workflows/infra.yml

1. OIDC で Azure にサインイン
2. base.bicep で ACR を作る
3. `runner/` 配下のハッシュをタグにして、イメージがなければビルドして push（中身が同じなら省略）
4. main.bicep をデプロイし、プロジェクトのエンドポイントをジョブのサマリーに表示

### .github/workflows/agents.yml

| ジョブ | 動くタイミング | 場所 |
|---|---|---|
| validate | プル リクエスト、main への push、infra 完了後、手動 | GitHub-hosted runner |
| deploy | main への push、infra 完了後、手動（**プル リクエストでは動かない**） | `[self-hosted, linux, foundry-private]` |

プル リクエストでは反映しないので、レビューを通って main に入ったものだけが Foundry に届きます。

## 構築手順

**初めての人は [docs/setup-guide.md](docs/setup-guide.md)（画面操作まで書いた詳細な手順書）を見てください。**
以下は慣れている人向けの要約です。

> 順番に注意：GitHub の Variables と Secret を登録してから push してください。
> 先に push すると、設定値がない状態で infra ワークフローが動いて失敗します。

### 1. GitHub のリポジトリを作る

**必ずプライベート リポジトリ** にしてください（パブリック リポジトリで Self-hosted runner を使うと、
他人のプル リクエストのコードが VNet 内で実行されるおそれがあります）。
このフォルダーの中身を push します。

### 2. Runner 用の PAT を作る

GitHub → Settings → Developer settings → Personal access tokens → **Fine-grained tokens** → Generate new token

| 項目 | 値 |
|---|---|
| Repository access | Only select repositories → このリポジトリ |
| Actions | Read-only |
| Administration | Read and write（Runner の登録に必要） |
| Metadata | Read-only |

有効期限があるので、期限前に作り直して Secret を更新し、infra ワークフローを再実行してください。

### 3. Azure の準備（1 回だけ）

Azure Portal の Cloud Shell（Bash）で、このリポジトリを clone して実行します。

```bash
GH_OWNER=<GitHubのユーザー名かOrg名> GH_REPO=<リポジトリ名> bash scripts/bootstrap.sh
```

最後に表示される値を、GitHub の Settings → Secrets and variables → Actions に登録します。

| 種類 | 名前 |
|---|---|
| Variables | `AZURE_CLIENT_ID`、`AZURE_TENANT_ID`、`AZURE_SUBSCRIPTION_ID`、`AZURE_RESOURCE_GROUP`、`AZURE_LOCATION` |
| Secrets | `RUNNER_GITHUB_PAT`（手順 2 の PAT） |

### 4. push する

main ブランチに push すると、infra ワークフローが自動で動きます（15〜20 分）。
agents ワークフローの deploy は、infra が Runner を作り終えるまで「Waiting for a runner」で待機し、
Runner ができると自動で実行されます。
プロジェクトのエンドポイントは Bicep が Runner の環境変数に設定するので、手で登録する必要はありません。

### 5. 以降の使い方

`agents/*.yaml` を変更して main に入れるだけで、自動的に Foundry に反映されます。

## 費用の目安（東日本、1 か月常設）

| 項目 | 目安 |
|---|---|
| Foundry の Private Endpoint | 約 $7.3 |
| Private DNS ゾーン × 3 | 約 $1.5 |
| ACR Basic | 約 $5 |
| Container Apps ジョブ | 動いた分だけ。毎月の無料枠に収まる可能性が高い |
| Log Analytics | 少量なのでほぼ $0 |
| モデル（GlobalStandard） | 使ったトークン分だけ |
| GitHub | $0（Free プラン。標準ランナーは月 2,000 分まで無料） |
| **合計** | **月 $14 前後（約 2,000 円）+ トークン代** |

使わない期間は、リソースグループごと削除すれば費用は止まります。
作り直すときは、bootstrap.sh（GitHub 用の ID もリソースグループと一緒に消えるため）→
`AZURE_CLIENT_ID` の更新 → infra ワークフローの実行、で同じ構成に戻せます。
Foundry は削除後も論理削除で残るので、同じ名前で作り直す前に purge が必要です（手順書の「後片付け」を参照）。

## 注意点と今後の拡張

- **Runner の外向き通信**：Container Apps 環境の既定の外向き通信で GitHub と PyPI に出ています。
  さらに絞る場合は、NAT Gateway や Azure Firewall（FQDN 許可リスト）を追加します（費用が増えます）
- **Runner イメージの更新**：GitHub は古い Runner にジョブを渡さなくなります。
  `runner/` を少し変更（コメントの更新など）して push すれば、最新のベース イメージで作り直されます
- **PAT の代わりに GitHub App**：KEDA のスケーラーと Runner の登録は GitHub App にも対応しています。
  期限切れの管理をなくしたい場合に検討してください
- **Foundry ポータルでの確認**：公開アクセスが無効なので、自分の PC からはポータルでエージェントを見られません。
  `allowedIpAddresses` で一時的に許可するか、VPN や踏み台 VM を使ってください
- **ツールの追加**：エージェントから閉域の AI Search などを使う場合は、
  Basic setup では届かないため、Standard setup（VNet 注入、Cosmos DB、Storage、AI Search）への拡張が必要です
- **リージョン**：モデル（gpt-5-mini の GlobalStandard）とエージェント機能が、選んだリージョンで使えるか事前に確認してください。
  使えない場合は `infra/main.bicep` の `modelName` と `modelVersion` を変更してください
