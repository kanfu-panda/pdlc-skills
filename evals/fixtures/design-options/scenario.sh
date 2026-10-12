#!/usr/bin/env bash
# 场景：design-options【A-live】
#
# 契约：/pdlc-design 遇到值得比较的技术取舍，先列 2～3 个候选方案、给出推荐，再按选定的方案写设计；
# 问不了人（--autonomous）时选推荐方案，并把「设计方案=…」记成一条自动决策。设计阶段不写实现代码。
#
# fixture：PRD 要求计算历史跨进程保留、两个终端同时写不能坏，又要求尽量不加依赖——存储怎么做是个真实的取舍
# （追加写文本 + 文件锁 / SQLite / 每条一个文件……）。判别点：设计文档里有「方案比较」节且表里至少两个候选，
# 状态机 design 那条 history 记了设计方案的决策。照旧版正文直接写一份设计的 agent 两条都过不去。

# shellcheck disable=SC2034  # 下列 SCENARIO_* 由 evals/run.sh source 后消费
SCENARIO_ID="design-options"
SCENARIO_TIER="A-live"
SCENARIO_DESC="有技术取舍时先比较 2～3 个方案再写设计，自主模式下按推荐选并记成自动决策"
SCENARIO_STAGE="design"
SCENARIO_FEATURE_ID="F20260901-100000"
SCENARIO_ARGS="${SCENARIO_FEATURE_ID} --autonomous"
SCENARIO_STATE_NEXT_STEP="pdlc-design"

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
  [ "${stage}" = "design" ] || { eval_note "last_phase_result.stage 应为 design，实际「${stage}」"; rc=1; }
  [ "${cur}" = "design" ] || { eval_note "current_stage 应为 design，实际「${cur}」"; rc=1; }
  [ "${nxt}" = "pdlc-tdd" ] || { eval_note "next_step 应为 pdlc-tdd，实际「${nxt}」"; rc=1; }
  [ "${ok}" = "true" ] || { eval_note "last_phase_result.ok 应为 true，实际「${ok}」"; rc=1; }

  # ① 设计阶段不写实现代码
  if [ "$(eval_sha "${EVAL_FIXTURE_DIR}/project/src/calc.sh")" != "$(eval_sha "${proj}/src/calc.sh")" ]; then
    eval_note "src/calc.sh 被修改——设计阶段写了实现代码"; rc=1
  fi

  # ② 设计文档里有方案比较节，表里至少两个候选
  local docs best=0 f n
  docs="$(find "${proj}/docs/02_design" -type f -name "*${SCENARIO_FEATURE_ID}*.md" 2>/dev/null)"
  if [ -z "${docs}" ]; then
    eval_note "docs/02_design/ 下没有文件名含 ${SCENARIO_FEATURE_ID} 的设计文档"; return 1
  fi
  while IFS= read -r f; do
    # 取「方案比较」标题到下一个同级或更高级标题之间的内容，数表格数据行（去掉表头与分隔行）
    n="$(awk '
      /^#+[[:space:]]/ {
        lvl = match($0, /[^#]/) - 1
        if (insec && lvl <= seclvl) insec = 0
        if (!insec && $0 ~ /方案比较|方案对比|候选方案|[Aa]lternatives|[Oo]ptions/) { insec = 1; seclvl = lvl; next }
      }
      insec && /^[[:space:]]*\|/ {
        if ($0 ~ /^[[:space:]]*\|[[:space:]:|-]+\|?[[:space:]]*$/) next
        rows++
      }
      END { print (rows > 0 ? rows - 1 : 0) }' "${f}")"
    [ "${n}" -gt "${best}" ] && best="${n}"
  done <<< "${docs}"
  if [ "${best}" -lt 2 ]; then
    eval_note "设计文档里没有至少两个候选的方案比较表（数到的候选行：${best}）"; rc=1
  fi

  # ③ 自主模式下把选定方案记成自动决策
  if ! jq -e '[.history[]? | select(.stage == "design") | .auto_decisions[]? | .point // "" | test("方案|[Dd]esign")] | any' "${state}" >/dev/null 2>&1; then
    eval_note "design 那条 history 没有记「设计方案=…」的自动决策"; rc=1
  fi

  return "${rc}"
}
