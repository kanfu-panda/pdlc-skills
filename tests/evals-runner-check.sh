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

# 上面的行为断言只在**两道防线同时失守**时才变红（任一道单独还在，循环就不会断流）。
# 所以两道各配一条静态断言，单层被拆掉时就报出来，而不是等到都没了才发现。
if grep -q 'read -r s <&3' "$RUNNER" && grep -q 'done 3<<<' "$RUNNER"; then
    echo "  ✓ 第一道：场景循环走 FD 3（与 stdin 隔离）"
    pass=$((pass + 1))
else
    echo "  ✗ 第一道失守：场景循环仍从 stdin 读场景名"
    fail=$((fail + 1))
fi

# agent 分支有两条（claude / codex），两条都必须隔离 stdin
agent_calls="$(grep -c '2>&1 </dev/null' "$RUNNER")"
if [[ "$agent_calls" -eq 2 ]]; then
    echo "  ✓ 第二道：claude / codex 两条 agent 调用都带 </dev/null"
    pass=$((pass + 1))
else
    echo "  ✗ 第二道失守：只有 ${agent_calls}/2 条 agent 调用隔离了 stdin"
    fail=$((fail + 1))
fi

echo ""
echo "Final: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
