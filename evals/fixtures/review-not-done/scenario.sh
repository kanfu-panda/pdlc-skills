#!/usr/bin/env bash
# 场景：review-not-done【A-live】
#
# 契约：评审通过 = current_stage 写 review、next_step 写 pdlc-ship，**不写任何 `_done`**。
# `_done` 的含义是「已发布」，只由 /pdlc-ship、/pdlc-deploy 写；评审就写 review_done，
# /pdlc-ship 就分不清哪些功能发布过，发布说明会重复或漏收。旧版正文有过这个写法，且 frontmatter 的
# terminal_state: review_done 字面上就在诱导它。
#
# fixture：calc-mul 已实现，unit / lint 真跑都是绿的，CHANGELOG 已有本 ID 的条目——
# 一份没有阻塞项的干净评审。诚实的结果：写出评审报告，状态机推进到 review → pdlc-ship，ok=true。

# shellcheck disable=SC2034  # 下列 SCENARIO_* 由 evals/run.sh source 后消费
SCENARIO_ID="review-not-done"
SCENARIO_TIER="A-live"
SCENARIO_DESC="评审通过写 review → pdlc-ship，不写任何 _done"
SCENARIO_STAGE="review"
SCENARIO_FEATURE_ID="F20260801-090000"
SCENARIO_ARGS="${SCENARIO_FEATURE_ID} --autonomous"
SCENARIO_STATE_NEXT_STEP="pdlc-review"

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

  local cur nxt stage ok
  cur="$(jq -r '.current_stage | tostring' "${state}")"
  nxt="$(jq -r '.next_step | tostring' "${state}")"
  stage="$(jq -r '.last_phase_result.stage // empty' "${state}")"
  ok="$(jq -r '.last_phase_result.ok | tostring' "${state}")"

  # ① 本场景的判别点：任何 _done 都是契约破坏（current_stage 与 history 都查）
  local rc=0
  case "${cur}" in
    *_done) eval_note "current_stage=「${cur}」——评审不得写 _done（只有 ship / deploy 写）"; rc=1 ;;
  esac
  if jq -e '[.history[]?.stage | tostring | select(endswith("_done"))] | length > 0' "${state}" >/dev/null 2>&1; then
    eval_note "history 里出现了 _done 阶段——评审不得写"; rc=1
  fi

  [ -n "${stage}" ] || { eval_note "last_phase_result.stage 缺失（模型未跑完本阶段）"; [ "${rc}" -eq 1 ] && return 1; return 2; }
  [ "${stage}" = "review" ] || { eval_note "last_phase_result.stage=「${stage}」，应为「review」"; rc=1; }

  # 干净代码却判了阻塞：不是本场景要测的契约，但也不是诚实结果——记为抖动，不掩盖上面的破坏
  if [ "${ok}" = "false" ] && [ "${rc}" -eq 0 ]; then
    eval_note "评审判了阻塞（blocked_reason=$(jq -r '.last_phase_result.blocked_reason | tostring' "${state}")）——fixture 无阻塞项，记为抖动"
    return 2
  fi

  # ② 通过即推进到 review → pdlc-ship
  [ "${cur}" = "review" ] || { [ "${rc}" -eq 1 ] || eval_note "current_stage 应为 review，实际「${cur}」"; rc=1; }
  [ "${nxt}" = "pdlc-ship" ] || { eval_note "next_step 应为 pdlc-ship，实际「${nxt}」"; rc=1; }
  [ "${ok}" = "true" ] || { eval_note "last_phase_result.ok 应为 true，实际「${ok}」"; rc=1; }

  # ③ 评审报告落盘
  if ! find "${proj}/docs/07_reviews/code" -maxdepth 1 -name "${SCENARIO_FEATURE_ID}-*review*.md" 2>/dev/null | grep -q .; then
    eval_note "docs/07_reviews/code/ 下没有 ${SCENARIO_FEATURE_ID}-*-review.md"; rc=1
  fi

  # ④ 评审的自动修复不得把代码改坏
  if ! ( cd "${proj}" && bash scripts/unit.sh ) >/dev/null 2>&1; then
    eval_note "评审后真跑 unit 变红了——自动修复引入了回归"; rc=1
  fi

  return "${rc}"
}
