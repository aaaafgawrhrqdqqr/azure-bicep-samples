# push の前に、公開してはいけない文字列が入っていないかを調べる。見つかったら終了コード 1。
# 使い方: .\tools\check-secrets.ps1   （.git\hooks\pre-push からも呼ぶ）
param([string]$Root = (Split-Path $PSScriptRoot -Parent))
$patterns = @(
  @{ n = 'GUID（テナント ID・サブスクリプション ID・オブジェクト ID の可能性）'; p = '\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b' }
  @{ n = 'メール アドレス'; p = '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' }
  @{ n = 'onmicrosoft.com のドメイン'; p = '\.onmicrosoft\.com' }
  @{ n = '秘密鍵'; p = '-----BEGIN [A-Z ]*PRIVATE KEY-----' }
  @{ n = 'ストレージ アカウント キー・接続文字列'; p = 'AccountKey=|SharedAccessSignature=|sig=[A-Za-z0-9%]{20,}' }
  @{ n = 'パスワードらしき値'; p = '(?i)(password|passwd|secret|apikey|api_key)\s*[:=]\s*[''"][^''"]{6,}[''"]' }
  @{ n = 'GitHub トークン'; p = 'gh[pousr]_[A-Za-z0-9]{30,}' }
)
# 例として載せてよい GUID（Azure の組み込みロールの定義 ID など）は、ファイルの同じ行に「# allow-guid」と書く
$files = Get-ChildItem -Path $Root -Recurse -File | Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.Name -ne 'check-secrets.ps1' }
$hits = 0
foreach ($f in $files) {
  $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    foreach ($x in $patterns) {
      if ($l -match $x.p) {
        if ($x.n -like 'GUID*' -and $l -match 'allow-guid') { continue }
        if ($x.n -eq 'メール アドレス' -and $l -match 'noreply\.github\.com|example\.(com|org)') { continue }
        "[NG] $($x.n): $($f.FullName.Substring($Root.Length + 1)):$($i + 1)"; $hits++
      }
    }
  }
}
if ($hits) { "見つかった件数: $hits（公開しない）"; exit 1 } else { 'OK: 公開してはいけない文字列は見つからなかった'; exit 0 }
