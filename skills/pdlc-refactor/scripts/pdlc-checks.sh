#!/usr/bin/env bash
# pdlc-checks.sh —— 按 test-commands.yml 真跑 check 命令，把退出码按三态映射成状态机的 checks JSON
#
# 用法：bash pdlc-checks.sh [--only unit,coverage,lint,e2e] [--red] [项目根目录]   （项目根缺省为当前目录）
#
#   默认        跑全部四项，stdout 输出 {"tests_pass":…,"coverage_pass":…,"lint_clean":…,"e2e_pass":…}
#   --only      只跑列出的项（本阶段需要哪几项就列哪几项），输出只含对应的键，顺序固定
#   --red       tdd 红灯验证：只跑 unit，输出 {"red_verified":…}——方向与 tests_pass 相反，失败才是要的结果
#
# 三态（references/templates/prompts/check-commands.md）：
#   退出码 0                                → true
#   非 0（命令跑起来了，只是没过）            → false
#   126 / 127、命令为空、仍是模板占位 <…>     → null  （无法判定，多为 yml 过期；绝不能写成 false）
#
# 为什么要有它：键名、布尔类型、三态映射原先全靠模型读正文自己写，真机上同一 fixture 轮与轮之间
# 就换一种错法（键名照抄 yml 的 unit / lint、值写成「4 passed, 1 failed」、127 折成 false）。
# 这些都是确定性的事；模型只负责把 stdout 原样写进 last_phase_result.checks。
#
# 每条命令的退出码、判定与输出末尾回显在 stderr，完整输出存到 stderr 里给出的日志目录。
#
# 退出码：0 已跑完（结果好坏都是 0，看 JSON）· 2 无法执行（没有 yml、参数错误）——此时 stdout 为空。
# 不依赖 jq。兼容 macOS 自带的 bash 3.2（不用 mapfile / 关联数组）。
set -u

ALL_ITEMS="unit coverage lint e2e"
ONLY=""
RED=0
ROOT="."

usage() { sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//' >&2; }
die() { echo "pdlc-checks: $1" >&2; exit 2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --only) [ $# -ge 2 ] || die "--only 需要参数，如 --only unit,lint"; ONLY="$2"; shift 2 ;;
        --red) RED=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) usage; die "未知参数：$1" ;;
        *) ROOT="$1"; shift ;;
    esac
done

YML="$ROOT/docs/00_standards/test-commands.yml"
[ -f "$YML" ] || die "没有 ${YML}，无法判定任何 check（先跑 /pdlc-test-setup）"

if [ "$RED" = 1 ]; then
    ITEMS="unit"
elif [ -n "$ONLY" ]; then
    ITEMS=""
    for want in $ALL_ITEMS; do
        case ",$ONLY," in *",$want,"*) ITEMS="$ITEMS $want" ;; esac
    done
    for got in $(printf '%s' "$ONLY" | tr ',' ' '); do
        case " $ALL_ITEMS " in *" $got "*) ;; *) die "--only 里的「${got}」不是 check 项（只有 ${ALL_ITEMS}）" ;; esac
    done
else
    ITEMS="$ALL_ITEMS"
fi

# 取某一项的命令：认 key: "…" / key: '…' / key: 裸值（裸值去掉行尾 # 注释）
cmd_of() {
    awk -v k="$1" '
        $0 ~ "^"k"[ \t]*:" {
            v = $0; sub("^"k"[ \t]*:[ \t]*", "", v)
            q = substr(v, 1, 1)
            if (q == "\"" || q == "\047") {
                v = substr(v, 2); i = index(v, q)
                if (i > 0) v = substr(v, 1, i - 1)
            } else {
                sub(/[ \t]+#.*$/, "", v); sub(/[ \t]+$/, "", v)
            }
            print v; exit
        }' "$YML"
}

key_of() {
    case "$1" in
        unit) [ "$RED" = 1 ] && echo red_verified || echo tests_pass ;;
        coverage) echo coverage_pass ;;
        lint) echo lint_clean ;;
        e2e) echo e2e_pass ;;
    esac
}

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pdlc-checks.XXXXXX")" || die "无法创建日志目录"
json=""
stale=""
for item in $ITEMS; do
    cmd="$(cmd_of "$item")"
    key="$(key_of "$item")"
    log="$LOG_DIR/$item.log"
    case "$cmd" in
        ""|"<"*">")
            val=null
            echo "· ${item}: 未配置命令（空或仍是模板占位）→ ${key}=null（无法判定）" >&2
            stale="$stale $item"
            ;;
        *)
            ( cd "$ROOT" && bash -c "$cmd" ) >"$log" 2>&1 </dev/null
            rc=$?
            if [ "$rc" = 126 ] || [ "$rc" = 127 ]; then
                val=null; stale="$stale $item"
            elif [ "$rc" = 0 ]; then
                if [ "$RED" = 1 ]; then val=false; else val=true; fi
            else
                if [ "$RED" = 1 ]; then val=true; else val=false; fi
            fi
            echo "· ${item}: \`${cmd}\` → exit ${rc} → ${key}=${val}（完整输出：${log}）" >&2
            tail -n 15 "$log" | sed 's/^/    │ /' >&2
            ;;
    esac
    json="${json:+$json,}\"$key\":$val"
done

if [ -n "$stale" ]; then
    echo "⚠️ test-commands.yml 疑似过期：${stale# } 跑不了（126/127/空命令），判为「无法判定」而不是「没通过」。补救：/pdlc-test-setup --refresh" >&2
fi
if [ "$RED" = 1 ] && [ "$json" = '"red_verified":false' ]; then
    echo "⚠️ 意外全绿：新写的测试一条都没失败——测试没约束住待实现的行为（或代码早已存在），本阶段应阻塞交给人判断" >&2
fi

printf '{%s}\n' "$json"
