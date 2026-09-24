#!/usr/bin/env bash
# evals/run.sh 的驱动层回归测试（A-det：确定性代码，用桩测，不烧额度）。
#
# 守的是一条真实踩过的坑：runner 用 `done <<< "$SCENARIOS"` 把场景名喂在 stdin 上，
# 而循环体里调的 agent CLI **会读 stdin**（实测 `codex exec` 会把管道内容当额外输入
# 吃掉）。结果是——跑完第一个场景，剩下的场景名被 agent 喝干，循环静默结束，
# 汇总照常打印，看不出少跑了 3 个。**覆盖面缩水而报告照常收尾**，比直接报错坏得多。
#
# 本测试把 `codex` 换成一个「会读 stdin」的桩来复现该条件，断言：
#   1. 所有场景都真的跑到（少一个即红）
#   2. 桩什么都没产出时，结论是「无结论」(退出 2)，不冒充通过
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR" || exit 1
RUNNER="$SCRIPT_DIR/evals/run.sh"

pass=0
fail=0

if ! command -v jq >/dev/null 2>&1; then
    echo "⚠️  jq 未安装，跳过 evals runner 测试"
    exit 0
fi

expect_n="$(find evals/fixtures -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
if [[ "$expect_n" -lt 2 ]]; then
    echo "⚠️  场景不足 2 个（当前 ${expect_n}），断流 bug 无法体现，跳过"
    exit 0
fi

BIN="$(mktemp -d)"
trap 'rm -rf "$BIN"' EXIT
one="$(basename "$(find evals/fixtures -mindepth 1 -maxdepth 1 -type d | sort | head -1)")"

# 桩 codex：只做一件关键事——**读 stdin**。真 codex 就是这么干的；
# runner 若没把 agent 的 stdin 隔离掉，这一口就会把剩下的场景名喝走。
cat > "$BIN/codex" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null 2>&1
exit 0
STUB
chmod +x "$BIN/codex"

echo "Test: 场景循环不被 agent 抢走 stdin"

out="$(PATH="$BIN:$PATH" bash "$RUNNER" --platform codex </dev/null 2>&1)"
rc=$?
ran_n="$(grep -c '^══ ' <<< "$out")"

if [[ "$ran_n" -eq "$expect_n" ]]; then
    echo "  ✓ ${expect_n} 个场景全部跑到（agent 读 stdin 也没断流）"
    pass=$((pass + 1))
else
    echo "  ✗ 只跑了 ${ran_n}/${expect_n} 个场景——agent 抢走了 stdin，循环提前断流"
    echo "    修法：invoke_agent 的调用加 </dev/null，场景循环走 FD 3"
    fail=$((fail + 1))
fi

# 桩不产出任何状态机，所有场景只能是「无结论」。若这里出现 0（全通过），
# 说明断言在拿"什么都没发生"当通过——那是最危险的假绿。
if [[ "$rc" -eq 2 ]]; then
    echo "  ✓ 桩无产出 → 结论「无结论」(退出 2)，未冒充通过"
    pass=$((pass + 1))
else
    echo "  ✗ 桩无产出时退出码为 ${rc}，期望 2（无结论）"
    fail=$((fail + 1))
fi

# codex 臂只能测已安装的投影（~/.codex），汇总必须照实说，不能只盖一个仓库 commit 了事
if grep -qF '被测技能：已安装的 Codex 投影' <<< "$out"; then
    echo "  ✓ codex 臂汇总写明被测的是已安装投影"; pass=$((pass + 1))
else
    echo "  ✗ codex 臂汇总没写被测的是哪份技能"; fail=$((fail + 1))
fi

# 上面的行为断言只在**两道防线同时失守**时才变红（任一道单独还在，循环就不会断流）。
# 所以两道各配一条静态断言，单层被拆掉时就报出来，而不是等到都没了才发现。
if grep -q 'read -r s <&3' "$RUNNER" && grep -q 'done 3<<<' "$RUNNER"; then
    echo "  ✓ 第一道：场景循环走 FD 3（与 stdin 隔离）"
    pass=$((pass + 1))
else
    echo "  ✗ 第一道失守：场景循环仍从 stdin 读场景名"
    fail=$((fail + 1))
fi

# agent 分支有三条（claude / codex / copilot），每条都必须隔离 stdin
agent_calls="$(grep -c '2>&1 </dev/null' "$RUNNER")"
if [[ "$agent_calls" -eq 3 ]]; then
    echo "  ✓ 第二道：claude / codex / copilot 三条 agent 调用都带 </dev/null"
    pass=$((pass + 1))
else
    echo "  ✗ 第二道失守：只有 ${agent_calls}/3 条 agent 调用隔离了 stdin"
    fail=$((fail + 1))
fi

# ─── copilot 臂：测工作树的标准投影，装在 fixture 项目里 ───
# copilot 没有 --plugin-dir 这类开关，读的是 .agents/skills/。runner 必须把工作树构建出的
# Agent Skills 投影装进 fixture 副本自己的 .agents/skills/——测的是待合并的代码，也不碰用户的全局目录
echo ""
echo "Test: copilot 臂装工作树投影到 fixture 项目、按 skill 名触发"
cat > "$BIN/copilot" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$BIN/copilot-argv"
find .agents/skills -mindepth 1 -maxdepth 1 -name 'pdlc-*' 2>/dev/null | wc -l | tr -d ' ' > "$BIN/copilot-skills"
cat >/dev/null 2>&1
exit 0
STUB
chmod +x "$BIN/copilot"
rm -f "$BIN/copilot-argv" "$BIN/copilot-skills"
out="$(PATH="$BIN:$PATH" bash "$RUNNER" --platform copilot --only "$one" </dev/null 2>&1)"
if [[ "$(cat "$BIN/copilot-skills" 2>/dev/null)" == "36" ]]; then
    echo "  ✓ 调用时 fixture 项目的 .agents/skills 里有 36 个 pdlc skill"; pass=$((pass + 1))
else
    echo "  ✗ 调用时 fixture 项目里没有装好投影（看到 $(cat "$BIN/copilot-skills" 2>/dev/null || echo 0) 个）"; fail=$((fail + 1))
fi
if grep -qx -- '-p' "$BIN/copilot-argv" 2>/dev/null && grep -q '^按 pdlc ' "$BIN/copilot-argv" 2>/dev/null \
    && grep -qx -- '--allow-all-tools' "$BIN/copilot-argv" 2>/dev/null; then
    echo "  ✓ 以 copilot -p \"按 pdlc <阶段> …\" --allow-all-tools 调用"; pass=$((pass + 1))
else
    echo "  ✗ copilot 调用形态不对：$(tr '\n' ' ' < "$BIN/copilot-argv" 2>/dev/null)"; fail=$((fail + 1))
fi
if grep -qF '被测技能：工作树的 Agent Skills 投影' <<< "$out"; then
    echo "  ✓ 汇总写明被测的是工作树投影"; pass=$((pass + 1))
else
    echo "  ✗ copilot 臂汇总没写被测的是哪份技能"; fail=$((fail + 1))
fi


# ─── claude 臂默认测工作树，而不是已安装版本 ───
# 真事：一次发版前核验里，eval 汇总盖着「仓库版本：<HEAD>」，实际加载的却是已安装的上一个版本——
# /pdlc-* 解析到的是装好的插件。于是新规则的场景「失败」了，差点据此去改一个本来已经修好的问题。
# claude 有 --plugin-dir，可以直接加载工作树；这里断言它默认就这么做，并在汇总里说清楚测的是哪份。
echo ""
echo "Test: claude 臂默认加载工作树（--plugin-dir），汇总写明被测的是哪份插件"
cat > "$BIN/claude" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$BIN/claude-argv"
cat >/dev/null 2>&1
exit 0
STUB
chmod +x "$BIN/claude"

rm -f "$BIN/claude-argv"
out="$(PATH="$BIN:$PATH" bash "$RUNNER" --platform claude --only "$one" </dev/null 2>&1)"
if grep -qx -- '--plugin-dir' "$BIN/claude-argv" 2>/dev/null && grep -qxF "$SCRIPT_DIR" "$BIN/claude-argv" 2>/dev/null; then
    echo "  ✓ 默认把 --plugin-dir <仓库根> 传给 claude"; pass=$((pass + 1))
else
    echo "  ✗ 默认没有传 --plugin-dir <仓库根>——跑到的是已安装版本"; fail=$((fail + 1))
fi
if grep -qF '被测插件：工作树' <<< "$out"; then
    echo "  ✓ 汇总写明「被测插件：工作树」"; pass=$((pass + 1))
else
    echo "  ✗ 汇总没写被测的是工作树"; fail=$((fail + 1))
fi

# EVAL_PLUGIN_DIR 显式置空 → 测已安装版本（发版后回头验线上版本时用），汇总照实说
rm -f "$BIN/claude-argv"
out="$(EVAL_PLUGIN_DIR='' PATH="$BIN:$PATH" bash "$RUNNER" --platform claude --only "$one" </dev/null 2>&1)"
if grep -qx -- '--plugin-dir' "$BIN/claude-argv" 2>/dev/null; then
    echo "  ✗ EVAL_PLUGIN_DIR 置空仍传了 --plugin-dir"; fail=$((fail + 1))
else
    echo "  ✓ EVAL_PLUGIN_DIR 置空 → 不传 --plugin-dir"; pass=$((pass + 1))
fi
if grep -qF '被测插件：已安装版本' <<< "$out"; then
    echo "  ✓ 汇总写明「被测插件：已安装版本」"; pass=$((pass + 1))
else
    echo "  ✗ 汇总没写被测的是已安装版本"; fail=$((fail + 1))
fi

# 设了 CLAUDE_FLAGS 却没设 EVAL_CLAUDE_FLAGS：run.sh 读的是后者，前者会被静默覆盖——必须出声
out="$(CLAUDE_FLAGS='--model x' PATH="$BIN:$PATH" bash "$RUNNER" --platform claude --only "$one" </dev/null 2>&1)"
if grep -qF 'EVAL_CLAUDE_FLAGS' <<< "$out"; then
    echo "  ✓ 设了 CLAUDE_FLAGS 却没设 EVAL_CLAUDE_FLAGS → 告警"; pass=$((pass + 1))
else
    echo "  ✗ CLAUDE_FLAGS 被静默忽略，没有告警"; fail=$((fail + 1))
fi

echo ""
echo "Final: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
