#!/usr/bin/env bash
# PDLC 多功能收敛循环驱动：把一个或多个功能各自推过机械收敛段 tdd → implement → review。
#
# 用法：
#   pdlc-loop.sh <功能ID>... --platform claude|codex [选项]
#   pdlc-loop.sh --ready     --platform claude|codex [选项]   # 挑出所有处于收敛段、未阻塞的功能
#   pdlc-loop.sh --status [--project DIR]                     # 看最近一次运行的进度
# 选项：
#   --parallel N          同时跑几个功能（默认 1）。N>1 时每个功能在自己的 git worktree 里跑
#   --max-steps N         每个功能至多跑几步（默认 4 = 3 段 + 1 步余量）
#   --max-budget-usd X    claude 平台每次调用的预算上限（claude 真跑时必填）
#   --project DIR, -C DIR 项目根目录（默认当前目录）
#   --dry-run             只打印每个功能的下一步决策，不调用模型、不写任何东西
# 退出码：0=全部收敛  2=有功能阻塞 / 被跳过  3=达步数上限  4=平台命令出错  5=状态没推进  64=用法错
#        （多个功能时取最大的那个）
#
# 每一步都是一个全新进程：claude -p "/pdlc-<阶段> <ID> --autonomous" 或
# codex exec "按 pdlc <阶段> <ID> --autonomous"。每步之后重读状态机判定：ok=false 即停（fail-stop），
# current_stage 没变即停（stuck-stop）。收敛 = next_step 为 pdlc-ship；**绝不调用 ship / deploy**，发布永远留人。
#
# depends_on：依赖先跑；依赖没收敛，依赖方就不跑。并行时依赖方在被依赖方的 worktree 里接着跑
# （这样看得到它的改动）；同时依赖两个本次运行中的功能则跳过，等合并后再单独跑。
#
# 运行记录：git 项目写在 <git 公共目录>/pdlc-loop/，非 git 项目写在 docs/.pdlc-state/_loop/。
# 每个功能一份记录 + 一份日志，/pdlc-status 通过 --status 读它们。
#
# 兼容 macOS 自带的 bash 3.2（不用关联数组、mapfile、wait -n）。
# shellcheck disable=SC2016  # 单引号里的 $x 是 jq 变量，不是 shell 变量
set -uo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM=""
PARALLEL=1
MAX_STEPS=4
BUDGET=""
PROJECT="$PWD"
DRY_RUN=0
READY=0
STATUS=0
IDS=""
POLL="${PDLC_LOOP_POLL:-2}"
STALE_MIN="${PDLC_LOOP_STALE_MIN:-45}"
# 可用环境变量整体替换 claude 的权限参数（默认与 evals 一致）
CLAUDE_FLAGS="${PDLC_LOOP_CLAUDE_FLAGS:---allowedTools Bash Read Write Edit Glob Grep}"

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}
die() { echo "错误：$1" >&2; exit 64; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform)       PLATFORM="${2:-}"; shift 2 || die "--platform 需要取值" ;;
        --parallel)       PARALLEL="${2:-}"; shift 2 || die "--parallel 需要取值" ;;
        --max-steps)      MAX_STEPS="${2:-}"; shift 2 || die "--max-steps 需要取值" ;;
        --max-budget-usd) BUDGET="${2:-}"; shift 2 || die "--max-budget-usd 需要取值" ;;
        --project|-C)     PROJECT="${2:-}"; shift 2 || die "--project 需要目录" ;;
        --dry-run)        DRY_RUN=1; shift ;;
        --ready)          READY=1; shift ;;
        --status)         STATUS=1; shift ;;
        -h|--help)        usage 0 ;;
        -*)               echo "未知参数：$1" >&2; usage 64 ;;
        *)                IDS="$IDS $1"; shift ;;
    esac
done

[[ -d "$PROJECT" ]] || die "项目目录不存在：$PROJECT"
PROJECT="$(cd "$PROJECT" && pwd)"
STATE_DIR="$PROJECT/docs/.pdlc-state"
command -v jq >/dev/null 2>&1 || die "需要 jq"

IS_GIT=0
COMMON=""
if git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1; then
    IS_GIT=1
    COMMON="$(cd "$PROJECT" && cd "$(git rev-parse --git-common-dir)" && pwd)"
    STORE="$COMMON/pdlc-loop"
else
    STORE="$STATE_DIR/_loop"
fi

# 字段分隔用 0x1F：tab 属于 IFS 空白，连续的空字段会被 read 合并、后面的字段整体错位
US=$'\x1f'
now() { date +%s; }
fmt_dur() {  # 秒 → 1h12m / 14m / 40s
    local s="$1"
    if [[ "$s" -ge 3600 ]]; then printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60))
    elif [[ "$s" -ge 60 ]]; then printf '%dm' $((s / 60))
    else printf '%ds' "$s"; fi
}
rel() {  # 项目内的路径显示成相对路径
    case "$1" in "$PROJECT") echo "." ;; "$PROJECT"/*) echo "${1#"$PROJECT"/}" ;; *) echo "$1" ;; esac
}

# ════════════════════════════ --status ════════════════════════════
if [[ "$STATUS" -eq 1 ]]; then
    [[ -f "$STORE/latest" ]] || exit 0
    RUN_ID="$(head -1 "$STORE/latest")"
    RD="$STORE/$RUN_ID"
    [[ -f "$RD/run.json" ]] || exit 0
    t="$(now)"
    IFS="$US" read -r r_start r_fin r_pid r_host r_plat r_par r_max <<< "$(jq -r '[.started_ts, (.finished_ts // ""), .pid, .host, .platform, .parallel, .max_steps] | map(tostring) | join("\u001f")' "$RD/run.json")"
    alive=unknown
    if [[ "$r_host" == "$(hostname)" ]]; then
        if kill -0 "$r_pid" 2>/dev/null; then alive=yes; else alive=no; fi
    fi
    if [[ -n "$r_fin" ]]; then label="已结束"; elapsed=$((r_fin - r_start))
    elif [[ "$alive" == no ]]; then label="未正常收尾"; elapsed=$((t - r_start))
    else label="运行中"; elapsed=$((t - r_start)); fi
    echo "🔁 循环运行 ${RUN_ID}（$r_plat · 并行 $r_par · 每个功能至多 $r_max 步）· 已用 $(fmt_dur "$elapsed") · $label"

    n=0 c_done=0 c_run=0 c_queue=0 c_block=0 c_skip=0 c_stop=0
    lines="" hints=""
    for id in $(jq -r '.features[]' "$RD/run.json"); do
        f="$RD/$id.json"
        [[ -f "$f" ]] || continue
        n=$((n + 1))
        IFS="$US" read -r st stage steps s_ts ss_ts f_ts note wd <<< "$(jq -r '[.status, (.stage // ""), (.steps // 0), (.started_ts // ""), (.step_started_ts // ""), (.finished_ts // ""), (.note // ""), (.workdir // "")] | map(tostring) | join("\u001f")' "$f")"
        dur=""
        [[ -n "$s_ts" ]] && dur="，用时 $(fmt_dur $(( ${f_ts:-$t} - s_ts )))"
        case "$st" in
            done)
                c_done=$((c_done + 1))
                lines="$lines  ✅ $id  ${stage}，待发布（$steps 步${dur}）"$'\n'
                if [[ -n "$wd" && "$wd" != "$PROJECT" && "$wd" != "." ]]; then
                    lines="$lines       产物在 $(rel "$wd")（分支 $(git -C "$wd" branch --show-current 2>/dev/null || echo "pdlc-loop/$id")），审阅合并后再 /pdlc-ship"$'\n'
                fi ;;
            running)
                c_run=$((c_run + 1))
                step_el=0; [[ -n "$ss_ts" ]] && step_el=$((t - ss_ts))
                lines="$lines  ▶ $id  $stage · 第 $steps 步，本步已 $(fmt_dur "$step_el")"$'\n'
                if [[ "$step_el" -gt $((STALE_MIN * 60)) ]]; then
                    hints="$hints  ⚠️ $id 这一步已跑 $(fmt_dur "$step_el")，超过 $STALE_MIN 分钟——看日志 $RD/$id.log"$'\n'
                fi ;;
            queued)
                c_queue=$((c_queue + 1))
                lines="$lines  ⏳ $id  排队${note:+（${note}）}"$'\n' ;;
            blocked)
                c_block=$((c_block + 1))
                lines="$lines  ⛔ $id  $note"$'\n' ;;
            skipped)
                c_skip=$((c_skip + 1))
                lines="$lines  ⏭ $id  $note"$'\n' ;;
            *)
                c_stop=$((c_stop + 1))
                lines="$lines  🛑 $id  ${note}（日志 $RD/$id.log）"$'\n' ;;
        esac
    done
    summary="  进度：$n 个功能 · ✅ 收敛 $c_done"
    [[ "$c_run" -gt 0 ]]   && summary="$summary · ▶ 运行中 $c_run"
    [[ "$c_queue" -gt 0 ]] && summary="$summary · ⏳ 排队 $c_queue"
    [[ "$c_block" -gt 0 ]] && summary="$summary · ⛔ 阻塞 $c_block"
    [[ "$c_skip" -gt 0 ]]  && summary="$summary · ⏭ 跳过 $c_skip"
    [[ "$c_stop" -gt 0 ]]  && summary="$summary · 🛑 停机 $c_stop"
    echo "$summary"
    printf '%s' "$lines"
    if [[ -z "$r_fin" && "$alive" == no ]]; then
        hints="  ⚠️ 驱动进程 $r_pid 已不在，但这次运行没有正常收尾（可能被中断）。记录停在中断那一刻；重跑同样的命令会从各功能当前阶段继续"$'\n'"$hints"
    elif [[ -z "$r_fin" && "$alive" == unknown ]]; then
        hints="  ℹ️ 驱动跑在另一台机器（${r_host}）上，这里无法判断它是否还在运行"$'\n'"$hints"
    fi
    [[ "$c_block" -gt 0 || "$c_skip" -gt 0 ]] && hints="$hints  · 阻塞 / 跳过的功能需要人处理，处理后重跑即可"$'\n'
    [[ "$c_done" -gt 0 ]] && hints="$hints  · 收敛的功能交人工 /pdlc-ship（循环永远不发布）"$'\n'
    [[ -n "$hints" ]] && printf '  提示：\n%s' "$hints"
    exit 0
fi

# ════════════════════════════ 参数校验 ════════════════════════════
case "$PLATFORM" in
    claude|codex) ;;
    "") die "缺 --platform（claude 或 codex）" ;;
    *)  die "未知平台 '$PLATFORM'（只支持 claude / codex）" ;;
esac
[[ "$PARALLEL" =~ ^[1-9][0-9]*$ ]]  || die "--parallel 需正整数（得到 '$PARALLEL'）"
[[ "$MAX_STEPS" =~ ^[1-9][0-9]*$ ]] || die "--max-steps 需正整数（得到 '$MAX_STEPS'）"
[[ -n "$IDS" && "$READY" -eq 1 ]] && die "功能ID 与 --ready 只能二选一"
[[ -z "$IDS" && "$READY" -eq 0 ]] && die "缺功能ID（或用 --ready 挑出所有处于收敛段的功能）"
[[ -d "$STATE_DIR" ]] || die "状态目录不存在：$STATE_DIR"
if [[ "$DRY_RUN" -eq 0 ]]; then
    if [[ "$PLATFORM" == claude ]]; then
        [[ -n "$BUDGET" ]] || die "claude 平台真跑必须给 --max-budget-usd（每次调用的预算上限）——自主循环持续花钱，预算是硬护栏"
        [[ "$BUDGET" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "--max-budget-usd 需数字（得到 '$BUDGET'）"
    fi
    command -v "$PLATFORM" >/dev/null 2>&1 || die "需要 $PLATFORM CLI（或用 --dry-run 看决策）"
    [[ "$PARALLEL" -gt 1 && "$IS_GIT" -eq 0 ]] && die "--parallel 大于 1 需要 git 仓库（每个功能在自己的 worktree 里跑）"
fi

# 与 pdlc-loop-next 同一张映射：以 next_step 为主键，blocked_reason / 终态优先。
# next_step 缺失或为 null → blocked：收敛段里没有阶段会合法写出 null，那只可能是状态残缺。
compute_next() {
    local n
    n="$(jq -r '
      if (.last_phase_result.blocked_reason // null) != null then "blocked"
      elif ((.current_stage // "") | endswith("_done")) then "done"
      else (.next_step // "null") as $ns
        | if ($ns == "pdlc-tdd" or $ns == "pdlc-implement" or $ns == "pdlc-review") then $ns
          elif ($ns == "pdlc-ship" or $ns == "pdlc-deploy") then "done"
          else "blocked" end
      end' "$1" 2>/dev/null)"
    case "$n" in
        pdlc-tdd|pdlc-implement|pdlc-review|done|blocked) printf '%s\n' "$n" ;;
        *) printf 'blocked\n' ;;
    esac
}

if [[ "$READY" -eq 1 ]]; then
    for f in "$STATE_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        b="$(basename "$f" .json)"
        case "$b" in _*|statusline) continue ;; esac
        case "$(compute_next "$f")" in pdlc-tdd|pdlc-implement|pdlc-review) IDS="$IDS $b" ;; esac
    done
    if [[ -z "$IDS" ]]; then
        echo "没有处于收敛段（tdd / implement / review）且未阻塞的功能，无事可做。"
        exit 0
    fi
fi
for id in $IDS; do
    [[ -f "$STATE_DIR/$id.json" ]] || die "状态机不存在：$STATE_DIR/$id.json"
done

in_run() { local x; for x in $IDS; do [[ "$x" == "$1" ]] && return 0; done; return 1; }
deps_of() {  # 只认形如功能 / 缺陷 ID 的依赖目标
    jq -r '(.relations.depends_on // []) | if type == "array" then .[] else empty end
           | select(type == "string" and test("^[FB][0-9]{8}-[0-9]+$"))' "$STATE_DIR/$1.json" 2>/dev/null
}
skill_model() {  # skill frontmatter 的 recommended_model（驱动从 bin/ 或某个 skill 的 scripts/ 运行都找得到）
    local f
    for f in "$SELF_DIR/../skills/pdlc-$1/SKILL.md" "$SELF_DIR/../../pdlc-$1/SKILL.md"; do
        [[ -f "$f" ]] && { sed -n 's/^recommended_model: *//p' "$f" | head -1; return 0; }
    done
}
platform_cmd() {  # platform_cmd <阶段短名> <ID> <工作目录> → 打印将执行的命令
    local short="$1" id="$2" wd="$3" m=""
    if [[ "$PLATFORM" == codex ]]; then
        printf 'codex exec -C "%s" -s workspace-write --skip-git-repo-check "按 pdlc %s %s --autonomous"\n' "$wd" "$short" "$id"
    else
        case "$CLAUDE_FLAGS" in *--model*) ;; *) m="$(skill_model "$short")" ;; esac
        printf '(cd "%s" && claude -p "/pdlc-%s %s --autonomous" --max-budget-usd %s%s %s)\n' \
            "$wd" "$short" "$id" "${BUDGET:-<预算>}" "${m:+ --model $m}" "$CLAUDE_FLAGS"
    fi
}

# ════════════════════════════ --dry-run ════════════════════════════
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "🔁 PDLC loop [dry-run]：平台=$PLATFORM  并行=$PARALLEL  每个功能至多 $MAX_STEPS 步  项目=$PROJECT"
    worst=0
    for id in $IDS; do
        for d in $(deps_of "$id"); do
            if in_run "$d"; then
                echo "[$id] 依赖 ${d}（本次运行中，等它收敛后再跑）"
            elif [[ ! -f "$STATE_DIR/$d.json" ]] || [[ "$(compute_next "$STATE_DIR/$d.json")" != "done" ]]; then
                echo "[$id] ⛔ 依赖 $d 不在本次运行里且尚未收敛——会被跳过"
                [[ "$worst" -lt 2 ]] && worst=2
            fi
        done
        next="$(compute_next "$STATE_DIR/$id.json")"
        case "$next" in
            done)
                echo "[$id] ✅ 已收敛到 review_done（或更后），无需再跑" ;;
            blocked)
                reason="$(jq -r '.last_phase_result.blocked_reason // empty' "$STATE_DIR/$id.json" 2>/dev/null)"
                echo "[$id] ⛔ blocked：${reason:-（状态机无法解析、结构残缺 / 缺 next_step，或 next_step 超出收敛段——需人工）}"
                [[ "$worst" -lt 2 ]] && worst=2 ;;
            *)
                wd="$PROJECT"
                [[ "$PARALLEL" -gt 1 ]] && wd="$PROJECT/.worktrees/pdlc-loop/$id"
                echo "[$id] 下一步 $next → 将执行：$(platform_cmd "${next#pdlc-}" "$id" "$wd")" ;;
        esac
    done
    exit "$worst"
fi

# ════════════════════════════ 真跑 ════════════════════════════
mkdir -p "$STORE" || die "无法创建运行记录目录 $STORE"
LOCK="$STORE/lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    other="$(cat "$LOCK/pid" 2>/dev/null)"
    if [[ -n "$other" ]] && kill -0 "$other" 2>/dev/null; then
        die "这个项目已有一个循环在跑（进程 ${other}）。两个循环同时写同一批状态机会互相覆盖"
    fi
    rm -rf "$LOCK"
    mkdir "$LOCK" 2>/dev/null || die "无法获取运行锁 $LOCK"
fi
echo $$ > "$LOCK/pid"

RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$STORE/$RUN_ID"
mkdir -p "$RUN_DIR"
printf '%s\n' "$RUN_ID" > "$STORE/latest"
jq -n --arg run "$RUN_ID" --argjson t "$(now)" --argjson pid $$ --arg host "$(hostname)" \
    --arg plat "$PLATFORM" --argjson par "$PARALLEL" --argjson max "$MAX_STEPS" \
    --arg ids "${IDS# }" \
    '{run_id:$run, started_ts:$t, finished_ts:null, pid:$pid, host:$host, platform:$plat,
      parallel:$par, max_steps:$max, features:($ids | split(" ")), exit_code:null}' > "$RUN_DIR/run.json"

rec() { printf '%s/%s.json' "$RUN_DIR" "$1"; }
rec_upd() {  # rec_upd <ID> <jq 参数…>：原子改写该功能的记录
    local f; f="$(rec "$1")"; shift
    jq "$@" "$f" > "$f.tmp.$$" && mv "$f.tmp.$$" "$f"
}
rec_get() { jq -r "$2 // empty" "$(rec "$1")" 2>/dev/null; }
for id in $IDS; do
    jq -n --arg id "$id" --arg stage "$(jq -r '.current_stage // ""' "$STATE_DIR/$id.json")" \
        '{id:$id, status:"queued", stage:$stage, steps:0, started_ts:null, step_started_ts:null,
          finished_ts:null, note:"", workdir:null, rc:null}' > "$(rec "$id")"
done

# 结束一个功能：写记录、打一行、以对应退出码退出（在 worker 子进程里调用）
finish() {  # finish <ID> <状态> <退出码> <说明> [当前阶段]
    rec_upd "$1" --arg st "$2" --argjson rc "$3" --arg note "$4" --arg stage "${5:-}" --argjson t "$(now)" \
        '.status=$st | .rc=$rc | .note=$note | .finished_ts=$t | (if $stage != "" then .stage=$stage else . end)'
    echo "[$1] $4"
    exit "$3"
}

run_feature() {  # run_feature <ID> <工作目录>（后台子进程）
    trap - EXIT INT TERM
    local id="$1" wd="$2" state="$2/docs/.pdlc-state/$1.json" log="$RUN_DIR/$1.log"
    local step=0 next short before after okv reason m
    rec_upd "$id" --argjson t "$(now)" '.started_ts=$t'
    while :; do
        next="$(compute_next "$state")"
        case "$next" in
            done)
                finish "$id" "done" 0 "✅ 收敛到 review_done（next_step=pdlc-ship）——交人工决定 /pdlc-ship" "$(jq -r '.current_stage // ""' "$state")" ;;
            blocked)
                reason="$(jq -r '.last_phase_result.blocked_reason // empty' "$state" 2>/dev/null)"
                finish "$id" blocked 2 "⛔ blocked：${reason:-状态机无法解析、结构残缺 / 缺 next_step，或 next_step 超出收敛段——需人工}" ;;
        esac
        step=$((step + 1))
        [[ "$step" -gt "$MAX_STEPS" ]] && finish "$id" capped 3 "🛑 达步数上限（${MAX_STEPS}）——停机防空转。下一步本该是 $next"
        short="${next#pdlc-}"
        before="$(jq -r '.current_stage // ""' "$state")"
        rec_upd "$id" --arg stage "$before" --argjson s "$step" --argjson t "$(now)" '.stage=$stage | .steps=$s | .step_started_ts=$t'
        echo "[$id] ▶ 第 $step 步：pdlc-${short}（当前 stage=${before}）"
        printf '\n===== 第 %s 步 pdlc-%s · %s =====\n' "$step" "$short" "$(date '+%F %T')" >> "$log"
        if [[ "$PLATFORM" == codex ]]; then
            codex exec -C "$wd" -s workspace-write --skip-git-repo-check "按 pdlc $short $id --autonomous" \
                < /dev/null >> "$log" 2>&1
        else
            m=""
            case "$CLAUDE_FLAGS" in *--model*) ;; *) m="$(skill_model "$short")" ;; esac
            # shellcheck disable=SC2086  # CLAUDE_FLAGS 按空白拆成多个参数
            (cd "$wd" && claude -p "/pdlc-$short $id --autonomous" --max-budget-usd "$BUDGET" \
                ${m:+--model "$m"} $CLAUDE_FLAGS < /dev/null >> "$log" 2>&1)
        fi || finish "$id" error 4 "❌ $PLATFORM 命令非零退出（pdlc-${short}）——停机，见日志 $log" "$before"
        # 状态机是唯一真源，不信平台的输出
        okv="$(jq -r '.last_phase_result.ok // "null"' "$state" 2>/dev/null)"
        after="$(jq -r '.current_stage // ""' "$state" 2>/dev/null)"
        if [[ "$okv" != true ]]; then
            finish "$id" blocked 2 "⛔ fail-stop：$(jq -r '.last_phase_result.blocked_reason // "last_phase_result.ok 不是 true"' "$state" 2>/dev/null)" "$after"
        fi
        [[ "$after" == "$before" ]] && finish "$id" stuck 5 "🛑 stuck-stop：current_stage 没推进（仍是 ${after}，违反 IRON LAW 第 6 条）" "$after"
        echo "[$id]    ✓ $before → $after"
    done
}

committed() {  # 状态文件已入库且与 HEAD 一致（worktree 从 HEAD 建，看得到的只有入库的版本）
    git -C "$PROJECT" ls-files --error-unmatch "docs/.pdlc-state/$1.json" >/dev/null 2>&1 &&
        git -C "$PROJECT" diff --quiet HEAD -- "docs/.pdlc-state/$1.json" 2>/dev/null
}
ensure_worktree() {  # ensure_worktree <ID> → 打印 worktree 路径；失败返回 1
    local id="$1" path="$PROJECT/.worktrees/pdlc-loop/$1" br="pdlc-loop/$1" ex="$COMMON/info/exclude"
    if [[ -e "$path/.git" ]]; then echo "$path"; return 0; fi
    mkdir -p "$COMMON/info"
    grep -qxF "/.worktrees/pdlc-loop/" "$ex" 2>/dev/null || echo "/.worktrees/pdlc-loop/" >> "$ex"
    if git -C "$PROJECT" show-ref --verify --quiet "refs/heads/$br"; then
        git -C "$PROJECT" worktree add -q "$path" "$br" >> "$RUN_DIR/$id.log" 2>&1 || return 1
    else
        git -C "$PROJECT" worktree add -q -b "$br" "$path" HEAD >> "$RUN_DIR/$id.log" 2>&1 || return 1
    fi
    echo "$path"
}

skip() {  # skip <ID> <说明>（主进程里调用）
    rec_upd "$1" --arg note "$2" --argjson t "$(now)" '.status="skipped" | .rc=2 | .note=$note | .finished_ts=$t'
    echo "[$1] ⏭ 跳过：$2"
}
pidfile() { printf '%s/.%s.pid' "$RUN_DIR" "$1"; }
alive_worker() { local p; p="$(cat "$(pidfile "$1")" 2>/dev/null)"; [[ -n "$p" ]] && kill -0 "$p" 2>/dev/null; }

# shellcheck disable=SC2329  # 由下面的 trap 调用
on_interrupt() {
    local id p
    for id in $IDS; do
        if alive_worker "$id"; then
            p="$(cat "$(pidfile "$id")")"
            pkill -TERM -P "$p" 2>/dev/null
            kill -TERM "$p" 2>/dev/null
            rec_upd "$id" --argjson t "$(now)" '.status="stopped" | .rc=4 | .note="被中断" | .finished_ts=$t'
        fi
    done
    jq --argjson t "$(now)" '.finished_ts=$t | .exit_code=130' "$RUN_DIR/run.json" > "$RUN_DIR/run.json.tmp" \
        && mv "$RUN_DIR/run.json.tmp" "$RUN_DIR/run.json"
    rm -rf "$LOCK"
    echo "⚠️ 已中断，正在跑的步骤已终止。重跑同样的命令会从各功能当前阶段继续。"
    exit 130
}
trap on_interrupt INT TERM
trap 'rm -rf "$LOCK"' EXIT

echo "🔁 PDLC loop：平台=$PLATFORM  并行=$PARALLEL  每个功能至多 $MAX_STEPS 步  功能：$(echo "$IDS" | wc -w | tr -d ' ') 个"
echo "   运行记录：${RUN_DIR}（看进度：$0 --status --project $(rel "$PROJECT")）"

# 调度：按给出的顺序扫描排队的功能，依赖满足且有空位就启动
while :; do
    active=0 pending=0 started=0
    for id in $IDS; do
        if [[ "$(rec_get "$id" .status)" == running ]]; then
            if alive_worker "$id"; then active=$((active + 1))
            elif [[ "$(rec_get "$id" .status)" == running ]]; then
                rec_upd "$id" --argjson t "$(now)" '.status="error" | .rc=4 | .note="worker 进程意外退出" | .finished_ts=$t'
            fi
        fi
    done
    for id in $IDS; do
        [[ "$(rec_get "$id" .status)" == queued ]] || continue
        pending=$((pending + 1))
        wait_dep=0 note="" indeps=""
        for d in $(deps_of "$id"); do
            if in_run "$d"; then
                case "$(rec_get "$d" .status)" in
                    queued|running) wait_dep=1 ;;
                    done) indeps="$indeps $d" ;;
                    *) note="依赖 $d 未收敛（$(rec_get "$d" .status)），不跑本功能" ;;
                esac
            elif [[ ! -f "$STATE_DIR/$d.json" ]]; then
                note="依赖 $d 的状态文件不存在"
            elif [[ "$(compute_next "$STATE_DIR/$d.json")" != "done" ]]; then
                note="依赖 $d 不在本次运行里，且尚未收敛（下一步 $(compute_next "$STATE_DIR/$d.json")）"
            fi
            [[ -n "$note" ]] && break
        done
        if [[ -n "$note" ]]; then skip "$id" "$note"; started=1; continue; fi
        [[ "$wait_dep" -eq 1 ]] && { rec_upd "$id" --arg n "等依赖收敛" '.note=$n'; continue; }
        [[ "$active" -ge "$PARALLEL" ]] && break

        if [[ "$PARALLEL" -eq 1 ]]; then
            wd="$PROJECT"
        else
            # shellcheck disable=SC2086  # indeps 按空白拆成依赖列表
            set -- $indeps
            if [[ $# -eq 0 ]]; then
                if ! committed "$id" && [[ ! -e "$PROJECT/.worktrees/pdlc-loop/$id/.git" ]]; then
                    skip "$id" "状态文件未提交或有未提交改动，worktree 里看不到最新状态——先提交再并行跑"; started=1; continue
                fi
                wd="$(ensure_worktree "$id")" || { skip "$id" "建 worktree 失败，见日志 $RUN_DIR/$id.log"; started=1; continue; }
            elif [[ $# -eq 1 ]]; then
                wd="$(rec_get "$1" .workdir)"
                if ! committed "$id"; then
                    skip "$id" "状态文件未提交或有未提交改动，依赖 $1 的 worktree 里看不到它——先提交再并行跑"; started=1; continue
                fi
                busy=0
                for o in $IDS; do
                    [[ "$(rec_get "$o" .status)" == running && "$(rec_get "$o" .workdir)" == "$wd" ]] && busy=1
                done
                [[ "$busy" -eq 1 ]] && continue
            else
                skip "$id" "依赖$indeps 在各自的 worktree 里收敛，改动还没合到一起——合并后再单独跑本功能"; started=1; continue
            fi
        fi
        rec_upd "$id" --arg wd "$wd" '.status="running" | .workdir=$wd | .note=""'
        run_feature "$id" "$wd" &
        echo $! > "$(pidfile "$id")"
        active=$((active + 1)) started=1
    done
    [[ "$pending" -eq 0 && "$active" -eq 0 ]] && break
    if [[ "$active" -eq 0 && "$started" -eq 0 ]]; then
        # 没有在跑的、也启动不了新的：剩下的都在等彼此
        for id in $IDS; do
            [[ "$(rec_get "$id" .status)" == queued ]] && skip "$id" "依赖成环（或依赖了成环的功能），无法排出先后"
        done
        break
    fi
    sleep "$POLL"
done
wait 2>/dev/null

worst=0
for id in $IDS; do
    r="$(rec_get "$id" .rc)"
    [[ -n "$r" && "$r" -gt "$worst" ]] && worst="$r"
done
jq --argjson t "$(now)" --argjson rc "$worst" '.finished_ts=$t | .exit_code=$rc' "$RUN_DIR/run.json" > "$RUN_DIR/run.json.tmp" \
    && mv "$RUN_DIR/run.json.tmp" "$RUN_DIR/run.json"
echo ""
bash "$0" --status --project "$PROJECT"
exit "$worst"
