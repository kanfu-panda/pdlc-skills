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
#   - 子进程节流：配置一把 jq、状态文件一把 jq、字段用 builtin read —— 全程 ≤3 个 jq
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

US=$'\037'   # Unit Separator：非空白分隔符，read 拆分时能保留空字段（tab 会被折叠）

# 读 stdin JSON，取当前目录；读失败 / 无输入 → 回退到 $PWD
input="$(cat 2>/dev/null || true)"
cwd=""
if [[ -n "$input" ]]; then
    cwd="$(printf '%s' "$input" | jq -r '(.workspace.current_dir // .cwd // empty)' 2>/dev/null || true)"
fi
[[ -z "$cwd" ]] && cwd="$PWD"

state_dir="$cwd/docs/.pdlc-state"

# 快路径：非 PDLC 项目 → 立即吐空（绝大多数刷新走这条，0 个 jq）
[[ -d "$state_dir" ]] || exit 0

# ─── 读配置（全局 + 项目级覆盖），一把 jq 解析完 → builtin read 进变量 ───
CFG_GLOBAL="${HOME}/.claude/pdlc-statusline.json"
CFG_PROJECT="$state_dir/statusline.json"

# 默认值（无配置文件时零 jq）
C_PROGRESS=true; C_NEXT=true; C_ICON=true; C_CHECKS=auto; C_ELAPSED=auto
C_FULLID=false;  C_PICK=auto; C_COLOR=true; C_WINDOW=5

cfg_files=()
[[ -f "$CFG_GLOBAL" ]]  && cfg_files+=("$CFG_GLOBAL")
[[ -f "$CFG_PROJECT" ]] && cfg_files+=("$CFG_PROJECT")
if [[ ${#cfg_files[@]} -gt 0 ]]; then
    # 一次 jq：合并（项目级覆盖全局）+ 取全部 9 个键（用 has 判在场，正确处理值为 false 的键）
    cfg_rec="$(jq -rs '
        def pick(o; k; dflt): if (o|has(k)) then (o[k]|tostring) else dflt end;
        (reduce .[] as $x ({}; . * $x)) as $c
        | [ pick($c;"show_progress_bar";"true"),
            pick($c;"show_next";"true"),
            pick($c;"show_run_icon";"true"),
            pick($c;"show_checks";"auto"),
            pick($c;"show_elapsed";"auto"),
            pick($c;"show_full_id";"false"),
            pick($c;"pick_feature";"auto"),
            pick($c;"color";"true"),
            pick($c;"window";"5") ] | join("")' "${cfg_files[@]}" 2>/dev/null || true)"
    if [[ -n "$cfg_rec" ]]; then
        IFS="$US" read -r C_PROGRESS C_NEXT C_ICON C_CHECKS C_ELAPSED C_FULLID C_PICK C_COLOR C_WINDOW <<< "$cfg_rec"
    fi
fi

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

# ─── 一把 jq 解析全部窗口内文件 → 每行一条 US 分隔记录 ───
# 字段：id / name / stage / next / run_mode / blocked / unit / lint / cov / at
# 关键点：
#   - 布尔字段（checks）不能用 `// ""`——jq 的 `//` 把 false 也当空，会让「检查未通过」消失；用 b() 显式判 null
#   - 字符串字段去掉换行/制表，保证一条记录一行、可被 read 逐行取
declare -a rows=()
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    rows+=("$line")
done < <(jq -r '
    def s(x): (x // "") | tostring | gsub("[\r\n\t]"; " ");
    def b(x): if x == null then "" else (x|tostring) end;
    [ s(.feature_id), s(.feature_name), s(.current_stage), s(.next_step),
      (.run_mode // "interactive"),
      s(.last_phase_result.blocked_reason),
      b(.last_phase_result.checks.tests_pass),
      b(.last_phase_result.checks.lint_clean),
      b(.last_phase_result.checks.coverage_pass),
      s(.last_phase_result.at)
    ] | join("")' "${files[@]}" 2>/dev/null)
[[ ${#rows[@]} -eq 0 ]] && exit 0

# 展示层的「终态」= current_stage 以 _done 结尾（feature_done / fix_done）。
# 不把 next_step==null 当终态：原子 fix 流程 next 恒为 null 却未完成，误判会显示「✅ done」。
is_terminal() { # <stage>
    case "$1" in *_done) return 0 ;; esac
    return 1
}

# ─── 选择要显示的 feature（§5.4 优先级），字段用 builtin read 取，不起子进程 ───
pick=""
if [[ "$C_PICK" != "auto" && "$C_PICK" != "latest" ]]; then
    for r in "${rows[@]}"; do
        IFS="$US" read -r rid _ _ _ _ _ _ _ _ _ <<< "$r"
        [[ "$rid" == "$C_PICK" ]] && { pick="$r"; break; }
    done
elif [[ "$C_PICK" == "latest" ]]; then
    pick="${rows[0]}"
fi
if [[ -z "$pick" ]]; then
    # auto 第一优先：blocked（窗口内）抢显示权
    for r in "${rows[@]}"; do
        IFS="$US" read -r _ _ _ _ _ rblocked _ _ _ _ <<< "$r"
        [[ -n "$rblocked" ]] && { pick="$r"; break; }
    done
fi
if [[ -z "$pick" ]]; then
    # auto 第二优先：最近的非终态
    for r in "${rows[@]}"; do
        IFS="$US" read -r _ _ rstage _ _ _ _ _ _ _ <<< "$r"
        if ! is_terminal "$rstage"; then pick="$r"; break; fi
    done
fi
[[ -z "$pick" ]] && pick="${rows[0]}"   # 全终态 → 最近一个（渲染 ✅）

# ─── 解出字段（一次 read；US 非空白，空字段不折叠） ───
IFS="$US" read -r F_ID F_NAME F_STAGE F_NEXT F_MODE F_BLOCKED F_UNIT F_LINT F_COV F_AT <<< "$pick"

# 当前时刻只取一次（elapsed 复用，省 date 子进程）
NOW_EPOCH="$(date +%s)"

# 停留时长，解析失败则空
elapsed_str() {
    local at="$1" epoch diff
    [[ -z "$at" ]] && return 0
    at="${at:0:19}"   # 取 YYYY-MM-DDTHH:MM:SS
    if   epoch="$(date -d "$at" +%s 2>/dev/null)"; then :
    elif epoch="$(date -j -f '%Y-%m-%dT%H:%M:%S' "$at" +%s 2>/dev/null)"; then :
    else return 0; fi
    diff=$(( NOW_EPOCH - epoch ))
    (( diff < 0 )) && diff=0
    if   (( diff < 3600 ));  then printf '⏱%dm' $(( diff / 60 ))
    elif (( diff < 86400 )); then printf '⏱%dh' $(( diff / 3600 ))
    else                          printf '⏱%dd' $(( diff / 86400 )); fi
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

# 进度条：固定「功能流水线」轨（PRD·设计·TDD·实现·评审·发布），高亮当前段。
# 诚实化：当前阶段不在该轨内时（如 fix 原子流程、自定义阶段）→ 只显阶段名，绝不硬套误导性 F 轨。
progress_done=0
if [[ "$C_PROGRESS" == "true" ]]; then
    if is_terminal "$F_STAGE"; then
        line="$line · $(col '32' '✅ done')"
        progress_done=1
    else
        stages_key=(requirements design tdd impl review ship)
        stages_lbl=(PRD 设计 TDD 实现 评审 发布)
        idx=-1
        for i in "${!stages_key[@]}"; do
            [[ "${stages_key[$i]}" == "$F_STAGE" ]] && { idx="$i"; break; }
        done
        if (( idx >= 0 )); then
            bar=""
            for i in "${!stages_key[@]}"; do
                seg="${stages_lbl[$i]}"
                if (( i == idx )); then seg="[$(col '1;36' "$seg")]"; else seg="$(col '90' "$seg")"; fi
                [[ -n "$bar" ]] && bar="$bar$(col '90' '·')"
                bar="$bar$seg"
            done
            line="$line · $bar"
        elif [[ -n "$F_STAGE" ]]; then
            # 非 F 流水线阶段（如 fix 流程）：只显当前阶段名，不伪造进度条
            line="$line · $(col '1;36' "$F_STAGE")"
        fi
    fi
fi

# 下一步
if [[ "$C_NEXT" == "true" && -n "$F_NEXT" && "$F_NEXT" != "null" ]]; then
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
    if is_terminal "$F_STAGE"; then
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
        if   [[ "$2" == "true" ]];  then col '32' "✓$1"
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
