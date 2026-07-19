#!/usr/bin/env python3
"""Codex 适配器：把 skills/*/SKILL.md 投影为 Codex CLI 自定义 prompts。

单一源 = skills/*/SKILL.md；本脚本按 ADR 0003 §5 的四步做「构建期投影」：
  1. 内联 @include 片段 → 每个 prompt 自包含（不依赖 Claude 的运行时约定）
  2. 重写 frontmatter → 只留 Codex 认的 description / argument-hint
  3. 物化命名空间 → 把 next_step 写成正文里的「下一步」指令
  4. 丢弃 Claude-Code-only 能力（statusline 配置、自主收敛引擎）

用法：
  python3 adapters/build_codex.py [输出目录]   # 默认 dist/codex
产物：
  <out>/prompts/pdlc-*.md      转译后的 Codex prompts（拷到 ~/.codex/prompts/）
  <out>/templates/             文档模板（拷到 ~/.codex/pdlc/templates/）
  <out>/pdlc-methodology.md    平台中立方法论（供自然语言路径按需引用）

详见 adapters/README.md 与 docs/decisions/0003-multi-platform-adapters.md。
"""
import re
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SKILLS = REPO / "skills"
PROMPTS_SRC = REPO / "references" / "templates" / "prompts"
TEMPLATES_SRC = REPO / "references" / "templates"
METHODOLOGY = REPO / "docs" / "pdlc-methodology.md"

# 本 PoC 暂不投影。区分两类原因，别一概说成「Claude 绑死」：
#   pdlc-settings   —— 真·Claude-only：配状态栏 / 改全局 settings.json，Codex 无等价机制。
#   pdlc-loop-run   —— 部分耦合：默认「Task 版」用 Claude Code 的 Task 子代理派发（Codex 无直接等价）；
#                      「外部 Runbook 版」原理可移植（bash 循环换 claude→codex），但需 Codex 驱动脚本 +
#                      过 ADR 0003 §6.1 状态完整性准入闸后才敢放行（防 --autonomous 下写脏共用状态）。
#   pdlc-loop-next  —— 逻辑本身平台中立（只读状态机、按 next_step 打印下一跳 token），并非绑死；
#                      但它是 loop-run 的低层 helper，单独投影是个无引擎消费的孤儿命令，
#                      故随整套「循环工程」系统一起留后续，不拆散。
# 其它平台可手动逐阶段驱动达到同样产物（见 pdlc-methodology.md §9）。
DENYLIST = {"pdlc-settings", "pdlc-loop-next", "pdlc-loop-run"}

# 模板在 Codex 侧的安装位置（install.sh --target codex 会把模板拷到这里）
CODEX_TEMPLATES = "~/.codex/pdlc/templates"

INCLUDE_RE = re.compile(r"<!--\s*@include\s+templates/prompts/([a-z0-9-]+)\.md\s*-->")
FM_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)


def parse_frontmatter(text):
    """拆出 YAML frontmatter 与正文。只解析顶层 `key: value`（值不跨行），足够本用途。"""
    m = FM_RE.match(text)
    if not m:
        return {}, text
    fm = {}
    for line in m.group(1).splitlines():
        # 跳过缩进行（列表项/续行）与无冒号行
        if line[:1].isspace() or ":" not in line:
            continue
        key, _, val = line.partition(":")
        fm[key.strip()] = val.strip()
    return fm, text[m.end():]


#   每个片段首行是来源标记注释（如 `<!-- IRON LAW · 被所有 Layer 1/2 命令 @include -->`），
#   内联时剥掉——避免把 Claude 术语（Layer 1/2、@include）带进 Codex prompt。
SOURCE_MARKER_RE = re.compile(r"^<!--.*?-->\n\n?", re.DOTALL)


def inline_includes(body):
    """把 <!-- @include templates/prompts/X.md --> 替换为片段原文（剥去首行来源标记），产出自包含 prompt。"""
    def repl(m):
        frag = PROMPTS_SRC / f"{m.group(1)}.md"
        if not frag.exists():
            sys.exit(f"错误：缺失片段 {frag}")
        text = frag.read_text(encoding="utf-8").rstrip("\n")
        return SOURCE_MARKER_RE.sub("", text, count=1)

    return INCLUDE_RE.sub(repl, body)


def rewrite_template_refs(body):
    """@include 已内联，剩余的 templates/ 一律指文档模板，改写到 Codex 安装位置。"""
    return body.replace("templates/", f"{CODEX_TEMPLATES}/")


def next_step_note(fm):
    """把 frontmatter 的 next_step 物化成正文指令（Codex 不把 frontmatter 当逻辑）。"""
    nxt = fm.get("next_step", "").strip().strip("'\"")
    if not nxt or nxt in ("null", "~"):
        return ""
    return (
        f"\n\n---\n\n"
        f"## 下一步（PDLC 链式推进）\n\n"
        f"本阶段收尾后，下一跳是 **`/{nxt}`**。在 Codex 里可直接调用 `/{nxt}` prompt，"
        f"或用自然语言「按 pdlc {nxt.replace('pdlc-', '')}」继续。链式推进以状态机 "
        f"`docs/.pdlc-state/<feature-id>.json` 的 `next_step` 为准。\n"
    )


def transpile(text):
    fm, body = parse_frontmatter(text)
    body = inline_includes(body)
    body = rewrite_template_refs(body)

    # Codex 认的 frontmatter：description + 可选 argument-hint
    head = ["---", f"description: {fm.get('description', '').strip()}"]
    hint = fm.get("argument-hint", "").strip()
    if hint:
        head.append(f"argument-hint: {hint}")
    head.append("---")

    return "\n".join(head) + "\n" + body.lstrip("\n") + next_step_note(fm)


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "dist" / "codex"
    prompts_out = out / "prompts"
    templates_out = out / "templates"

    # 全新构建：清掉旧产物
    if out.exists():
        shutil.rmtree(out)
    prompts_out.mkdir(parents=True)
    templates_out.mkdir(parents=True)

    ported, skipped = [], []
    for skill_dir in sorted(SKILLS.iterdir()):
        name = skill_dir.name
        src = skill_dir / "SKILL.md"
        if not src.exists():
            continue
        if name in DENYLIST:
            skipped.append(name)
            continue
        result = transpile(src.read_text(encoding="utf-8"))
        if INCLUDE_RE.search(result):
            sys.exit(f"错误：{name} 转译后仍残留 @include（片段缺失？）")
        (prompts_out / f"{name}.md").write_text(result, encoding="utf-8")
        ported.append(name)

    # 拷文档模板（供改写后的 templates/ 引用解析）
    for tpl in sorted(TEMPLATES_SRC.glob("*-template.*")):
        shutil.copy2(tpl, templates_out / tpl.name)

    # 拷平台中立方法论（自然语言路径按需引用）
    if METHODOLOGY.exists():
        shutil.copy2(METHODOLOGY, out / "pdlc-methodology.md")

    print(f"✅ Codex 适配器构建完成 → {out}")
    print(f"   prompts: {len(ported)} 个（denylist 跳过 {len(skipped)}：{', '.join(skipped)}）")
    print(f"   templates: {len(list(templates_out.glob('*')))} 个")
    return 0


if __name__ == "__main__":
    sys.exit(main())
