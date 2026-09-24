#!/usr/bin/env python3
"""Agent Skills 标准投影：把 skills/*/SKILL.md 投影成符合 Agent Skills 开放标准的 skill 集。

标准见 https://agentskills.io/specification 。支持它的工具（GitHub Copilot、Gemini CLI、OpenCode、Amp、
Goose、Cursor、Codex 等）都按「文件夹 + SKILL.md（name + description）」加载、按描述触发。
决策见 docs/decisions/0007-agent-skills-standard.md。

源码 skills/ 是 Claude Code 形态（顶层有 argument-hint、PDLC 内部字段，正文用 $ARGUMENTS 与斜杠命令），
Claude Code 直接用它。其它工具用本脚本的产物：
  1. 内联 @include 片段（源里的内联区块先折叠回裸标记，再内联），剥掉 adapter:claude-only 块
  2. frontmatter 只留标准字段：name、description（追加触发提示）、license、metadata（值一律为字符串）
  3. 「参数：$ARGUMENTS」改写成自然语言——其它工具不保证替换占位符
  4. 正文开头说明 /pdlc-<名字> 指同名技能；next_step 写成正文末尾的「下一步」
  5. 不投影 Claude Code 专属的 skill（状态栏配置、Task 版收敛引擎）

用法：
  python3 adapters/build_agent_skills.py [输出目录]   # 默认 dist/agent-skills
  python3 adapters/build_agent_skills.py --help
产物：
  <out>/skills/pdlc-*/          标准 skill：SKILL.md + 自带的 assets/ scripts/
  <out>/pdlc-methodology.md     平台中立方法论（不读 skill 的工具可以放进 AGENTS.md）
"""
import json
import re
import shutil
import sys
from pathlib import Path

from sync_skills import collapse_regions

REPO = Path(__file__).resolve().parent.parent
SKILLS = REPO / "skills"
PROMPTS_SRC = REPO / "references" / "templates" / "prompts"
METHODOLOGY = REPO / "docs" / "pdlc-methodology.md"

# 不投影：
#   pdlc-settings  —— 配置 Claude Code 状态栏、改全局 settings.json，其它工具没有等价机制
#   pdlc-loop-run  —— 默认的 Task 版用 Claude Code 的 Task 子代理派发。多功能循环驱动 bin/pdlc-loop.sh
#                     随 pdlc-status 投影出去，外部驱动的用法不受影响
DENYLIST = {
    "pdlc-settings",
    "pdlc-loop-run",
}

INCLUDE_RE = re.compile(r"<!--\s*@include\s+templates/prompts/([a-z0-9-]+)\.md\s*-->")
FM_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
# 源里被 <!-- adapter:claude-only-start/end --> 包住的块只对 Claude Code 成立（如 claude -p 管线、
# 到 ~/.claude/plugins 下找脚本）。skill 正文与片段里都可能有，所以内联前后各剥一次
CLAUDE_ONLY_RE = re.compile(
    r"[ \t]*<!--\s*adapter:claude-only-start\s*-->.*?<!--\s*adapter:claude-only-end\s*-->\n?",
    re.DOTALL,
)
# 片段首行是给贡献者看的来源注释（如「被所有 Layer 1/2 命令 @include」），内联时剥掉
SOURCE_MARKER_RE = re.compile(r"^<!--.*?-->\n\n?", re.DOTALL)
# 「<标签>: $ARGUMENTS」或单独一个 $ARGUMENTS 的整行
ARG_LINE_RE = re.compile(r"^(?P<label>[^\n]*?)\s*\$ARGUMENTS[ \t]*$", re.MULTILINE)
ARG_TEXT = "用户请求里跟在技能名后面的内容（功能ID、需求描述或参数）"

# Agent Skills 靠 description 匹配触发，这句帮模型把「用 pdlc …」「按 pdlc …」关联到本技能
TRIGGER_SUFFIX = "当用户用自然语言要求执行该 PDLC 阶段（如「用 pdlc …」「按 pdlc …」）时使用。"
SLASH_NOTE = (
    "> 本技能集中的 `/pdlc-<名字>` 指同名技能 `pdlc-<名字>`；工具不支持斜杠命令时，"
    "用自然语言让它按该技能执行（如「按 pdlc review 执行 <功能ID>」）。\n\n"
)
# 产物目录里只可能出现这些条目。"prompts" 是 v1.5.0 的旧产物、"templates" 是 v1.6.4 及以前的产物，
# 留在白名单里，否则从旧版本升级时会被下面的守卫误判
KNOWN_OUTPUTS = {"skills", "templates", "pdlc-methodology.md", "prompts"}


def parse_frontmatter(text):
    """拆出 frontmatter 与正文。只解析顶层 `key: value`（值不跨行），足够本用途。"""
    m = FM_RE.match(text)
    if not m:
        return {}, text
    fm = {}
    for line in m.group(1).splitlines():
        if line[:1].isspace() or ":" not in line:
            continue
        key, _, val = line.partition(":")
        fm[key.strip()] = val.strip()
    return fm, text[m.end():]


def inline_includes(body):
    def repl(m):
        frag = PROMPTS_SRC / f"{m.group(1)}.md"
        if not frag.exists():
            sys.exit(f"错误：缺失片段 {frag}")
        return SOURCE_MARKER_RE.sub("", frag.read_text(encoding="utf-8").rstrip("\n"), count=1)

    return INCLUDE_RE.sub(repl, body)


def rewrite_arguments(body):
    def repl(m):
        label = m.group("label").rstrip()
        if not label:
            return f"参数：{ARG_TEXT}"
        return f"{label.rstrip(':：').rstrip()}：{ARG_TEXT}"

    body = ARG_LINE_RE.sub(repl, body)
    if "$ARGUMENTS" in body:
        sys.exit("错误：正文里有不成行的 $ARGUMENTS，无法改写（应单独一行：`<标签>: $ARGUMENTS`）")
    return body


def next_step_note(fm):
    nxt = fm.get("next_step", "").strip().strip("'\"")
    if not nxt or nxt in ("null", "~"):
        return ""
    short = nxt.replace("pdlc-", "")
    return (
        f"\n\n---\n\n"
        f"## 下一步（PDLC 链式推进）\n\n"
        f"本阶段收尾后，下一跳是 **{nxt}** 技能。用自然语言「按 pdlc {short}」继续即可"
        f"（技能按描述触发；支持斜杠命令的工具也可以直接调用它）。链式推进以状态机 "
        f"`docs/.pdlc-state/<feature-id>.json` 的 `next_step` 为准。\n"
    )


def yaml_str(s):
    """双引号 YAML 字符串（JSON 字符串是合法的 YAML 双引号标量），避免冒号、方括号等被当成语法。"""
    return json.dumps(s, ensure_ascii=False)


def frontmatter(fm):
    meta = [("pdlc-layer", fm.get("layer", "")), ("pdlc-stage", fm.get("stage", ""))]
    nxt = fm.get("next_step", "").strip("'\"")
    if nxt and nxt not in ("null", "~"):
        meta.append(("pdlc-next-step", nxt))
    desc = fm.get("description", "").strip()
    if desc and desc[-1] not in "。.！!？?":
        desc += "。"
    lines = [
        "---",
        f"name: {fm['name']}",
        f"description: {yaml_str(desc + TRIGGER_SUFFIX)}",
        "license: MIT",
        "metadata:",
    ]
    lines += [f"  {k}: {yaml_str(v)}" for k, v in meta if v]
    lines.append("---")
    return "\n".join(lines) + "\n"


def transpile(text):
    fm, body = parse_frontmatter(text)
    body = collapse_regions(body)
    body = CLAUDE_ONLY_RE.sub("", body)
    body = inline_includes(body)
    body = CLAUDE_ONLY_RE.sub("", body)
    body = rewrite_arguments(body)
    body = body.lstrip("\n")
    # 说明放在第一个标题之后，模型读到正文开头就知道斜杠命令怎么理解
    m = re.match(r"(#[^\n]*\n\n?)", body)
    body = body[: m.end()] + SLASH_NOTE + body[m.end():] if m else SLASH_NOTE + body
    return frontmatter(fm) + body + next_step_note(fm)


def parse_out(argv, default):
    """只接受一个不以 - 开头的输出目录；-h / --help 打印用法。返回 None 表示已打印用法。"""
    if argv and argv[0] in ("-h", "--help"):
        print(__doc__)
        return None
    # 曾把 --dry-run 当成目录名，在当前目录下建出一个 --dry-run/
    if any(a.startswith("-") for a in argv) or len(argv) > 1:
        sys.exit(f"错误：只接受一个输出目录参数（得到 {' '.join(argv)}）")
    return Path(argv[0]) if argv else default


def build(out):
    skills_out = out / "skills"
    # out 是命令行传入的任意路径：只删「看起来纯是本脚本产物」的目录，防止手滑指向真实目录被递归删除
    if out.exists() and any(out.iterdir()):
        foreign = sorted(p.name for p in out.iterdir() if p.name not in KNOWN_OUTPUTS)
        if foreign:
            sys.exit(
                f"错误：输出目录 {out} 含非构建产物（{', '.join(foreign)}）——拒绝删除，防误删真实数据。\n"
                f"      请指向空目录或专用构建目录。"
            )
        shutil.rmtree(out)
    skills_out.mkdir(parents=True)

    ported, skipped = [], []
    for skill_dir in sorted(SKILLS.iterdir()):
        src = skill_dir / "SKILL.md"
        if not src.exists():
            continue
        if skill_dir.name in DENYLIST:
            skipped.append(skill_dir.name)
            continue
        result = transpile(src.read_text(encoding="utf-8"))
        if INCLUDE_RE.search(result):
            sys.exit(f"错误：{skill_dir.name} 投影后仍残留 @include（片段缺失？）")
        (skills_out / skill_dir.name).mkdir()
        (skills_out / skill_dir.name / "SKILL.md").write_text(result, encoding="utf-8")
        # 模板与脚本随 skill 自带（adapters/sync_skills.py 同步），正文的 assets/ scripts/ 引用原样可解析
        for sub in ("assets", "scripts"):
            if (skill_dir / sub).is_dir():
                shutil.copytree(skill_dir / sub, skills_out / skill_dir.name / sub)
        ported.append(skill_dir.name)

    if METHODOLOGY.exists():
        shutil.copy2(METHODOLOGY, out / "pdlc-methodology.md")
    return ported, skipped


def main(argv=None, default=REPO / "dist" / "agent-skills", label="Agent Skills 标准投影"):
    out = parse_out(sys.argv[1:] if argv is None else argv, default)
    if out is None:
        return 0
    ported, skipped = build(out)
    print(f"✅ {label}构建完成 → {out}")
    print(f"   skills: {len(ported)} 个（denylist 跳过 {len(skipped)}：{', '.join(skipped)}）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
