#!/usr/bin/env bash
# pdlc-advance.sh —— 阶段收尾时推进状态机的唯一写入口：自己跑检查、自己判 ok、整段写入
#
# 用法：bash pdlc-advance.sh <功能ID> --stage <阶段短名> --next <下一跳命令名|null> [选项] [项目根]
#
#   --produced a,b          本阶段产物（相对项目根，逗号分隔）
#   --blocked "<原因>"       主动交还人类：照跑检查如实记录，但不推进，原因写进 blocked_reason
#   --decision "<点>=<选择>" autonomous 下自动前进的确认点，可重复，记进 auto_decisions
#   --autonomous            本次调用带了 --autonomous（写进 run_mode）
#   --name <kebab-case>     状态文件还不存在时必填（新建）
#   --done                  写 <阶段>_done：只给 ship（ship_done）与 deploy（deploy_done）用
#   --tests-changed "<理由>" impl / refactor / review 改动了 tdd 阶段写的测试时必须给，理由记进 auto_decisions
#   --self-audit P,F,M      自检通过 / 未通过 / 需人工 的条数（仅供参考，不影响 ok）
#
# 各阶段跑哪些检查由本脚本按阶段决定，调用方不能挑：
#   tdd → 红灯验证（--red）· impl / fix / refactor → unit,coverage,lint · review → unit,coverage,lint,e2e
#   e2e → e2e · requirements / design / ship / deploy / feature → 不跑
# 项目没有 docs/00_standards/test-commands.yml → checks 写 {}（无法客观判定，与旧规则一致，不当作失败）。
#
# ok 的判定：tdd 要求 red_verified=true；其它阶段任一检查为 false 即不推进（null = 无法判定，不拦）。
# 测试指纹：tdd 推进时记下它写的测试文件的哈希；impl / refactor / review 推进时重算，变了就不推进，
# 除非带 --tests-changed（此时以改后的内容作新基准）。没有指纹的旧功能不比对。
#
# 退出码：0 已推进 · 3 未推进（检查没过、主动 block、测试被改）· 2 无法执行（参数错、缺 jq、状态文件损坏）
# stdout 一行 JSON：{"ok":…,"current_stage":…,"next_step":…,"checks":…,"blocked_reason":…}
# 兼容 macOS 自带的 bash 3.2。
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
LEGAL_STAGES="requirements design tdd impl review e2e ship deploy fix refactor feature"

die() { echo "pdlc-advance: $1" >&2; exit 2; }
usage() { sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//' >&2; }

FID=""; STAGE=""; NEXT=""; NEXT_SET=0; PRODUCED=""; BLOCKED=""; AUTONOMOUS=0; NAME=""; DONE=0
TESTS_CHANGED=""; SELF_AUDIT=""; ROOT="."; DECISIONS="[]"

need() { [ $# -ge 2 ] && [ -n "$2" ] || die "$1 需要一个值"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --stage)         need "$@"; STAGE="$2"; shift 2 ;;
        --next)          need "$@"; NEXT="$2"; NEXT_SET=1; shift 2 ;;
        --produced)      need "$@"; PRODUCED="$2"; shift 2 ;;
        --blocked)       need "$@"; BLOCKED="$2"; shift 2 ;;
        --decision)      need "$@"; DECISIONS="$(jq -c --arg d "$2" '. + [$d]' <<< "$DECISIONS" 2>/dev/null)" \
                           || die "缺 jq，无法推进状态机"; shift 2 ;;
        --autonomous)    AUTONOMOUS=1; shift ;;
        --name)          need "$@"; NAME="$2"; shift 2 ;;
        --done)          DONE=1; shift ;;
        --tests-changed) need "$@"; TESTS_CHANGED="$2"; shift 2 ;;
        --self-audit)    need "$@"; SELF_AUDIT="$2"; shift 2 ;;
        -h|--help)       usage; exit 0 ;;
        -*)              usage; die "未知参数：$1" ;;
        *)               if [ -z "$FID" ]; then FID="$1"; else ROOT="$1"; fi; shift ;;
    esac
done

command -v jq >/dev/null 2>&1 || die "缺 jq，无法推进状态机（按 state-update 规则手写，并在报告里写明「未经脚本」）"
printf '%s' "$FID" | grep -qE '^[FB][0-9]{8}-([0-9]{6}|[0-9]{2})$' || die "功能ID「${FID}」不合法（F/B<YYYYMMDD>-<HHMMSS>）"
case " $LEGAL_STAGES " in *" $STAGE "*) ;; *) die "--stage「${STAGE}」不是阶段短名（${LEGAL_STAGES}）" ;; esac
[ "$NEXT_SET" = 1 ] || die "缺 --next（下一跳命令名；流程结束写 null）"
[ "$NEXT" = "null" ] || printf '%s' "$NEXT" | grep -qE '^pdlc-[a-z][a-z-]*$' || die "--next「${NEXT}」不是命令名"
if [ "$DONE" = 1 ]; then
    case "$STAGE" in ship|deploy) ;; *) die "--done 只用于 ship / deploy（_done 的含义是已发布）" ;; esac
fi
if [ -n "$SELF_AUDIT" ]; then
    printf '%s' "$SELF_AUDIT" | grep -qE '^[0-9]+,[0-9]+,[0-9]+$' || die "--self-audit 应为 通过,未通过,需人工（如 12,0,1）"
fi

STATE="$ROOT/docs/.pdlc-state/$FID.json"
if [ -f "$STATE" ]; then
    jq -e 'type == "object"' "$STATE" >/dev/null 2>&1 || die "${STATE} 不是合法的 JSON 对象，不覆盖它（先修好或交给人）"
else
    [ -n "$NAME" ] || die "${STATE} 不存在，新建需要 --name <kebab-case>"
fi

# 下一跳命令名 → 下一阶段短名。与 state-update.md 的 stage-map 表一致（tests/advance-check.sh 钉住）
advanced_short() {
    case "$1" in
        pdlc-tdd) echo tdd ;; pdlc-implement) echo impl ;; pdlc-review) echo review ;;
        pdlc-design) echo design ;; pdlc-ship) echo ship ;; pdlc-deploy) echo deploy ;;
        *) echo "" ;;
    esac
}
if [ "$NEXT" != "null" ] && [ -z "$(advanced_short "$NEXT")" ]; then
    die "--next「${NEXT}」不在阶段映射表里（pdlc-tdd / pdlc-implement / pdlc-review / pdlc-design / pdlc-ship / pdlc-deploy）"
fi

NOW="$(date +%Y-%m-%dT%H:%M:%S%z | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/')"

sha_of() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    else sha256sum "$1" | awk '{print $1}'; fi
}

# ─── 检查 ───
CHECKS="{}"
OK=1
REASON=""
# --blocked 也照跑本阶段的检查：交还人类时状态里照样要有如实的检查结果（v1.7.10 实测：
# 模型发现测试自相矛盾后带 --blocked 收尾，若不跑检查，tests_pass=false 这条事实就丢了）
if :; then
    case "$STAGE" in
        tdd)                ARGS="--red" ;;
        impl|fix|refactor)  ARGS="--only unit,coverage,lint" ;;
        review)             ARGS="--only unit,coverage,lint,e2e" ;;
        e2e)                ARGS="--only e2e" ;;
        *)                  ARGS="" ;;
    esac
    if [ -n "$ARGS" ]; then
        [ -f "$SELF_DIR/pdlc-checks.sh" ] || die "找不到同目录的 pdlc-checks.sh"
        # shellcheck disable=SC2086  # ARGS 需要词分割
        out="$(bash "$SELF_DIR/pdlc-checks.sh" $ARGS "$ROOT")"; crc=$?
        if [ "$crc" -eq 0 ] && jq -e 'type == "object"' <<< "$out" >/dev/null 2>&1; then
            CHECKS="$out"
        elif [ "$crc" -eq 2 ]; then
            echo "pdlc-advance: 没有可跑的 check（多为项目没有 test-commands.yml），checks 写 {}" >&2
        else
            die "pdlc-checks.sh 异常（退出 ${crc}），未写状态机"
        fi
    fi
    if [ -n "$BLOCKED" ]; then
        OK=0; REASON="$BLOCKED"
    elif [ "$STAGE" = "tdd" ] && [ "$CHECKS" != "{}" ]; then
        if [ "$(jq -r '.red_verified | tostring' <<< "$CHECKS")" != "true" ]; then
            OK=0
            REASON="红灯未验证：red_verified=$(jq -r '.red_verified | tostring' <<< "$CHECKS")（false = 新测试意外全绿，null = 测试命令跑不了）"
        fi
    else
        failed="$(jq -r '[to_entries[] | select(.value == false) | .key] | join("、")' <<< "$CHECKS")"
        if [ -n "$failed" ]; then OK=0; REASON="检查未通过：${failed} 为 false"; fi
    fi
fi

# ─── 测试指纹 ───
FINGERPRINT="null"
if [ "$OK" = 1 ] && [ "$STAGE" = "tdd" ] && [ -n "$PRODUCED" ]; then
    FINGERPRINT="{}"
    oldifs="$IFS"; IFS=','
    for p in $PRODUCED; do
        p="$(printf '%s' "$p" | sed 's/^ *//; s/ *$//')"
        case "$p" in docs/*|"") continue ;; esac
        [ -f "$ROOT/$p" ] || continue
        FINGERPRINT="$(jq -c --arg k "$p" --arg v "$(sha_of "$ROOT/$p")" '. + {($k): $v}' <<< "$FINGERPRINT")"
    done
    IFS="$oldifs"
    [ "$FINGERPRINT" = "{}" ] && FINGERPRINT="null"
fi
if [ "$OK" = 1 ] && [ -f "$STATE" ]; then
    case "$STAGE" in impl|refactor|review)
        fp="$(jq -c '[.history[]? | select(type == "object" and (.tests_fingerprint | type) == "object")] | last | .tests_fingerprint // empty' "$STATE")"
        if [ -n "$fp" ]; then
            changed=""
            while IFS="$(printf '\t')" read -r path want; do
                [ -n "$path" ] || continue
                if [ ! -f "$ROOT/$path" ]; then changed="${changed}${changed:+、}${path}（已删除）"
                elif [ "$(sha_of "$ROOT/$path")" != "$want" ]; then changed="${changed}${changed:+、}${path}"; fi
            done <<< "$(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<< "$fp")"
            if [ -n "$changed" ]; then
                if [ -n "$TESTS_CHANGED" ]; then
                    DECISIONS="$(jq -c --arg d "改动 tdd 写的测试（${changed}）=${TESTS_CHANGED}" '. + [$d]' <<< "$DECISIONS")"
                    # 认可了这次改动，就以改后的内容作新基准，后面的阶段对它比对，不再反复拦同一处
                    FINGERPRINT="{}"
                    while IFS= read -r path; do
                        [ -n "$path" ] && [ -f "$ROOT/$path" ] || continue
                        FINGERPRINT="$(jq -c --arg k "$path" --arg v "$(sha_of "$ROOT/$path")" '. + {($k): $v}' <<< "$FINGERPRINT")"
                    done <<< "$(jq -r 'keys[]' <<< "$fp")"
                    [ "$FINGERPRINT" = "{}" ] && FINGERPRINT="null"
                else
                    OK=0
                    REASON="tdd 阶段写的测试被改动：${changed}。实现阶段不改测试；确需改动，带 --tests-changed \"<理由>\" 重跑，理由会记进 auto_decisions 给人看"
                fi
            fi
        fi
        ;;
    esac
fi

# ─── 写入 ───
RUN_MODE="interactive"; [ "$AUTONOMOUS" = 1 ] && RUN_MODE="autonomous"
ADV="$(advanced_short "$NEXT")"
CUR="$STAGE"; [ "$DONE" = 1 ] && CUR="${STAGE}_done"
[ -f "$STATE" ] && BASE="$(cat "$STATE")" || BASE="null"
mkdir -p "$ROOT/docs/.pdlc-state" || die "无法创建 docs/.pdlc-state/"
TMP="$STATE.tmp.$$"

jq -n \
    --argjson base "$BASE" --arg fid "$FID" --arg name "$NAME" --arg now "$NOW" \
    --arg stage "$STAGE" --arg cur "$CUR" --arg next "$NEXT" --arg adv "$ADV" \
    --argjson ok "$([ "$OK" = 1 ] && echo true || echo false)" --arg reason "$REASON" \
    --argjson checks "$CHECKS" --arg mode "$RUN_MODE" --arg produced "$PRODUCED" \
    --argjson decisions "$DECISIONS" --argjson fp "$FINGERPRINT" --arg audit "$SELF_AUDIT" '
    def nn($s): if $s == "" or $s == "null" then null else $s end;
    def six: {extends: [], depends_on: [], supersedes: [], resolves: [], conflicts_with: [], relates_to: []};
    ($produced | split(",") | map(gsub("^ +| +$"; "")) | map(select(length > 0))) as $prod
    | ($audit | if . == "" then null else (split(",") | map(tonumber)) end) as $sa
    | ($decisions | map(capture("^(?<point>.*?)=(?<chose>.*)$") // {point: ., chose: ""} | . + {at: $now})) as $dec
    | (if $base == null then
         {feature_id: $fid, feature_name: $name, created_at: $now, current_stage: $stage,
          run_mode: $mode, history: [], relations: six, next_step: null}
       else $base end) as $s
    | $s
    | .run_mode = $mode
    | if $ok then
        .history = ((.history // []) + [
            {stage: $stage, done_at: $now, produced: $prod}
            + (if $sa then {self_audit: {passed: $sa[0], failed: $sa[1], manual: $sa[2]}} else {} end)
            + (if ($dec | length) > 0 then {auto_decisions: $dec} else {} end)
            + (if $fp != null then {tests_fingerprint: $fp} else {} end)
          ])
        | .current_stage = $cur
        | .next_step = nn($next)
      else . end
    | .last_phase_result = (
        {stage: $stage, ok: $ok, advanced_to: (if $ok then nn($adv) else null end), checks: $checks}
        + (if $sa then {self_audit: {failed: $sa[1]}} else {} end)
        + {blocked_reason: (if $ok then null else $reason end), run_mode: $mode, at: $now})
    ' > "$TMP" 2>/dev/null || { rm -f "$TMP"; die "生成状态 JSON 失败，未写状态机"; }
mv "$TMP" "$STATE" || { rm -f "$TMP"; die "写回 ${STATE} 失败"; }

# 写完体检：只回显本功能状态文件的偏差
if [ -f "$SELF_DIR/pdlc-state-lint.sh" ]; then
    lint="$(bash "$SELF_DIR/pdlc-state-lint.sh" "$ROOT" 2>/dev/null | awk -F'\t' -v f="$FID.json" '$1 == f')"
    [ -z "$lint" ] || printf 'pdlc-advance: 体检发现本功能状态文件的偏差：\n%s\n' "$lint" >&2
fi

jq -c '{ok: .last_phase_result.ok, current_stage, next_step, checks: .last_phase_result.checks,
        blocked_reason: .last_phase_result.blocked_reason}' "$STATE"
[ "$OK" = 1 ] && exit 0 || exit 3
