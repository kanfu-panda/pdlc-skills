#!/usr/bin/env bash
# bin/pdlc-state-lint.sh 回归测试（A-det：确定性脚本，用构造的状态文件测，不烧模型额度）。
#
# 背景：拿一个「半接入」PDLC 的真实项目跑 /pdlc-status、/pdlc-relate impact、/pdlc-retro，
# 三条命令都跑完了，但结论里有错——两个不同的 skill 各自拿状态文件里的 terminal_state
# （状态机契约里根本没有这个字段）当成「已抵达终态」；阶段名 prd / implementation /
# implement 混写，被静默归一化后算进表头数字；done_at 只有日期精度，阶段耗时全算成 0.0h。
# 命令本身没坏，坏在**读侧没有任何契约体检**：输入不合契约时模型只能边猜边算，
# 猜出来的东西还被当成了结论。
#
# 本脚本把体检做成确定性代码——同样的输入永远得到同样的偏差清单。退出码三态：
#   0 = 已体检、全部合契约
#   1 = 已体检、有偏差（仍可继续，但结论必须先披露这些偏差）
#   2 = 无法体检（无状态目录 / 缺 jq）——「查不了」绝不能当成「没问题」
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR" || exit 1

LINT="$SCRIPT_DIR/bin/pdlc-state-lint.sh"
# 脚本在 bin/ 下、会在用户机器上直接执行，必须兼容 macOS 自带的 bash 3.2——
# 有 /bin/bash 就用它跑，PATH 上的 Homebrew bash 5 会放过 3.2 跑不了的写法。
LINT_BASH="bash"
[ -x /bin/bash ] && LINT_BASH="/bin/bash"

pass=0
fail=0

if ! command -v jq >/dev/null 2>&1; then
    echo "⚠️  jq 未安装，跳过 state-lint 测试"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

new_proj() { local d="$TMP/p$RANDOM$RANDOM"; mkdir -p "$d/docs/.pdlc-state"; printf '%s' "$d"; }
put() { printf '%s\n' "$3" > "$1/docs/.pdlc-state/$2"; }   # put <项目> <文件名> <JSON>

OUT=""
RC=0
lint() { OUT="$("$LINT_BASH" "$LINT" "$1" 2>/dev/null)"; RC=$?; }

# has <代码> [文件名子串] —— 输出里是否有该偏差代码（且文件列含该子串）
has() { awk -F'\t' -v c="$1" -v f="${2:-}" '$2==c && index($1,f){hit=1} END{exit !hit}' <<< "$OUT"; }
# has_detail <代码> <文件名子串> <说明子串> —— 同上，且说明列含该子串
has_detail() { awk -F'\t' -v c="$1" -v f="$2" -v d="$3" '$2==c && index($1,f) && index($3,d){hit=1} END{exit !hit}' <<< "$OUT"; }

ok()  { echo "  ✓ $1"; pass=$((pass + 1)); }
bad() { echo "  ✗ $1"; [ -n "${2:-}" ] && printf '    %s\n' "$2"; fail=$((fail + 1)); }
assert_rc()   { if [ "$RC" = "$2" ]; then ok "$1"; else bad "$1" "退出码 ${RC}，期望 $2；输出：$OUT"; fi; }
assert_has()  { if has "$2" "${3:-}"; then ok "$1"; else bad "$1" "未找到偏差代码 $2（${3:-任意文件}）；输出：$OUT"; fi; }
assert_none() { if has "$2" "${3:-}"; then bad "$1" "不该出现 $2；输出：$OUT"; else ok "$1"; fi; }
assert_grep() { if grep -qF -- "$2" <<< "$OUT"; then ok "$1"; else bad "$1" "输出未含「$2」：$OUT"; fi; }

# 合契约的状态机（字段、阶段短名、时间精度、关系块形态都按 state-update.md）
CLEAN_A='{"feature_id":"F20260728-101500","feature_name":"calc-add",
 "created_at":"2026-07-28T10:15:00+08:00","current_stage":"impl","run_mode":"interactive",
 "history":[{"stage":"requirements","done_at":"2026-07-28T10:20:00+08:00","produced":[]},
            {"stage":"impl","done_at":"2026-07-28T11:00:00+08:00","produced":[]}],
 "last_phase_result":{"stage":"impl","ok":true,"advanced_to":"review","checks":{},
   "blocked_reason":null,"at":"2026-07-28T11:00:00+08:00"},
 "relations":{"extends":[],"depends_on":["F20260727-090000"],"supersedes":[],"resolves":[],
   "conflicts_with":[],"relates_to":[]},
 "next_step":"pdlc-review"}'
# 已到终态的（current_stage 以 _done 结尾），也是 A 的 depends_on 目标
CLEAN_B='{"feature_id":"F20260727-090000","feature_name":"calc-base",
 "created_at":"2026-07-27T09:00:00+08:00","current_stage":"feature_done","run_mode":"interactive",
 "history":[{"stage":"review","done_at":"2026-07-27T18:00:00+08:00","produced":[]}],
 "last_phase_result":{"stage":"review","ok":true,"advanced_to":null,"checks":{},
   "blocked_reason":null,"at":"2026-07-27T18:00:00+08:00"},
 "next_step":null}'

echo "Test: 合契约的状态机"
P="$(new_proj)"
put "$P" F20260728-101500.json "$CLEAN_A"
put "$P" F20260727-090000.json "$CLEAN_B"
lint "$P"
assert_rc "全部合契约 → 退出 0" 0
if [ -z "$OUT" ]; then ok "无偏差行"; else bad "无偏差行" "实际：$OUT"; fi

echo "Test: 读侧跳过的非状态文件"
# 与状态栏同一条规则：_ 前缀是索引文件、statusline.json 是配置，都不是功能状态机
put "$P" _relations.json '{"nodes":{},"edges":[],"index":{}}'
put "$P" statusline.json '{"window":5}'
lint "$P"
assert_rc "_relations.json / statusline.json 不参与体检 → 仍退出 0" 0

echo "Test: 半接入形态——每类偏差一份文件，逐条对得上"
P="$(new_proj)"
put "$P" F20260727-090000.json "$CLEAN_B"

# ① terminal_state 写进了状态机实例（它只是 skill frontmatter 的字段）+ 表外字段 title
put "$P" F20260801-01.json '{"feature_id":"F20260801-01","feature_name":"a",
 "created_at":"2026-08-01T09:00:00+08:00","current_stage":"review","history":[],
 "last_phase_result":{"stage":"review","ok":true,"at":"2026-08-01T09:00:00+08:00"},
 "next_step":"pdlc-ship","terminal_state":"review_done","title":"标题"}'
# ② 缺 created_at、缺 last_phase_result
put "$P" F20260801-02.json '{"feature_id":"F20260801-02","feature_name":"b",
 "current_stage":"review","history":[],"next_step":"pdlc-ship"}'
# ③ 阶段名用了别名（prd / implementation / implement）与完全未知的名字
put "$P" F20260801-03.json '{"feature_id":"F20260801-03","feature_name":"c",
 "created_at":"2026-08-01T09:00:00+08:00","current_stage":"review",
 "history":[{"stage":"prd","done_at":"2026-08-01T09:10:00+08:00"},
            {"stage":"implementation","done_at":"2026-08-01T10:00:00+08:00"},
            {"stage":"implement","done_at":"2026-08-01T11:00:00+08:00"},
            {"stage":"polish","done_at":"2026-08-01T12:00:00+08:00"}],
 "last_phase_result":{"stage":"review","ok":true,"at":"2026-08-01T12:00:00+08:00"},
 "next_step":"pdlc-ship"}'
# ④ next_step 带散文后缀、done_at 只有日期
put "$P" F20260801-04.json '{"feature_id":"F20260801-04","feature_name":"d",
 "created_at":"2026-08-01T09:00:00+08:00","current_stage":"review",
 "history":[{"stage":"review","done_at":"2026-08-01"}],
 "last_phase_result":{"stage":"review","ok":true,"at":"2026-08-01T09:00:00+08:00"},
 "next_step":"pdlc-ship（等评审通过）"}'
# ⑤ relations 是数组而不是六键对象
put "$P" F20260801-05.json '{"feature_id":"F20260801-05","feature_name":"e",
 "created_at":"2026-08-01T09:00:00+08:00","current_stage":"review","history":[],
 "last_phase_result":{"stage":"review","ok":true,"at":"2026-08-01T09:00:00+08:00"},
 "relations":[{"type":"blocks","target":"导出模块"}],"next_step":"pdlc-ship"}'
# ⑥ relations 是对象，但键在六类之外、目标不是 feature ID、目标 ID 无对应状态文件
put "$P" F20260801-06.json '{"feature_id":"F20260801-06","feature_name":"f",
 "created_at":"2026-08-01T09:00:00+08:00","current_stage":"review","history":[],
 "last_phase_result":{"stage":"review","ok":true,"at":"2026-08-01T09:00:00+08:00"},
 "relations":{"extends":["F20260727-090000"],"blocks":["F20260727-090000"],
   "depends_on":["F0-infra","F20269999-000000"]},
 "next_step":"pdlc-ship"}'
# ⑦ 走的是修复流程（history 有 fix / bugfix 阶段），ID 却是 F 开头
put "$P" F20260801-07.json '{"feature_id":"F20260801-07","feature_name":"g",
 "created_at":"2026-08-01T09:00:00+08:00","current_stage":"review",
 "history":[{"stage":"bugfix","done_at":"2026-08-01T09:30:00+08:00"}],
 "last_phase_result":{"stage":"review","ok":true,"at":"2026-08-01T09:30:00+08:00"},
 "next_step":"pdlc-ship"}'
# ⑧ JSON 本身损坏
printf '{"feature_id": "F20260801-08", ' > "$P/docs/.pdlc-state/F20260801-08.json"
# ⑨ current_stage 既不是短名、也不以 _done 结尾
put "$P" F20260801-09.json '{"feature_id":"F20260801-09","feature_name":"i",
 "created_at":"2026-08-01T09:00:00+08:00","current_stage":"polishing","history":[],
 "last_phase_result":{"stage":"review","ok":true,"at":"2026-08-01T09:00:00+08:00"},
 "next_step":"pdlc-ship"}'

snap() { (cd "$1" && find . -type f -exec shasum {} + | sort); }
before="$(snap "$P")"
lint "$P"
after="$(snap "$P")"
assert_rc "有偏差 → 退出 1（可继续，但须披露）" 1
assert_has "terminal_state 写进实例 → terminal_state-in-instance" terminal_state-in-instance F20260801-01
assert_has "表外顶层字段 title → non-contract-field"               non-contract-field F20260801-01
if has_detail non-contract-field F20260801-01 terminal_state; then
    bad "terminal_state 不重复报成普通表外字段" "$OUT"
else
    ok "terminal_state 不重复报成普通表外字段"
fi
assert_has "缺 created_at → missing-field"                          missing-field F20260801-02
assert_grep "missing-field 的说明点名字段"                          "created_at"
assert_has "缺 last_phase_result → missing-last_phase_result"       missing-last_phase_result F20260801-02
assert_has "阶段别名 → stage-alias"                                 stage-alias F20260801-03
assert_grep "别名说明给出归一化目标 prd→requirements"               "prd→requirements"
assert_grep "别名说明给出归一化目标 implementation→impl"            "implementation→impl"
assert_grep "别名说明给出归一化目标 implement→impl"                 "implement→impl"
assert_has "未知阶段名 → stage-unknown"                             stage-unknown F20260801-03
assert_has "next_step 带散文 → next_step-not-command"               next_step-not-command F20260801-04
assert_has "done_at 只有日期 → timestamp-no-time"                   timestamp-no-time F20260801-04
assert_has "relations 为数组 → relations-not-object"                relations-not-object F20260801-05
assert_has "relations 表外类型 blocks → relations-unknown-type"     relations-unknown-type F20260801-06
assert_has "relations 目标不是 ID → relations-target-not-id"        relations-target-not-id F20260801-06
assert_has "relations 目标 ID 无状态文件 → relations-dangling"      relations-dangling F20260801-06
if has_detail relations-dangling F20260801-06 F20260727-090000; then
    bad "指向存在文件的 ID 不报悬空" "$OUT"
else
    ok "指向存在文件的 ID 不报悬空"
fi
assert_has "修复流程却是 F 开头 → id-prefix-mismatch"               id-prefix-mismatch F20260801-07
assert_has "JSON 损坏 → json-invalid"                               json-invalid F20260801-08
assert_has "current_stage 非法 → current_stage-unknown"            current_stage-unknown F20260801-09
assert_none "以 _done 结尾的 current_stage 不误报"                  current_stage-unknown F20260727-090000
# 体检只读：它会在用户项目里跑，不许动任何文件
if [ "$before" = "$after" ]; then ok "体检前后项目文件逐字节不变（只读）"; else bad "体检改动了项目文件"; fi
assert_none "合契约的那份不被误报"                                  missing-field F20260727-090000

# 输出格式是给 skill 与后续工具消费的：每行恰好三列（文件 / 代码 / 说明）
if awk -F'\t' 'NF!=3{b=1} END{exit b}' <<< "$OUT"; then ok "每行恰好三列（文件 / 代码 / 说明）"; else bad "每行恰好三列" "$OUT"; fi

echo "Test: 仓库根另有一个 .pdlc-state/"
P="$(new_proj)"
put "$P" F20260728-101500.json "$CLEAN_A"
put "$P" F20260727-090000.json "$CLEAN_B"
mkdir -p "$P/.pdlc-state" && printf '# 轻量登记\n' > "$P/.pdlc-state/state.md"
lint "$P"
assert_rc "两个状态目录并存 → 退出 1" 1
assert_has "报 second-state-dir" second-state-dir

echo "Test: 无法体检的情形（三态的第三态）"
P="$TMP/no-state-$RANDOM"; mkdir -p "$P"
lint "$P"
assert_rc "无 docs/.pdlc-state/ → 退出 2" 2

P="$(new_proj)"
lint "$P"
assert_rc "状态目录为空 → 退出 0（体检了，没东西不合规）" 0

# jq 不在 /usr/bin:/bin 里时才能构造「缺 jq」；否则跳过而不是假装测过
if ! PATH=/usr/bin:/bin command -v jq >/dev/null 2>&1; then
    P="$(new_proj)"; put "$P" F20260728-101500.json "$CLEAN_A"
    OUT="$(PATH=/usr/bin:/bin "$LINT_BASH" "$LINT" "$P" 2>/dev/null)"; RC=$?
    assert_rc "缺 jq → 退出 2，而不是 0" 2
else
    echo "  - 跳过「缺 jq」用例：本机 /usr/bin 下就有 jq，构造不出缺失环境"
fi

echo ""
echo "Final: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
