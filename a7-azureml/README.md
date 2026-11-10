# a7-azureml

ブログ「たいやきまんの技術備忘録」AI 編 A7（Azure Machine Learning のセキュリティ）で使った Bicep です。

## 作られるもの

| リソース | 内容 |
|---|---|
| Azure Machine Learning ワークスペース | マネージド VNet（承認された送信のみを許可、Firewall SKU は Basic、作成時にプロビジョニング）、既定のデータストアは ID ベース、`allowedIpRanges` の IP だけパブリック アクセスを許可（空なら無効） |
| Storage | 共有キー無効、匿名アクセス無効 |
| Key Vault | RBAC、消去保護あり（論理削除の保持 7 日） |
| Application Insights と Log Analytics | 監視用 |
| ロールの割り当て | 指定したプリンシパルに AzureML データ サイエンティスト（ワークスペース）、Storage Blob Data Contributor と Storage File Data Privileged Contributor（Storage） |

## デプロイ（Azure CLI、PowerShell の例）

```powershell
az group create -n rg-a7-bicep -l japaneast
$me = az ad signed-in-user show --query id -o tsv
$ip = (Invoke-RestMethod https://api.ipify.org) + '/32'
az deployment group create -g rg-a7-bicep -f main.bicep -p principalId=$me "allowedIpRanges=[\`"$ip\`"]"
```

- マネージド VNet の分離モードは、あとから戻せません（承認された送信のみ → インターネット送信を許可には変えられない）。
- 承認された送信のみでは、PyPI などインターネットへの送信は止まります。FQDN の送信規則を足すと Azure Firewall の料金がかかります。
- ID ベースのデータストアでは、コンピューティング インスタンスを使う人に Storage のデータ ロールが必要です。ないと StorageMountError で作成に失敗します。
- `networkAcls` は Bicep の型定義にまだないため、警告（BCP037）を抑止しています。
- コンピューティングは作りません。作る場合は、使い終わったら停止・削除してください。

## 片付け

ワークスペースは `forceToPurge=true` を付けて完全に削除してから、リソース グループを削除します。
Windows の `az rest` に `&` を含む URL を渡すと途中で切れるため、PowerShell の `Invoke-WebRequest` で呼んでいます。

```powershell
$ws = az resource list -g rg-a7-bicep --resource-type Microsoft.MachineLearningServices/workspaces --query "[0].name" -o tsv
$id = az resource show -g rg-a7-bicep -n $ws --resource-type Microsoft.MachineLearningServices/workspaces --query id -o tsv
$t = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
Invoke-WebRequest -UseBasicParsing -Method Delete -Uri "https://management.azure.com$($id)?api-version=2025-06-01&forceToPurge=true" -Headers @{ Authorization = "Bearer $t" }
# ワークスペースが消えたのを確かめてから
az group delete -n rg-a7-bicep --yes
```

Key Vault は消去保護があるため、論理的な削除の状態で 7 日残ります（料金はかかりません）。
