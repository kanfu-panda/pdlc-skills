#!/usr/bin/env python3
"""把唯一源头同步进每个 skill 文件夹，让 skill 自包含。

为什么需要它：skill 运行时，模型只拿到「本 skill 目录」和 SKILL.md 正文——frontmatter 看不见，
插件根目录下的 references/、bin/ 也没有任何路径告诉它去哪找。靠 HTML 注释约定「运行时去读片段」，
读不读全凭模型临场发挥；Agent Skills 开放标准同样要求 skill 文件夹自包含、引用相对 skill 根目录。

唯一源头（只改这里）：
  references/templates/prompts/*.md   共享片段
  references/templates/*              文档模板
  bin/*.sh                            随插件分发的脚本

同步产物（skills/<name>/ 下，由本脚本生成，勿手改）：
  1. SKILL.md 里的 <!-- @include templates/prompts/X.md --> 展开成内联区块（起止标记包住片段原文）
  2. 写状态机的命令（内联了 state-update 片段）：在该区块前生成 pdlc:meta 区块，
     写明 frontmatter 的 stage / next_step——模型看不见 frontmatter
  3. 正文引用的 `assets/X` → 复制 references/templates/X
  4. 正文引用的 `scripts/pdlc-*.sh` → 复制 bin/ 下同名脚本（保留可执行位）
  assets/ scripts/ 下无人引用的文件会被删除——这两个目录只放同步产物。

用法：
  python3 adapters/sync_skills.py           # 同步（改了片段 / 模板 / 脚本后重跑）
  python3 adapters/sync_skills.py --check   # 只检查：有漂移则逐项列出并退出 1（tests/ 调用它）

幂等：先把已有区块折叠回裸标记，再重新展开，所以片段改动后重跑即可刷新。
Codex 适配器（build_codex.py）复用这里的折叠逻辑，从裸标记出发做它自己的投影。
"""
import filecmp
import re
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SKILLS = REPO / "skills"
PROMPTS = REPO / "references" / "templates" / "prompts"
TEMPLATES = REPO / "references" / "templates"
BIN = REPO / "bin"

INCLUDE_RE = re.compile(r"<!--\s*@include\s+templates/prompts/([a-z0-9-]+)\.md\s*-->")
BEGIN = "<!-- @include templates/prompts/{0}.md（已内联于下方，无需另读） -->"
END = "<!-- @include-end templates/prompts/{0}.md -->"
REGION_RE = re.compile(
    r"<!-- @include templates/prompts/([a-z0-9-]+)\.md（已内联于下方，无需另读） -->\n"
    r".*?\n<!-- @include-end templates/prompts/\1\.md -->",
    re.DOTALL,
)
META_RE = re.compile(r"<!-- pdlc:meta[^\n]*-->\n.*?\n<!-- pdlc:meta-end -->\n", re.DOTALL)
FM_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
# 片段首行是给贡献者看的来源注释（如「被所有 Layer 1/2 命令 @include」），内联时剥掉
SOURCE_MARKER_RE = re.compile(r"^<!--.*?-->\n\n?", re.DOTALL)
# 资产 / 脚本引用只认反引号包住的这两种形态，避免误伤正文里谈论用户项目的 assets/、scripts/
ASSET_RE = re.compile(r"`assets/([a-z0-9.-]+)`")
SCRIPT_RE = re.compile(r"`scripts/(pdlc-[a-z0-9-]+\.sh)`")


def collapse_regions(body):
    """只把内联区块折叠回裸 @include 标记（Codex 投影从这里出发，按它自己的规则内联）。"""
    return REGION_RE.sub(lambda m: f"<!-- @include templates/prompts/{m.group(1)}.md -->", body)


def collapse(body):
    """折叠内联区块，并去掉 pdlc:meta 区块——回到源头形态。"""
    return collapse_regions(META_RE.sub("", body))


def fragment_text(name):
    src = PROMPTS / f"{name}.md"
    if not src.exists():
        sys.exit(f"错误：缺失片段 {src.relative_to(REPO)}")
    return SOURCE_MARKER_RE.sub("", src.read_text(encoding="utf-8"), count=1).rstrip("\n")


def fm_value(fm, key):
    m = re.search(rf"^{key}:\s*(.*)$", fm, re.MULTILINE)
    return m.group(1).strip() if m else ""


def meta_block(fm):
    stage, nxt = fm_value(fm, "stage"), fm_value(fm, "next_step")
    if nxt in ("", "null", "~"):
        hop = "下一跳 `null`（流程到此结束：`next_step` 写 `null`）"
    else:
        hop = f"下一跳 `{nxt}`（写进 `next_step`，交接时提示）"
    return (
        "<!-- pdlc:meta 由 frontmatter 生成（adapters/sync_skills.py），勿手改 -->\n"
        f"> **本命令的状态机取值**：阶段短名 `{stage}`（写进 `history[].stage` 与 "
        f"`last_phase_result.stage`）；{hop}。\n"
        "<!-- pdlc:meta-end -->\n"
    )


def render(text):
    """源头形态或旧的同步产物 → 当前应有的 SKILL.md 全文。"""
    m = FM_RE.match(text)
    fm, body = (m.group(1), text[m.end():]) if m else ("", text)
    head = text[: m.end()] if m else ""
    body = collapse(body)
    if "<!-- @include templates/prompts/state-update.md -->" in body:
        body = body.replace(
            "<!-- @include templates/prompts/state-update.md -->",
            meta_block(fm) + "<!-- @include templates/prompts/state-update.md -->",
            1,
        )
    body = INCLUDE_RE.sub(
        lambda mm: f"{BEGIN.format(mm.group(1))}\n{fragment_text(mm.group(1))}\n{END.format(mm.group(1))}",
        body,
    )
    return head + body


def plan_files(skill_dir, body):
    """该 skill 应有的 assets/ scripts/ 副本：{目标路径: 源路径}。"""
    want = {}
    for a in sorted(set(ASSET_RE.findall(body))):
        src = TEMPLATES / a
        if not src.is_file():
            sys.exit(f"错误：{skill_dir.name} 引用了 assets/{a}，但源头 {src.relative_to(REPO)} 不存在")
        want[skill_dir / "assets" / a] = src
    for s in sorted(set(SCRIPT_RE.findall(body))):
        src = BIN / s
        if not src.is_file():
            sys.exit(f"错误：{skill_dir.name} 引用了 scripts/{s}，但源头 {src.relative_to(REPO)} 不存在")
        want[skill_dir / "scripts" / s] = src
    return want


def main(argv):
    check = "--check" in argv
    drift, written = [], []

    for skill_dir in sorted(p for p in SKILLS.iterdir() if (p / "SKILL.md").is_file()):
        skill_md = skill_dir / "SKILL.md"
        cur = skill_md.read_text(encoding="utf-8")
        new = render(cur)
        rel = skill_md.relative_to(REPO)
        if new != cur:
            drift.append(f"{rel}：内联区块 / meta 区块与源头不一致")
            if not check:
                skill_md.write_text(new, encoding="utf-8")
                written.append(str(rel))

        want = plan_files(skill_dir, new)
        for dst, src in want.items():
            if dst.exists() and filecmp.cmp(dst, src, shallow=False) and \
                    (dst.stat().st_mode & 0o111) == (src.stat().st_mode & 0o111):
                continue
            drift.append(f"{dst.relative_to(REPO)}：缺失或与 {src.relative_to(REPO)} 不一致")
            if not check:
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)
                written.append(str(dst.relative_to(REPO)))
        for sub in ("assets", "scripts"):
            d = skill_dir / sub
            if not d.is_dir():
                continue
            for p in sorted(d.iterdir()):
                if p not in want:
                    drift.append(f"{p.relative_to(REPO)}：无人引用的多余副本")
                    if not check:
                        p.unlink()
                        written.append(f"删除 {p.relative_to(REPO)}")
            if not check and not any(d.iterdir()):
                d.rmdir()

    if check:
        if drift:
            print("❌ skill 与源头有漂移（改了片段 / 模板 / 脚本后请运行 python3 adapters/sync_skills.py）：")
            for line in drift:
                print(f"   - {line}")
            return 1
        print("✅ 所有 skill 与源头一致")
        return 0

    print(f"✅ 同步完成：{len(written)} 处改动" if written else "✅ 已是最新，无改动")
    for line in written:
        print(f"   - {line}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
