"""反映したエージェントに実際にメッセージを送り、応答が返るか確認する。

agents/*.yaml の smoke_test.input があるエージェントだけを対象にする。
expect_any に語句があれば、そのどれかが応答に含まれていることも確認する。
"""

from __future__ import annotations

import os
import sys

from agent_defs import load_agent_defs


def main() -> None:
    endpoint = os.environ.get("FOUNDRY_PROJECT_ENDPOINT")
    if not endpoint:
        sys.exit("環境変数 FOUNDRY_PROJECT_ENDPOINT がありません")

    from azure.ai.projects import AIProjectClient
    from azure.identity import DefaultAzureCredential

    project = AIProjectClient(endpoint=endpoint, credential=DefaultAzureCredential())

    failed = False
    for d in load_agent_defs():
        if not d.smoke_input:
            print(f"スキップ: {d.name}（smoke_test.input なし）")
            continue

        # エージェントに紐づいた OpenAI 互換クライアントで、Responses API を呼ぶ
        openai = project.get_openai_client(agent_name=d.name)
        response = openai.responses.create(input=d.smoke_input)
        text = (response.output_text or "").strip()

        if not text:
            print(f"失敗: {d.name} の応答が空です", file=sys.stderr)
            failed = True
            continue
        if d.smoke_expect_any and not any(w in text for w in d.smoke_expect_any):
            print(f"失敗: {d.name} の応答に {d.smoke_expect_any} のどれも含まれていません", file=sys.stderr)
            failed = True

        print(f"--- {d.name} ---\nQ: {d.smoke_input}\nA: {text[:500]}\n")

    if failed:
        sys.exit(1)
    print("動作確認 OK")


if __name__ == "__main__":
    main()
