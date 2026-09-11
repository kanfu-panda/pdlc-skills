#!/usr/bin/env bash
# pdlc-state-lint.sh —— 读状态机之前的契约体检（确定性、只读）
#
# 用法：bash pdlc-state-lint.sh [项目根目录]      （缺省为当前目录）
#
# 逐份读 <项目根>/docs/.pdlc-state/*.json，对照状态机契约，把每一处偏差打成一行：
#     <文件名><TAB><偏差代码><TAB><说明>
# 偏差代码的含义，以及读侧（/pdlc-status、/pdlc-retro、/pdlc-relate）该怎么处理，
# 见 references/templates/prompts/state-read.md 的偏差代码表。
#
# 为什么要有它：状态文件不一定都是 /pdlc-* 命令写的。字段对不上契约时，读侧的模型只能
# 边猜边算——曾有两个不同的命令各自拿 terminal_state（契约里没有这个字段）判终态，
# 把「目标是完成」报成了「已经完成」。把体检做成代码，同样的输入永远得到同样的偏差清单，
# 读侧只负责把它们披露在结论前面。
#
# 退出码三态（与 check 命令的三态同一条纪律——「查不了」绝不能当成「没问题」）：
#   0  已体检，全部合契约
#   1  已体检，有偏差（读侧可以继续，但结论必须先披露这些偏差）
#   2  无法体检：没有 docs/.pdlc-state/、缺 jq，或体检自身出错
#
# 只读：不写任何文件。兼容 macOS 自带的 bash 3.2（不用 mapfile / 关联数组）。
set -u

# 下面三份清单由 tests/frontmatter-check.sh 断言：
#   LEGAL_STAGES / STAGE_ALIASES 必须与 state-read.md 的 stage-names 表一致；
#   FINDING_CODES 必须与 state-read.md 的偏差代码表逐一对应。
# 本脚本在目标项目里运行、读不到插件的 skills/，所以清单只能内嵌——断言保证它不漂。
LEGAL_STAGES="requirements design tdd impl review e2e ship deploy fix refactor task feature"
STAGE_ALIASES="prd:requirements implement:impl implementation:impl bugfix:fix"
# shellcheck disable=SC2034  # 脚本自己不读它：它是偏差代码的声明清单，供 frontmatter-check 与片段对账
FINDING_CODES="json-invalid missing-field missing-last_phase_result terminal_state-in-instance non-contract-field stage-alias stage-unknown current_stage-unknown next_step-not-command timestamp-no-time relations-not-object relations-unknown-type relations-target-not-id relations-dangling id-prefix-mismatch second-state-dir"

ROOT="${1:-.}"
STATE_DIR="$ROOT/docs/.pdlc-state"

if ! command -v jq >/dev/null 2>&1; then
    echo "pdlc-state-lint: 缺 jq，无法体检" >&2
    exit 2
fi
if [ ! -d "$STATE_DIR" ]; then
    echo "pdlc-state-lint: 没有 ${STATE_DIR}，无法体检" >&2
    exit 2
fi

# 与状态栏同一条规则：_ 前缀是自动生成的索引（如 _relations.json），
# statusline.json 是配置，都不是功能状态机
is_state_file() {
    case "${1##*/}" in
        _*|statusline.json) return 1 ;;
    esac
    return 0
}

# 现存的 feature ID（= 状态文件名去掉 .json），供判断关系目标是否悬空
ids=""
for f in "$STATE_DIR"/*.json; do
    [ -e "$f" ] || continue
    is_state_file "$f" || continue
    b="${f##*/}"
    ids="${ids}${b%.json}
"
done
ids_json="$(printf '%s' "$ids" | jq -R -s 'split("\n") | map(select(length > 0))')"

files=0
findings=0
broken=0

for f in "$STATE_DIR"/*.json; do
    [ -e "$f" ] || continue
    is_state_file "$f" || continue
    base="${f##*/}"
    files=$((files + 1))

    # 先单独判合法性：把「文件坏了」和「体检程序自己出错」分开，后者属于无法体检
    if ! jq empty "$f" >/dev/null 2>&1; then
        printf '%s\t%s\t%s\n' "$base" "json-invalid" "不是合法 JSON，已跳过"
        findings=$((findings + 1))
        continue
    fi

    if ! out="$(jq -r --arg legal "$LEGAL_STAGES" --arg aliases "$STAGE_ALIASES" --argjson ids "$ids_json" '
        def emit($c; $d): "\($c)\t\($d | tostring | gsub("[\t\r\n]"; " "))";
        def inarr($a; $x): ($a | map(. == $x) | any);
        def legal: ($legal | split(" "));
        def aliasmap: ($aliases | split(" ") | map(split(":") | {(.[0]): .[1]}) | add);
        def canon($v): (aliasmap[$v] // $v);
        def hastime: (type == "string") and test("T[0-9]{2}:[0-9]{2}");
        def sixkeys: ["extends", "depends_on", "supersedes", "resolves", "conflicts_with", "relates_to"];
        def allowed: ["feature_id", "feature_name", "created_at", "current_stage", "run_mode",
                      "history", "last_phase_result", "relations", "next_step"];
        def idre: "^[FB][0-9]{8}-([0-9]{6}|[0-9]{2})$";
        def hist: (.history | if type == "array" then to_entries[] | select(.value | type == "object") else empty end);
        def stage_check($where; $v):
            if ($v | type) != "string" then empty
            elif inarr(legal; $v) then empty
            elif aliasmap[$v] != null then
                emit("stage-alias"; "\($where)=\($v) 是别名，读侧按 \($v)→\(aliasmap[$v]) 归一化（须披露）")
            else
                emit("stage-unknown"; "\($where)=\($v) 既不是阶段短名也不是已知别名")
            end;

        if type != "object" then emit("json-invalid"; "顶层不是 JSON 对象，已跳过")
        else
          ( ["feature_id", "current_stage", "history", "next_step", "created_at"][] as $k
            | select(has($k) | not) | emit("missing-field"; "缺 \($k)") ),
          ( select(has("last_phase_result") | not)
            | emit("missing-last_phase_result"; "缺 last_phase_result（多为旧文件），不推断本阶段结果与 checks") ),
          ( select(has("terminal_state"))
            | emit("terminal_state-in-instance"; "实例含 terminal_state=\(.terminal_state)，它是目标不是事实，已忽略；判终态只看 current_stage") ),
          ( keys[] as $k | select($k != "terminal_state" and (inarr(allowed; $k) | not))
            | emit("non-contract-field"; "表外字段 \($k)，已忽略") ),
          ( hist | .key as $i | .value | stage_check("history[\($i)].stage"; .stage) ),
          ( select((.last_phase_result | type) == "object")
            | stage_check("last_phase_result.stage"; .last_phase_result.stage) ),
          ( .current_stage as $cs | select(($cs | type) == "string")
            | select(($cs | endswith("_done")) | not) | select(inarr(legal; $cs) | not)
            | emit("current_stage-unknown"; "current_stage=\($cs) 既不是阶段短名，也不以 _done 结尾") ),
          ( select(has("next_step")) | .next_step as $n | select($n != null)
            | select((($n | type) == "string" and ($n | test("^pdlc-[a-z][a-z-]*$"))) | not)
            | emit("next_step-not-command"; "next_step=\($n) 不是纯命令名，不据此推断下一步") ),
          ( select(has("created_at")) | select(.created_at | hastime | not)
            | emit("timestamp-no-time"; "created_at=\(.created_at) 没有时刻") ),
          ( hist | .key as $i | .value | select(has("done_at")) | select(.done_at | hastime | not)
            | emit("timestamp-no-time"; "history[\($i)].done_at=\(.done_at) 没有时刻，耗时类指标不可测") ),
          ( select((.last_phase_result | type) == "object" and (.last_phase_result | has("at")))
            | select(.last_phase_result.at | hastime | not)
            | emit("timestamp-no-time"; "last_phase_result.at=\(.last_phase_result.at) 没有时刻") ),
          ( select(has("relations")) | .relations as $r
            | if ($r | type) == "object" then
                ( $r | to_entries[] | select(.key != "_updated_at") | . as $e
                  | if (inarr(sixkeys; $e.key) | not) then
                      emit("relations-unknown-type"; "关系类型 \($e.key) 不在六类之内，不入图")
                    else
                      ($e.value | if type == "array" then .[] else . end) as $t
                      | if (($t | type) == "string" and ($t | test(idre))) then
                          ( select(inarr($ids; $t) | not)
                            | emit("relations-dangling"; "\($e.key) → \($t)，没有对应的状态文件") )
                        else
                          emit("relations-target-not-id"; "\($e.key) → \($t)，目标不是 feature ID，不入图")
                        end
                    end )
              elif $r == null then empty
              else
                emit("relations-not-object"; "relations 是 \($r | type)\(if ($r | type) == "array" then "（\($r | length) 条）" else "" end)，契约要求六键对象；该文件的关系不入图")
              end ),
          ( select([hist | .value.stage | select(type == "string") | canon(.)] | inarr(.; "fix"))
            | select(((.feature_id // "") | tostring | startswith("B")) | not)
            | emit("id-prefix-mismatch"; "history 有修复阶段，feature_id=\(.feature_id // "缺") 却不以 B 开头；缺陷计数仍按 ID 前缀口径") )
        end
    ' "$f" 2>/dev/null)"; then
        echo "pdlc-state-lint: 体检 ${base} 时出错（体检自身的问题），该文件未完成体检" >&2
        broken=1
        continue
    fi

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        printf '%s\t%s\n' "$base" "$line"
        findings=$((findings + 1))
    done <<< "$out"
done

# 仓库根另有一个 .pdlc-state/：常见于先有一份轻量登记、后来又照格式建了 docs/.pdlc-state/ 的项目
if [ -d "$ROOT/.pdlc-state" ]; then
    printf '%s\t%s\t%s\n' ".pdlc-state/" "second-state-dir" "仓库根另有一个 .pdlc-state/；PDLC 只读写 docs/.pdlc-state/，两处并存容易让人以为状态在另一处"
    findings=$((findings + 1))
fi

echo "pdlc-state-lint: ${files} 份状态文件，${findings} 处偏差" >&2

[ "$broken" -eq 1 ] && exit 2
[ "$findings" -gt 0 ] && exit 1
exit 0
