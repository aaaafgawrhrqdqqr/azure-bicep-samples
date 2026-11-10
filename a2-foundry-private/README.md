# a2-foundry-private

ブログ「たいやきまんの技術備忘録」AI 編 A2（Microsoft Foundry の閉域化）で使った Bicep です。

## 作られるもの

| リソース | 内容 |
|---|---|
| Foundry リソース（AIServices、S0） | パブリック ネットワーク アクセスを無効、API キー認証を無効、信頼されたサービスの例外は有効 |
| プロジェクト | `proj-a2` |
| モデルのデプロイ | `gpt-5-mini`（2025-08-07）、グローバル標準、容量 10 |
| VNet | `vnet-a2`（`snet-app`、`snet-pe`） |
| プライベート エンドポイント | 対象サブリソース `account`、`snet-pe` に配置 |
| プライベート DNS ゾーン | `privatelink.services.ai.azure.com`、`privatelink.openai.azure.com`、`privatelink.cognitiveservices.azure.com` と VNet リンク |
| ロールの割り当て | 指定したプリンシパルに Foundry User |

## デプロイ（Azure CLI、PowerShell の例）

```powershell
az group create -n rg-a2-bicep -l japaneast
$me = az ad signed-in-user show --query id -o tsv
az deployment group create -g rg-a2-bicep -f main.bicep -p principalId=$me
```

- パブリック アクセスが無効なので、モデルの呼び出しや Foundry ポータルのプロジェクトの機能は、この VNet（またはピアリングした VNet、VPN、ExpressRoute）からだけ使えます。
- 呼び出しは Entra ID のトークン（スコープ `https://ai.azure.com/.default`）で行います。
- プライベート エンドポイント、プライベート DNS ゾーン、モデルの呼び出しに料金がかかります。

## 片付け

```powershell
az group delete -n rg-a2-bicep --yes
```

削除した Foundry リソースは論理的な削除の状態で残ります。完全に消す場合は `az cognitiveservices account purge` を使います。
