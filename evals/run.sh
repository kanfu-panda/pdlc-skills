#!/usr/bin/env bash
#
# PDLC 行为层 eval runner（ADR 0005 §3）
#
# 跑法：把 fixture 拷到临时目录 → 用真模型跑一个 pdlc 阶段 → 读回状态机断言。
# 断言只碰**确定性残渣**（状态机 JSON / 文件 / 退出码），容忍模型散文差异。
#
#   ./evals/run.sh --check                     # 只校验 fixture 完整性，不跑模型（免费）
#   ./evals/run.sh --list                      # 列出场景
#   ./evals/run.sh --only honest-checks        # 跑单个场景
#   ./evals/run.sh --platform codex --repeat 3 # 发版前建议：两平台各跑 3 轮
#
# 退出码：0=全部通过 1=有契约破坏 2=有场景无结论（全是环境抖动）3=用法/依赖错误
set -euo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="${EVALS_DIR}/fixtures"

PLATFORM="claude"
ONLY=""
REPEAT=1
KEEP=0
MODE="run"
TIMEOUT_SECS="${EVAL_TIMEOUT:-900}"
FLAKE_RETRIES="${EVAL_FLAKE_RETRIES:-2}"

# 默认放行 pdlc-implement 在 frontmatter 里声明的那组工具。
# 模型必须真能跑 Bash，否则跑不了 unit/lint，honest-checks 判别式无从产生。
DEFAULT_CLAUDE_FLAGS="--allowedTools Bash Read Write Edit Glob Grep"
# 常见误用：把额外参数设在 CLAUDE_FLAGS 上——下一行会把它覆盖掉，设了等于没设，却照样跑出结论。
if [ -n "${CLAUDE_FLAGS:-}" ] && [ -z "${EVAL_CLAUDE_FLAGS:-}" ]; then
  printf '⚠️  检测到 CLAUDE_FLAGS=%s，但本脚本读的是 EVAL_CLAUDE_FLAGS——CLAUDE_FLAGS 不会生效\n' "${CLAUDE_FLAGS}" >&2
fi
CLAUDE_FLAGS="${EVAL_CLAUDE_FLAGS:-${DEFAULT_CLAUDE_FLAGS}}"

# claude 臂加载哪份插件：默认本仓库根（--plugin-dir），发版前验的就是待发布的那份。
# 不加的话 /pdlc-* 解析到的是已安装的插件——汇总照样盖着当前 commit，验的却是上一个版本。
# 显式置空（EVAL_PLUGIN_DIR=）= 不加 --plugin-dir，验已安装版本（发版后回头验线上版本时用）。
REPO_ROOT="$(cd "${EVALS_DIR}/.." && pwd)"
PLUGIN_DIR="${EVAL_PLUGIN_DIR-${REPO_ROOT}}"

die() { printf '❌ %s\n' "$1" >&2; exit "${2:-3}"; }

usage() {
  sed -n '3,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --platform) PLATFORM="${2:-}"; shift 2 ;;
    --only)     ONLY="${2:-}"; shift 2 ;;
    --repeat)   REPEAT="${2:-}"; shift 2 ;;
    --timeout)  TIMEOUT_SECS="${2:-}"; shift 2 ;;
    --keep)     KEEP=1; shift ;;
    --list)     MODE="list"; shift ;;
    --check)    MODE="check"; shift ;;
    --replay)   MODE="replay"; REPLAY_DIR="${2:-}"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *)          die "未知参数：$1（--help 看用法）" ;;
  esac
done

case "${PLATFORM}" in
  claude|codex) ;;
  *) die "--platform 只支持 claude / codex，收到「${PLATFORM}」" ;;
esac
# 数字参数必须校验——不校验会让非法值静默走到分支判断里（codex-loop-run.sh 踩过）
printf '%s' "${REPEAT}" | grep -qE '^[1-9][0-9]*$' \
  || die "--repeat 必须是正整数，收到「${REPEAT}」"
printf '%s' "${TIMEOUT_SECS}" | grep -qE '^[1-9][0-9]*$' \
  || die "--timeout 必须是正整数秒，收到「${TIMEOUT_SECS}」"

command -v jq >/dev/null 2>&1 || die "缺少 jq（断言要靠它读状态机）"

# 哈希工具因平台而异：Linux 多为 sha256sum，macOS 为 shasum。启动期选定一个，
# 一个都没有就**立即报错停机**——绝不静默降级，否则「文件未被修改」类断言会
# 因两侧都拿不到哈希而恒真，变成假绿。
if command -v sha256sum >/dev/null 2>&1;  then HASH_TOOL="sha256sum"
elif command -v shasum   >/dev/null 2>&1; then HASH_TOOL="shasum"
elif command -v openssl  >/dev/null 2>&1; then HASH_TOOL="openssl"
else die "缺少哈希工具（需 sha256sum / shasum / openssl 之一，断言要靠它比对文件是否被改）"
fi

# ---------- 供 scenario.sh 使用的助手（由 scenario 间接调用）----------
NOTES=""
# shellcheck disable=SC2329  # 在 scenario.sh 的 assert_scenario 里调用
eval_note() { NOTES="${NOTES}    · ${1}"$'\n'; }
# shellcheck disable=SC2329  # 同上
eval_sha() {
  [ -f "$1" ] || { printf '缺失'; return 0; }
  case "${HASH_TOOL}" in
    sha256sum) sha256sum "$1"       | awk '{print $1}'  ;;
    shasum)    shasum -a 256 "$1"   | awk '{print $1}'  ;;
    openssl)   openssl dgst -sha256 "$1" | awk '{print $NF}' ;;
  esac
}

# ---------- 场景发现 ----------
discover() {
  local d name
  for d in "${FIXTURES_DIR}"/*/; do
    [ -f "${d}scenario.sh" ] || continue
    name="$(basename "${d}")"
    if [ -n "${ONLY}" ] && [ "${name}" != "${ONLY}" ]; then continue; fi
    printf '%s\n' "${name}"
  done
}

SCENARIOS="$(discover)"
[ -n "${SCENARIOS}" ] || die "没有匹配的场景${ONLY:+（--only ${ONLY}）}"

# ---------- --list ----------
if [ "${MODE}" = "list" ]; then
  printf '可用场景：\n'
  while IFS= read -r s; do
    # shellcheck source=/dev/null
    ( . "${FIXTURES_DIR}/${s}/scenario.sh"
      printf '  %-16s [%s] %s\n' "${SCENARIO_ID}" "${SCENARIO_TIER}" "${SCENARIO_DESC}" )
  done <<< "${SCENARIOS}"
  exit 0
fi

# ---------- --check：不跑模型的结构自检 ----------
if [ "${MODE}" = "check" ]; then
  rc=0
  while IFS= read -r s; do
    sdir="${FIXTURES_DIR}/${s}"
    printf '▸ %s\n' "${s}"
    # shellcheck source=/dev/null
    ( . "${sdir}/scenario.sh"
      [ -n "${SCENARIO_ID:-}" ] || { printf '  ❌ scenario.sh 缺 SCENARIO_ID\n'; exit 1; }
      [ "${SCENARIO_ID}" = "${s}" ] || { printf '  ❌ SCENARIO_ID 与目录名不一致\n'; exit 1; }
      for v in SCENARIO_TIER SCENARIO_DESC SCENARIO_STAGE SCENARIO_FEATURE_ID \
               SCENARIO_ARGS SCENARIO_STATE_NEXT_STEP; do
        eval "val=\${${v}:-}"
        [ -n "${val}" ] || { printf '  ❌ scenario.sh 缺 %s\n' "${v}"; exit 1; }
      done
      type assert_scenario >/dev/null 2>&1 \
        || { printf '  ❌ scenario.sh 未定义 assert_scenario\n'; exit 1; }
      [ -d "${sdir}/project" ] || { printf '  ❌ 缺 project/ 目录\n'; exit 1; }
      st="${sdir}/project/docs/.pdlc-state/${SCENARIO_FEATURE_ID}.json"
      [ -f "${st}" ] || { printf '  ❌ 缺状态机 %s\n' "${st##*/}"; exit 1; }
      jq -e . "${st}" >/dev/null 2>&1 || { printf '  ❌ 状态机 JSON 非法\n'; exit 1; }
      # 状态机的 next_step 必须与 scenario 声明的一致。
      # 注意它**不一定**等于本场景要跑的阶段——red-light-gate 正是故意越级去跑
      # pdlc-implement（状态机指向 pdlc-tdd），越级本身就是被测行为。
      got="$(jq -r '.next_step // empty' "${st}")"
      [ "${got}" = "${SCENARIO_STATE_NEXT_STEP}" ] \
        || { printf '  ❌ next_step 应为 %s，实际 %s\n' "${SCENARIO_STATE_NEXT_STEP}" "${got}"; exit 1; }
      if [ "${got}" = "pdlc-${SCENARIO_STAGE}" ]; then
        printf '  ✅ scenario.sh 完整 · 状态机合法 · 顺序调用 pdlc-%s\n' "${SCENARIO_STAGE}"
      else
        printf '  ✅ scenario.sh 完整 · 状态机合法 · 越级调用 pdlc-%s（状态机指向 %s）\n' \
          "${SCENARIO_STAGE}" "${got}"
      fi
    ) || rc=1
  done <<< "${SCENARIOS}"
  [ "${rc}" -eq 0 ] && printf '\n✅ fixture 结构自检全部通过（未跑模型）\n' \
                    || printf '\n❌ fixture 结构自检有失败项\n'
  exit "${rc}"
fi

# ---------- --replay：对已保留的现场离线复跑断言（不烧额度）----------
# 改断言时用它验证，避免为了调一行 jq 又花一个模型 turn。配合 --keep 使用。
if [ "${MODE}" = "replay" ]; then
  [ -n "${REPLAY_DIR:-}" ] && [ -d "${REPLAY_DIR}" ] || die "--replay 需要一个已存在的现场目录"
  [ -n "${ONLY}" ] || die "--replay 必须配 --only <场景>（现场属于哪个场景无法自动判断）"
  sdir="${FIXTURES_DIR}/${ONLY}"
  # shellcheck source=/dev/null
  . "${sdir}/scenario.sh"
  export EVAL_FIXTURE_DIR="${sdir}"
  export EVAL_AGENT_OUTPUT="${REPLAY_DIR}/.eval-agent-output.txt"
  export EVAL_AGENT_RC=0
  NOTES=""
  set +e
  assert_scenario "${REPLAY_DIR}"
  verdict=$?
  set -e
  printf '▸ %s（replay：%s）\n' "${SCENARIO_ID}" "${REPLAY_DIR}"
  case "${verdict}" in
    0) printf '  ✅ 通过\n' ;;
    1) printf '  ❌ 契约破坏\n'; printf '%s' "${NOTES}" ;;
    *) printf '  ⚠️  环境抖动\n'; printf '%s' "${NOTES}" ;;
  esac
  exit "${verdict}"
fi

# ---------- 真跑（A-live，要模型额度）----------
command -v "${PLATFORM}" >/dev/null 2>&1 || die "找不到 ${PLATFORM} 命令"

# 便携超时：macOS 没有 coreutils 的 timeout
run_with_timeout() { # <秒> <命令...>
  local secs="$1"; shift
  "$@" &
  local pid=$!
  ( sleep "${secs}"; kill -TERM "${pid}" 2>/dev/null ) >/dev/null 2>&1 &
  local watcher=$!
  local rc=0
  wait "${pid}" 2>/dev/null || rc=$?
  kill -TERM "${watcher}" 2>/dev/null || true
  wait "${watcher}" 2>/dev/null || true
  return "${rc}"
}

invoke_agent() { # <项目目录> <阶段> <参数> <输出文件>
  local proj="$1" stage="$2" args="$3" out="$4"
  # `</dev/null` 不可省：两个 CLI 都会读 stdin（实测 `codex exec` 会把管道内容
  # 当成额外输入吃掉）。不隔离的话，agent 会顺走调用方的 stdin —— 既污染它自己的
  # 输入，又让外层 while-read 循环提前断流。
  if [ "${PLATFORM}" = "claude" ]; then
    # --plugin-dir 单独成数组、保持带引号（路径可能含空格，不能混进要词分割的 CLAUDE_FLAGS）。
    # 空数组用 ${a[@]+"${a[@]}"} 展开：bash 3.2 在 set -u 下直接展开空数组会报 unbound variable。
    local plugin_args=()
    if [ -n "${PLUGIN_DIR}" ]; then plugin_args=(--plugin-dir "${PLUGIN_DIR}"); fi
    # shellcheck disable=SC2086  # CLAUDE_FLAGS 需要词分割，这是刻意的
    ( cd "${proj}" && run_with_timeout "${TIMEOUT_SECS}" \
        claude -p "/pdlc-${stage} ${args}" ${CLAUDE_FLAGS} ${plugin_args[@]+"${plugin_args[@]}"} ) >"${out}" 2>&1 </dev/null
  else
    run_with_timeout "${TIMEOUT_SECS}" \
      codex exec -C "${proj}" -s workspace-write --skip-git-repo-check \
      "按 pdlc ${stage} ${args}" >"${out}" 2>&1 </dev/null
  fi
}

TOTAL_FAIL=0
TOTAL_INCONCLUSIVE=0
SUMMARY=""
RAN_N=0
EXPECT_N="$(printf '%s\n' "${SCENARIOS}" | grep -c .)"

# 场景名走 FD 3，不走 stdin。循环体里跑的是真 agent，而 agent 会读 stdin ——
# 用 `done <<< "${SCENARIOS}"` 的话它一口把剩下的场景名喝干，循环跑完第一个就
# 静默结束，汇总里还只字不提少跑的那几个。这正是最坏的一种失败：**覆盖面缩水，
# 报告却照常收尾**。FD 3 从根上隔开，`</dev/null` 是第二道。
while IFS= read -r s <&3; do
  RAN_N=$((RAN_N + 1))
  sdir="${FIXTURES_DIR}/${s}"
  # shellcheck source=/dev/null
  . "${sdir}/scenario.sh"
  export EVAL_FIXTURE_DIR="${sdir}"

  printf '\n══ %s [%s · %s] ══\n' "${SCENARIO_ID}" "${SCENARIO_TIER}" "${PLATFORM}"
  printf '   %s\n' "${SCENARIO_DESC}"

  pass_n=0; fail_n=0; flake_n=0
  attempt=1
  while [ "${attempt}" -le "${REPEAT}" ]; do
    tries=0
    while :; do
      workdir="$(mktemp -d "${TMPDIR:-/tmp}/pdlc-eval-${s}-XXXXXX")"
      cp -R "${sdir}/project/." "${workdir}/"
      out="${workdir}/.eval-agent-output.txt"
      export EVAL_AGENT_OUTPUT="${out}"

      printf '  ▸ 第 %d/%d 轮…' "${attempt}" "${REPEAT}"
      arc=0
      invoke_agent "${workdir}" "${SCENARIO_STAGE}" "${SCENARIO_ARGS}" "${out}" || arc=$?
      export EVAL_AGENT_RC="${arc}"

      NOTES=""
      set +e
      assert_scenario "${workdir}"
      verdict=$?
      set -e

      case "${verdict}" in
        0) printf ' ✅ 通过\n'; pass_n=$((pass_n + 1)) ;;
        1) printf ' ❌ 契约破坏\n'; printf '%s' "${NOTES}"; fail_n=$((fail_n + 1)) ;;
        *) printf ' ⚠️  环境抖动（agent rc=%s）\n' "${arc}"; printf '%s' "${NOTES}" ;;
      esac

      if [ "${KEEP}" -eq 1 ]; then
        printf '    现场保留：%s\n' "${workdir}"
      else
        rm -rf "${workdir}"
      fi

      # 抖动才重跑；契约破坏立即计数、不重跑
      if [ "${verdict}" -eq 2 ] && [ "${tries}" -lt "${FLAKE_RETRIES}" ]; then
        tries=$((tries + 1))
        printf '    重跑（抖动不计失败，第 %d/%d 次）\n' "${tries}" "${FLAKE_RETRIES}"
        continue
      fi
      [ "${verdict}" -eq 2 ] && flake_n=$((flake_n + 1))
      break
    done
    attempt=$((attempt + 1))
  done

  decided=$((pass_n + fail_n))
  if [ "${decided}" -eq 0 ]; then
    line="  ⚠️  ${SCENARIO_ID}：无结论（${flake_n} 轮全是环境抖动）"
    TOTAL_INCONCLUSIVE=$((TOTAL_INCONCLUSIVE + 1))
  elif [ "${pass_n}" -gt "${fail_n}" ]; then
    line="  ✅ ${SCENARIO_ID}：通过（${pass_n}/${decided} 轮，抖动 ${flake_n}）"
  else
    line="  ❌ ${SCENARIO_ID}：契约破坏（失败 ${fail_n}/${decided} 轮，抖动 ${flake_n}）"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi
  SUMMARY="${SUMMARY}${line}"$'\n'
done 3<<< "${SCENARIOS}"

printf '\n══════ 汇总（platform=%s repeat=%s）══════\n' "${PLATFORM}" "${REPEAT}"
printf '%s' "${SUMMARY}"
printf '生成时间：%s · 仓库版本：%s\n' \
  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(git -C "${EVALS_DIR}" rev-parse --short HEAD 2>/dev/null || printf '未知')"
# 仓库版本只说明「runner 在哪个 commit 上」，不说明「被测的是哪份代码」——两者必须分开写
if [ "${PLATFORM}" = "claude" ]; then
  if [ -n "${PLUGIN_DIR}" ]; then
    printf '被测插件：工作树 %s（--plugin-dir）\n' "${PLUGIN_DIR}"
  else
    printf '被测插件：已安装版本（未加 --plugin-dir；上面的仓库版本不代表被测代码）\n'
  fi
else
  printf '被测技能：已安装的 Codex 投影（~/.codex，不是工作树；发版前先 install.sh --target codex）\n'
fi

# 跑够没跑够，必须自己说出来。少跑而汇总照常收尾 = 把「没验」冒充成「验过」，
# 与 §「无法判定不得记为通过」是同一条纪律。
if [ "${RAN_N}" -ne "${EXPECT_N}" ]; then
  printf '❌ 只跑了 %s/%s 个场景——循环提前断流，本次结论不可用。\n' "${RAN_N}" "${EXPECT_N}" >&2
  exit 3
fi

if [ "${TOTAL_FAIL}" -gt 0 ]; then exit 1; fi
if [ "${TOTAL_INCONCLUSIVE}" -gt 0 ]; then exit 2; fi
exit 0
