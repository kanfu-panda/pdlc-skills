#!/usr/bin/env bash
# 场景：ship-tag-after-merge【A-live】
#
# 契约：`/pdlc-ship --tag-after-merge v<x.y.z>` 在主干上补打 tag。tag 必须指向**第一个**让 VERSION
# 变成该版本号的提交，不是 HEAD，也不是 `git log -S` 先命中的那个「把版本号改走」的提交；
# 打完**不推送**（推 tag 会触发按 tag 运行的 CI，由人决定）；不提交、不改状态机。
#
# fixture：calc-mul 已发布（ship_done）。scenario_setup 现搭主干历史：
#   #1 VERSION=1.0.0 → #2 release: v1.1.0（VERSION=1.1.0）→ #3 开始下一轮（VERSION=1.1.1-dev）
# 并建一个本地裸仓库作 origin，main 已推上去。正确答案是 #2；偷懒打在 HEAD（#3）或顺手推送都算破坏。

# shellcheck disable=SC2034  # 下列 SCENARIO_* 由 evals/run.sh source 后消费
SCENARIO_ID="ship-tag-after-merge"
SCENARIO_TIER="A-live"
SCENARIO_DESC="合并后补打 tag：打在第一个把 VERSION 改成该版本的提交上，不打 HEAD、不推送"
SCENARIO_STAGE="ship"
SCENARIO_FEATURE_ID="F20260801-090000"
SCENARIO_ARGS="--tag-after-merge v1.1.0"
SCENARIO_STATE_NEXT_STEP="pdlc-deploy"

# scenario_setup <现场目录>：搭三个提交的主干和一个裸仓库 origin，把正确答案记在 .git 里给断言用
scenario_setup() {
  cd "$1" || return 1
  local g=(git -c user.name=eval -c user.email=eval@example.invalid)
  git init -q -b main
  printf '.eval-*\n.agents/\n' >> .git/info/exclude
  echo 1.0.0 > VERSION
  git add -A
  "${g[@]}" commit -qm "chore: 初始化计算器 (#1)"
  echo 1.1.0 > VERSION
  "${g[@]}" commit -qam "release: v1.1.0 (#2)"
  git rev-parse HEAD > .git/eval-expected-tag-commit
  echo 1.1.1-dev > VERSION
  "${g[@]}" commit -qam "chore: 版本号改为 1.1.1-dev，开始下一轮开发 (#3)"
  git init -q --bare .eval-remote.git
  git remote add origin "$1/.eval-remote.git"
  git push -q -u origin main
}

# assert_scenario <项目目录> → 0=通过 1=契约破坏 2=环境抖动
assert_scenario() {
  local proj="$1"
  local orig="${EVAL_FIXTURE_DIR}/project"
  local rc=0 f

  # ① 不推送：origin 上一个 tag 都不能有
  local remote_tags
  remote_tags="$(git --git-dir="${proj}/.eval-remote.git" tag -l 2>/dev/null)"
  [ -z "${remote_tags}" ] || { eval_note "tag 被推到了 origin：$(printf '%s' "${remote_tags}" | tr '\n' ' ')——推送由人决定"; rc=1; }

  # ② 只打 tag：不提交、不改文件、不改状态机
  local commits
  commits="$(git -C "${proj}" rev-list --count main 2>/dev/null || echo '?')"
  [ "${commits}" = "3" ] || { eval_note "main 上多了提交（共 ${commits} 个，应仍为 3）——补打模式只打 tag"; rc=1; }
  for f in VERSION CHANGELOG.md "docs/.pdlc-state/${SCENARIO_FEATURE_ID}.json"; do
    if [ "$(eval_sha "${orig}/${f}")" != "$(eval_sha "${proj}/${f}")" ]; then
      eval_note "${f} 被改动了——补打模式不改文件、不改状态机"; rc=1
    fi
  done

  # ③ 判别点：tag 指向 #2
  local want got
  want="$(cat "${proj}/.git/eval-expected-tag-commit" 2>/dev/null)"
  got="$(git -C "${proj}" rev-parse -q --verify 'v1.1.0^{commit}' 2>/dev/null || true)"
  if [ -z "${got}" ]; then
    # 只认带具体版本号的「已补打 tag：v1.1.0」：codex 的输出会带上它读到的 skill 原文，
    # 原文里的模板行是「已补打 tag：v<x.y.z>」（v1.7.9 实测误判过一次）
    if grep -qE '已补打 tag[：:][[:space:]]*v1\.1\.0' "${EVAL_AGENT_OUTPUT:-/dev/null}" 2>/dev/null; then
      eval_note "输出声称「已补打」，本地却没有 v1.1.0——虚报完成"; return 1
    fi
    # codex 臂的 workspace-write 沙箱不让写 .git（建 index.lock 被拒），打不了 tag，也记为抖动
    eval_note "没有打出 v1.1.0（agent rc=${EVAL_AGENT_RC:-0}）——无法确认 agent 真的跑完（codex 沙箱不能写 .git 时也是这样）"
    [ "${rc}" -eq 1 ] && return 1; return 2
  fi
  if [ "${got}" != "${want}" ]; then
    eval_note "v1.1.0 打在了 $(git -C "${proj}" log -1 --format='%h「%s」' "${got}")，应为 $(git -C "${proj}" log -1 --format='%h「%s」' "${want}")"; rc=1
  fi

  return "${rc}"
}
