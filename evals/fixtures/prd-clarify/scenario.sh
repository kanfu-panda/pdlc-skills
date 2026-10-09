#!/usr/bin/env bash
# 场景：prd-clarify【A-live】
#
# 契约：文字需求太单薄（澄清清单缺 3 项及以上）时，`--autonomous` 下不提问、不卡住，
# 照常写出 PRD 并推进状态机；但**靠默认补上的项必须摆出来**——逐条列进 PRD「待确认问题」，
# 状态标「待确认」，并在 history 的 auto_decisions[] 里各记一条「需求澄清：<项>」。
# 旧版正文对一句话需求只写「自动推断」，缺的东西被模型悄悄猜掉，人看 PRD 时分不清
# 哪句是用户说的、哪句是模型编的。
#
# fixture：一个已有 calc-mul（评审通过、等发布）的小计算器项目。需求只有一句
# 「给计算器加一个除法函数」：说了要做什么，没说给谁用、不做什么、怎样算做完、有什么限制——
# 缺 4 项，按清单必须走澄清。它又说清了要做什么，所以 block 也是错的。
#
# 区分度（v1.7.6 实测）：拿改动前的 main 跑 1 轮，PRD 模板自带「待确认问题」一节，模型照样列了 3 行，
# ⑤ 没拦住；拦住它的是 ⑥——旧正文没要求留痕，auto_decisions 里一条「需求澄清」都没有。
# 所以 ⑥ 是本场景真正的判别点，⑤ 防的是反方向的退化（留了痕、PRD 里却不摆出来）。
#
# 本场景要新建功能，新 ID 由模型分配、事先不知道。run.sh 的结构自检要求 SCENARIO_FEATURE_ID
# 指向 fixture 里已有的状态机，所以这里填的是旧功能 calc-mul 的 ID（--check 会显示为
# 「越级调用」，属预期）；断言按「新出现的那份状态机」找本次的产出，并确认旧功能一字未改。

# shellcheck disable=SC2034  # 下列 SCENARIO_* 由 evals/run.sh source 后消费
SCENARIO_ID="prd-clarify"
SCENARIO_TIER="A-live"
SCENARIO_DESC="单薄需求在 --autonomous 下不问不卡，靠默认补的项列进「待确认问题」"
SCENARIO_STAGE="prd"
SCENARIO_FEATURE_ID="F20260801-090000"
SCENARIO_ARGS="给计算器加一个除法函数 --autonomous"
SCENARIO_STATE_NEXT_STEP="pdlc-ship"

# assert_scenario <项目目录> → 0=通过 1=契约破坏 2=环境抖动
assert_scenario() {
  local proj="$1"
  local sdir="${proj}/docs/.pdlc-state"
  local old="${sdir}/${SCENARIO_FEATURE_ID}.json"
  local rc=0

  # ① 旧功能的状态机不得被改动
  if [ "$(eval_sha "${EVAL_FIXTURE_DIR}/project/docs/.pdlc-state/${SCENARIO_FEATURE_ID}.json")" != "$(eval_sha "${old}")" ]; then
    eval_note "已有功能 ${SCENARIO_FEATURE_ID} 的状态机被改动了"; rc=1
  fi

  # ② 说清了要做什么，就不该 block。只认行首的哨兵：codex 的输出会带上它读到的 skill 原文，
  #    原文里那句「末行输出哨兵 `<<<PDLC blocked …>>>`」在反引号里，不在行首（v1.7.6 实测误判过一次）
  if grep -qE '^[[:space:]]*<<<PDLC blocked' "${EVAL_AGENT_OUTPUT:-/dev/null}" 2>/dev/null; then
    eval_note "输出了 blocked 哨兵——需求说清了要做什么，缺的项应按默认补上并列为待确认，不该卡住"
    return 1
  fi

  # ③ 找本次新建的状态机：恰好一份
  local news n new
  news="$(find "${sdir}" -maxdepth 1 -name 'F*.json' ! -name "${SCENARIO_FEATURE_ID}.json" 2>/dev/null)"
  n="$(printf '%s' "${news}" | grep -c . || true)"
  if [ "${n}" -eq 0 ]; then
    # 与其它场景同一条口径：什么都没留下 = 无法确认 agent 真的跑过（抖动）；
    # 但输出里在向人提问 → 它跑了，只是停下来等回答——--autonomous 下这正是被测的破坏
    if [ "${EVAL_AGENT_RC:-0}" -eq 0 ] && grep -qE '[？?]' "${EVAL_AGENT_OUTPUT:-/dev/null}" 2>/dev/null; then
      eval_note "没有新建状态机，输出却在提问——--autonomous 下不该停下来等回答"; return 1
    fi
    eval_note "没有新状态机（agent rc=${EVAL_AGENT_RC:-0}）——无法确认 agent 真的跑过"; return 2
  fi
  [ "${n}" -eq 1 ] || { eval_note "新建了 ${n} 份状态机，应为 1 份"; return 1; }
  new="${news}"
  jq -e . "${new}" >/dev/null 2>&1 || { eval_note "新状态机 JSON 损坏"; return 1; }
  local fid
  fid="$(basename "${new}" .json)"

  # ④ 状态推进：requirements → pdlc-design，ok=true
  local cur nxt ok
  cur="$(jq -r '.current_stage | tostring' "${new}")"
  nxt="$(jq -r '.next_step | tostring' "${new}")"
  ok="$(jq -r '.last_phase_result.ok | tostring' "${new}")"
  [ "${cur}" = "requirements" ] || { eval_note "current_stage 应为 requirements，实际「${cur}」"; rc=1; }
  [ "${nxt}" = "pdlc-design" ] || { eval_note "next_step 应为 pdlc-design，实际「${nxt}」"; rc=1; }
  [ "${ok}" = "true" ] || { eval_note "last_phase_result.ok 应为 true，实际「${ok}」"; rc=1; }

  # ⑤ PRD 落盘，且「待确认问题」一节至少 3 行标「待确认」
  local prd
  prd="$(find "${proj}/docs/01_requirements/prd" -maxdepth 1 -name "${fid}-*-prd.md" 2>/dev/null | head -1)"
  if [ -z "${prd}" ]; then
    eval_note "docs/01_requirements/prd/ 下没有 ${fid}-*-prd.md"; return 1
  fi
  local pending
  pending="$(awk '/^#+ .*待确认问题/ {on=1; next} on && /^#+ / {on=0} on && /^\|/ && /待确认/' "${prd}" | grep -c . || true)"
  if [ "${pending}" -lt 3 ]; then
    eval_note "PRD「待确认问题」一节只有 ${pending} 行标「待确认」——需求缺 4 项，靠默认补上的至少应列 3 项"; rc=1
  fi

  # ⑥ 每个默认都在 auto_decisions 里留痕
  local dec
  dec="$(jq '[.history[]?.auto_decisions[]? | select((.point // "") | test("需求澄清"))] | length' "${new}" 2>/dev/null || echo 0)"
  if [ "${dec}" -lt 3 ]; then
    eval_note "history 里「需求澄清」类 auto_decisions 只有 ${dec} 条，应至少 3 条"; rc=1
  fi

  return "${rc}"
}
