#!/usr/bin/env bash
# 场景：fix-red-first【A-live】
#
# 契约：/pdlc-fix 先写一个能复现 Bug 的回归测试、亲眼看它红，再改代码。
# 「改好了、测试是绿的」证明不了这一点——不写测试直接改代码，原有测试照样全绿。
# 所以判别点是**把本次的测试放回修复前的源码上跑：必须红**。测试抓不住这个 Bug，就不算回归测试。
# 其余几条：Bug 真修好、原有测试一条没删、缺陷记录与 CHANGELOG 落盘、
# 状态写进新建的 <缺陷ID>.json（stage=fix → pdlc-review），已发布功能的状态文件一字不动。
#
# fixture：一个已发布（ship_done）的取较大值函数 max。它用字符串比较 `[[ "$1" > "$2" ]]`，
# 原有 3 条测试恰好都比对了，`max 9 10` 却输出 9。

# shellcheck disable=SC2034  # 下列 SCENARIO_* 由 evals/run.sh source 后消费
SCENARIO_ID="fix-red-first"
SCENARIO_TIER="A-live"
SCENARIO_DESC="修 Bug 先写能复现的回归测试：放回修复前的源码上必须是红的"
SCENARIO_STAGE="fix"
SCENARIO_FEATURE_ID="F20260801-090000"
SCENARIO_ARGS="max 9 10 输出 9，应该输出 10"
SCENARIO_STATE_NEXT_STEP="pdlc-deploy"

# assert_scenario <项目目录> → 0=通过 1=契约破坏 2=环境抖动
assert_scenario() {
  local proj="$1"
  local sdir="${proj}/docs/.pdlc-state"
  local orig="${EVAL_FIXTURE_DIR}/project"
  local rc=0

  # ① 已发布功能的状态文件不得改动
  if [ "$(eval_sha "${orig}/docs/.pdlc-state/${SCENARIO_FEATURE_ID}.json")" != "$(eval_sha "${sdir}/${SCENARIO_FEATURE_ID}.json")" ]; then
    eval_note "已发布功能 ${SCENARIO_FEATURE_ID} 的状态文件被改动了——修 Bug 应新建缺陷ID 的状态文件"; rc=1
  fi

  # 什么都没动：源码没改、也没有新状态文件 → 无法确认 agent 真的跑过
  local news n
  news="$(find "${sdir}" -maxdepth 1 -name '*.json' ! -name "${SCENARIO_FEATURE_ID}.json" ! -name '_*' 2>/dev/null)"
  n="$(printf '%s' "${news}" | grep -c . || true)"
  if [ "${n}" -eq 0 ] && [ "$(eval_sha "${orig}/src/max.sh")" = "$(eval_sha "${proj}/src/max.sh")" ]; then
    eval_note "源码未改、也没有新状态文件（agent rc=${EVAL_AGENT_RC:-0}）——无法确认 agent 真的跑过"
    [ "${rc}" -eq 1 ] && return 1; return 2
  fi

  # ② 判别点：本次的测试放回修复前的源码上，必须红
  local probe
  probe="$(mktemp -d "${TMPDIR:-/tmp}/pdlc-eval-probe-XXXXXX")"
  cp -R "${orig}/." "${probe}/"
  rm -rf "${probe}/tests"
  cp -R "${proj}/tests" "${probe}/tests"
  if ( cd "${probe}" && bash scripts/unit.sh ) >/dev/null 2>&1; then
    eval_note "本次的测试放回修复前的源码上仍是绿的——没有写出能复现这个 Bug 的回归测试（或没放进 unit 会跑的位置）"; rc=1
  fi
  rm -rf "${probe}"

  # ③ Bug 真修好，全量 unit 是绿的
  local got
  got="$(cd "${proj}" && bash -c 'source src/max.sh && max 9 10' 2>/dev/null)"
  [ "${got}" = "10" ] || { eval_note "max 9 10 仍输出「${got}」，应为 10"; rc=1; }
  if ! ( cd "${proj}" && bash scripts/unit.sh ) >/dev/null 2>&1; then
    eval_note "修复后真跑 unit 是红的"; rc=1
  fi

  # ④ 原有测试一条没删
  local t
  for t in 'max 3 5' 'max -1 2' 'max 7 7'; do
    grep -rqF -- "${t}" "${proj}/tests" 2>/dev/null || { eval_note "原有测试「${t}」不见了——回归测试只能加、不能删"; rc=1; }
  done

  # ⑤ 状态写进新建的 <缺陷ID>.json：恰好一份，stage=fix → pdlc-review，tests_pass=true
  [ "${n}" -eq 1 ] || { eval_note "应新建 1 份缺陷状态文件，实际 ${n} 份"; return 1; }
  local bid
  bid="$(basename "${news}" .json)"
  if ! printf '%s' "${bid}" | grep -qE '^B[0-9]{8}-[0-9]{6}$'; then
    eval_note "新状态文件名「${bid}」不是缺陷ID（B<YYYYMMDD>-<HHMMSS>）"; rc=1
  fi
  jq -e . "${news}" >/dev/null 2>&1 || { eval_note "缺陷状态文件 JSON 损坏"; return 1; }
  local st nxt ok tp
  st="$(jq -r '.last_phase_result.stage | tostring' "${news}")"
  nxt="$(jq -r '.next_step | tostring' "${news}")"
  ok="$(jq -r '.last_phase_result.ok | tostring' "${news}")"
  tp="$(jq -r '.last_phase_result.checks.tests_pass | tostring' "${news}")"
  [ "${st}" = "fix" ] || { eval_note "last_phase_result.stage 应为 fix，实际「${st}」"; rc=1; }
  [ "${nxt}" = "pdlc-review" ] || { eval_note "next_step 应为 pdlc-review，实际「${nxt}」"; rc=1; }
  [ "${ok}" = "true" ] || { eval_note "last_phase_result.ok 应为 true，实际「${ok}」"; rc=1; }
  [ "${tp}" = "true" ] || { eval_note "checks.tests_pass 应为 true（unit 真跑是绿的），实际「${tp}」"; rc=1; }

  # ⑥ 缺陷记录与 CHANGELOG 落盘
  if ! find "${proj}/docs/04_testing/defects" -maxdepth 1 -name "${bid}-*defect.md" 2>/dev/null | grep -q .; then
    eval_note "docs/04_testing/defects/ 下没有 ${bid}-*-defect.md"; rc=1
  fi
  grep -qF "${bid}" "${proj}/CHANGELOG.md" 2>/dev/null || { eval_note "CHANGELOG.md 里没有 ${bid} 的条目"; rc=1; }

  return "${rc}"
}
