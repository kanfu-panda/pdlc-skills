#!/usr/bin/env bash
# Validate frontmatter of every command source file under references/commands/.
#
# Checks:
#   1. Required fields present: name / description / argument-hint / allowed-tools / layer / stage
#   2. `layer` value must be 1 / 2 / 3
#   3. Layer 1 / 2 commands that produce artifacts must @include templates/prompts/iron-law.md
#      (query/utility commands with empty `produces` are exempt)
#   4. `next_step` (when set) must point to a real pdlc-* command name
#   5. Every @include path must resolve to a real file under references/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

required_fields=(name description argument-hint allowed-tools layer stage)
fail=0
pass=0

# Collect every command's `name` field (with pdlc- prefix) to build the set of valid next_step targets.
valid_command_names=""
for f in references/commands/*.md; do
    name=$(awk '/^---$/ { fm = !fm; next } fm && $1 == "name:" { print $2; exit }' "$f")
    [[ -n "$name" ]] && valid_command_names="$valid_command_names $name"
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

is_valid_command() {
    case " $valid_command_names " in
        *" $1 "*) return 0 ;;
        *)        return 1 ;;
    esac
}

# Returns 0 (true) if `produces:` has at least one entry — supports both
# inline form (`produces: [a, b]`) and block form (multiple `- path` lines).
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

for f in references/commands/*.md; do
    bname="$(basename "$f")"
    issues=()

    # 1. Required fields present
    for field in "${required_fields[@]}"; do
        if ! has_field "$f" "$field"; then
            issues+=("missing field: $field")
        fi
    done

    # 2. `layer` must be 1, 2, or 3
    layer=$(extract_field "$f" layer)
    case "$layer" in
        1|2|3) ;;
        *) issues+=("invalid layer value: '$layer' (must be 1, 2, or 3)") ;;
    esac

    # 3. Layer 1/2 commands that produce artifacts must @include iron-law
    if [[ "$layer" == "1" || "$layer" == "2" ]] && has_non_empty_produces "$f"; then
        if ! grep -q '@include templates/prompts/iron-law\.md' "$f"; then
            issues+=("Layer $layer command (with non-empty produces) must @include templates/prompts/iron-law.md")
        fi
    fi

    # 4. `next_step` (when present) must reference a real command
    if has_field "$f" next_step; then
        next_step=$(extract_field "$f" next_step)
        if [[ -n "$next_step" && "$next_step" != "null" ]]; then
            if ! is_valid_command "$next_step"; then
                issues+=("next_step '$next_step' does not match any command name under references/commands/")
            fi
        fi
    fi

    # 5. Every @include path must resolve to a real file
    while IFS= read -r included; do
        [[ -z "$included" ]] && continue
        full="references/$included"
        if [[ ! -f "$full" ]]; then
            issues+=("@include path not found: $included")
        fi
    done < <(grep -oE '@include [a-zA-Z0-9_/.-]+\.md' "$f" 2>/dev/null | awk '{print $2}' | sort -u || true)

    if [[ ${#issues[@]} -gt 0 ]]; then
        echo "✗ $bname"
        for issue in "${issues[@]}"; do
            echo "    - $issue"
        done
        fail=$((fail + 1))
    else
        pass=$((pass + 1))
    fi
done

echo ""
echo "Result: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
