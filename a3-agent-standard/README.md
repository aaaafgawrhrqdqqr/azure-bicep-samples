# a3-agent-standard

ブログ「たいやきまんの技術備忘録」AI 編 A3（Foundry Agent Service の標準セットアップと VNet インジェクション）で使った Bicep です。

## 作られるもの

| ファイル | リソース | 内容 |
|---|---|---|
| deps.bicep | VNet | `vnet-a3`（10.30.0.0/16）。`snet-agent`（10.30.0.0/24、`Microsoft.App/environments` に委任）、`snet-pe`（10.30.1.0/24） |
| deps.bicep | Cosmos DB for NoSQL | サーバーレス、キー認証を無効、パブリック アクセスを無効 |
| deps.bicep | AI 検索 | Basic、キー認証を無効、パブリック アクセスを無効 |
| deps.bicep | Storage | 共有キーを無効、パブリック アクセスを無効 |
| deps.bicep | プライベート エンドポイントと DNS ゾーン | Cosmos DB（Sql）、AI 検索（searchService）、Storage（blob） |
| main.bicep | Foundry リソース（AIServices、S0） | パブリック アクセスを無効、API キー認証を無効、`networkInjections`（scenario `agent`）で `snet-agent` を指定 |
| main.bicep | プライベート エンドポイントと DNS ゾーン | 対象サブリソース `account`。`privatelink.services.ai.azure.com`、`privatelink.openai.azure.com`、`privatelink.cognitiveservices.azure.com` |
| main.bicep | プロジェクト | `proj-a3`。Cosmos DB、Storage、AI 検索への接続（Entra ID 認証） |
| main.bicep | 機能ホスト | 会話、ファイル、ベクター ストアの保存先に上の 3 つの接続を指定 |
| main.bicep | ロールの割り当て | プロジェクトのマネージド ID に Cosmos DB Operator、Cosmos DB Built-in Data Contributor、Storage Blob Data Contributor、Storage Blob Data Owner、Search Index Data Contributor、Search Service Contributor。指定したプリンシパルに Foundry User |
| main.bicep | モデルのデプロイ | `gpt-5-mini`（2025-08-07）、グローバル標準、容量 10 |

## デプロイ（Azure CLI、PowerShell の例）

```powershell
az provider register -n Microsoft.App
az group create -n rg-a3-bicep -l japaneast
$me = az ad signed-in-user show --query id -o tsv
az deployment group create -g rg-a3-bicep -f main.bicep -p principalId=$me
```

- パブリック アクセスが無効なので、エージェントの作成や会話は、この VNet（またはピアリングした VNet、VPN、ExpressRoute）からだけ行えます。
- エージェントのツールに Web 検索を入れると、その通信は VNet を通りません。
- Cosmos DB、AI 検索、プライベート エンドポイント、プライベート DNS ゾーン、モデルの呼び出しに料金がかかります。AI 検索 Basic は時間単位の料金です。

## 片付け

VNet インジェクションを使った Foundry リソースは、削除して purge してから VNet を削除します。
プロジェクトが残っていると Foundry リソースを削除できないので、先にプロジェクトを削除します。

```powershell
$fdy = az cognitiveservices account list -g rg-a3-bicep --query "[0].name" -o tsv
$acc = az cognitiveservices account show -g rg-a3-bicep -n $fdy --query id -o tsv
az resource delete --ids "$acc/projects/proj-a3" --api-version 2025-04-01-preview
az cognitiveservices account delete -g rg-a3-bicep -n $fdy
az cognitiveservices account purge -g rg-a3-bicep -n $fdy -l japaneast
az group delete -n rg-a3-bicep --yes
```
