#!/usr/bin/env bash
# bin/pdlc-advance.sh（阶段收尾推进状态机的唯一写入口）与 bin/pdlc-guard.sh（可选的 Claude Code hooks）的回归测试。
#
# 守的是「状态推进不再靠模型自觉」这件事：检查由脚本自己跑、红了就不推进、tdd 写的测试被改了就不推进，
# 以及对既有项目的兼容——没有 test-commands.yml、旧格式状态文件、没有测试指纹的旧功能，都不能因为
# 换了写入口就被卡住。hooks 默认关闭，没有开关文件时必须一律放行。
# 全部用桩项目跑，不烧模型额度；脚本走 macOS 自带的 /bin/bash（3.2）时也要能过。
# shellcheck disable=SC2015,SC2016  # SC2015：ok / bad 恒返回 0，`条件 && ok || bad` 只在条件不成立时走 bad。SC2016：桩脚本里的 $(…) 是要写进文件的字面量
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR" || exit 1
ADV="$SCRIPT_DIR/bin/pdlc-advance.sh"
GUARD="$SCRIPT_DIR/bin/pdlc-guard.sh"
BASH_BIN="bash"; [ -x /bin/bash ] && BASH_BIN="/bin/bash"

pass=0
fail=0
ok()  { echo "  ✓ $1"; pass=$((pass + 1)); }
bad() { echo "  ✗ $1${2:+（$2）}"; fail=$((fail + 1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "期望「$2」，实际「$3」"; fi; }

command -v jq >/dev/null 2>&1 || { echo "⚠️  jq 未安装，无法运行本测试——这不算通过" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FID="F20261012-090000"

# 桩项目：unit / lint 的退出码由 .unit_rc / .lint_rc 控制；coverage、e2e 留空（→ null）
mkproj() {
    local d="$TMP/p-$RANDOM"
    mkdir -p "$d/docs/00_standards" "$d/docs/.pdlc-state" "$d/scripts" "$d/tests" "$d/src"
    printf 'unit: "bash scripts/unit.sh"\ncoverage: ""\nlint: "bash scripts/lint.sh"\ne2e: ""\n' > "$d/docs/00_standards/test-commands.yml"
    printf 'exit "$(cat .unit_rc 2>/dev/null || echo 0)"\n' > "$d/scripts/unit.sh"
    printf 'exit "$(cat .lint_rc 2>/dev/null || echo 0)"\n' > "$d/scripts/lint.sh"
    echo 'echo test' > "$d/tests/test_a.sh"
    printf '%s' "$d"
}
adv() { local d="$1"; shift; ( cd "$d" && "$BASH_BIN" "$ADV" "$@" . ) 2>"$TMP/adv.err"; }
st()  { jq -r "$2 | tostring" "$1/docs/.pdlc-state/$FID.json"; }

echo "Test: 新建与 requirements（不跑检查）"
P="$(mkproj)"
adv "$P" "$FID" --stage requirements --next pdlc-design >/dev/null; rc=$?
eq "缺 --name 新建 → 退出 2" 2 "$rc"
[ -e "$P/docs/.pdlc-state/$FID.json" ] && bad "缺 --name 却建了文件" || ok "缺 --name 不建文件"
adv "$P" "$FID" --stage requirements --next pdlc-design --name calc-x --produced docs/01_requirements/prd/a.md >/dev/null; rc=$?
eq "新建 requirements → 退出 0" 0 "$rc"
eq "current_stage=requirements" requirements "$(st "$P" .current_stage)"
eq "next_step=pdlc-design" pdlc-design "$(st "$P" .next_step)"
eq "advanced_to=design" design "$(st "$P" .last_phase_result.advanced_to)"
eq "requirements 不跑检查 → checks={}" "{}" "$(st "$P" '.last_phase_result.checks | tojson')"
eq "新建时补齐六类关系" 6 "$(st "$P" '.relations | keys | length')"
eq "feature_name 来自 --name" calc-x "$(st "$P" .feature_name)"
st "$P" .created_at | grep -qE 'T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$' \
    && ok "时间戳是带时刻与时区的 ISO 8601" || bad "时间戳格式不对" "$(st "$P" .created_at)"

echo "Test: tdd 红灯验证与测试指纹"
echo 0 > "$P/.unit_rc"
adv "$P" "$FID" --stage tdd --next pdlc-implement --produced tests/test_a.sh >/dev/null; rc=$?
eq "新测试意外全绿 → 退出 3（不推进）" 3 "$rc"
eq "全绿时 current_stage 仍是 requirements" requirements "$(st "$P" .current_stage)"
eq "全绿时 next_step 不变" pdlc-design "$(st "$P" .next_step)"
st "$P" .last_phase_result.blocked_reason | grep -q '红灯未验证' && ok "blocked_reason 写明红灯未验证" || bad "blocked_reason 没写原因"
echo 1 > "$P/.unit_rc"
adv "$P" "$FID" --stage tdd --next pdlc-implement --produced tests/test_a.sh,docs/04_testing/unit-tests/plan.md >/dev/null; rc=$?
eq "unit 失败 = 红灯成立 → 退出 0" 0 "$rc"
eq "red_verified=true" true "$(st "$P" .last_phase_result.checks.red_verified)"
eq "指纹只记非 docs/ 的测试文件" '["tests/test_a.sh"]' "$(st "$P" '.history[-1].tests_fingerprint | keys | tojson')"

echo "Test: impl——检查红了不推进，测试被改不推进"
adv "$P" "$FID" --stage impl --next pdlc-review >/dev/null; rc=$?
eq "unit 仍红 → 退出 3" 3 "$rc"
eq "红时 current_stage 仍是 tdd" tdd "$(st "$P" .current_stage)"
eq "红时 advanced_to=null" null "$(st "$P" .last_phase_result.advanced_to)"
st "$P" .last_phase_result.blocked_reason | grep -q 'tests_pass' && ok "blocked_reason 点名 tests_pass" || bad "blocked_reason 没点名失败的检查"
echo 0 > "$P/.unit_rc"
echo 'echo test changed' > "$P/tests/test_a.sh"
adv "$P" "$FID" --stage impl --next pdlc-review >/dev/null; rc=$?
eq "改了 tdd 写的测试 → 退出 3" 3 "$rc"
st "$P" .last_phase_result.blocked_reason | grep -q 'tests/test_a.sh' && ok "blocked_reason 点名被改的测试文件" || bad "没点名被改的测试"
adv "$P" "$FID" --stage impl --next pdlc-review --autonomous --tests-changed "断言和设计矛盾，改成设计的值" >/dev/null; rc=$?
eq "--autonomous 下带 --tests-changed 也不推进 → 退出 3（模型不能自己批准改测试）" 3 "$rc"
eq "自主模式改测试时 current_stage 仍是 tdd" tdd "$(st "$P" .current_stage)"
st "$P" .last_phase_result.blocked_reason | grep -q '断言和设计矛盾' && ok "blocked_reason 带上给出的理由，交人判断" || bad "blocked_reason 没带理由" "$(st "$P" .last_phase_result.blocked_reason)"
st "$P" .last_phase_result.blocked_reason | grep -q 'tests/test_a.sh' && ok "blocked_reason 点名被改的测试文件（自主模式）" || bad "自主模式没点名被改的测试"
adv "$P" "$FID" --stage impl --next pdlc-review --tests-changed "断言写反了，已和设计核对" >/dev/null; rc=$?
eq "交互模式（人已同意）带 --tests-changed → 退出 0" 0 "$rc"
st "$P" '.history[-1].auto_decisions[0].point' | grep -q '改动 tdd 写的测试' && ok "改测试的理由记进 auto_decisions" || bad "理由没记进 auto_decisions"
eq "null（coverage 未配置）不拦" null "$(st "$P" .last_phase_result.checks.coverage_pass)"
eq "lint 通过" true "$(st "$P" .last_phase_result.checks.lint_clean)"
eq "认可改动后以改后内容作新基准" "$(shasum -a 256 "$P/tests/test_a.sh" 2>/dev/null | awk '{print $1}' || sha256sum "$P/tests/test_a.sh" | awk '{print $1}')" \
    "$(st "$P" '.history[-1].tests_fingerprint["tests/test_a.sh"]')"

echo "Test: review——主动 block 与 lint 红"
adv "$P" "$FID" --stage review --next pdlc-ship --blocked "评审存在阻塞级待人工项" >/dev/null; rc=$?
eq "--blocked → 退出 3" 3 "$rc"
eq "--blocked 照跑检查、如实记录" true "$(st "$P" .last_phase_result.checks.tests_pass)"
eq "--blocked 原因原样写入" "评审存在阻塞级待人工项" "$(st "$P" .last_phase_result.blocked_reason)"
echo 1 > "$P/.unit_rc"
adv "$P" "$FID" --stage review --next pdlc-ship --blocked "测试自相矛盾，交还人类" >/dev/null
eq "--blocked 且 unit 红 → tests_pass=false 照样记下" false "$(st "$P" .last_phase_result.checks.tests_pass)"
eq "--blocked 时 blocked_reason 用调用方给的原因" "测试自相矛盾，交还人类" "$(st "$P" .last_phase_result.blocked_reason)"
echo 0 > "$P/.unit_rc"
echo 1 > "$P/.lint_rc"
adv "$P" "$FID" --stage review --next pdlc-ship >/dev/null; rc=$?
eq "lint 红 → 退出 3" 3 "$rc"
echo 0 > "$P/.lint_rc"
adv "$P" "$FID" --stage review --next pdlc-ship --autonomous --decision "非阻塞人工项=记录在案" --self-audit 9,0,1 >/dev/null; rc=$?
eq "全绿 → 退出 0" 0 "$rc"
eq "review 跑四项检查（e2e 为 null）" '["coverage_pass","e2e_pass","lint_clean","tests_pass"]' "$(st "$P" '.last_phase_result.checks | keys | tojson')"
eq "run_mode=autonomous" autonomous "$(st "$P" .run_mode)"
eq "self_audit 记进 history" 1 "$(st "$P" .history[-1].self_audit.manual)"
eq "评审通过不写 _done" review "$(st "$P" .current_stage)"

echo "Test: ship / deploy 的 --done"
adv "$P" "$FID" --stage review --next pdlc-ship --done >/dev/null; rc=$?
eq "--done 用在 review 上 → 退出 2" 2 "$rc"
adv "$P" "$FID" --stage ship --next pdlc-deploy --done >/dev/null; rc=$?
eq "ship --done → 退出 0" 0 "$rc"
eq "current_stage=ship_done" ship_done "$(st "$P" .current_stage)"
eq "advanced_to=deploy" deploy "$(st "$P" .last_phase_result.advanced_to)"
adv "$P" "$FID" --stage deploy --next null --done >/dev/null
eq "deploy --done → deploy_done" deploy_done "$(st "$P" .current_stage)"
eq "流程结束 next_step=null" null "$(st "$P" .next_step)"
eq "流程结束 advanced_to=null" null "$(st "$P" .last_phase_result.advanced_to)"
lint_out="$("$BASH_BIN" bin/pdlc-state-lint.sh "$P" 2>&1)"; lrc=$?
eq "一路写下来状态体检 0 偏差" 0 "$lrc"
[ "$lrc" -eq 0 ] || echo "$lint_out" | head -5

echo "Test: 参数守卫"
adv "$P" "$FID" --stage implement --next pdlc-review >/dev/null; eq "阶段写成命令名 implement → 退出 2" 2 "$?"
adv "$P" "$FID" --stage impl --next "pdlc-review（等评审）" >/dev/null; eq "--next 带说明文字 → 退出 2" 2 "$?"
adv "$P" "$FID" --stage impl >/dev/null; eq "缺 --next → 退出 2" 2 "$?"
adv "$P" "F2026-1" --stage impl --next pdlc-review >/dev/null; eq "功能ID 不合法 → 退出 2" 2 "$?"
adv "$P" "$FID" --stage impl --next pdlc-quality >/dev/null; eq "--next 不在映射表 → 退出 2" 2 "$?"
echo '{broken' > "$P/docs/.pdlc-state/F20261012-090001.json"
adv "$P" F20261012-090001 --stage impl --next pdlc-review >/dev/null; eq "状态文件损坏 → 退出 2" 2 "$?"
eq "损坏的文件原样不动" '{broken' "$(cat "$P/docs/.pdlc-state/F20261012-090001.json")"

echo "Test: 既有项目兼容"
Q="$(mkproj)"; rm "$Q/docs/00_standards/test-commands.yml"
adv "$Q" "$FID" --stage impl --next pdlc-review --name old-proj >/dev/null; rc=$?
eq "没有 test-commands.yml → 照常推进（退出 0）" 0 "$rc"
eq "没有 test-commands.yml → checks={}" "{}" "$(st "$Q" '.last_phase_result.checks | tojson')"
R="$(mkproj)"
cat > "$R/docs/.pdlc-state/F20260501-01.json" <<'EOF'
{ "feature_id": "F20260501-01", "feature_name": "legacy", "created_at": "2026-05-01",
  "current_stage": "tdd", "history": [ { "stage": "tdd", "done_at": "2026-05-01" } ],
  "next_step": "pdlc-implement", "custom_note": "保留我" }
EOF
echo 'echo changed' > "$R/tests/test_a.sh"
( cd "$R" && "$BASH_BIN" "$ADV" F20260501-01 --stage impl --next pdlc-review . ) >/dev/null 2>&1; rc=$?
eq "旧格式状态文件（-NN ID、无 last_phase_result、无指纹）照常推进" 0 "$rc"
eq "旧文件的其它字段原样保留" "保留我" "$(jq -r .custom_note "$R/docs/.pdlc-state/F20260501-01.json")"
eq "旧 history 保留、追加本阶段" "tdd impl" "$(jq -r '[.history[].stage] | join(" ")' "$R/docs/.pdlc-state/F20260501-01.json")"
eq "没有指纹的旧功能改了测试也不拦" impl "$(jq -r .current_stage "$R/docs/.pdlc-state/F20260501-01.json")"

echo "Test: 映射表与 state-update.md 一致"
map_doc="$(awk '/<!-- stage-map:start -->/{f=1;next} /<!-- stage-map:end -->/{f=0} f' references/templates/prompts/state-update.md \
    | awk -F'|' 'NF>=3 { c=$2; s=$3; gsub(/[ `]/,"",c); gsub(/[ `]/,"",s); if (c ~ /^pdlc-/) print c"="s }' | sort)"
map_sh="$(grep -oE 'pdlc-[a-z]+\) echo [a-z]+' bin/pdlc-advance.sh | sed -E 's/\) echo /=/' | sort)"
eq "pdlc-advance.sh 的映射与 stage-map 表逐行相同" "$map_doc" "$map_sh"
legal_lint="$(sed -n 's/^LEGAL_STAGES="\(.*\)"/\1/p' bin/pdlc-state-lint.sh)"
legal_adv="$(sed -n 's/^LEGAL_STAGES="\(.*\)"/\1/p' bin/pdlc-advance.sh)"
eq "合法阶段与 pdlc-state-lint.sh 一致" "$legal_lint" "$legal_adv"

# ─── hooks（Claude Code 专属，默认关闭）───
echo "Test: pdlc-guard.sh——没有开关文件时一律放行"
H="$(mkproj)"
pre() { # pre <项目> <被写的文件绝对路径> → stdout
    jq -n --arg p "$2" --arg c "$1" '{hook_event_name: "PreToolUse", tool_name: "Write", cwd: $c, tool_input: {file_path: $p, content: "x"}}' \
        | CLAUDE_PROJECT_DIR="$1" "$BASH_BIN" "$GUARD" pre
}
out="$(pre "$H" "$H/docs/.pdlc-state/$FID.json")"; rc=$?
eq "未开启：写状态文件 → 退出 0" 0 "$rc"
eq "未开启：不输出任何决定" "" "$out"

echo "Test: pdlc-guard.sh pre——开启后拦直接写状态文件"
printf '# pdlc hooks\nstate_write_guard: on\nlint_on_stop: on\n' > "$H/docs/00_standards/pdlc-hooks.yml"
out="$(pre "$H" "$H/docs/.pdlc-state/$FID.json")"
eq "写 F*.json → deny" deny "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<< "$out")"
jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<< "$out" | grep -q 'pdlc-advance.sh' \
    && ok "拒绝理由指向 scripts/pdlc-advance.sh" || bad "拒绝理由没说该怎么写"
out="$(pre "$H" "$H/docs/.pdlc-state/B20261012-090000.json")"
eq "写 B*.json → deny" deny "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<< "$out")"
eq "写 _relations.json → 放行" "" "$(pre "$H" "$H/docs/.pdlc-state/_relations.json")"
eq "写 statusline.json → 放行" "" "$(pre "$H" "$H/docs/.pdlc-state/statusline.json")"
eq "写源码 → 放行" "" "$(pre "$H" "$H/src/a.sh")"
printf 'state_write_guard: off\nlint_on_stop: on\n' > "$H/docs/00_standards/pdlc-hooks.yml"
eq "state_write_guard: off → 放行" "" "$(pre "$H" "$H/docs/.pdlc-state/$FID.json")"

echo "Test: pdlc-guard.sh stop——只看本次有改动的状态文件"
stop() { jq -n --arg c "$1" --argjson a "$2" '{hook_event_name: "Stop", cwd: $c, stop_hook_active: $a}' \
    | CLAUDE_PROJECT_DIR="$1" "$BASH_BIN" "$GUARD" stop; }
G="$(mkproj)"
printf 'lint_on_stop: on\n' > "$G/docs/00_standards/pdlc-hooks.yml"
( cd "$G" && git init -q && git add -A && git -c user.name=t -c user.email=t@example.invalid commit -qm init ) >/dev/null 2>&1
eq "没有改动的状态文件 → 放行" "" "$(stop "$G" false)"
printf '{"feature_id":"%s","current_stage":"impl","history":[],"next_step":"pdlc-review（等评审）","created_at":"2026-10-12"}\n' "$FID" > "$G/docs/.pdlc-state/$FID.json"
out="$(stop "$G" false)"
eq "改动的状态文件有偏差 → block" block "$(jq -r '.decision // empty' <<< "$out")"
jq -r '.reason // empty' <<< "$out" | grep -q 'next_step-not-command' && ok "block 理由里有体检结果" || bad "block 理由没带体检结果"
eq "stop_hook_active=true → 不再拦（防死循环）" "" "$(stop "$G" true)"
rm -f "$G/docs/.pdlc-state/$FID.json"
( cd "$G" && "$BASH_BIN" "$ADV" "$FID" --stage impl --next pdlc-review --name g . ) >/dev/null 2>&1
eq "经 pdlc-advance.sh 写的状态文件 → 放行" "" "$(stop "$G" false)"
printf 'lint_on_stop: off\n' > "$G/docs/00_standards/pdlc-hooks.yml"
echo '{bad' > "$G/docs/.pdlc-state/F20261012-090002.json"
eq "lint_on_stop: off → 放行" "" "$(stop "$G" false)"
M="$TMP/mono-$RANDOM"; mkdir -p "$M"; ( cd "$M" && git init -q ) >/dev/null 2>&1
SUB="$(mkproj)"; mv "$SUB" "$M/app"; SUB="$M/app"; printf 'lint_on_stop: on\n' > "$SUB/docs/00_standards/pdlc-hooks.yml"
printf '{"feature_id":"%s","current_stage":"impl","history":[],"next_step":"x y","created_at":"2026-10-12"}\n' "$FID" > "$SUB/docs/.pdlc-state/$FID.json"
eq "项目在仓库子目录里也认得出改动的状态文件 → block" block "$(stop "$SUB" false | jq -r '.decision // empty')"
N="$(mkproj)"; printf 'lint_on_stop: on\n' > "$N/docs/00_standards/pdlc-hooks.yml"
echo '{bad' > "$N/docs/.pdlc-state/$FID.json"
eq "不是 git 仓库 → 放行（判断不了哪些是本次改动）" "" "$(stop "$N" false)"

echo "Test: hooks.json 接线"
eq "hooks/hooks.json 是合法 JSON" 0 "$(jq empty hooks/hooks.json >/dev/null 2>&1; echo $?)"
eq "PreToolUse 匹配 Write|Edit" "Write|Edit" "$(jq -r '.hooks.PreToolUse[0].matcher' hooks/hooks.json)"
jq -r '[.. | .command? // empty] | join(" ")' hooks/hooks.json | grep -q 'CLAUDE_PLUGIN_ROOT}/bin/pdlc-guard.sh' \
    && ok "hook 命令走 \${CLAUDE_PLUGIN_ROOT}/bin/pdlc-guard.sh" || bad "hook 命令路径不对"
[ -x "$GUARD" ] && ok "pdlc-guard.sh 可执行" || bad "pdlc-guard.sh 不可执行"

echo ""
echo "Final: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
