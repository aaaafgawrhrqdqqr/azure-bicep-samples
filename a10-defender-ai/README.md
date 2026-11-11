# a10-defender-ai

ブログ「たいやきまんの技術備忘録」AI 編 A10（Defender for Cloud の AI 脅威保護）で使った Bicep です。

## 作られるもの

| リソース | 内容 |
|---|---|
| Defender プラン「AI サービス」 | サブスクリプションの `Microsoft.Security/pricings/AI` を Standard にする。**サブスクリプション全体に効く** |
| プランのコンポーネント | `AIPromptEvidence`（アラートに疑わしいプロンプトの一部を載せる。`promptEvidence`、既定 true）、`AIModelScanner`（AI モデルのセキュリティ。`modelScanner`、既定 true） |
| リソース グループ | `resourceGroupName`（既定 rg-a10-bicep） |
| Foundry（AIServices） | キー認証を無効（`disableLocalAuth: true`）、gpt-5-mini（GlobalStandard、容量 20）。`foundry.bicep` |

## デプロイ（Azure CLI、PowerShell の例）

サブスクリプションのスコープでデプロイします。

```powershell
az deployment sub create -l japaneast -n a10-defender-ai -f main.bicep
```

- デプロイは 1 分ほどで終わります。
- AI サービス プランには 30 日間の無料試用版があります（スキャンするトークンは 750 億個まで）。試用後は、スキャンしたトークン数に応じた料金がかかります。
- プランをオンにした直後の呼び出しは、アラートにならないことがあります（記事の検証では、オンにして 3 分以内の脱獄の文はアラートにならず、9 分後の分がアラートになりました）。
- モデルを呼ぶには、呼び出す ID に Cognitive Services OpenAI ユーザーを Foundry リソースの範囲で付けます（この Bicep には含めていません）。

## 呼び出し（エンドユーザーの情報を付ける）

```powershell
$t = az account get-access-token --scope https://cognitiveservices.azure.com/.default --query accessToken -o tsv
$u = 'https://<Foundry 名>.cognitiveservices.azure.com/openai/deployments/gpt-5-mini/chat/completions?api-version=2025-04-01-preview'
$body = [ordered]@{
  messages = @(@{ role = 'user'; content = 'こんにちは' })
  max_completion_tokens = 200
  reasoning_effort = 'minimal'
  user_security_context = [ordered]@{ end_user_id = '<エンドユーザーの Entra ID のオブジェクト ID>'; source_ip = '<エンドユーザーの IP アドレス>'; application_name = '<アプリ名>' }
} | ConvertTo-Json -Depth 6
Invoke-WebRequest -Method Post -Uri $u -Headers @{ Authorization = "Bearer $t"; 'Content-Type' = 'application/json' } -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing
```

## 片付け

```powershell
az group delete -n rg-a10-bicep --yes
# Foundry は論理的な削除の状態で残るので purge する
az cognitiveservices account purge -l japaneast -g rg-a10-bicep -n <名前>
# プランをオフに戻す（サブスクリプション全体の設定）
az security pricing create -n AI --tier Free
```
