#!/usr/bin/env bash
# install.sh behaviour regression test.
#
# Current architecture: install.sh just rsyncs into <scope>/.claude/skills/pdlc/.
# It does NOT preprocess @include or branch on IDE target. This test focuses
# on "did the right files land in the right place".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

pass=0
fail=0

assert_contains() {
    local desc="$1" expected="$2" actual="$3"
    if grep -qF "$expected" <<< "$actual"; then
        echo "  ✓ $desc"
        pass=$((pass + 1))
    else
        echo "  ✗ $desc"
        echo "    expected to contain: $expected"
        echo "    got: $actual"
        fail=$((fail + 1))
    fi
}

assert_file_exists() {
    local desc="$1" path="$2"
    if [[ -f "$path" ]]; then
        echo "  ✓ $desc"
        pass=$((pass + 1))
    else
        echo "  ✗ $desc (missing: $path)"
        fail=$((fail + 1))
    fi
}

assert_file_absent() {
    local desc="$1" path="$2"
    if [[ ! -e "$path" ]]; then
        echo "  ✓ $desc"
        pass=$((pass + 1))
    else
        echo "  ✗ $desc (unexpectedly present: $path)"
        fail=$((fail + 1))
    fi
}

# ─── Test 1: project install layout ───
echo "Test: project install layout"
TMPDIR=$(mktemp -d)
TARGET_PROJECT="$TMPDIR/myproj"
mkdir -p "$TARGET_PROJECT"
bash install.sh --project "$TARGET_PROJECT" >/dev/null 2>&1

SKILL_ROOT="$TARGET_PROJECT/.claude/skills/pdlc"

assert_file_exists "SKILL.md installed"                      "$SKILL_ROOT/SKILL.md"
assert_file_exists "README.md installed"                     "$SKILL_ROOT/README.md"
assert_file_exists "VERSION installed"                       "$SKILL_ROOT/VERSION"
assert_file_exists "references/commands/prd.md installed"    "$SKILL_ROOT/references/commands/prd.md"
assert_file_exists "references/commands/implement.md installed" "$SKILL_ROOT/references/commands/implement.md"
assert_file_exists "iron-law.md installed"                   "$SKILL_ROOT/references/templates/prompts/iron-law.md"
assert_file_exists "prd-template.md installed"               "$SKILL_ROOT/references/templates/prd-template.md"

# Files that should be excluded from install
assert_file_absent "install.sh excluded"        "$SKILL_ROOT/install.sh"
assert_file_absent "tests/ excluded"            "$SKILL_ROOT/tests"
assert_file_absent "CLAUDE.md excluded"         "$SKILL_ROOT/CLAUDE.md"
assert_file_absent "CHANGELOG.md excluded"      "$SKILL_ROOT/CHANGELOG.md"
assert_file_absent "CONTRIBUTING.md excluded"   "$SKILL_ROOT/CONTRIBUTING.md"
assert_file_absent "CODE_OF_CONDUCT.md excluded" "$SKILL_ROOT/CODE_OF_CONDUCT.md"
assert_file_absent "SECURITY.md excluded"       "$SKILL_ROOT/SECURITY.md"
assert_file_absent ".editorconfig excluded"     "$SKILL_ROOT/.editorconfig"

# ─── Test 2: SKILL.md frontmatter ───
echo ""
echo "Test: SKILL.md frontmatter"
skill_head="$(head -5 "$SKILL_ROOT/SKILL.md")"
assert_contains "SKILL.md has 'name: pdlc'"        "name: pdlc"   "$skill_head"
assert_contains "SKILL.md has description field"   "description:" "$skill_head"

# ─── Test 3: command frontmatter parses ───
echo ""
echo "Test: commands contain expected frontmatter"
prd_head="$(head -10 "$SKILL_ROOT/references/commands/prd.md")"
assert_contains "prd.md has name field"   "name:"   "$prd_head"
assert_contains "prd.md has layer field"  "layer:"  "$prd_head"
assert_contains "prd.md has stage field"  "stage:"  "$prd_head"

# ─── Test 4: upgrade is idempotent ───
echo ""
echo "Test: upgrade is idempotent"
bash install.sh --upgrade --project "$TARGET_PROJECT" >/dev/null 2>&1
assert_file_exists "SKILL.md still present after upgrade"   "$SKILL_ROOT/SKILL.md"
assert_file_exists "prd.md still present after upgrade"     "$SKILL_ROOT/references/commands/prd.md"

# ─── Test 5: uninstall cleans up ───
echo ""
echo "Test: uninstall removes install dir"
bash install.sh --uninstall --project "$TARGET_PROJECT" >/dev/null 2>&1
assert_file_absent "SKILL_ROOT removed after uninstall"     "$SKILL_ROOT"

rm -rf "$TMPDIR"

echo ""
echo "Final: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
