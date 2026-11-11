# a9-ai-monitoring

ブログ「たいやきまんの技術備忘録」AI 編 A9（AI の監視とログ）で使った Bicep です。

## 作られるもの

| リソース | 内容 |
|---|---|
| Foundry（AIServices） | キー認証を無効（`disableLocalAuth: true`）、gpt-5-mini（GlobalStandard、容量は `capacity`、既定 10） |
| Log Analytics ワークスペース | リソース ログとメトリックの保存先（保持 30 日） |
| Application Insights | トレースの保存先（上のワークスペースを使う） |
| 診断設定 | Foundry のすべてのリソース ログ（`allLogs`）と `AllMetrics` を Log Analytics へ |
| アクション グループ | 所有者ロールを持つユーザーへのメール（Azure Resource Manager のロールへのメール） |
| メトリック アラート | `ModelRequests` の `StatusCode` = 429 が、5 分間で `throttleThreshold`（既定 5）を超えたら発生。評価は 1 分ごと |
| ログ検索アラート | `AzureDiagnostics` の `RequestResponse` に 401 が 1 件でもあれば発生。評価は 5 分ごと |

## デプロイ（Azure CLI、PowerShell の例）

```powershell
az group create -n rg-a9-bicep -l japaneast
az deployment group create -g rg-a9-bicep -f main.bicep
```

- デプロイは 1 分ほどで終わります。
- モデルを呼ぶには、呼び出す ID に Cognitive Services OpenAI ユーザーを Foundry リソースの範囲で付けます（この Bicep には含めていません）。
- 診断設定を作った直後の呼び出しは、Log Analytics に出ないことがあります（記事の検証では、保存から 16 分以内の呼び出しは出ず、64 分後の呼び出しから出ました）。
- コンテンツ フィルターで拒否された要求（アプリには 400）は、記事の検証ではリソース ログとメトリックに 200 として記録されました。状態コードのアラートでは拾えません。
- ログ検索アラートは評価の間隔で料金が変わります。間隔を変えるときは、テンプレートの `evaluationFrequency` を書き換えます。
- Application Insights を Foundry のプロジェクトに接続する操作（トレース用）は、Foundry ポータルで行います。

## 呼び出し

```powershell
$t = az account get-access-token --scope https://cognitiveservices.azure.com/.default --query accessToken -o tsv
$u = 'https://<Foundry 名>.cognitiveservices.azure.com/openai/deployments/gpt-5-mini/chat/completions?api-version=2025-04-01-preview'
$body = @{ messages = @(@{ role = 'user'; content = 'こんにちは' }); max_completion_tokens = 200; reasoning_effort = 'minimal' } | ConvertTo-Json -Depth 5
Invoke-WebRequest -Method Post -Uri $u -Headers @{ Authorization = "Bearer $t"; 'Content-Type' = 'application/json' } -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing
```

## 片付け

```powershell
az group delete -n rg-a9-bicep --yes
# Foundry は論理的な削除の状態で残るので purge する
az cognitiveservices account list-deleted -o table
az cognitiveservices account purge -l japaneast -g rg-a9-bicep -n <名前>
```
