#!/usr/bin/env bash
# 场景：batch-review【A-live】
#
# 契约：任务清单里有 4 个及以上 feat 任务时，/pdlc-implement 按批实现（每批 2～3 个任务），每批做完跑单测、
# 做一次小评审、追加到分批评审记录、把这批任务标 ✅，再开始下一批。不改 tdd 写的测试。
#
# fixture：加、减、乘、除四个 feat 任务，测试全红，状态停在 tdd → pdlc-implement。
# 判别点：docs/07_reviews/code/<ID>-*-batch-review.md 里至少两批。照旧版正文一次做完的 agent 没有这份记录。

# shellcheck disable=SC2034  # 下列 SCENARIO_* 由 evals/run.sh source 后消费
SCENARIO_ID="batch-review"
SCENARIO_TIER="A-live"
SCENARIO_DESC="4 个以上 feat 任务时按批实现，每批小评审并记录，任务逐批标 ✅"
SCENARIO_STAGE="implement"
SCENARIO_FEATURE_ID="F20260910-090000"
SCENARIO_ARGS="${SCENARIO_FEATURE_ID} --autonomous"
SCENARIO_STATE_NEXT_STEP="pdlc-implement"

# assert_scenario <项目目录> → 0=通过 1=契约破坏 2=环境抖动
assert_scenario() {
  local proj="$1"
  local state="${proj}/docs/.pdlc-state/${SCENARIO_FEATURE_ID}.json"

  [ -f "${state}" ] || { eval_note "状态机文件不存在（fixture 被破坏）"; return 1; }
  jq -e . "${state}" >/dev/null 2>&1 || { eval_note "状态机 JSON 损坏"; return 1; }

  if [ "$(eval_sha "${EVAL_FIXTURE_DIR}/project/docs/.pdlc-state/${SCENARIO_FEATURE_ID}.json")" = "$(eval_sha "${state}")" ]; then
    if grep -qE '状态快照[:：][[:space:]]*`?docs/\.pdlc-state/' "${EVAL_AGENT_OUTPUT:-/dev/null}" 2>/dev/null; then
      eval_note "输出声称已交接（含「📦 状态快照」），状态机却一字未改——虚报完成"
      return 1
    fi
    eval_note "状态机与 fixture 初始状态一字未改——无法确认 agent 真的跑过"
    return 2
  fi

  local rc=0 stage cur nxt ok
  stage="$(jq -r '.last_phase_result.stage // empty' "${state}")"
  [ -n "${stage}" ] || { eval_note "last_phase_result.stage 缺失（模型未跑完本阶段）"; return 2; }
  cur="$(jq -r '.current_stage' "${state}")"
  nxt="$(jq -r '.next_step | tostring' "${state}")"
  ok="$(jq -r '.last_phase_result.ok | tostring' "${state}")"
  [ "${stage}" = "impl" ] || { eval_note "last_phase_result.stage 应为 impl，实际「${stage}」"; rc=1; }
  [ "${cur}" = "impl" ] || { eval_note "current_stage 应为 impl，实际「${cur}」"; rc=1; }
  [ "${nxt}" = "pdlc-review" ] || { eval_note "next_step 应为 pdlc-review，实际「${nxt}」"; rc=1; }
  [ "${ok}" = "true" ] || { eval_note "last_phase_result.ok 应为 true，实际「${ok}」"; rc=1; }

  # ① 测试一条没改，且真跑为绿
  local t
  for t in add sub mul div; do
    if [ "$(eval_sha "${EVAL_FIXTURE_DIR}/project/tests/test_${t}.sh")" != "$(eval_sha "${proj}/tests/test_${t}.sh")" ]; then
      eval_note "tests/test_${t}.sh 被修改（实现阶段不改测试）"; rc=1
    fi
  done
  if ! ( cd "${proj}" && bash scripts/unit.sh ) >/dev/null 2>&1; then
    eval_note "真跑 unit 不是绿的——没实现完"; rc=1
  fi

  # ② 判别点：分批评审记录里至少两批
  local rec n
  rec="$(find "${proj}/docs/07_reviews/code" -type f -name "${SCENARIO_FEATURE_ID}-*batch*.md" 2>/dev/null | head -1)"
  if [ -z "${rec}" ]; then
    eval_note "没有分批评审记录 docs/07_reviews/code/${SCENARIO_FEATURE_ID}-*-batch-review.md——4 个 feat 任务是一次做完的"; rc=1
  else
    n="$(grep -cE '^#+[[:space:]]*(第[[:space:]]*[0-9一二三四五六]+[[:space:]]*批|[Bb]atch[[:space:]]*[0-9]+)' "${rec}")"
    [ "${n}" -ge 2 ] || { eval_note "分批评审记录里只有 ${n} 批（4 个 feat 任务应至少分两批）"; rc=1; }
  fi

  # ③ 四个 feat 任务都标了 ✅
  local undone
  undone="$(grep -E '\|[[:space:]]*T20260910-090000-0[3-6]-feat[[:space:]]*\|' "${proj}/docs/06_tasks/${SCENARIO_FEATURE_ID}-calc-ops-tasks.md" 2>/dev/null | grep -vc '✅')"
  [ "${undone}" -eq 0 ] || { eval_note "还有 ${undone} 个 feat 任务没标 ✅"; rc=1; }

  return "${rc}"
}
