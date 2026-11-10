# a1-foundry-auth

ブログ「たいやきまんの技術備忘録」AI 編 A1（Microsoft Foundry の構成要素と認証・RBAC）で使った Bicep です。

## 作られるもの

| リソース | 内容 |
|---|---|
| Foundry リソース（Microsoft.CognitiveServices/accounts、種類 AIServices、S0） | API キー認証を無効（`disableLocalAuth: true`）、システム割り当てマネージド ID |
| プロジェクト（accounts/projects） | `proj-a1`、システム割り当てマネージド ID |
| モデルのデプロイ（accounts/deployments） | `gpt-5-mini`（2025-08-07）、グローバル標準、容量 10（10,000 TPM） |
| ロールの割り当て | 指定したプリンシパルに Foundry User（Foundry リソースのスコープ） |

## デプロイ（Azure CLI、PowerShell の例）

```powershell
az group create -n rg-a1-bicep -l japaneast
$me = az ad signed-in-user show --query id -o tsv
az deployment group create -g rg-a1-bicep -f main.bicep -p principalId=$me
```

- モデルの呼び出しは Entra ID のトークン（スコープ `https://ai.azure.com/.default`）で行います。ロールの割り当てが反映されるまで数分かかることがあります。
- gpt-5-mini をデプロイできるリージョンとクォータは、事前に確かめてください。
- 呼び出しの料金（トークン数に応じた従量課金）がかかります。

## 片付け

```powershell
az group delete -n rg-a1-bicep --yes
```

削除した Foundry リソースは論理的な削除の状態で残り、同じ名前をすぐには使えません。完全に消す場合は `az cognitiveservices account purge` を使います。
