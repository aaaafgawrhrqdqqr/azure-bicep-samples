# =============================================================================
# GitHub Actions の Self-hosted runner（Container Apps ジョブ用）
# Microsoft の公式チュートリアルのサンプルをもとに、
#   - エージェントのデプロイに使う Python を追加
#   - 起動時に GitHub のトークンを環境変数から消す
# ようにしたもの。
#
# ベース イメージは GitHub 公式の Runner イメージ。
# Runner は古くなると GitHub がジョブを渡さなくなるため、定期的に作り直す
# （runner/ 配下を変更して push すれば、infra ワークフローが作り直す）。
# 本番では :latest ではなく、バージョンを固定して計画的に上げるのがおすすめ。
# =============================================================================
FROM ghcr.io/actions/actions-runner:latest

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl jq git \
      python3 python3-venv python3-pip \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /home/runner/entrypoint.sh
RUN chmod +x /home/runner/entrypoint.sh

USER runner
WORKDIR /home/runner

ENTRYPOINT ["/home/runner/entrypoint.sh"]
