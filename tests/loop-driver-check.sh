#!/usr/bin/env bash
# 多功能收敛循环驱动 bin/pdlc-loop.sh 的回归测试（用假的 claude / codex，不花模型额度）。
#
# 覆盖：
#   - 用法守卫：没给功能也没 --ready、ID 与 --ready 同给、未知平台、非法数字参数、
#     claude 真跑缺 --max-budget-usd、状态机不存在 → 退出 64
#   - --ready 只挑机械收敛段里的功能（tdd / implement / review），跳过已收敛与阻塞的
#   - 串行：多个功能逐个收敛；总退出码取各功能最坏的那个；绝不调用 ship / deploy
#   - claude 平台：命令形态（/pdlc-<阶段> <ID> --autonomous、预算、按 skill 推荐的模型）
#   - depends_on：依赖先跑；依赖没收敛则跳过被依赖者；成环的全部跳过、不调用模型
#   - 并行：每个功能一个 git worktree，互不干扰；确实同时在跑；worktree 目录不污染 git status；
#     状态文件没提交的功能不进 worktree；依赖链在依赖方的 worktree 里接着跑
#   - 运行记录：git 项目记在 .git/pdlc-loop/，非 git 项目记在 docs/.pdlc-state/_loop/（体检不把它当状态机）
#   - --status：计数、每个功能一行、驱动进程已不在 / 单步过久的提示，不给预计完成时间
# shellcheck disable=SC2015  # ok / bad 恒返回 0，`条件 && ok || bad` 只在条件不成立时走 bad
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR" || exit 1
DRIVER="$SCRIPT_DIR/bin/pdlc-loop.sh"
# 驱动要兼容 macOS 自带的 bash 3.2：有 /bin/bash 就用它跑，免得 PATH 上的 bash 5 掩盖兼容问题
SH=bash; [[ -x /bin/bash ]] && SH=/bin/bash

pass=0
fail=0
ok()  { echo "  ✓ $1"; pass=$((pass + 1)); }
bad() { echo "  ✗ $1"; [[ -n "${2:-}" ]] && printf '    %s\n' "$2"; fail=$((fail + 1)); }

if ! command -v jq >/dev/null 2>&1; then
    echo "⚠️  jq 未安装，跳过循环驱动测试"
    exit 0
fi

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

# ─── 假的 claude / codex ───
# 两者都从各自的参数里取出「阶段 + 功能ID」，把调用记进 ${STUB_LOG}，再按 $STUB_PLAN
# （每行「功能ID 行为」）改写当前目录下的状态机。行为：advance（默认）/ failstop / stuck / error。
# STUB_SLEEP 秒数用来制造重叠，验证并行。
BIN="$ROOT/bin"
mkdir -p "$BIN"
cat > "$BIN/stub-core" <<'STUB'
#!/usr/bin/env bash
# 用法：stub-core <平台> <工作目录> <阶段> <功能ID> <完整参数…>
plat="$1" wd="$2" stage="$3" id="$4"; shift 4
printf '%s\t%s\t%s\t%s\tstart\t%s\n' "$plat" "$id" "$stage" "$wd" "$*" >> "$STUB_LOG"
[ -n "${STUB_SLEEP:-}" ] && sleep "$STUB_SLEEP"
beh="$(awk -v i="$id" '$1==i{print $2}' "${STUB_PLAN:-/dev/null}" 2>/dev/null | head -1)"
[ -z "$beh" ] && beh=advance
S="$wd/docs/.pdlc-state/$id.json"; tmp="$S.tmp"
case "$beh" in
  error) printf '%s\t%s\t%s\t%s\tend\n' "$plat" "$id" "$stage" "$wd" >> "$STUB_LOG"; exit 1 ;;
  failstop) jq '.last_phase_result={ok:false,blocked_reason:"stub failstop"}' "$S" > "$tmp" ;;
  stuck)    jq '.last_phase_result={ok:true,blocked_reason:null}' "$S" > "$tmp" ;;
  *)
    case "$stage" in
      tdd)       jq '.current_stage="tdd"   |.next_step="pdlc-implement"|.last_phase_result={ok:true,blocked_reason:null}' "$S" > "$tmp" ;;
      implement) jq '.current_stage="impl"  |.next_step="pdlc-review"   |.last_phase_result={ok:true,blocked_reason:null}' "$S" > "$tmp" ;;
      *)         jq '.current_stage="review"|.next_step="pdlc-ship"     |.last_phase_result={ok:true,blocked_reason:null}' "$S" > "$tmp" ;;
    esac ;;
esac
mv "$tmp" "$S"
printf '%s\t%s\t%s\t%s\tend\n' "$plat" "$id" "$stage" "$wd" >> "$STUB_LOG"
STUB
cat > "$BIN/claude" <<'STUB'
#!/usr/bin/env bash
# claude -p "/pdlc-<阶段> <ID> --autonomous" …
for a in "$@"; do case "$a" in /pdlc-*) cmd="$a" ;; esac; done
set -- $cmd; stage="${1#/pdlc-}"; id="$2"
exec "$(dirname "$0")/stub-core" claude "$PWD" "$stage" "$id" "$0 ${*} ${ALL_ARGS:-}"
STUB
cat > "$BIN/codex" <<'STUB'
#!/usr/bin/env bash
# codex exec -C <目录> … "按 pdlc <阶段> <ID> --autonomous"
wd="$PWD"; prev=""
for a in "$@"; do
  [ "$prev" = "-C" ] && wd="$a"
  case "$a" in "按 pdlc "*) cmd="$a" ;; esac
  prev="$a"
done
set -- $cmd; stage="$3"; id="$4"
exec "$(dirname "$0")/stub-core" codex "$wd" "$stage" "$id" "$*"
STUB
chmod +x "$BIN"/*
# claude 桩要看到完整参数（预算、模型）：用一层包装把 "$@" 记进 ALL_ARGS
mv "$BIN/claude" "$BIN/claude-inner"
cat > "$BIN/claude" <<'STUB'
#!/usr/bin/env bash
ALL_ARGS="$*" exec "$(dirname "$0")/claude-inner" "$@"
STUB
chmod +x "$BIN/claude"

# ─── 项目夹具 ───
# mkstate <项目> <ID> <current_stage> <next_step|null> [blocked_reason|null] [依赖ID,…]
mkstate() {
    local proj="$1" id="$2" stage="$3" nxt="$4" reason="${5:-null}" deps="${6:-}"
    mkdir -p "$proj/docs/.pdlc-state"
    jq -n --arg id "$id" --arg st "$stage" --arg nx "$nxt" --arg r "$reason" --arg d "$deps" '
      { feature_id: $id, feature_name: "demo", created_at: "2026-09-24T10:00:00+08:00",
        current_stage: $st, run_mode: "interactive",
        history: [ { stage: $st, done_at: "2026-09-24T10:00:00+08:00", produced: [] } ],
        last_phase_result: { stage: $st, ok: true, advanced_to: null, checks: {}, self_audit: { failed: 0 },
                             blocked_reason: (if $r == "null" then null else $r end), run_mode: "interactive",
                             at: "2026-09-24T10:00:00+08:00" },
        relations: { extends: [], depends_on: ($d | split(",") | map(select(. != ""))), supersedes: [],
                     resolves: [], conflicts_with: [], relates_to: [] },
        next_step: (if $nx == "null" then null else $nx end) }' > "$proj/docs/.pdlc-state/$id.json"
}
mkgit() {  # 把目录变成 git 仓库并提交全部内容
    git -C "$1" init -q -b main && git -C "$1" config user.name t && git -C "$1" config user.email t@t \
      && git -C "$1" add -A && git -C "$1" commit -q -m init
}
stage_of() { jq -r '.current_stage' "$1/docs/.pdlc-state/$2.json"; }

# run_driver <项目> [参数…] —— 输出进 ${OUT}，退出码进 ${RC}
run_driver() {
    local proj="$1"; shift
    OUT="$(cd "$proj" && PATH="$BIN:$PATH" STUB_LOG="$STUB_LOG" STUB_PLAN="${STUB_PLAN:-}" \
        STUB_SLEEP="${STUB_SLEEP:-}" PDLC_LOOP_POLL=0.2 "$SH" "$DRIVER" "$@" 2>&1)"
    RC=$?
}
expect_rc() {  # expect_rc <描述> <期望退出码>
    if [[ "${RC}" == "$2" ]]; then ok "$1（退出 ${RC}）"; else bad "$1（退出 ${RC}，期望 $2）" "$OUT"; fi
}
expect_out() {  # expect_out <描述> <应包含的文本>
    if grep -qF -- "$2" <<< "$OUT"; then ok "$1"; else bad "$1" "期望包含「${2}」，实际：$OUT"; fi
}
calls() { if [[ -f "$STUB_LOG" ]]; then grep -c "	start	" "$STUB_LOG"; else echo 0; fi; }

# ═══ 用法守卫 ═══
echo "Test: 用法守卫"
P="$ROOT/usage"; mkstate "$P" F20260924-100000 tdd pdlc-implement
STUB_LOG="$ROOT/usage.log"
run_driver "$P" --platform codex;                              expect_rc "没给功能也没 --ready" 64
run_driver "$P" F20260924-100000 --ready --platform codex;     expect_rc "功能ID 与 --ready 同给" 64
run_driver "$P" F20260924-100000 --platform cursor;            expect_rc "未知平台" 64
run_driver "$P" F20260924-100000 --platform codex --parallel 0; expect_rc "--parallel 非正整数" 64
run_driver "$P" F20260924-100000 --platform codex --max-steps x; expect_rc "--max-steps 非正整数" 64
run_driver "$P" F20260924-100000 --platform claude;            expect_rc "claude 真跑缺 --max-budget-usd" 64
expect_out "缺预算时说明原因" "--max-budget-usd"
run_driver "$P" F20260924-199999 --platform codex;             expect_rc "状态机不存在" 64
run_driver "$P" F20260924-100000;                              expect_rc "缺 --platform" 64
[[ "$(calls)" == "0" ]] && ok "用法错时一次模型都没调用" || bad "用法错时调用了模型"

# ═══ dry-run 与 --ready ═══
echo ""
echo "Test: dry-run 与 --ready 挑选"
P="$ROOT/ready"
mkstate "$P" F20260924-100001 tdd    pdlc-implement
mkstate "$P" F20260924-100002 impl   pdlc-review
mkstate "$P" F20260924-100003 review pdlc-ship               # 已收敛
mkstate "$P" F20260924-100004 impl   pdlc-review "等人确认"   # 阻塞
mkstate "$P" F20260924-100005 requirements pdlc-design       # 收敛段之前
mkstate "$P" F20260924-100006 ship_done pdlc-deploy          # 已发布
STUB_LOG="$ROOT/ready.log"
run_driver "$P" --ready --platform codex --dry-run
expect_rc "dry-run 只看决策" 0
expect_out "--ready 挑中 tdd 段的功能" "F20260924-100001"
expect_out "--ready 挑中 review 段的功能" "F20260924-100002"
for skip in F20260924-100003 F20260924-100004 F20260924-100005 F20260924-100006; do
    grep -qF "$skip" <<< "$OUT" && bad "--ready 不该挑 $skip" "$OUT" || ok "--ready 跳过 $skip"
done
expect_out "dry-run 打印将执行的命令" "按 pdlc implement F20260924-100001 --autonomous"
[[ "$(calls)" == "0" ]] && ok "dry-run 不调用模型" || bad "dry-run 调用了模型"
[[ ! -e "$P/docs/.pdlc-state/_loop" ]] && ok "dry-run 不写运行记录" || bad "dry-run 写了运行记录"
run_driver "$P" F20260924-100004 --platform codex --dry-run
expect_rc "显式给阻塞的功能 → dry-run 报 blocked" 2
expect_out "带出阻塞原因" "等人确认"

# ═══ 串行：codex ═══
echo ""
echo "Test: 串行收敛（codex）"
P="$ROOT/serial"
mkstate "$P" F20260924-110001 tdd  pdlc-implement
mkstate "$P" F20260924-110002 impl pdlc-review
STUB_LOG="$ROOT/serial.log"
run_driver "$P" F20260924-110001 F20260924-110002 --platform codex
expect_rc "两个功能都收敛" 0
[[ "$(stage_of "$P" F20260924-110001)" == review && "$(stage_of "$P" F20260924-110002)" == review ]] \
    && ok "两个功能都推进到 review" || bad "未都推进到 review"
[[ "$(calls)" == "3" ]] && ok "共 3 次调用（2 + 1）" || bad "调用次数 $(calls)，期望 3"
grep -q 'ship\|deploy' <(cut -f3 "$STUB_LOG") && bad "调用了 ship / deploy" || ok "绝不调用 ship / deploy"
[[ -d "$P/docs/.pdlc-state/_loop" ]] && ok "非 git 项目的运行记录在 docs/.pdlc-state/_loop/" || bad "非 git 项目没写运行记录"
lint_out="$(bash bin/pdlc-state-lint.sh "$P" 2>&1)"
grep -q '_loop' <<< "$lint_out" && bad "体检把 _loop 当成了状态机" "$lint_out" || ok "体检不理会 _loop/"
run_driver "$P" --status
expect_out "--status 汇总收敛数" "收敛 2"
expect_out "--status 每个功能一行" "F20260924-110002"
grep -q '预计\|ETA' <<< "$OUT" && bad "--status 不该给预计完成时间" "$OUT" || ok "--status 不给预计完成时间"

# ═══ 退出码与护栏 ═══
echo ""
echo "Test: 护栏与总退出码"
P="$ROOT/guard"
mkstate "$P" F20260924-120001 tdd pdlc-implement
mkstate "$P" F20260924-120002 tdd pdlc-implement
STUB_LOG="$ROOT/guard.log"
printf 'F20260924-120002 failstop\n' > "$ROOT/plan"
STUB_PLAN="$ROOT/plan" run_driver "$P" F20260924-120001 F20260924-120002 --platform codex
expect_rc "一个收敛、一个 fail-stop → 总退出 2" 2
[[ "$(stage_of "$P" F20260924-120001)" == review ]] && ok "fail-stop 不影响另一个功能" || bad "另一个功能被连累"
run_driver "$P" --status
expect_out "--status 列出阻塞原因" "stub failstop"
mkstate "$P" F20260924-120003 tdd pdlc-implement
run_driver "$P" F20260924-120003 --platform codex --max-steps 1
expect_rc "达步数上限 → 3" 3
mkstate "$P" F20260924-120004 tdd pdlc-implement
printf 'F20260924-120004 stuck\n' > "$ROOT/plan"
STUB_PLAN="$ROOT/plan" run_driver "$P" F20260924-120004 --platform codex
expect_rc "状态没推进 → 5" 5
mkstate "$P" F20260924-120005 tdd pdlc-implement
printf 'F20260924-120005 error\n' > "$ROOT/plan"
STUB_PLAN="$ROOT/plan" run_driver "$P" F20260924-120005 --platform codex
expect_rc "平台命令出错 → 4" 4

# ═══ claude 平台的命令形态 ═══
echo ""
echo "Test: claude 平台"
P="$ROOT/claude"
mkstate "$P" F20260924-130001 impl pdlc-review
STUB_LOG="$ROOT/claude.log"
run_driver "$P" F20260924-130001 --platform claude --max-budget-usd 3
expect_rc "claude 平台收敛" 0
line="$(grep '	start	' "$STUB_LOG" | head -1)"
grep -qF -- '/pdlc-review F20260924-130001 --autonomous' <<< "$line" && ok "命令是 /pdlc-review <ID> --autonomous" || bad "命令形态不对" "$line"
grep -qF -- '--max-budget-usd 3' <<< "$line" && ok "带上预算" || bad "没带预算" "$line"
grep -qF -- '--model sonnet' <<< "$line" && ok "按 skill 推荐的模型" || bad "没按推荐模型" "$line"

# ═══ depends_on ═══
echo ""
echo "Test: depends_on 排序与跳过"
P="$ROOT/deps"
mkstate "$P" F20260924-140001 impl pdlc-review null F20260924-140002   # 依赖 140002
mkstate "$P" F20260924-140002 impl pdlc-review
STUB_LOG="$ROOT/deps.log"
run_driver "$P" F20260924-140001 F20260924-140002 --platform codex
expect_rc "依赖链收敛" 0
first="$(grep '	start	' "$STUB_LOG" | head -1 | cut -f2)"
[[ "$first" == F20260924-140002 ]] && ok "被依赖的先跑（虽然排在后面）" || bad "先跑的是 $first"
P="$ROOT/deps-fail"
mkstate "$P" F20260924-141001 impl pdlc-review null F20260924-141002
mkstate "$P" F20260924-141002 impl pdlc-review
STUB_LOG="$ROOT/deps-fail.log"
printf 'F20260924-141002 failstop\n' > "$ROOT/plan"
STUB_PLAN="$ROOT/plan" run_driver "$P" F20260924-141001 F20260924-141002 --platform codex
expect_rc "依赖没收敛 → 总退出 2" 2
grep -q 'F20260924-141001' <(cut -f2 "$STUB_LOG") && bad "依赖没收敛还跑了依赖方" || ok "依赖没收敛就不跑依赖方"
run_driver "$P" --status
expect_out "--status 说明跳过原因" "依赖 F20260924-141002"
P="$ROOT/deps-cycle"
mkstate "$P" F20260924-142001 impl pdlc-review null F20260924-142002
mkstate "$P" F20260924-142002 impl pdlc-review null F20260924-142001
STUB_LOG="$ROOT/deps-cycle.log"
run_driver "$P" F20260924-142001 F20260924-142002 --platform codex
expect_rc "依赖成环 → 2" 2
[[ "$(calls)" == "0" ]] && ok "成环时一次模型都没调用" || bad "成环时调用了模型"
expect_out "说明成环" "成环"
P="$ROOT/deps-outside"
mkstate "$P" F20260924-143001 impl pdlc-review null F20260924-143002
mkstate "$P" F20260924-143002 design pdlc-tdd      # 不在本次运行里，也没收敛
STUB_LOG="$ROOT/deps-outside.log"
run_driver "$P" F20260924-143001 --platform codex
expect_rc "依赖不在本次运行且没收敛 → 2" 2
[[ "$(calls)" == "0" ]] && ok "不跑依赖未满足的功能" || bad "跑了依赖未满足的功能"

# ═══ 并行 + worktree ═══
echo ""
echo "Test: 并行（git worktree）"
P="$ROOT/par"
mkstate "$P" F20260924-150001 impl pdlc-review
mkstate "$P" F20260924-150002 impl pdlc-review
mkstate "$P" F20260924-150003 impl pdlc-review null F20260924-150001   # 依赖 150001
mkgit "$P"
mkstate "$P" F20260924-150004 impl pdlc-review                          # 未提交
STUB_LOG="$ROOT/par.log"
STUB_SLEEP=1 run_driver "$P" F20260924-150001 F20260924-150002 F20260924-150003 F20260924-150004 --platform codex --parallel 2
expect_rc "有功能因状态文件未提交被跳过 → 2" 2
W1="$P/.worktrees/pdlc-loop/F20260924-150001"; W2="$P/.worktrees/pdlc-loop/F20260924-150002"
[[ -d "$W1" && -d "$W2" ]] && ok "每个功能一个 worktree" || bad "没建 worktree" "$OUT"
[[ "$(stage_of "$W1" F20260924-150001)" == review && "$(stage_of "$W2" F20260924-150002)" == review ]] \
    && ok "worktree 里的功能推进到 review" || bad "worktree 里没推进"
[[ "$(stage_of "$P" F20260924-150001)" == impl ]] && ok "主工作区的状态文件不被改动" || bad "主工作区被改动"
[[ "$(git -C "$W1" branch --show-current)" == pdlc-loop/F20260924-150001 ]] \
    && ok "worktree 在 pdlc-loop/<ID> 分支上" || bad "分支名不对"
# 同时在跑：某个功能的 start 出现在另一个的 start 与 end 之间
overlap="$(awk -F'\t' '$5=="start"{s[$2]=NR} $5=="end"{e[$2]=NR} END{
    for (a in s) for (b in s) if (a!=b && s[b]>s[a] && s[b]<e[a]) {print "yes"; exit}}' "$STUB_LOG")"
[[ "$overlap" == yes ]] && ok "两个功能确实同时在跑" || bad "没有重叠，像是串行" "$(cat "$STUB_LOG")"
[[ "$(grep '	F20260924-150003	' "$STUB_LOG" | head -1 | cut -f4)" == "$W1" ]] \
    && ok "依赖方在被依赖方的 worktree 里接着跑" || bad "依赖方没在被依赖方的 worktree 里跑" "$(cat "$STUB_LOG")"
[[ "$(stage_of "$W1" F20260924-150003)" == review ]] && ok "依赖方也收敛" || bad "依赖方没收敛"
grep -q 'F20260924-150004' <(cut -f2 "$STUB_LOG") && bad "状态文件未提交的功能进了 worktree" || ok "状态文件未提交的功能不进 worktree"
st="$(git -C "$P" status --porcelain | grep -v 'F20260924-150004' || true)"
[[ -z "$st" ]] && ok "worktree 目录不出现在 git status 里" || bad "git status 有多余内容" "$st"
[[ -d "$P/.git/pdlc-loop" ]] && ok "git 项目的运行记录在 .git/pdlc-loop/" || bad "git 项目没把运行记录放 .git/pdlc-loop/"
run_driver "$P" --status
expect_out "--status 说明未提交的原因" "未提交"
expect_out "--status 指出产物所在 worktree" ".worktrees/pdlc-loop/F20260924-150001"

# ═══ 运行锁与中断 ═══
echo ""
echo "Test: 运行锁与中断"
P="$ROOT/lock"
mkstate "$P" F20260924-170001 impl pdlc-review
STUB_LOG="$ROOT/lock.log"
mkdir -p "$P/docs/.pdlc-state/_loop/lock"; echo $$ > "$P/docs/.pdlc-state/_loop/lock/pid"
run_driver "$P" F20260924-170001 --platform codex
expect_rc "已有循环在跑（锁里的进程还活着）→ 64" 64
expect_out "说明已有循环在跑" "已有一个循环在跑"
[[ "$(calls)" == "0" ]] && ok "被锁挡住时不调用模型" || bad "被锁挡住仍调用了模型"
echo 999999 > "$P/docs/.pdlc-state/_loop/lock/pid"
run_driver "$P" F20260924-170001 --platform codex
expect_rc "锁里的进程已不在 → 接管锁照常跑" 0
[[ ! -e "$P/docs/.pdlc-state/_loop/lock" ]] && ok "跑完释放锁" || bad "跑完没释放锁"
P="$ROOT/intr"
mkstate "$P" F20260924-171001 impl pdlc-review
STUB_LOG="$ROOT/intr.log"
( cd "$P" && PATH="$BIN:$PATH" STUB_LOG="$STUB_LOG" STUB_SLEEP=5 PDLC_LOOP_POLL=0.2 \
    exec "$SH" "$DRIVER" F20260924-171001 --platform codex > "$ROOT/intr.out" 2>&1 ) &
dpid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q 'start' "$STUB_LOG" 2>/dev/null && break; sleep 0.3; done
kill -TERM "$dpid"; wait "$dpid"; RC=$?; OUT="$(cat "$ROOT/intr.out")"
expect_rc "收到 SIGTERM → 130" 130
expect_out "说明已中断" "已中断"
[[ "$(stage_of "$P" F20260924-171001)" == impl ]] && ok "被打断的那一步没有写状态机" || bad "被打断的一步写了状态机"
run_driver "$P" --status
expect_out "--status 标出被中断的功能" "被中断"
expect_out "--status 显示这次运行已结束" "已结束"
[[ ! -e "$P/docs/.pdlc-state/_loop/lock" ]] && ok "中断后释放锁" || bad "中断后没释放锁"

# ═══ --status 的异常提示 ═══
echo ""
echo "Test: --status 提示"
P="$ROOT/status"; mkdir -p "$P/docs/.pdlc-state"
run_driver "$P" --status
expect_rc "没有运行记录 → 0" 0
[[ -z "$OUT" ]] && ok "没有运行记录时什么都不输出" || bad "没有运行记录却有输出" "$OUT"
# 伪造一次中断的运行：驱动进程已不在、某功能的这一步开始于 2 小时前
R="$P/docs/.pdlc-state/_loop/20260924-080000"; mkdir -p "$R"
printf '20260924-080000\n' > "$P/docs/.pdlc-state/_loop/latest"
now="$(date +%s)"
jq -n --argjson t "$((now - 7300))" --arg h "$(hostname)" '{run_id:"20260924-080000", started_ts:$t, finished_ts:null,
    pid:999999, host:$h, platform:"claude", parallel:1, max_steps:4, features:["F20260924-160001"]}' > "$R/run.json"
jq -n --argjson t "$((now - 7200))" '{id:"F20260924-160001", status:"running", stage:"impl", steps:2,
    started_ts:$t, step_started_ts:$t, finished_ts:null, note:"", workdir:"."}' > "$R/F20260924-160001.json"
run_driver "$P" --status
expect_out "驱动进程已不在 → 提示可能被中断" "中断"
expect_out "单步过久 → 提示看日志" "日志"
expect_out "运行中的功能标出阶段" "impl"

echo ""
echo "Final: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
