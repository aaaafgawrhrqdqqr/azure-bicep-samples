#!/bin/bash
# =============================================================================
# 最初に 1 回だけ、手で実行する準備スクリプト（Azure Cloud Shell の Bash を想定）
#
#   1. 必要なリソース プロバイダーを登録する
#   2. リソースグループを作る
#   3. GitHub Actions（infra ワークフロー）用の Managed Identity を作り、
#      OIDC のフェデレーション資格情報と権限を付ける
#
# 使い方:
#   GH_OWNER=<GitHubのユーザー名かOrg名> GH_REPO=<リポジトリ名> bash scripts/bootstrap.sh
# =============================================================================
set -euo pipefail

: "${GH_OWNER:?GH_OWNER を指定してください}"
: "${GH_REPO:?GH_REPO を指定してください}"
RG="${RG:-rg-foundry-private-cicd}"
LOCATION="${LOCATION:-japaneast}"
IDENTITY="${IDENTITY:-id-github-infra}"

echo "== リソース プロバイダーの登録 =="
for ns in Microsoft.App Microsoft.CognitiveServices Microsoft.ContainerRegistry \
          Microsoft.ManagedIdentity Microsoft.Network Microsoft.OperationalInsights; do
  az provider register --namespace "$ns" --output none
done

echo "== リソースグループ: $RG ($LOCATION) =="
az group create --name "$RG" --location "$LOCATION" --output none
RG_ID=$(az group show --name "$RG" --query id -o tsv)

echo "== GitHub Actions 用の Managed Identity: $IDENTITY =="
az identity create --name "$IDENTITY" --resource-group "$RG" --output none
CLIENT_ID=$(az identity show -n "$IDENTITY" -g "$RG" --query clientId -o tsv)
PRINCIPAL_ID=$(az identity show -n "$IDENTITY" -g "$RG" --query principalId -o tsv)

# main ブランチで動いたワークフローだけが、この ID でサインインできる
az identity federated-credential create \
  --name github-main \
  --identity-name "$IDENTITY" \
  --resource-group "$RG" \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:${GH_OWNER}/${GH_REPO}:ref:refs/heads/main" \
  --audiences "api://AzureADTokenExchange" \
  --output none

# GitHub が ID 付きの新しい形式の subject
#   repo:<owner>@<ownerId>/<repo>@<repoId>:ref:refs/heads/main
# を送ってくるリポジトリもある。分かっている場合は GH_OIDC_SUBJECT で渡すと一緒に登録する。
# （分からなければ、infra ワークフローの失敗ログに表示される subject を使って後から追加できる）
if [ -n "${GH_OIDC_SUBJECT:-}" ]; then
  az identity federated-credential create \
    --name github-main-ids \
    --identity-name "$IDENTITY" \
    --resource-group "$RG" \
    --issuer "https://token.actions.githubusercontent.com" \
    --subject "$GH_OIDC_SUBJECT" \
    --audiences "api://AzureADTokenExchange" \
    --output none
fi

# 権限はこのリソースグループだけに限定する
#   - 共同作成者: リソースを作る
#   - ロールベースのアクセス制御管理者: Bicep の中でロールを割り当てる（AcrPull、Foundry User）
echo "== 権限の割り当て（ID の反映待ちで失敗したら、少し待って再実行してください）=="
for role in "Contributor" "Role Based Access Control Administrator"; do
  az role assignment create \
    --assignee-object-id "$PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "$role" \
    --scope "$RG_ID" \
    --output none
done

cat <<EOF

完了しました。GitHub のリポジトリ → Settings → Secrets and variables → Actions の
「Variables」に次を登録してください。

  AZURE_CLIENT_ID        = $CLIENT_ID
  AZURE_TENANT_ID        = $(az account show --query tenantId -o tsv)
  AZURE_SUBSCRIPTION_ID  = $(az account show --query id -o tsv)
  AZURE_RESOURCE_GROUP   = $RG
  AZURE_LOCATION         = $LOCATION

「Secrets」には次を登録してください。

  RUNNER_GITHUB_PAT      = Runner 用の fine-grained PAT（README の手順を参照）
EOF
