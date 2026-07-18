#!/usr/bin/env bash
# pdlc-statusline.sh —— PDLC 状态栏片段（自包含、只读、非 PDLC 项目吐空）
#
# 用法：
#   pdlc-statusline.sh              # 渲染模式：从 stdin 读 Claude Code 的 JSON，吐一行 PDLC 状态
#   pdlc-statusline.sh --install    # 在稳定路径 ~/.claude/pdlc-statusline 建符号链接指向本脚本
#   pdlc-statusline.sh --uninstall  # 移除该符号链接
#   pdlc-statusline.sh --help       # 帮助
#
# 设计契约（见 docs/decisions/0002-statusline-pdlc-status.md）：
#   - 默认关闭：只有用户把本脚本追加进其唯一的 statusLine.command 才生效
#   - 渲染 <10ms：非 PDLC 项目 / 无状态文件 → 立即吐空退出（快路径）
#   - 永不阻塞终端：任何异常（无 jq / 文件损坏 / 权限）→ 静默吐空，退出码 0
#   - 只读本地状态文件，绝不发起网络请求
#   - 多 feature 懒解析：按 mtime 只解析最近 N 个，blocked 只在窗口内抢显示权

set -uo pipefail

# ─── 稳定路径符号链接（升级不断） ───
STABLE_LINK="${HOME}/.claude/pdlc-statusline"

resolve_self() {
    # 解析本脚本的真实绝对路径（跟随符号链接）
    local src="${BASH_SOURCE[0]}" dir
    while [[ -L "$src" ]]; do
        dir="$(cd -P "$(dirname "$src")" && pwd)"
        src="$(readlink "$src")"
        [[ "$src" != /* ]] && src="$dir/$src"
    done
    cd -P "$(dirname "$src")" && printf '%s/%s\n' "$(pwd)" "$(basename "$src")"
}

do_install() {
    local self target_dir
    self="$(resolve_self)"
    target_dir="$(dirname "$STABLE_LINK")"
    mkdir -p "$target_dir"
    ln -sf "$self" "$STABLE_LINK"
    echo "✅ 已建立稳定链接：$STABLE_LINK → $self"
    echo "   请把 '$STABLE_LINK' 追加到你的 statusLine.command 后面（用 /pdlc-settings 可自动完成）。"
}

do_uninstall() {
    if [[ -L "$STABLE_LINK" ]]; then
        rm -f "$STABLE_LINK"
        echo "✅ 已移除稳定链接：$STABLE_LINK"
    else
        echo "ℹ️ 未发现稳定链接：$STABLE_LINK（无需移除）"
    fi
}

show_help() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
    --install)   do_install;   exit 0 ;;
    --uninstall) do_uninstall; exit 0 ;;
    --help|-h)   show_help;     exit 0 ;;
esac

# ─── 从这里起是渲染模式 ───

# jq 是软依赖：缺失即静默吐空（不给用户强加安装负担）
command -v jq >/dev/null 2>&1 || exit 0

# 读 stdin JSON，取当前目录；读失败 / 无输入 → 回退到 $PWD
input="$(cat 2>/dev/null || true)"
cwd=""
if [[ -n "$input" ]]; then
    cwd="$(printf '%s' "$input" | jq -r '(.workspace.current_dir // .cwd // empty)' 2>/dev/null || true)"
fi
[[ -z "$cwd" ]] && cwd="$PWD"

state_dir="$cwd/docs/.pdlc-state"

# 快路径：非 PDLC 项目 → 立即吐空
[[ -d "$state_dir" ]] || exit 0

# ─── 读配置（全局 + 项目级覆盖），解析一次 ───
CFG_GLOBAL="${HOME}/.claude/pdlc-statusline.json"
CFG_PROJECT="$state_dir/statusline.json"

# 合并配置：项目级覆盖全局；缺省用内置默认。全部一次 jq 解析完。
read_config() {
    local merged='{}'
    [[ -f "$CFG_GLOBAL" ]]  && merged="$(jq -s '.[0] * .[1]' <(echo "$merged") "$CFG_GLOBAL" 2>/dev/null || echo "$merged")"
    [[ -f "$CFG_PROJECT" ]] && merged="$(jq -s '.[0] * .[1]' <(echo "$merged") "$CFG_PROJECT" 2>/dev/null || echo "$merged")"
    printf '%s' "$merged"
}
CONFIG="$(read_config)"

cfg() {
    # cfg <key> <default>
    local v
    v="$(printf '%s' "$CONFIG" | jq -r --arg k "$1" '.[$k] // empty' 2>/dev/null || true)"
    [[ -z "$v" ]] && v="$2"
    printf '%s' "$v"
}

C_PROGRESS="$(cfg show_progress_bar true)"
C_NEXT="$(cfg show_next true)"
C_ICON="$(cfg show_run_icon true)"
C_CHECKS="$(cfg show_checks auto)"
C_ELAPSED="$(cfg show_elapsed auto)"
C_FULLID="$(cfg show_full_id false)"
C_PICK="$(cfg pick_feature auto)"
C_COLOR="$(cfg color true)"
C_WINDOW="$(cfg window 5)"

# 颜色关闭条件：配置 color=false 或环境 NO_COLOR
use_color=1
[[ "$C_COLOR" == "false" ]] && use_color=0
[[ -n "${NO_COLOR:-}" ]] && use_color=0

col() { # col <ansi-code> <text>
    if [[ "$use_color" == "1" ]]; then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi
}

# ─── 懒解析：按 mtime 取最近 N 个状态文件 ───
# ls -t 按修改时间新→旧排序，跨平台可用；剔除 statusline.json 后取前 N 个。
# 用 while-read 而非 mapfile（后者为 bash 4+，macOS 自带 bash 3.2 没有）。
files=()
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ "$(basename "$f")" == "statusline.json" ]] && continue
    files+=("$f")
    [[ ${#files[@]} -ge "$C_WINDOW" ]] && break
done < <(ls -t "$state_dir"/*.json 2>/dev/null)
[[ ${#files[@]} -eq 0 ]] && exit 0

# 每个文件解析成一行 TSV：id / name / stage / next / run_mode / blocked / unit / lint / cov / at
# 注意：布尔字段不能用 `// ""`——jq 的 `//` 把 false 也当空，会让「检查未通过」消失；
# 故对 tests_pass / lint_clean / coverage_pass 显式判 null。
parse_line() {
    jq -r '
        [ (.feature_id // ""),
          (.feature_name // ""),
          (.current_stage // ""),
          (.next_step // ""),
          (.run_mode // "interactive"),
          (.last_phase_result.blocked_reason // ""),
          (.last_phase_result.checks.tests_pass    | if . == null then "" else tostring end),
          (.last_phase_result.checks.lint_clean    | if . == null then "" else tostring end),
          (.last_phase_result.checks.coverage_pass | if . == null then "" else tostring end),
          (.last_phase_result.at // "")
        ] | @tsv' "$1" 2>/dev/null || true
}

is_terminal() { # <stage> <next>
    case "$1" in *_done) return 0 ;; esac
    [[ -z "$2" || "$2" == "null" ]] && return 0
    return 1
}

# ─── 选择要显示的 feature（§5.4 优先级） ───
pick=""          # 命中的 TSV 行
declare -a rows=()
for f in "${files[@]}"; do
    line="$(parse_line "$f")"
    [[ -z "$line" ]] && continue
    rows+=("$line")
done
[[ ${#rows[@]} -eq 0 ]] && exit 0

if [[ "$C_PICK" != "auto" && "$C_PICK" != "latest" ]]; then
    # 指定 ID
    for r in "${rows[@]}"; do
        id="$(printf '%s' "$r" | cut -f1)"
        [[ "$id" == "$C_PICK" ]] && { pick="$r"; break; }
    done
elif [[ "$C_PICK" == "latest" ]]; then
    pick="${rows[0]}"
fi

if [[ -z "$pick" ]]; then
    # auto：blocked（窗口内）优先 → 非终态最近 → 否则最近（终态，渲染 ✅）
    for r in "${rows[@]}"; do
        blocked="$(printf '%s' "$r" | cut -f6)"
        [[ -n "$blocked" ]] && { pick="$r"; break; }
    done
fi
if [[ -z "$pick" ]]; then
    for r in "${rows[@]}"; do
        stage="$(printf '%s' "$r" | cut -f3)"
        nxt="$(printf '%s' "$r" | cut -f4)"
        if ! is_terminal "$stage" "$nxt"; then pick="$r"; break; fi
    done
fi
[[ -z "$pick" ]] && pick="${rows[0]}"

# ─── 解出字段 ───
# 用 cut 而非 `IFS=$'\t' read`：tab 属空白字符，read 会把连续 tab（空字段）折叠、导致列错位。
F_ID="$(printf '%s' "$pick"    | cut -f1)"
F_NAME="$(printf '%s' "$pick"  | cut -f2)"
F_STAGE="$(printf '%s' "$pick" | cut -f3)"
F_NEXT="$(printf '%s' "$pick"  | cut -f4)"
F_MODE="$(printf '%s' "$pick"  | cut -f5)"
F_BLOCKED="$(printf '%s' "$pick" | cut -f6)"
F_UNIT="$(printf '%s' "$pick"  | cut -f7)"
F_LINT="$(printf '%s' "$pick"  | cut -f8)"
F_COV="$(printf '%s' "$pick"   | cut -f9)"
F_AT="$(printf '%s' "$pick"    | cut -f10)"

# 归一化 jq 的 "null"/"true"/"false"
norm() { [[ "$1" == "null" ]] && echo "" || echo "$1"; }
F_NEXT="$(norm "$F_NEXT")"
F_BLOCKED="$(norm "$F_BLOCKED")"

# 停留时长（分钟），解析失败则空
elapsed_str() {
    local at="$1" epoch now diff
    [[ -z "$at" ]] && return 0
    # 取 YYYY-MM-DDTHH:MM:SS 部分
    at="${at:0:19}"
    epoch=""
    if epoch="$(date -d "$at" +%s 2>/dev/null)"; then :
    elif epoch="$(date -j -f '%Y-%m-%dT%H:%M:%S' "$at" +%s 2>/dev/null)"; then :
    else return 0; fi
    now="$(date +%s)"
    diff=$(( now - epoch ))
    (( diff < 0 )) && diff=0
    if (( diff < 3600 )); then
        printf '⏱%dm' $(( diff / 60 ))
    elif (( diff < 86400 )); then
        printf '⏱%dh' $(( diff / 3600 ))
    else
        printf '⏱%dd' $(( diff / 86400 ))
    fi
}

# 显示名：默认 feature_name，配置 show_full_id 则用完整 ID
label="$F_NAME"
[[ "$C_FULLID" == "true" || -z "$label" ]] && label="$F_ID"

# ─── blocked 分支：全行最醒目 ───
if [[ -n "$F_BLOCKED" ]]; then
    reason="$F_BLOCKED"
    (( ${#reason} > 40 )) && reason="${reason:0:40}…"
    line="$(col '1;31' "⛔ PDLC")"
    line="$line $(col '1' "$label") $(col '31' "blocked: $reason")"
    el="$(elapsed_str "$F_AT")"
    [[ -n "$el" ]] && line="$line · $(col '90' "$el")"
    printf '%s\n' "$line"
    exit 0
fi

# ─── 正常分支 ───
line="$(col '36' "● PDLC")"
line="$line $(col '1' "$label")"

# 进度条
progress_done=0   # 进度条是否已渲染「✅ done」（终态），用于去掉运行图标里重复的 ✅
if [[ "$C_PROGRESS" == "true" ]]; then
    # 阶段序（短名 → 展示名）
    stages_key=(requirements design tdd impl review ship)
    stages_lbl=(PRD 设计 TDD 实现 评审 发布)
    if is_terminal "$F_STAGE" "$F_NEXT"; then
        line="$line · $(col '32' '✅ done')"
        progress_done=1
    else
        bar=""
        for i in "${!stages_key[@]}"; do
            seg="${stages_lbl[$i]}"
            if [[ "${stages_key[$i]}" == "$F_STAGE" ]]; then
                seg="[$(col '1;36' "$seg")]"
            else
                seg="$(col '90' "$seg")"
            fi
            [[ -n "$bar" ]] && bar="$bar$(col '90' '·')"
            bar="$bar$seg"
        done
        line="$line · $bar"
    fi
fi

# 下一步
if [[ "$C_NEXT" == "true" && -n "$F_NEXT" ]]; then
    nxt_short="${F_NEXT#pdlc-}"
    case "$nxt_short" in
        tdd)       nxt_lbl="TDD" ;;
        implement) nxt_lbl="实现" ;;
        review)    nxt_lbl="评审" ;;
        ship)      nxt_lbl="发布" ;;
        deploy)    nxt_lbl="部署" ;;
        design)    nxt_lbl="设计" ;;
        prd)       nxt_lbl="PRD" ;;
        *)         nxt_lbl="$nxt_short" ;;
    esac
    line="$line · $(col '33' "→$nxt_lbl")"
fi

# 运行图标（终态且进度条已显示「✅ done」时省略，避免重复 ✅）
if [[ "$C_ICON" == "true" ]]; then
    icon=""
    if is_terminal "$F_STAGE" "$F_NEXT"; then
        [[ "$progress_done" == "1" ]] || icon="✅"
    elif [[ "$F_MODE" == "autonomous" ]]; then
        icon="🤖"
    else
        icon="👤"
    fi
    [[ -n "$icon" ]] && line="$line · $icon"
fi

# 检查结果（auto → autonomous 才显示）
show_checks=0
case "$C_CHECKS" in
    true) show_checks=1 ;;
    auto) [[ "$F_MODE" == "autonomous" ]] && show_checks=1 ;;
esac
if [[ "$show_checks" == "1" ]]; then
    chk=""
    mark() { # <label> <value>
        if [[ "$2" == "true" ]]; then col '32' "✓$1"
        elif [[ "$2" == "false" ]]; then col '31' "✗$1"
        else printf ''; fi
    }
    for pair in "unit:$F_UNIT" "lint:$F_LINT" "cov:$F_COV"; do
        m="$(mark "${pair%%:*}" "${pair#*:}")"
        [[ -n "$m" ]] && chk="${chk:+$chk }$m"
    done
    [[ -n "$chk" ]] && line="$line · $chk"
fi

# 停留时长（auto → autonomous 才显示；blocked 已在上面处理）
show_elapsed=0
case "$C_ELAPSED" in
    true) show_elapsed=1 ;;
    auto) [[ "$F_MODE" == "autonomous" ]] && show_elapsed=1 ;;
esac
if [[ "$show_elapsed" == "1" ]]; then
    el="$(elapsed_str "$F_AT")"
    [[ -n "$el" ]] && line="$line · $(col '90' "$el")"
fi

printf '%s\n' "$line"
