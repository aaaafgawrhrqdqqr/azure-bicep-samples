# a6-guardrails

ブログ「たいやきまんの技術備忘録」AI 編 A6（ガードレール）で使った Bicep です。

## 作られるもの

| ファイル | リソース | 内容 |
|---|---|---|
| main.bicep | Foundry リソース（AIServices、S0） | API キー認証を無効、プロジェクト `proj-a6` |
| main.bicep | カスタム ブロックリスト | `bl-internal`（`blockedTerms` の語を完全一致で登録） |
| guardrail.bicep | カスタム ガードレール（RAI ポリシー） | `gr-custom`。既定の Microsoft.DefaultV2 と同じ 4 カテゴリ（中レベルでブロック）、脱獄、保護されたマテリアルに、間接プロンプト インジェクション（ブロック）とカスタム ブロックリスト（入力と出力）を追加 |
| guardrail.bicep | モデルのデプロイ | `gpt-5-mini`（2025-08-07）、グローバル標準、容量 10。`raiPolicyName` に `gr-custom` |
| main.bicep | Azure AI Content Safety（F0） | API キー認証を無効 |
| main.bicep | ロールの割り当て | 指定したプリンシパルに Foundry User（Foundry）と Cognitive Services User（Content Safety） |

## デプロイ（Azure CLI、PowerShell の例）

```powershell
az group create -n rg-a6-bicep -l japaneast
$me = az ad signed-in-user show --query id -o tsv
az deployment group create -g rg-a6-bicep -f main.bicep -p principalId=$me
```

- ガードレールとデプロイは、ブロックリストを作ってからモジュール（guardrail.bicep）で作ります。同じテンプレートに置くと、事前検証で「Resource has invalid blocklist reference」になります。
- 同じ Foundry リソースへの子リソースの作成を同時に送ると RequestConflict になるので、ブロックリストはプロジェクトのあとに、語は 1 つずつ作ります。
- このテンプレートで作ったときは、デプロイから約 1 分半でガードレールが効きました。既存のデプロイのガードレールをあとから変えたときは、効くまで約 17〜25 分かかりました。
- RAG の文書は、ユーザー メッセージの中で `"""<documents> … </documents>"""` で囲むと、間接プロンプト インジェクションの検出対象になります。
- モデルの呼び出しに料金がかかります。Content Safety の F0 は無料の枠です。

## 片付け

Foundry リソースは、プロジェクトを削除してから削除し、purge します。

```powershell
$fdy = az cognitiveservices account list -g rg-a6-bicep --query "[?kind=='AIServices'].name | [0]" -o tsv
$acc = az cognitiveservices account show -g rg-a6-bicep -n $fdy --query id -o tsv
az resource delete --ids "$acc/projects/proj-a6" --api-version 2025-04-01-preview
az cognitiveservices account delete -g rg-a6-bicep -n $fdy
az cognitiveservices account purge -g rg-a6-bicep -n $fdy -l japaneast
az group delete -n rg-a6-bicep --yes
```
