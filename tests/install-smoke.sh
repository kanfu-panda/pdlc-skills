#!/usr/bin/env bash
# Repo-layout + installer-script regression test.
#
# Since install.sh now wraps `claude plugin install` (which requires the
# claude CLI and isn't easily exercised in CI), this test focuses on
# verifying the repo layout the plugin system expects, plus the bits of
# install.sh that work without a claude CLI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

pass=0
fail=0

assert_exists() {
    local desc="$1" path="$2"
    if [[ -e "$path" ]]; then
        echo "  ✓ $desc"
        pass=$((pass + 1))
    else
        echo "  ✗ $desc (missing: $path)"
        fail=$((fail + 1))
    fi
}

assert_contains() {
    local desc="$1" expected="$2" actual="$3"
    if grep -qF "$expected" <<< "$actual"; then
        echo "  ✓ $desc"
        pass=$((pass + 1))
    else
        echo "  ✗ $desc"
        echo "    expected to contain: $expected"
        fail=$((fail + 1))
    fi
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  ✓ $desc"
        pass=$((pass + 1))
    else
        echo "  ✗ $desc (expected: $expected, got: $actual)"
        fail=$((fail + 1))
    fi
}

# ─── Test 1: plugin manifest layout ───
echo "Test: plugin manifest"
assert_exists ".claude-plugin/ directory exists"   ".claude-plugin"
assert_exists "plugin.json exists"                 ".claude-plugin/plugin.json"
assert_exists "marketplace.json exists"            ".claude-plugin/marketplace.json"

# Validate plugin.json basic fields
plugin_name=$(awk -F'"' '/"name"/{print $4; exit}' .claude-plugin/plugin.json)
plugin_version=$(awk -F'"' '/"version"/{print $4; exit}' .claude-plugin/plugin.json)
assert_eq "plugin.json name == 'pdlc'"             "pdlc"   "$plugin_name"
assert_eq "plugin.json version == VERSION"         "$(head -1 VERSION)"   "$plugin_version"

marketplace_name=$(awk -F'"' '/"name"/{print $4; exit}' .claude-plugin/marketplace.json)
assert_eq "marketplace.json name == 'pdlc-skills'" "pdlc-skills"   "$marketplace_name"

# ─── Test 2: skills layout ───
echo ""
echo "Test: skills/ layout"
assert_exists "skills/ directory exists" "skills"

skill_count=$(find skills -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
assert_eq "exactly 31 sub-skill directories" "31" "$skill_count"

for name in pdlc-feature pdlc-fix pdlc-status pdlc-prd pdlc-design pdlc-tdd pdlc-implement pdlc-review pdlc-ship; do
    assert_exists "skills/$name/SKILL.md exists" "skills/$name/SKILL.md"
done

missing=0
for d in skills/*/; do
    [[ -f "${d}SKILL.md" ]] || missing=$((missing + 1))
done
assert_eq "every skill dir has SKILL.md" "0" "$missing"

non_prefixed=0
for d in skills/*/; do
    name="$(basename "$d")"
    [[ "$name" == pdlc-* ]] || non_prefixed=$((non_prefixed + 1))
done
assert_eq "every skill dir name starts with 'pdlc-'" "0" "$non_prefixed"

# ─── Test 3: shared resources ───
echo ""
echo "Test: shared resources"
assert_exists "references/templates/ directory exists" "references/templates"

template_count=$(find references/templates -maxdepth 1 -name '*-template.md' | wc -l | tr -d ' ')
assert_eq "9 user-facing templates"                    "9"   "$template_count"

prompt_count=$(find references/templates/prompts -name '*.md' | wc -l | tr -d ' ')
assert_eq "9 shared prompt fragments"                  "9"   "$prompt_count"

for f in iron-law handoff feature-id defect-id pdlc-trace self-audit state-update loop-prevention output-language; do
    assert_exists "references/templates/prompts/$f.md exists" "references/templates/prompts/$f.md"
done

# ─── Test 4: install.sh without claude CLI ───
echo ""
echo "Test: install.sh (claude CLI not required for these subcommands)"

help_out="$(bash install.sh --help 2>&1)"
assert_contains "--help shows usage"                "Usage:"                          "$help_out"
assert_contains "--help mentions /pdlc-feature"     "/pdlc-feature"                   "$help_out"
assert_contains "--help mentions one-liner"         "raw.githubusercontent.com"       "$help_out"

version_out="$(bash install.sh --version 2>&1)"
assert_contains "--version shows version status"    "PDLC plugin version status"      "$version_out"
assert_contains "--version shows local clone"       "Local clone:"                    "$version_out"

bogus_out="$(bash install.sh --bogus 2>&1 || true)"
assert_contains "unknown arg shows error"           "Unknown argument"                "$bogus_out"

# ─── Test 5: docs / repo hygiene ───
echo ""
echo "Test: repo hygiene"
assert_exists "README.md exists"                    "README.md"
assert_exists "README.zh-CN.md exists"              "README.zh-CN.md"
assert_exists "LICENSE exists"                      "LICENSE"
assert_exists "VERSION exists"                      "VERSION"
assert_exists "CHANGELOG.md exists"                 "CHANGELOG.md"
assert_exists "CONTRIBUTING.md exists"              "CONTRIBUTING.md"
assert_exists "SECURITY.md exists"                  "SECURITY.md"
assert_exists "CODE_OF_CONDUCT.md exists"           "CODE_OF_CONDUCT.md"
assert_exists "docs/usage-guide.md exists"          "docs/usage-guide.md"

# Legacy structure must NOT exist
if [[ ! -e "SKILL.md" ]]; then
    echo "  ✓ no legacy root SKILL.md"
    pass=$((pass + 1))
else
    echo "  ✗ legacy root SKILL.md still present"
    fail=$((fail + 1))
fi

if [[ ! -e "references/commands" ]]; then
    echo "  ✓ no legacy references/commands/ dir"
    pass=$((pass + 1))
else
    echo "  ✗ legacy references/commands/ still present"
    fail=$((fail + 1))
fi

if [[ ! -e "docs/reference.md" ]]; then
    echo "  ✓ no legacy docs/reference.md"
    pass=$((pass + 1))
else
    echo "  ✗ legacy docs/reference.md still present"
    fail=$((fail + 1))
fi

echo ""
echo "Final: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
