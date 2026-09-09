#!/usr/bin/env bash
# Validate frontmatter of every sub-skill at skills/<name>/SKILL.md.
#
# Plugin context: each sub-skill is at `skills/<name>/SKILL.md` and gets
# exposed by Claude Code as `/pdlc-<name>` (the "pdlc" prefix comes from
# .claude-plugin/plugin.json's `name` field).
#
# Checks:
#   0. plugin.json exists and its `version` equals the VERSION file
#   1. Required frontmatter fields: name, description, argument-hint, allowed-tools, layer, stage
#   2. `layer` value must be 1 / 2 / 3
#   3. Layer 1/2 sub-skills that produce artifacts must @include
#      templates/prompts/iron-law.md (query/utility skills with empty
#      `produces` are exempt)
#   4. `next_step` (when set) must reference a real sub-skill (a directory
#      named accordingly under skills/)
#   5. Every @include path must resolve to a real file under references/
#   6. Sub-skill `name:` field must equal the parent directory name
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

required_fields=(name description argument-hint allowed-tools layer stage)
fail=0
pass=0

# Collect every sub-skill name (directory under skills/) for next_step validation
valid_skill_names=""
for d in skills/*/; do
    name="$(basename "$d")"
    valid_skill_names="$valid_skill_names $name"
done

has_field() {
    local file="$1" field="$2"
    awk -v field="$field" '
        /^---$/ { fm = !fm; next }
        fm && $1 == field":" { found = 1 }
        END { exit !found }
    ' "$file"
}

extract_field() {
    local file="$1" field="$2"
    awk -v field="$field" '
        /^---$/ { fm = !fm; next }
        fm && $1 == field":" { sub(/^[^:]+:[[:space:]]*/, ""); print; exit }
    ' "$file"
}

is_valid_skill_name() {
    case " $valid_skill_names " in
        *" $1 "*) return 0 ;;
        *)        return 1 ;;
    esac
}

has_non_empty_produces() {
    awk '
        /^---$/ { fm = !fm; next }
        !fm { next }
        /^produces:/ {
            value = $0
            sub(/^[^:]+:[[:space:]]*/, "", value)
            if (value == "[]" || value == "") { in_block = 1; next }
            if (value ~ /^\[.+\]$/) { print "yes"; exit }
            in_block = 1
            next
        }
        in_block && /^[a-zA-Z_-]+:/ { in_block = 0 }
        in_block && /^[[:space:]]+-[[:space:]]+/ { print "yes"; exit }
    ' "$1" | grep -q yes
}

# ─── 0. Plugin manifest sanity ───
echo "Checking plugin manifest..."
plugin_json=".claude-plugin/plugin.json"
if [[ ! -f "$plugin_json" ]]; then
    echo "  ✗ $plugin_json not found"
    fail=$((fail + 1))
else
    plugin_version=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$plugin_json" \
        | sed -E 's/.*"([^"]+)"$/\1/')
    file_version=$(head -1 VERSION 2>/dev/null || echo unknown)
    if [[ "$plugin_version" == "$file_version" ]]; then
        echo "  ✓ plugin.json version ($plugin_version) matches VERSION file"
        pass=$((pass + 1))
    else
        echo "  ✗ plugin.json version ($plugin_version) ≠ VERSION file ($file_version)"
        fail=$((fail + 1))
    fi
fi

# ─── 0b. Marketplace manifest version must also equal VERSION ───
# (plugin.json and marketplace.json版本锁步 bump；只校验 plugin.json 会让 marketplace 每次发版漏改)
marketplace_json=".claude-plugin/marketplace.json"
if [[ ! -f "$marketplace_json" ]]; then
    echo "  ✗ $marketplace_json not found"
    fail=$((fail + 1))
else
    marketplace_version=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$marketplace_json" \
        | sed -E 's/.*"([^"]+)"$/\1/')
    file_version=$(head -1 VERSION 2>/dev/null || echo unknown)
    if [[ "$marketplace_version" == "$file_version" ]]; then
        echo "  ✓ marketplace.json version ($marketplace_version) matches VERSION file"
        pass=$((pass + 1))
    else
        echo "  ✗ marketplace.json version ($marketplace_version) ≠ VERSION file ($file_version)"
        fail=$((fail + 1))
    fi
fi

# ─── 1-6. Per-sub-skill checks ───
for f in skills/*/SKILL.md; do
    skill_dir="$(dirname "$f")"
    skill_name="$(basename "$skill_dir")"
    issues=()

    for field in "${required_fields[@]}"; do
        if ! has_field "$f" "$field"; then
            issues+=("missing field: $field")
        fi
    done

    name_field=$(extract_field "$f" name)
    if [[ "$name_field" != "$skill_name" ]]; then
        issues+=("frontmatter name '$name_field' ≠ directory name '$skill_name'")
    fi

    layer=$(extract_field "$f" layer)
    case "$layer" in
        1|2|3) ;;
        *) issues+=("invalid layer value: '$layer' (must be 1, 2, or 3)") ;;
    esac

    if [[ "$layer" == "1" || "$layer" == "2" ]] && has_non_empty_produces "$f"; then
        if ! grep -q '@include templates/prompts/iron-law\.md' "$f"; then
            issues+=("Layer $layer sub-skill (with non-empty produces) must @include templates/prompts/iron-law.md")
        fi
    fi

    if has_field "$f" next_step; then
        next_step=$(extract_field "$f" next_step)
        if [[ -n "$next_step" && "$next_step" != "null" ]]; then
            if ! is_valid_skill_name "$next_step"; then
                issues+=("next_step '$next_step' does not match any sub-skill directory under skills/")
            fi
        fi
    fi

    while IFS= read -r included; do
        [[ -z "$included" ]] && continue
        full="references/$included"
        if [[ ! -f "$full" ]]; then
            issues+=("@include path not found: references/$included")
        fi
    done < <(grep -oE '@include [a-zA-Z0-9_/.-]+\.md' "$f" 2>/dev/null | awk '{print $2}' | sort -u || true)

    if [[ ${#issues[@]} -gt 0 ]]; then
        echo "✗ skills/$skill_name/SKILL.md"
        for issue in "${issues[@]}"; do
            echo "    - $issue"
        done
        fail=$((fail + 1))
    else
        pass=$((pass + 1))
    fi
done


# ─── 检查 7：阶段短名映射表必须与各 skill 的 stage frontmatter 一致 ───
# state-update.md 原先写「advanced_to = next_step 命令去掉 pdlc- 前缀」，这条规则对
# pdlc-implement 直接给错答案（短名是 impl 不是 implement），文档只能在紧邻处用 ⛔ 打
# 补丁——规则与规则的反例挨着写，模型两边都读得到。改为一张显式映射表后，由本断言
# 双向钉死，防止表和实现各自漂移：
#   ① 表里每一行的短名，必须等于该 skill 自己 frontmatter 声明的 stage
#   ② 任何 skill 的非 null next_step，都必须在表里有一行（防止新增阶段时表腐烂）
echo ""
echo "Check: 阶段短名映射表（advanced_to）"
MAP_FILE="references/templates/prompts/state-update.md"

stage_map() { # → 每行「<命令名> <短名>」
    awk '/<!-- stage-map:start -->/{f=1;next} /<!-- stage-map:end -->/{f=0} f' "$MAP_FILE" 2>/dev/null \
      | awk -F'|' 'NF>=3 { c=$2; s=$3; gsub(/[ `]/,"",c); gsub(/[ `]/,"",s);
                           if (c ~ /^pdlc-/) print c, s }'
}

map_n=0
while read -r cmd short; do
    [[ -z "$cmd" ]] && continue
    map_n=$((map_n + 1))
    if [[ ! -f "skills/$cmd/SKILL.md" ]]; then
        echo "  ✗ 映射表引用了不存在的 skill: $cmd"; fail=$((fail + 1)); continue
    fi
    declared="$(awk -F': *' '/^stage:/{print $2; exit}' "skills/$cmd/SKILL.md" | tr -d '\r')"
    if [[ "$declared" != "$short" ]]; then
        echo "  ✗ $cmd: 映射表写 '$short'，但该 skill frontmatter 声明 stage: '$declared'"
        fail=$((fail + 1))
    else
        echo "  ✓ ${cmd} → ${short}（与 frontmatter 一致）"; pass=$((pass + 1))
    fi
done < <(stage_map)

if [[ "$map_n" -eq 0 ]]; then
    echo "  ✗ 未在 $MAP_FILE 找到 stage-map 表（缺 <!-- stage-map:start --> 锚点？）"
    fail=$((fail + 1))
fi

# ② 反向：每个非 null 的 next_step 都必须在表里
missing_rows=""
for f in skills/*/SKILL.md; do
    ns="$(awk -F': *' '/^next_step:/{print $2; exit}' "$f" | tr -d '\r')"
    [[ -z "$ns" || "$ns" == "null" ]] && continue
    stage_map | grep -qE "^$ns " || missing_rows="${missing_rows}${ns} "
done
if [[ -z "$missing_rows" ]]; then
    echo "  ✓ 每个非 null 的 next_step 在映射表里都有对应行"; pass=$((pass + 1))
else
    echo "  ✗ 这些 next_step 在映射表里没有行（表已腐烂）: $missing_rows"; fail=$((fail + 1))
fi

echo ""
echo "Result: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
