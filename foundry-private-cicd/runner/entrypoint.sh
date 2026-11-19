#!/bin/bash
# =============================================================================
# Container Apps ジョブが起動するたびに実行される。
#   1. PAT を使って、短命の Runner 登録トークンを GitHub から取得する
#   2. PAT を環境変数から消す（ワークフローの各ステップから見えないようにする）
#   3. --ephemeral で登録し、ジョブを 1 つだけ実行して終了する（使い捨て）
# =============================================================================
set -euo pipefail

REGISTRATION_TOKEN="$(curl -fsSL -X POST \
  -H 'Accept: application/vnd.github+json' \
  -H "Authorization: Bearer ${GITHUB_PAT}" \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  "${REGISTRATION_TOKEN_API_URL}" | jq -r '.token')"

# 以降のプロセス（= ワークフローのステップ）に PAT を引き継がない
unset GITHUB_PAT

./config.sh \
  --url "${GH_URL}" \
  --token "${REGISTRATION_TOKEN}" \
  --labels "${RUNNER_LABELS:-foundry-private}" \
  --unattended \
  --ephemeral

unset REGISTRATION_TOKEN

# exec で置き換えるので、PID 1 の環境変数にも PAT は残らない
exec ./run.sh
