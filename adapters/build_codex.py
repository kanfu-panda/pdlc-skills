#!/usr/bin/env python3
"""Codex 入口：构建 Agent Skills 标准投影，供 install.sh --target codex 装到 ~/.codex/skills/。

我们验证过的 Codex 发行版读 ~/.codex/skills/<name>/SKILL.md（按 description 触发，不是斜杠命令），
加载的就是 Agent Skills 标准格式。所以 Codex 不再有自己的转译逻辑，产物与
adapters/build_agent_skills.py 完全相同，只是默认输出到 dist/codex。
见 docs/decisions/0007-agent-skills-standard.md（取代 ADR 0003 的逐平台转译器）。

用法：
  python3 adapters/build_codex.py [输出目录]   # 默认 dist/codex
  python3 adapters/build_codex.py --help
产物：
  <out>/skills/pdlc-*/          标准 skill（拷到 ~/.codex/skills/）
  <out>/pdlc-methodology.md     平台中立方法论
"""
import sys

from build_agent_skills import REPO, main

if __name__ == "__main__":
    if sys.argv[1:2] in (["-h"], ["--help"]):
        print(__doc__)
        sys.exit(0)
    sys.exit(main(default=REPO / "dist" / "codex", label="Codex 适配器（Agent Skills 标准投影）"))
