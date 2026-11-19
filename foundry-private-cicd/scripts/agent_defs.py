"""エージェント定義（agents/*.yaml）の読み込みと検証。

Azure のライブラリを使わないので、GitHub-hosted runner（Foundry に届かない場所）でも
プル リクエストの検証に使える。
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

import yaml

AGENTS_DIR = Path(__file__).resolve().parent.parent / "agents"
NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{0,62}$")


@dataclass
class AgentDef:
    path: Path
    name: str
    model: str
    instructions: str
    smoke_input: str | None = None
    smoke_expect_any: list[str] = field(default_factory=list)


def load_agent_defs(agents_dir: Path = AGENTS_DIR) -> list[AgentDef]:
    """agents/ 配下の YAML をすべて読み、検証して返す。問題があれば終了する。"""
    files = sorted(agents_dir.glob("*.yaml")) + sorted(agents_dir.glob("*.yml"))
    if not files:
        sys.exit(f"エージェント定義が見つかりません: {agents_dir}")

    errors: list[str] = []
    defs: list[AgentDef] = []
    seen: set[str] = set()

    for path in files:
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except yaml.YAMLError as e:
            errors.append(f"{path.name}: YAML の書き方が正しくありません: {e}")
            continue

        name = str(data.get("name", "")).strip()
        model = str(data.get("model", "")).strip()
        instructions = str(data.get("instructions", "")).strip()

        if not NAME_PATTERN.match(name):
            errors.append(f"{path.name}: name は英数字とハイフン（63 文字以内）で指定してください: {name!r}")
        if name in seen:
            errors.append(f"{path.name}: name {name!r} が別のファイルと重複しています")
        seen.add(name)
        if not model:
            errors.append(f"{path.name}: model（モデルのデプロイ名）がありません")
        if not instructions:
            errors.append(f"{path.name}: instructions がありません")

        smoke = data.get("smoke_test") or {}
        expect_any = smoke.get("expect_any") or []
        if not isinstance(expect_any, list):
            errors.append(f"{path.name}: smoke_test.expect_any はリストで指定してください")
            expect_any = []

        defs.append(
            AgentDef(
                path=path,
                name=name,
                model=model,
                instructions=instructions,
                smoke_input=smoke.get("input"),
                smoke_expect_any=[str(x) for x in expect_any],
            )
        )

    if errors:
        print("エージェント定義にエラーがあります:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        sys.exit(1)

    return defs
