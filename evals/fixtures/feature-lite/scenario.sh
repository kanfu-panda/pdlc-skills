#!/usr/bin/env bash
# 场景：feature-lite【A-live】
#
# 契约：`/pdlc-feature --lite` 只砍文档开销，不砍核心约束。
#   - 跳过任务拆解、PRD 评审、技术设计：不产出 docs/02_design/、docs/06_tasks/、docs/07_reviews/doc/ 下本功能的文件，
#     history 里没有 design 阶段
#   - PRD 只写三章：没有「非功能需求」一章
#   - 照常走 tdd → impl → review：收尾在 review → pdlc-ship、ok=true，评审记录落盘，unit 真跑是绿的
#
# fixture：与 prd-clarify 同一个小计算器项目（calc-mul 已评审、等发布）。需求写得足够完整，
# 不会触发需求澄清——本场景只测轻量模式本身。新功能 ID 由模型分配，所以 SCENARIO_FEATURE_ID
# 同 prd-clarify，填旧功能 calc-mul 的 ID（--check 显示为「越级调用」，属预期）。
#
# 这是一整条 feature 链路，一轮的模型开销明显高于其它单阶段场景。

# shellcheck disable=SC2034  # 下列 SCENARIO_* 由 evals/run.sh source 后消费
SCENARIO_ID="feature-lite"
SCENARIO_TIER="A-live"
SCENARIO_DESC="--lite 跳过任务拆解 / PRD 评审 / 技术设计，照常 tdd → impl → review"
SCENARIO_STAGE="feature"
SCENARIO_FEATURE_ID="F20260801-090000"
SCENARIO_ARGS="给计算器加一个除法函数 div：供项目内其它脚本调用，div <a> <b> 打印整数商（向零截断），除数为 0 时报错并返回 1；不做小数和取余；沿用 bash，写法与 src/mul.sh 一致 --lite --autonomous"
SCENARIO_STATE_NEXT_STEP="pdlc-ship"

# assert_scenario <项目目录> → 0=通过 1=契约破坏 2=环境抖动
assert_scenario() {
  local proj="$1"
  local sdir="${proj}/docs/.pdlc-state"
  local rc=0

  # ① 旧功能的状态机不得被改动
  if [ "$(eval_sha "${EVAL_FIXTURE_DIR}/project/docs/.pdlc-state/${SCENARIO_FEATURE_ID}.json")" != "$(eval_sha "${sdir}/${SCENARIO_FEATURE_ID}.json")" ]; then
    eval_note "已有功能 ${SCENARIO_FEATURE_ID} 的状态机被改动了"; rc=1
  fi

  # ② 本次新建的状态机：恰好一份；一份都没有 = 无法确认跑过（抖动）
  local news n new fid
  news="$(find "${sdir}" -maxdepth 1 -name 'F*.json' ! -name "${SCENARIO_FEATURE_ID}.json" 2>/dev/null)"
  n="$(printf '%s' "${news}" | grep -c . || true)"
  if [ "${n}" -eq 0 ]; then
    eval_note "没有新状态机（agent rc=${EVAL_AGENT_RC:-0}）——无法确认 agent 真的跑过"
    [ "${rc}" -eq 1 ] && return 1; return 2
  fi
  [ "${n}" -eq 1 ] || { eval_note "新建了 ${n} 份状态机，应为 1 份"; return 1; }
  new="${news}"
  jq -e . "${new}" >/dev/null 2>&1 || { eval_note "新状态机 JSON 损坏"; return 1; }
  fid="$(basename "${new}" .json)"

  # ③ 轻量模式的判别点：跳过的阶段一个产物都不该有，history 里没有 design
  local skipped
  skipped="$(find "${proj}/docs/02_design" "${proj}/docs/06_tasks" "${proj}/docs/07_reviews/doc" \
               -name "${fid}*" 2>/dev/null)"
  if [ -n "${skipped}" ]; then
    eval_note "轻量模式不该产出这些文件：$(printf '%s' "${skipped}" | sed "s|${proj}/||" | tr '\n' ' ')"; rc=1
  fi
  if jq -e '[.history[]?.stage | tostring | select(. == "design")] | length > 0' "${new}" >/dev/null 2>&1; then
    eval_note "history 里有 design 阶段——轻量模式应跳过技术设计"; rc=1
  fi

  # ④ PRD 只写三章
  local prd
  prd="$(find "${proj}/docs/01_requirements/prd" -maxdepth 1 -name "${fid}-*-prd.md" 2>/dev/null | head -1)"
  if [ -z "${prd}" ]; then
    eval_note "docs/01_requirements/prd/ 下没有 ${fid}-*-prd.md"; rc=1
  elif grep -qE '^#+ .*非功能需求' "${prd}"; then
    eval_note "PRD 里有「非功能需求」一章——轻量模式只写背景与目标、功能需求、待确认问题"; rc=1
  fi

  # ⑤ 核心约束照常：走到 review → pdlc-ship，评审记录落盘，unit 真跑是绿的
  local cur nxt ok
  cur="$(jq -r '.current_stage | tostring' "${new}")"
  nxt="$(jq -r '.next_step | tostring' "${new}")"
  ok="$(jq -r '.last_phase_result.ok | tostring' "${new}")"
  if [ "${ok}" = "false" ] && [ "${rc}" -eq 0 ]; then
    eval_note "中途判了阻塞（停在 ${cur}，blocked_reason=$(jq -r '.last_phase_result.blocked_reason | tostring' "${new}")）——需求完整、无阻塞项，记为抖动"
    return 2
  fi
  [ "${cur}" = "review" ] || { eval_note "current_stage 应为 review，实际「${cur}」"; rc=1; }
  [ "${nxt}" = "pdlc-ship" ] || { eval_note "next_step 应为 pdlc-ship，实际「${nxt}」"; rc=1; }
  [ "${ok}" = "true" ] || { eval_note "last_phase_result.ok 应为 true，实际「${ok}」"; rc=1; }
  local st
  for st in requirements tdd impl review; do
    jq -e --arg s "${st}" '[.history[]?.stage | tostring | select(. == $s)] | length > 0' "${new}" >/dev/null 2>&1 \
      || { eval_note "history 里缺 ${st} 阶段"; rc=1; }
  done
  if ! find "${proj}/docs/07_reviews/code" -maxdepth 1 -name "${fid}-*review*.md" 2>/dev/null | grep -q .; then
    eval_note "docs/07_reviews/code/ 下没有 ${fid}-*-review.md"; rc=1
  fi
  if ! ( cd "${proj}" && bash scripts/unit.sh ) >/dev/null 2>&1; then
    eval_note "真跑 unit 是红的"; rc=1
  fi

  return "${rc}"
}
