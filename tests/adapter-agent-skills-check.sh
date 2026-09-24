#!/usr/bin/env bash
# Agent Skills 标准投影（adapters/build_agent_skills.py）与 install.sh --target agents 的回归测试。
#
# 覆盖：
#   - 构建：36 个 skill（38 − 2 个 Claude Code 专属），自带的 assets/ scripts/ 随行、脚本可执行
#   - 标准符合性（确定性检查，不依赖网络）：name 与目录一致且合字符集、description 长度、
#     顶层字段只在标准允许的范围内、metadata 值为字符串、不用流式 YAML、正文引用的文件都在
#   - 正文：无残留 @include / $ARGUMENTS / Claude 专属块；有斜杠命令说明；下一步措辞平台中立
#   - 本机装了官方校验器 agentskills 时，对全部产物再跑一遍；没装则明确打印「跳过」
#   - 参数守卫：选项不会被当成输出目录；输出目录含非产物时拒绝删除
#   - Codex 入口（build_codex.py）产出与标准投影一致
#   - install.sh --target agents：用户级 / --project / --dest 三种落点，只动 pdlc-* 目录
# shellcheck disable=SC2015,SC2016  # SC2016：单引号里的 $ARGUMENTS 是要找的字面文本。SC2015：ok / bad 恒返回 0，`条件 && ok || bad` 只在条件不成立时走 bad
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR" || exit 1

pass=0
fail=0
ok()  { echo "  ✓ $1"; pass=$((pass + 1)); }
bad() { echo "  ✗ $1"; [[ -n "${2:-}" ]] && printf '    %s\n' "$2"; fail=$((fail + 1)); }
assert_eq() { if [[ "$3" == "$2" ]]; then ok "$1"; else bad "$1" "期望 ${2}，实际 $3"; fi; }

if ! command -v python3 >/dev/null 2>&1; then
    echo "⚠️  python3 未安装，跳过 Agent Skills 投影测试"
    exit 0
fi

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
OUT="$ROOT/out"

# ─── 构建 ───
echo "Test: 构建标准投影"
build_out="$(python3 adapters/build_agent_skills.py "$OUT" 2>&1)"; rc=$?
assert_eq "构建退出码 0" "0" "$rc"
n="$(find "$OUT/skills" -mindepth 1 -maxdepth 1 -type d -name 'pdlc-*' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "投影 36 个 skill（38 − 2 个 Claude Code 专属）" "36" "$n"
[[ ! -e "$OUT/skills/pdlc-settings" && ! -e "$OUT/skills/pdlc-loop-run" ]] \
    && ok "pdlc-settings / pdlc-loop-run 不投影" || bad "Claude Code 专属 skill 被投影了"
for s in pdlc-state-lint.sh pdlc-loop.sh; do
    [[ -x "$OUT/skills/pdlc-status/scripts/$s" ]] && ok "pdlc-status 带着可执行的 scripts/$s" || bad "pdlc-status 缺 scripts/$s"
done
[[ -f "$OUT/skills/pdlc-prd/assets/prd-template.md" ]] && ok "pdlc-prd 带着 assets/prd-template.md" || bad "pdlc-prd 缺模板"
grep -q "36" <<< "$build_out" && ok "构建输出报告 skill 数" || bad "构建输出没报告 skill 数" "$build_out"

# ─── 标准符合性（确定性检查）───
echo ""
echo "Test: 标准符合性（内置检查）"
CHECK="$ROOT/check.py"
cat > "$CHECK" <<'PY'
import re, sys
from pathlib import Path

ALLOWED = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}
NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
problems = []
root = Path(sys.argv[1])
for d in sorted(p for p in root.iterdir() if p.is_dir()):
    f = d / "SKILL.md"
    if not f.is_file():
        problems.append(f"{d.name}: 缺 SKILL.md"); continue
    text = f.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        problems.append(f"{d.name}: 没有 frontmatter"); continue
    fm, body = m.group(1), text[m.end():]
    top, meta, in_meta = {}, {}, False
    for line in fm.splitlines():
        if not line.strip():
            continue
        if line.startswith("  ") and in_meta:
            k, _, v = line.strip().partition(":")
            v = v.strip()
            if not v or v[0] in "[{-|>":
                problems.append(f"{d.name}: metadata.{k} 不是单行字符串")
            meta[k] = v
            continue
        if line[:1].isspace():
            problems.append(f"{d.name}: 顶层之外出现缩进行：{line!r}"); continue
        k, _, v = line.partition(":")
        v = v.strip()
        in_meta = (k == "metadata" and v == "")
        if v and v[0] in "[{":
            problems.append(f"{d.name}: {k} 用了流式 YAML")
        top[k] = v
    extra = set(top) - ALLOWED
    if extra:
        problems.append(f"{d.name}: 标准不允许的顶层字段 {sorted(extra)}")
    name = top.get("name", "")
    if name != d.name or not NAME_RE.match(name) or len(name) > 64:
        problems.append(f"{d.name}: name 不合规（{name!r}）")
    desc = top.get("description", "").strip("'\"")
    if not (1 <= len(desc) <= 1024):
        problems.append(f"{d.name}: description 长度 {len(desc)}")
    if "license" not in top:
        problems.append(f"{d.name}: 缺 license")
    if "metadata" in top and not meta:
        problems.append(f"{d.name}: metadata 为空块")
    for ref in set(re.findall(r"`((?:assets|scripts)/[A-Za-z0-9._-]+)`", body)):
        if not (d / ref).is_file():
            problems.append(f"{d.name}: 正文引用的 {ref} 不存在")
print("\n".join(problems))
PY
probs="$(python3 "$CHECK" "$OUT/skills" 2>&1)"
assert_eq "全部 skill 通过内置标准检查" "" "$probs"

# ─── 正文 ───
echo ""
echo "Test: 正文投影"
left="$(grep -rlF '$ARGUMENTS' "$OUT/skills" 2>/dev/null || true)"
assert_eq "无残留参数占位符（其它工具不保证替换）" "" "$left"
assert_eq "无残留 @include" "" "$(grep -rl '@include' "$OUT/skills" 2>/dev/null || true)"
assert_eq "无 adapter:claude-only 块" "" "$(grep -rl 'adapter:claude-only' "$OUT/skills" 2>/dev/null || true)"
assert_eq "无 Claude 插件路径" "" "$(grep -rlE 'CLAUDE_PLUGIN_ROOT|~/\.claude/plugins' "$OUT/skills" 2>/dev/null || true)"
no_note=""
for d in "$OUT"/skills/pdlc-*/; do
    grep -qF '指同名技能' "$d/SKILL.md" || no_note="$no_note $(basename "$d")"
done
assert_eq "每个 skill 都有斜杠命令说明" "" "${no_note# }"
src_n="$(grep -lF '$ARGUMENTS' skills/*/SKILL.md | grep -vcE 'pdlc-(settings|loop-run)/')"
out_n="$(grep -lF '用户请求里跟在技能名后面的内容' "$OUT"/skills/pdlc-*/SKILL.md | wc -l | tr -d ' ')"
assert_eq "源码里带参数行的 skill，投影后参数行都改写成自然语言" "$src_n" "$out_n"
grep -qF '下一步（PDLC 链式推进）' "$OUT/skills/pdlc-tdd/SKILL.md" && ok "next_step 物化为正文「下一步」" || bad "缺「下一步」"
grep -rqF '本 Codex' "$OUT/skills" && bad "下一步措辞还写死了 Codex" || ok "下一步措辞平台中立"
grep -qE '^  pdlc-next-step: "?pdlc-implement"?$' "$OUT/skills/pdlc-tdd/SKILL.md" && ok "metadata 带 pdlc-next-step" || bad "metadata 缺 pdlc-next-step"

# ─── 官方校验器（可选）───
echo ""
echo "Test: 官方校验器"
if command -v agentskills >/dev/null 2>&1; then
    bad_n=0
    for d in "$OUT"/skills/pdlc-*/; do agentskills validate "$d" >/dev/null 2>&1 || bad_n=$((bad_n + 1)); done
    assert_eq "官方校验器：0 个不通过" "0" "$bad_n"
else
    echo "  - 跳过官方校验：本机没有 agentskills 命令（pip install skills-ref 后会自动启用）——这不代表通过"
fi

# ─── 参数守卫 ───
echo ""
echo "Test: 参数守卫"
(cd "$ROOT" && python3 "$SCRIPT_DIR/adapters/build_agent_skills.py" --dry-run >/dev/null 2>&1); rc=$?
[[ "$rc" -ne 0 && ! -e "$ROOT/--dry-run" ]] && ok "选项不会被当成输出目录" || bad "--dry-run 被当成了输出目录（退出 ${rc}）"
mkdir -p "$ROOT/foreign" && echo keep > "$ROOT/foreign/notes.txt"
python3 adapters/build_agent_skills.py "$ROOT/foreign" >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 && -f "$ROOT/foreign/notes.txt" ]] && ok "输出目录含非产物时拒绝删除" || bad "含非产物的输出目录被清掉了"

# ─── Codex 入口 ───
echo ""
echo "Test: Codex 入口与标准投影一致"
python3 adapters/build_codex.py "$ROOT/codex" >/dev/null 2>&1
d="$(diff -r "$OUT/skills" "$ROOT/codex/skills" 2>&1 | head -5)"
assert_eq "build_codex.py 产出的 skills 与标准投影逐字节相同" "" "$d"

# ─── install.sh --target agents ───
echo ""
echo "Test: install.sh --target agents"
H="$ROOT/home"; mkdir -p "$H/.agents/skills/my-skill"; echo mine > "$H/.agents/skills/my-skill/SKILL.md"
inst() { HOME="$H" bash install.sh "$@" > "$ROOT/inst.out" 2>&1; }
inst --target agents; rc=$?
assert_eq "用户级安装退出 0" "0" "$rc"
assert_eq "装到 ~/.agents/skills 的 pdlc skill 数" "36" "$(find "$H/.agents/skills" -mindepth 1 -maxdepth 1 -name 'pdlc-*' | wc -l | tr -d ' ')"
[[ -f "$H/.agents/skills/my-skill/SKILL.md" ]] && ok "不动目标目录里的其它 skill" || bad "其它 skill 被删了"
[[ -x "$H/.agents/skills/pdlc-status/scripts/pdlc-loop.sh" ]] && ok "安装后脚本仍可执行" || bad "安装后脚本不可执行"
inst --target agents --uninstall; rc=$?
assert_eq "卸载退出 0" "0" "$rc"
assert_eq "卸载后没有 pdlc-* 残留" "0" "$(find "$H/.agents/skills" -mindepth 1 -maxdepth 1 -name 'pdlc-*' | wc -l | tr -d ' ')"
[[ -f "$H/.agents/skills/my-skill/SKILL.md" ]] && ok "卸载不动其它 skill" || bad "卸载删了其它 skill"
P="$ROOT/proj"; mkdir -p "$P"
inst --target agents --project "$P"; rc=$?
assert_eq "--project 安装退出 0" "0" "$rc"
[[ -f "$P/.agents/skills/pdlc-prd/SKILL.md" ]] && ok "--project 装到 <项目>/.agents/skills" || bad "--project 没装到项目目录"
inst --target agents --project "$ROOT/nope"; rc=$?
[[ "$rc" -ne 0 ]] && ok "--project 目录不存在 → 报错" || bad "--project 目录不存在却成功了"
D="$ROOT/cursor-skills"
inst --target agents --dest "$D"; rc=$?
assert_eq "--dest 安装退出 0" "0" "$rc"
[[ -f "$D/pdlc-prd/SKILL.md" ]] && ok "--dest 装到指定目录" || bad "--dest 没装到指定目录"
inst --target agents --dest "$D" --uninstall
assert_eq "--dest 卸载后没有 pdlc-* 残留" "0" "$(find "$D" -mindepth 1 -maxdepth 1 -name 'pdlc-*' | wc -l | tr -d ' ')"
inst --target cursor; rc=$?
[[ "$rc" -ne 0 ]] && ok "未知 --target 报错" || bad "未知 --target 没报错"

echo ""
echo "Final: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
