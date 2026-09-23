#!/usr/bin/env bash
# skill 自包含检查（A-det：纯静态，不烧模型额度）。
#
# 背景：skill 运行时，模型只拿到「本 skill 目录」+ SKILL.md 正文——frontmatter 看不见，
# 插件根目录下的 references/、bin/ 也没有任何路径告诉它去哪找。于是：
#   - 148 处 <!-- @include templates/prompts/X.md --> 能不能读到全凭模型临场发挥
#     （路径相对 references/，skill 的基准目录却是 skills/<name>/，两边对不上）；
#   - 近 30 处 `templates/X` 模板引用同样解析不了，另有 2 处指向早已不存在的 v1 路径；
#   - 体检脚本靠「上两级 / 环境变量 / 按修改时间猜最新缓存」去找，最后一条会挑到旧版本；
#   - 写状态机的命令被要求按 frontmatter 的 stage / next_step 写值，可它们看不见 frontmatter；
#   - `$ARGUMENTS` 嵌在句子里，被替换成参数（或空串）后句子读不通。
# Agent Skills 开放标准同样要求 skill 文件夹自包含、引用相对 skill 根目录。
#
# 本脚本钉住「自包含」的每一条：片段已内联、模板与脚本在 skill 自己的 assets/ scripts/ 下
# 且与唯一源头逐字节一致、frontmatter 取值已写进正文、参数占位符只出现在独立的一行。
# 解析逻辑刻意不复用 adapters/sync_skills.py——测试与被测对象共用一段代码，就会共用同一个 bug。
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO" || exit 1

pass=0
fail=0
ok()  { echo "  ✓ $1"; pass=$((pass + 1)); }
bad() { echo "  ✗ $1"; [ -n "${2:-}" ] && printf '    %s\n' "$2"; fail=$((fail + 1)); }

if ! command -v python3 >/dev/null 2>&1; then
    echo "✗ 需要 python3"; exit 1
fi

# ─── 1. 同步脚本存在，且源头与各 skill 里的副本没有漂移 ───
echo "Test: 同步脚本与漂移"
if [ -f adapters/sync_skills.py ]; then
    ok "adapters/sync_skills.py 存在"
    drift="$(python3 adapters/sync_skills.py --check 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then ok "sync --check 无漂移"; else bad "sync --check 无漂移（改了片段/模板/脚本后没重跑同步？）" "$drift"; fi
else
    bad "adapters/sync_skills.py 存在"
    bad "sync --check 无漂移" "同步脚本不存在"
fi

# ─── 2~6. 逐 skill 的结构检查（独立实现，不 import 同步脚本）───
# 每行输出：OK<TAB>描述 或 BAD<TAB>描述<TAB>细节。
# Python 先写进临时文件再执行：heredoc 放在 $(...) 里时，bash 3.2 会去配对正文里的反引号而解析失败。
PYCHK="$(mktemp)"
trap 'rm -f "$PYCHK"' EXIT
cat > "$PYCHK" <<'PY'
import re, filecmp, os
from pathlib import Path

SK = Path("skills"); PROMPTS = Path("references/templates/prompts")
TPL = Path("references/templates"); BIN = Path("bin")
FRAGS = sorted(p.stem for p in PROMPTS.glob("*.md"))

out = []
def ok(d): out.append(f"OK\t{d}")
def bad(d, x=""): out.append(f"BAD\t{d}\t{x}")

def split(text):
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    return (m.group(1), text[m.end():]) if m else ("", text)

def fm_val(fm, key):
    m = re.search(rf"^{key}:\s*(.*)$", fm, re.M)
    return m.group(1).strip() if m else None

OLD = re.compile(r"<!--\s*@include\s+templates/prompts/([a-z0-9-]+)\.md\s*-->")
BEGIN = re.compile(r"<!-- @include templates/prompts/([a-z0-9-]+)\.md（已内联于下方，无需另读） -->")
END = re.compile(r"<!-- @include-end templates/prompts/([a-z0-9-]+)\.md -->")
REGION = re.compile(r"<!-- @include templates/prompts/([a-z0-9-]+)\.md（已内联于下方，无需另读） -->\n"
                    r"(.*?)\n<!-- @include-end templates/prompts/\1\.md -->", re.S)
META = re.compile(r"<!-- pdlc:meta[^\n]*-->\n(.*?)\n<!-- pdlc:meta-end -->", re.S)
ASSET = re.compile(r"`assets/([a-z0-9.-]+)`")
SCRIPT = re.compile(r"`scripts/(pdlc-[a-z0-9-]+\.sh)`")

def outside_regions(body):
    return REGION.sub("", body)

bad_old, bad_pair, bad_content, bad_tpl, bad_asset, bad_stray = [], [], [], [], [], []
bad_script, bad_meta, bad_args, bad_xref = [], [], [], []
writers = 0

for d in sorted(SK.iterdir()):
    f = d / "SKILL.md"
    if not f.exists():
        continue
    name = d.name
    fm, body = split(f.read_text(encoding="utf-8"))

    # 2. 片段：不许残留旧式裸标记；起止标记成对；区块内容 = 片段原文（去掉首行来源注释）
    if OLD.search(body):
        bad_old.append(name)
    b, e = BEGIN.findall(body), END.findall(body)
    if b != e:
        bad_pair.append(f"{name}: begin={b} end={e}")
    inlined = set()
    for frag, content in REGION.findall(body):
        inlined.add(frag)
        src = (PROMPTS / f"{frag}.md")
        if not src.exists():
            bad_content.append(f"{name}: 片段 {frag}.md 不存在"); continue
        want = re.sub(r"^<!--.*?-->\n\n?", "", src.read_text(encoding="utf-8"), count=1, flags=re.S).rstrip("\n")
        if content != want:
            bad_content.append(f"{name}: {frag}.md 区块与片段不一致")

    # 3. 模板：正文不再有解析不了的 templates/ 与 v1 旧路径；assets 引用全能解析、与源头一致、无多余副本
    rest = outside_regions(body)
    for m in re.finditer(r"(?<![\w/.-])(?:\.claude/)?templates/[A-Za-z0-9._/-]+", rest):
        bad_tpl.append(f"{name}: {m.group(0)}")
    full = body  # 区块里（片段）引用的资产同样要在 skill 目录下
    refs = set(ASSET.findall(full))
    for a in sorted(refs):
        got, src = d / "assets" / a, TPL / a
        if not src.exists():
            bad_asset.append(f"{name}: assets/{a} 没有源头 references/templates/{a}")
        elif not got.exists():
            bad_asset.append(f"{name}: 缺 assets/{a}")
        elif not filecmp.cmp(got, src, shallow=False):
            bad_asset.append(f"{name}: assets/{a} 与源头不一致")
    if (d / "assets").is_dir():
        for p in sorted((d / "assets").iterdir()):
            if p.name not in refs:
                bad_stray.append(f"{name}: assets/{p.name} 无人引用")

    # 4. 脚本：scripts 引用全能解析、可执行、与 bin/ 源头一致；无多余副本
    srefs = set(SCRIPT.findall(full))
    for s in sorted(srefs):
        got, src = d / "scripts" / s, BIN / s
        if not src.exists():
            bad_script.append(f"{name}: scripts/{s} 没有源头 bin/{s}")
        elif not got.exists():
            bad_script.append(f"{name}: 缺 scripts/{s}")
        elif not os.access(got, os.X_OK):
            bad_script.append(f"{name}: scripts/{s} 不可执行")
        elif not filecmp.cmp(got, src, shallow=False):
            bad_script.append(f"{name}: scripts/{s} 与 bin/{s} 不一致")
    if (d / "scripts").is_dir():
        for p in sorted((d / "scripts").iterdir()):
            if p.name not in srefs:
                bad_stray.append(f"{name}: scripts/{p.name} 无人引用")

    # 5. 写状态机的命令：frontmatter 的 stage / next_step 必须写进正文（模型看不见 frontmatter）
    if "state-update" in inlined:
        writers += 1
        stage, nxt = fm_val(fm, "stage"), fm_val(fm, "next_step")
        m = META.search(body)
        if not m:
            bad_meta.append(f"{name}: 缺 pdlc:meta 区块")
        else:
            txt = m.group(1)
            if f"`{stage}`" not in txt:
                bad_meta.append(f"{name}: meta 未写阶段短名 {stage}")
            if f"`{nxt}`" not in txt:
                bad_meta.append(f"{name}: meta 未写下一跳 {nxt}")
            if body.find("<!-- pdlc:meta") > body.find("<!-- @include templates/prompts/state-update.md"):
                bad_meta.append(f"{name}: meta 应在 state-update 区块之前")

    # 6. 参数占位符：至多一处，且独占一行——要么「标签：」后面紧跟占位符，要么这一行只有占位符
    lines = [l for l in body.splitlines() if "$ARGUMENTS" in l]
    if len(lines) > 1:
        bad_args.append(f"{name}: 出现 {len(lines)} 次")
    for l in lines:
        if not re.fullmatch(r"\s*(?:(?:\*\*)?[^`$*]{1,20}(?:\*\*)?\s*[:：]\s*)?\$ARGUMENTS\s*", l):
            bad_args.append(f"{name}: 嵌在句子里：{l.strip()}")

    # 7. 交叉引用：正文（含内联片段）提到的片段文件名，必须也内联在本 skill 里
    for frag in FRAGS:
        if frag in inlined:
            continue
        if re.search(rf"`(?:templates/prompts/)?{re.escape(frag)}\.md`", body):
            bad_xref.append(f"{name}: 提到 {frag}.md，但本 skill 没有内联它")

def report(items, desc):
    if items: bad(desc, "; ".join(items[:8]) + (f" …（共 {len(items)} 处）" if len(items) > 8 else ""))
    else: ok(desc)

report(bad_old, "无旧式裸 @include 标记（全部已内联）")
report(bad_pair, "内联区块起止标记成对")
report(bad_content, "内联区块与片段原文逐字一致")
report(bad_tpl, "正文无解析不了的 templates/ 与 v1 旧路径")
report(bad_asset, "assets/ 引用全部可解析且与 references/templates/ 一致")
report(bad_script, "scripts/ 引用全部可解析、可执行且与 bin/ 一致")
report(bad_stray, "assets/ scripts/ 下无人引用的多余副本")
if writers == 12: ok("写状态机的命令共 12 个")
else: bad("写状态机的命令共 12 个", f"实际 {writers}")
report(bad_meta, "写状态机的命令正文里有 stage / next_step（frontmatter 对模型不可见）")
report(bad_args, "$ARGUMENTS 至多一处且独占一行")
report(bad_xref, "提到的片段文件名都内联在本 skill 里")
print("\n".join(out))
PY
results="$(python3 "$PYCHK")"
echo ""
echo "Test: 逐 skill 结构"
while IFS=$'\t' read -r st desc detail; do
    [ -n "$st" ] || continue
    if [ "$st" = "OK" ]; then ok "$desc"; else bad "$desc" "$detail"; fi
done <<< "$results"

# ─── 8. 查找逻辑不再依赖「上两级 / 按修改时间猜版本」───
echo ""
echo "Test: 脚本查找"
if grep -rn -F 'ls -td' skills references/templates/prompts >/dev/null 2>&1; then
    bad "skills 与片段里不再用 ls -td 按修改时间挑版本" "$(grep -rn -F 'ls -td' skills references/templates/prompts | head -3)"
else
    ok "skills 与片段里不再用 ls -td 按修改时间挑版本"
fi
read_frag="$(cat references/templates/prompts/state-read.md)"
# shellcheck disable=SC2016  # 反引号是要匹配的字面文本，不是命令替换
if grep -qF '`scripts/pdlc-state-lint.sh`' <<< "$read_frag"; then
    ok "state-read 片段指向 skill 自带的 scripts/pdlc-state-lint.sh"
else
    bad "state-read 片段指向 skill 自带的 scripts/pdlc-state-lint.sh"
fi
if grep -qF '上两级' <<< "$read_frag"; then
    bad "state-read 片段不再用「上两级」去插件根找脚本"
else
    ok "state-read 片段不再用「上两级」去插件根找脚本"
fi
for sk in pdlc-status pdlc-retro pdlc-relate; do
    if [ -x "skills/$sk/scripts/pdlc-state-lint.sh" ]; then ok "$sk 自带可执行的体检脚本"
    else bad "$sk 自带可执行的体检脚本"; fi
done

echo ""
echo "Final: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
