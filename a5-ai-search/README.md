# a5-ai-search

ブログ「たいやきまんの技術備忘録」AI 編 A5（Azure AI 検索のセキュリティ）で使った Bicep です。

## 作られるもの

| リソース | 内容 |
|---|---|
| Azure AI 検索（Basic） | API キーを無効にし、ロールベースのアクセス制御だけ。`allowedIpAddresses` の IP だけ許可。システム割り当てマネージド ID |
| Storage | 共有キー無効、匿名アクセス無効。ネットワークは既定で拒否し、信頼された Microsoft サービスの例外だけ。コンテナー `docs` |
| ロールの割り当て | 検索サービスのマネージド ID に Storage BLOB データ閲覧者、指定したプリンシパルに検索インデックス データ閲覧者 |

## デプロイ（Azure CLI、PowerShell の例）

```powershell
az group create -n rg-a5-bicep -l japaneast
$me = az ad signed-in-user show --query id -o tsv
$ip = Invoke-RestMethod https://api.ipify.org
az deployment group create -g rg-a5-bicep -f main.bicep -p principalId=$me "allowedIpAddresses=[\`"$ip\`"]"
```

- Basic は時間単位の料金がかかります。確認が終わったらすぐ削除してください。
- 呼び出しは Entra ID のトークン（スコープ `https://search.azure.com/.default`）で行います。API キーは 401 になります。
- Storage は既定で拒否なので、BLOB をアップロードするには、一時的に自分の IP を許可するか、VNet から操作します。
- インデクサーのデータ ソースは、接続文字列 `ResourceId=<Storage のリソース ID>;` でマネージド ID を使います。

## 片付け

```powershell
az group delete -n rg-a5-bicep --yes
```
