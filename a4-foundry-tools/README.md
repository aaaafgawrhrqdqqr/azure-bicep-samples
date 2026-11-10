# a4-foundry-tools

ブログ「たいやきまんの技術備忘録」AI 編 A4（Foundry Tools 共通のセキュリティ）で使った Bicep です。

## 作られるもの

| リソース | 内容 |
|---|---|
| Document Intelligence（FormRecognizer） | 既定は無料レベル F0。カスタム サブドメイン、API キー認証を無効 |
| ネットワーク | 既定で拒否し、`allowedIpAddresses` の IP だけ許可（空ならどこからも呼べない） |
| データ損失防止 | `restrictOutboundNetworkAccess` を有効にし、解析に渡す URL のドメインを `allowedFqdnList` に制限 |
| ロールの割り当て | 指定したプリンシパルに Cognitive Services User |

## デプロイ（Azure CLI、PowerShell の例）

```powershell
az group create -n rg-a4-bicep -l japaneast
$me = az ad signed-in-user show --query id -o tsv
$ip = Invoke-RestMethod https://api.ipify.org
az deployment group create -g rg-a4-bicep -f main.bicep -p principalId=$me "allowedIpAddresses=[\`"$ip\`"]"
```

- F0 はサブスクリプションごとに作れる数に制限があります。作れない場合は `skuName=S0` を指定します（従量課金）。
- 呼び出しは Entra ID のトークン（リソース `https://cognitiveservices.azure.com`）で行います。キーは使えません。
- `allowedFqdnList` にないドメインの URL を渡すと、403（`OutboundAccessForbidden`）になります。

## 片付け

```powershell
$name = az cognitiveservices account list -g rg-a4-bicep --query "[0].name" -o tsv
az cognitiveservices account delete -g rg-a4-bicep -n $name
az cognitiveservices account purge -g rg-a4-bicep -n $name -l japaneast
az group delete -n rg-a4-bicep --yes
```
