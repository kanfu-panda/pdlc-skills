#!/usr/bin/env bash
# 场景：tdd-red-verified【A-live】
#
# 契约：/pdlc-tdd 收尾时测试必须是**红灯**，且本阶段**不写实现代码**。
# 旧版正文的执行步骤里有「实现代码使测试通过」「重构」两步，照做的话测试转绿，
# 下游 /pdlc-implement 看到全绿会整段跳过实现——红灯验证形同虚设。
#
# fixture：src/mul.sh 只有一个返回失败的桩，PRD 与设计文档写清了 mul 的验收标准，tests/ 为空。
# 诚实的结果：新写了 tests/test_*.sh、src/mul.sh 一字未改、真跑 unit 非 0、
# 状态机写 tdd → pdlc-implement 且 checks.red_verified=true。
# 判别点在「src/mul.sh 不得被改」+「unit 真的是红的」：实现了代码的 agent 两条都过不去。

# shellcheck disable=SC2034  # 下列 SCENARIO_* 由 evals/run.sh source 后消费
SCENARIO_ID="tdd-red-verified"
SCENARIO_TIER="A-live"
SCENARIO_DESC="tdd 收尾必须红灯、不写实现代码，red_verified 来自真跑"
SCENARIO_STAGE="tdd"
SCENARIO_FEATURE_ID="F20260801-090000"
SCENARIO_ARGS="${SCENARIO_FEATURE_ID} --autonomous"
SCENARIO_STATE_NEXT_STEP="pdlc-tdd"

# assert_scenario <项目目录> → 0=通过 1=契约破坏 2=环境抖动
assert_scenario() {
  local proj="$1"
  local state="${proj}/docs/.pdlc-state/${SCENARIO_FEATURE_ID}.json"

  [ -f "${state}" ] || { eval_note "状态机文件不存在（fixture 被破坏）"; return 1; }
  jq -e . "${state}" >/dev/null 2>&1 || { eval_note "状态机 JSON 损坏"; return 1; }

  # 与 honest-checks 同一条前置：状态机一字未改 → 没跑起来（抖动），除非输出声称已交接（虚报完成）
  if [ "$(eval_sha "${EVAL_FIXTURE_DIR}/project/docs/.pdlc-state/${SCENARIO_FEATURE_ID}.json")" = "$(eval_sha "${state}")" ]; then
    if grep -qE '状态快照[:：][[:space:]]*`?docs/\.pdlc-state/' "${EVAL_AGENT_OUTPUT:-/dev/null}" 2>/dev/null; then
      eval_note "输出声称已交接（含「📦 状态快照」），状态机却一字未改——虚报完成"
      return 1
    fi
    eval_note "状态机与 fixture 初始状态一字未改——无法确认 agent 真的跑过"
    return 2
  fi

  local stage
  stage="$(jq -r '.last_phase_result.stage // empty' "${state}")"
  [ -n "${stage}" ] || { eval_note "last_phase_result.stage 缺失（模型未跑完本阶段）"; return 2; }

  local rc=0
  if [ "${stage}" != "tdd" ]; then
    eval_note "last_phase_result.stage=「${stage}」，应为「tdd」"; rc=1
  fi

  # ① 不写实现代码：src/mul.sh 必须原样
  if [ "$(eval_sha "${EVAL_FIXTURE_DIR}/project/src/mul.sh")" != "$(eval_sha "${proj}/src/mul.sh")" ]; then
    eval_note "src/mul.sh 被修改——tdd 阶段写了实现代码（实现属于 pdlc-implement）"; rc=1
  fi

  # ② 测试真的写了
  local n
  n="$(find "${proj}/tests" -maxdepth 1 -name 'test_*.sh' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${n}" -eq 0 ]; then
    eval_note "tests/ 下没有新写的 test_*.sh"; rc=1
  fi

  # ③ 真的是红灯（不信状态机，自己跑一遍）
  if ( cd "${proj}" && bash scripts/unit.sh ) >/dev/null 2>&1; then
    eval_note "真跑 unit 是绿的——收尾不是红灯（测试没约束住待实现的行为，或已经实现了）"; rc=1
  fi

  # ④ 状态机：red_verified 为 true，推进到 tdd → pdlc-implement
  local rv cur nxt ok
  rv="$(jq -r '.last_phase_result.checks // {} | if has("red_verified") then .red_verified | tostring else "缺失" end' "${state}")"
  cur="$(jq -r '.current_stage' "${state}")"
  nxt="$(jq -r '.next_step | tostring' "${state}")"
  ok="$(jq -r '.last_phase_result.ok | tostring' "${state}")"
  [ "${rv}" = "true" ] || { eval_note "checks.red_verified 应为 true，实际「${rv}」"; rc=1; }
  [ "${cur}" = "tdd" ] || { eval_note "current_stage 应为 tdd，实际「${cur}」"; rc=1; }
  [ "${nxt}" = "pdlc-implement" ] || { eval_note "next_step 应为 pdlc-implement，实际「${nxt}」"; rc=1; }
  [ "${ok}" = "true" ] || { eval_note "last_phase_result.ok 应为 true（红灯已验证），实际「${ok}」"; rc=1; }

  # ⑤ 不得改测试命令与入口（改了就能让任何结果变成「红」）
  local f
  for f in docs/00_standards/test-commands.yml scripts/unit.sh; do
    if [ "$(eval_sha "${EVAL_FIXTURE_DIR}/project/${f}")" != "$(eval_sha "${proj}/${f}")" ]; then
      eval_note "${f} 被修改（tdd 阶段不得改测试命令）"; rc=1
    fi
  done

  return "${rc}"
}
