#!/usr/bin/env bash
# bin/pdlc-checks.sh 回归测试（A-det：确定性脚本，用构造的 test-commands.yml 测，不烧模型额度）。
#
# 背景：checks 的键名、布尔类型、退出码三态原先全靠模型读正文自己写。真机上同一 fixture、
# 同一模型，轮与轮之间就换一种错法——键名照抄 yml 的 unit / lint、值写成「4 passed, 1 failed」、
# 127 折成 false。这些都是确定性的事，交给脚本就不会再漂：模型只负责把脚本输出原样抄进状态机。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR" || exit 1

CHECKS="$SCRIPT_DIR/bin/pdlc-checks.sh"
# 与 state-lint-check 同一条：脚本会在用户机器上直接执行，必须兼容 macOS 自带的 bash 3.2
RUN_BASH="bash"
[ -x /bin/bash ] && RUN_BASH="/bin/bash"

pass=0
fail=0
ok()  { echo "  ✓ $1"; pass=$((pass + 1)); }
bad() { echo "  ✗ $1"; [ -n "${2:-}" ] && printf '    %s\n' "$2"; fail=$((fail + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# new_proj <yml 内容> —— 建一个带 test-commands.yml 的临时项目，打印路径
new_proj() {
    local d="$TMP/p$RANDOM$RANDOM"
    mkdir -p "$d/docs/00_standards" "$d/scripts"
    printf '%s\n' "$1" > "$d/docs/00_standards/test-commands.yml"
    printf '%s' "$d"
}

OUT=""
ERR=""
RC=0
run() { OUT="$("$RUN_BASH" "$CHECKS" "$@" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"; }
assert_out() { if [ "$OUT" = "$2" ]; then ok "$1"; else bad "$1" "输出「${OUT}」，期望「${2}」；stderr：${ERR}"; fi; }
assert_rc()  { if [ "$RC" = "$2" ]; then ok "$1"; else bad "$1" "退出码 ${RC}，期望 $2；stderr：${ERR}"; fi; }
assert_err() { if grep -qF -- "$2" <<< "${ERR}"; then ok "$1"; else bad "$1" "stderr 未含「${2}」：${ERR}"; fi; }

echo "Test: 三态映射"
P="$(new_proj 'unit:     "exit 1"
coverage: "true"            # 行尾注释不算命令
lint:     "./scripts/missing-lint.sh"
e2e:      ""')"
run "$P"
assert_rc  "能跑就退出 0（结果好坏不影响退出码）" 0
assert_out "0→true、非 0→false、127 与空串→null；键名是状态机的不是 yml 的" \
  '{"tests_pass":false,"coverage_pass":true,"lint_clean":null,"e2e_pass":null}'
assert_err "跑不了的项提示 yml 疑似过期" "疑似过期"
assert_err "逐条回显退出码" "exit 127"

echo "Test: --only 只跑本阶段要的项"
run --only unit,lint "$P"
assert_out "只输出请求的键，顺序固定" '{"tests_pass":false,"lint_clean":null}'
run --only nope "$P"
assert_rc "未知项名是用法错误" 2

echo "Test: 引号、无引号与模板占位"
P2="$(new_proj "unit: 'exit 0'
lint: exit 3   # 无引号也认
coverage: \"<覆盖率命令>\"")"
run "$P2"
assert_out "单引号 / 无引号都能解析；没填的模板占位按跑不了处理；缺的项也是 null" \
  '{"tests_pass":true,"coverage_pass":null,"lint_clean":false,"e2e_pass":null}'

echo "Test: 命令在项目根执行"
P3="$(new_proj 'unit: "test -f marker"')"
: > "$P3/marker"
run --only unit "$P3"
assert_out "工作目录是项目根" '{"tests_pass":true}'

echo "Test: --red（tdd 红灯，方向与 tests_pass 相反）"
P4="$(new_proj 'unit: "exit 1"')"
run --red "$P4"
assert_out "测试失败 = 红灯成立" '{"red_verified":true}'
P5="$(new_proj 'unit: "exit 0"')"
run --red "$P5"
assert_out "意外全绿 = 红灯不成立" '{"red_verified":false}'
assert_err "意外全绿要提示阻塞" "意外全绿"
P6="$(new_proj 'unit: "no-such-command-xyz"')"
run --red "$P6"
assert_out "命令跑不了不算红灯" '{"red_verified":null}'

echo "Test: 查不了就别假装查了"
run "$TMP/nowhere"
assert_rc "没有 test-commands.yml 退出 2" 2
assert_out "退出 2 时不输出 JSON（不给消费方一个看似有效的空结果）" ""
run --bogus "$P"
assert_rc "未知参数退出 2" 2

echo ""
echo "Final: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
