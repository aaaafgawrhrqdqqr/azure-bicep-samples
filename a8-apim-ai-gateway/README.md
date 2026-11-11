# a8-apim-ai-gateway

ブログ「たいやきまんの技術備忘録」AI 編 A8（API Management の AI ゲートウェイ）で使った Bicep です。

## 作られるもの

| リソース | 内容 |
|---|---|
| Foundry（AIServices） | キー認証を無効（`disableLocalAuth: true`）、gpt-5-mini（GlobalStandard、容量 10） |
| Content Safety | キー認証を無効。価格レベルは `contentSafetySku`（既定 F0。F0 はサブスクリプションに 1 つだけ） |
| API Management | 価格レベルは `apimSku`（既定 Developer）、システム割り当てマネージド ID |
| ロールの割り当て | APIM の ID に Cognitive Services OpenAI ユーザー（Foundry）と Cognitive Services ユーザー（Content Safety） |
| バックエンド | Foundry と Content Safety。どちらもマネージド ID（`https://cognitiveservices.azure.com`）で認証 |
| API | `/aoai/openai/deployments/{deployment-id}/chat/completions`。サブスクリプション キーのヘッダー名は `api-key` |
| ポリシー | `llm-token-limit`（サブスクリプションごと、既定 300 トークン/分）→ `llm-emit-token-metric` → `llm-content-safety`（4 カテゴリ レベル 4、プロンプト攻撃の検出） |
| サブスクリプション | `team-a`（スコープはこの API だけ） |
| 監視 | Log Analytics、Application Insights、APIM のロガー（Application Insights と Azure Monitor）、API の LLM ログ（プロンプトと応答、各 32768 バイト）、診断設定（GatewayLogs と GatewayLlmLogs） |

## デプロイ（Azure CLI、PowerShell の例）

```powershell
az group create -n rg-a8-bicep -l japaneast
az deployment group create -g rg-a8-bicep -f main.bicep -p publisherEmail=<管理者のメール アドレス>
```

- Developer の APIM は作成に 30 分ほどかかります。Developer は SLA のない評価用です。
- すでに F0 の Content Safety がある場合は `contentSafetySku=S0` を付けます。
- `llm-token-limit` を `llm-content-safety` より前に置いています。逆にすると、上限を超えた要求でも Content Safety を呼び、F0 では呼び出しの制限で 403 になることがあります。
- ブロックリストはデータ プレーンの API で作るため、この Bicep には含めていません。使う場合は Content Safety にブロックリストを作り、ポリシーの `llm-content-safety` に `<blocklists><id>名前</id></blocklists>` を足します。
- バックエンドの `managedIdentity` は Bicep の型定義にまだないため、警告（BCP037）を抑止しています。
- 診断設定を作ってから、ログが Log Analytics に出始めるまで時間がかかります（記事の検証では 15 分ほど）。

## 呼び出し

```powershell
$k = '<team-a のサブスクリプション キー>'
$u = 'https://<APIM 名>.azure-api.net/aoai/openai/deployments/gpt-5-mini/chat/completions?api-version=2025-04-01-preview'
$body = @{ messages = @(@{ role = 'user'; content = 'こんにちは' }); max_completion_tokens = 200; reasoning_effort = 'minimal' } | ConvertTo-Json -Depth 5
Invoke-WebRequest -Method Post -Uri $u -Headers @{ 'api-key' = $k; 'Content-Type' = 'application/json' } -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing
```

キーは Azure portal の APIM ⇒ サブスクリプション ⇒ team-a で確認できます。

## 片付け

```powershell
az group delete -n rg-a8-bicep --yes
# Foundry と Content Safety は論理的な削除の状態で残るので purge する
az cognitiveservices account list-deleted -o table
az cognitiveservices account purge -l japaneast -g rg-a8-bicep -n <名前>
# APIM も論理的な削除の状態で残る
az apim deletedservice list -o table
az apim deletedservice purge --service-name <APIM 名> -l japaneast
```
