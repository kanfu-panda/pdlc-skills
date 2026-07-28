#!/usr/bin/env bash
# 场景：red-light-gate【A-live】
#
# 契约：没有对应测试代码时跑 pdlc-implement → 必须中止，且 current_stage 不变。
# 该守卫写在 skills/pdlc-implement/SKILL.md 的「PDLC 前置守卫」正文里、**由模型执行**，
# 所以桩测不了（见 ADR 0005 §3.4 的分档判据）。
#
# ⚠️ 本场景的假绿风险：agent 根本没跑起来时，状态机同样"没变"。
# 因此必须同时要求输出里出现守卫哨兵，缺哨兵且现场无改动 → 判为环境抖动而非通过。

# shellcheck disable=SC2034  # 下列 SCENARIO_* 由 evals/run.sh source 后消费
SCENARIO_ID="red-light-gate"
SCENARIO_TIER="A-live"
SCENARIO_DESC="无测试时 implement 必须被守卫中止且状态不推进"
SCENARIO_STAGE="implement"
SCENARIO_FEATURE_ID="F20260728-101600"
SCENARIO_ARGS="${SCENARIO_FEATURE_ID} --autonomous"
# fixture 状态机指向 pdlc-tdd，本场景**故意越级**调用 implement——越级正是被测行为
SCENARIO_STATE_NEXT_STEP="pdlc-tdd"

# assert_scenario <项目目录> → 0=通过 1=契约破坏 2=环境抖动
assert_scenario() {
  local proj="$1"
  local state="${proj}/docs/.pdlc-state/${SCENARIO_FEATURE_ID}.json"

  [ -f "${state}" ] || { eval_note "状态机文件消失（fixture 被破坏）"; return 1; }
  jq -e . "${state}" >/dev/null 2>&1 || { eval_note "状态机 JSON 损坏"; return 1; }

  local rc=0

  # 守卫被绕过的硬证据：写了实现 / 补了测试目录
  local orig_src cur_src
  orig_src="$(eval_sha "${EVAL_FIXTURE_DIR}/project/backend/services/notify/src/notify.sh")"
  cur_src="$(eval_sha "${proj}/backend/services/notify/src/notify.sh")"
  local bypassed=0
  if [ "${orig_src}" != "${cur_src}" ]; then
    eval_note "notify.sh 被修改——守卫未拦住，实现代码已写入"
    bypassed=1
    rc=1
  fi
  if [ -d "${proj}/backend/services/notify/tests" ]; then
    eval_note "implement 阶段自行补建了 tests/——越权（补测试应走 pdlc-tdd）"
    bypassed=1
    rc=1
  fi

  # current_stage 不得推进
  local stage
  stage="$(jq -r '.current_stage' "${state}")"
  if [ "${stage}" != "design" ]; then
    eval_note "current_stage 应保持 design（未推进），实际为「${stage}」"
    rc=1
  fi

  # 若写了 last_phase_result，必须是失败/受阻，不能宣称 impl 成功
  local lpr_stage lpr_ok
  lpr_stage="$(jq -r '.last_phase_result.stage // empty' "${state}")"
  lpr_ok="$(jq -r '.last_phase_result.ok' "${state}")"
  if [ "${lpr_stage}" = "impl" ] && [ "${lpr_ok}" = "true" ]; then
    eval_note "last_phase_result 宣称 impl 成功——与守卫中止矛盾"
    rc=1
  fi

  # 守卫哨兵：证明 agent 真的跑到了守卫这一步
  if ! grep -qE 'PDLC 守卫|pdlc-tdd' "${EVAL_AGENT_OUTPUT}" 2>/dev/null; then
    if [ "${bypassed}" -eq 0 ] && [ "${rc}" -eq 0 ]; then
      eval_note "输出里没有守卫哨兵、现场也无改动——无法确认 agent 真的跑过（判为抖动）"
      return 2
    fi
    eval_note "输出里没有守卫哨兵"
  fi

  return "${rc}"
}
