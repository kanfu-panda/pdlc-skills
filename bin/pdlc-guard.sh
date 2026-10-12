#!/usr/bin/env bash
# pdlc-guard.sh —— PDLC 的可选 Claude Code hooks（hooks/hooks.json 调用），默认关闭
#
# 用法（由 Claude Code 调用，stdin 是 hook 事件 JSON）：
#   pdlc-guard.sh pre    PreToolUse（Write|Edit）：拦下直接写 docs/.pdlc-state/F*.json / B*.json
#   pdlc-guard.sh stop   Stop：对本次有改动的状态文件跑一次体检，有偏差就拦一次收尾，把结果交给模型去改
#
# 开关在目标项目的 docs/00_standards/pdlc-hooks.yml（/pdlc-settings hooks on|off 写入）：
#   state_write_guard: on    # pre 生效
#   lint_on_stop: on         # stop 生效
# 文件不存在、对应项不是 on、缺 jq、读不懂输入——一律放行（退出 0、不输出）。插件的 hooks 随插件启用
# 就会注册，没有单独关掉它们的开关，所以「默认不打扰」只能在这里自己做到。
#
# 这是护栏不是沙箱：在 Bash 里用 jq 重定向写状态文件，PreToolUse 拦不到；stop 的体检就是给这种情况兜底的。
# 兼容 macOS 自带的 bash 3.2。
set -u

MODE="${1:-}"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# 不在 skill 里时没有 scripts/，拒绝理由里一并给出插件自带的那份
ALT="${SELF_DIR}/pdlc-advance.sh"

command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat 2>/dev/null)" || exit 0
jq -e 'type == "object"' <<< "$INPUT" >/dev/null 2>&1 || exit 0

PROJ="${CLAUDE_PROJECT_DIR:-}"
[ -n "$PROJ" ] || PROJ="$(jq -r '.cwd // empty' <<< "$INPUT")"
[ -n "$PROJ" ] && [ -d "$PROJ" ] || exit 0
CONF="$PROJ/docs/00_standards/pdlc-hooks.yml"
[ -f "$CONF" ] || exit 0

enabled() { grep -qE "^[[:space:]]*$1:[[:space:]]*[\"']?(on|true|yes)[\"']?[[:space:]]*(#.*)?$" "$CONF"; }

case "$MODE" in
    pre)
        enabled state_write_guard || exit 0
        path="$(jq -r '.tool_input.file_path // empty' <<< "$INPUT")"
        case "$path" in
            */docs/.pdlc-state/F*.json|*/docs/.pdlc-state/B*.json|docs/.pdlc-state/F*.json|docs/.pdlc-state/B*.json) ;;
            *) exit 0 ;;
        esac
        jq -n --arg f "${path##*/}" --arg alt "$ALT" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
            permissionDecisionReason: ("状态文件 " + $f + " 只能经 pdlc-advance.sh 写入（它会自己跑检查、判 ok、整段写入）：skill 里用自带的 scripts/pdlc-advance.sh，不在 skill 里用 " + $alt + "。用法：bash <脚本> <功能ID> --stage <阶段短名> --next <下一跳命令名|null> [--produced …] <项目根>。本项目开了 PDLC 护栏（docs/00_standards/pdlc-hooks.yml 的 state_write_guard）。")}}'
        ;;
    stop)
        enabled lint_on_stop || exit 0
        [ "$(jq -r '.stop_hook_active // false' <<< "$INPUT")" = "true" ] && exit 0
        git -C "$PROJ" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
        changed="$(git -C "$PROJ" status --porcelain --untracked-files=all -- docs/.pdlc-state 2>/dev/null \
            | sed -E 's/^.{3}//; s/.* -> //' | sed -nE 's#^(.*/)?docs/\.pdlc-state/([FB][^/]*\.json)$#\2#p')"
        [ -n "$changed" ] || exit 0
        lint="$(bash "$SELF_DIR/pdlc-state-lint.sh" "$PROJ" 2>/dev/null)"
        hits="$(printf '%s\n' "$lint" | awk -F'\t' -v list="$changed" '
            BEGIN { n = split(list, a, "\n"); for (i = 1; i <= n; i++) want[a[i]] = 1 }
            ($1 in want) { print }')"
        [ -n "$hits" ] || exit 0
        jq -n --arg h "$hits" --arg alt "$ALT" '{decision: "block",
            reason: ("本次改动的状态文件没过契约体检（pdlc-state-lint.sh），先改正再收尾：\n" + $h + "\n推进阶段请用 pdlc-advance.sh（skill 里是自带的 scripts/pdlc-advance.sh，不在 skill 里用 " + $alt + "），不要手写状态 JSON。")}'
        ;;
    *) exit 0 ;;
esac
exit 0
