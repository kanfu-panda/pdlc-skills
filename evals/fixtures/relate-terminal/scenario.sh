#!/usr/bin/env bash
# 场景：relate-terminal【A-live】
#
# 验 `/pdlc-relate rebuild` 算节点终态时**只看 current_stage**，不看 terminal_state。
#
# 这是一次真机验证里坐实的错误结论：一份状态文件停在 review，实例里却写着
# `terminal_state: "review_done"`（契约外字段——skill frontmatter 的 terminal_state 是
# 「走完后应到达的终态名」，是目标不是事实）。重建出的索引把它标成了 `terminal: true`，
# 影响分析随之宣称它「已抵达终态」。另一个命令在同一批数据上独立犯了同样的错，
# 所以这不是某次模型发挥失常，而是契约的洞——需要一个真跑的场景把它钉住。
#
# 判别力来自三个方向同时成立：
#   ① 陷阱节点（review + terminal_state=review_done）terminal 必须是 false
#   ② 对照节点（current_stage=feature_done）terminal 必须是 true——挡住「一律 false」的偷懒写法
#   ③ 合法的 depends_on 边必须在，散文目标（「报表导出模块」）不得被解读成节点或边
# 另外 rebuild 只维护索引，不许改状态文件本身。
#
# 节点与边的字段名按 pdlc-relate 的约定：nodes 以 ID 为键、含 terminal；edges 是含 from / to 的扁平列表。

# shellcheck disable=SC2034  # 下列 SCENARIO_* 由 evals/run.sh source 后消费
SCENARIO_ID="relate-terminal"
SCENARIO_TIER="A-live"
SCENARIO_DESC="关系索引的终态只看 current_stage，不看 terminal_state"
SCENARIO_STAGE="relate"
SCENARIO_FEATURE_ID="F20260728-130000"
SCENARIO_ARGS="rebuild"
SCENARIO_STATE_NEXT_STEP="pdlc-review"

# 取某节点的 terminal；节点缺失时回显「缺节点」。nodes 允许是以 ID 为键的对象或含 id 的数组
_rt_terminal() { # _rt_terminal <索引文件> <feature ID>
  jq -r --arg id "$2" '
    (.nodes | if type == "object" then .[$id] else (map(select(.id == $id))[0]) end)
    | if . == null then "缺节点" else (.terminal | tostring) end' "$1" 2>/dev/null
}

# assert_scenario <项目目录> → 0=通过 1=契约破坏 2=环境抖动
assert_scenario() {
  local proj="$1"
  local st="${proj}/docs/.pdlc-state"
  local idx="${st}/_relations.json"
  local rc=0 id orig cur t

  # rebuild 只维护索引，不许改状态文件本身
  for id in F20260728-110000 F20260728-120000 F20260728-130000; do
    orig="$(eval_sha "${EVAL_FIXTURE_DIR}/project/docs/.pdlc-state/${id}.json")"
    cur="$(eval_sha "${st}/${id}.json")"
    if [ "${orig}" != "${cur}" ]; then
      eval_note "状态文件 ${id}.json 被改动——rebuild 只该维护索引"
      rc=1
    fi
  done

  if [ ! -f "${idx}" ]; then
    # 没产索引、状态也没动 = 无从判断 → 抖动（与其余场景「没产物即抖动」一致）
    if [ "${rc}" -eq 0 ]; then
      eval_note "未产出 _relations.json——无法确认 agent 是否真的跑完（不可判，非契约破坏）"
      return 2
    fi
    return "${rc}"
  fi
  if ! jq -e . "${idx}" >/dev/null 2>&1; then
    eval_note "_relations.json 不是合法 JSON"
    return 1
  fi

  # ① 陷阱：停在 review、实例里写着 terminal_state=review_done → 不是终态
  t="$(_rt_terminal "${idx}" F20260728-110000)"
  if [ "${t}" != "false" ]; then
    eval_note "F20260728-110000 停在 review（terminal_state 只是目标），terminal 应为 false，实际「${t}」"
    rc=1
  fi

  # ② 对照：current_stage=feature_done → 终态
  t="$(_rt_terminal "${idx}" F20260728-120000)"
  if [ "${t}" != "true" ]; then
    eval_note "F20260728-120000 的 current_stage=feature_done，terminal 应为 true，实际「${t}」"
    rc=1
  fi

  # ③ 合法的 depends_on 边必须入图
  if ! jq -e '[.edges[]? | select(.from == "F20260728-130000" and .to == "F20260728-110000")] | length > 0' \
       "${idx}" >/dev/null 2>&1; then
    eval_note "缺 F20260728-130000 → F20260728-110000 的 depends_on 边"
    rc=1
  fi

  # ③ 散文目标不得被解读成边（「不入图」不是丢弃，是交给人判断，不许硬解读成 feature）
  if jq -e '[.edges[]? | .to | tostring | select(test("^[FB][0-9]{8}-") | not)] | length > 0' \
       "${idx}" >/dev/null 2>&1; then
    eval_note "有边指向非 feature ID——散文目标被硬解读成了节点"
    rc=1
  fi

  return "${rc}"
}
