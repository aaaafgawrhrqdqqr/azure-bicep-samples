"""agents/*.yaml を Foundry のプロンプト エージェントとして反映する。

使い方:
  python scripts/deploy_agents.py --validate-only   # 定義の検証だけ（Azure に接続しない）
  python scripts/deploy_agents.py                   # 検証して Foundry に反映

必要な環境変数:
  FOUNDRY_PROJECT_ENDPOINT  例: https://<resource>.services.ai.azure.com/api/projects/<project>
  AZURE_CLIENT_ID           Runner の Managed Identity（Container Apps ジョブが設定済み）

反映のたびに、エージェントの「新しいバージョン」が作られる。
以前のバージョンは Foundry に残るので、問題があれば前のバージョンに戻せる。
"""

from __future__ import annotations

import argparse
import os
import sys

from agent_defs import load_agent_defs


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--validate-only", action="store_true", help="定義の検証だけ行う")
    args = parser.parse_args()

    defs = load_agent_defs()
    print(f"エージェント定義 {len(defs)} 件の検証 OK: {', '.join(d.name for d in defs)}")
    if args.validate_only:
        return

    endpoint = os.environ.get("FOUNDRY_PROJECT_ENDPOINT")
    if not endpoint:
        sys.exit("環境変数 FOUNDRY_PROJECT_ENDPOINT がありません（VNet 内の Runner で実行しているか確認）")

    # Azure のライブラリは、実際に反映するときだけ読み込む
    from azure.ai.projects import AIProjectClient
    from azure.ai.projects.models import PromptAgentDefinition
    from azure.identity import DefaultAzureCredential

    # Container Apps ジョブでは Managed Identity が使われる（AZURE_CLIENT_ID で指定）
    credential = DefaultAzureCredential()
    project = AIProjectClient(endpoint=endpoint, credential=credential)

    for d in defs:
        agent = project.agents.create_version(
            agent_name=d.name,
            definition=PromptAgentDefinition(
                model=d.model,
                instructions=d.instructions,
            ),
        )
        print(f"反映しました: {agent.name}（バージョン {agent.version}）← {d.path.name}")


if __name__ == "__main__":
    main()
