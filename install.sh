#!/usr/bin/env bash
# pdlc-skills installer for Claude Code.
#
# Thin wrapper around `claude plugin marketplace add` + `claude plugin install`.
# Lets users install/upgrade/uninstall pdlc-skills with a single curl
# one-liner; falls back to the local clone as a marketplace source when run
# from a checkout (so contributors can test their changes locally).
set -euo pipefail

GITHUB_OWNER="kanfu-panda"
GITHUB_REPO="pdlc-skills"
PLUGIN_NAME="pdlc"
MARKETPLACE_NAME="pdlc-skills"   # matches `name` in .claude-plugin/marketplace.json
GITHUB_RAW_VERSION_URL="https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/main/VERSION"

# ─── Detect mode ───
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
fi

IS_LOCAL_CLONE=0
if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/.claude-plugin/plugin.json" ]]; then
  IS_LOCAL_CLONE=1
fi

# Marketplace source: prefer local clone (for contributors), else GitHub repo.
if [[ "$IS_LOCAL_CLONE" -eq 1 ]]; then
  MARKETPLACE_SOURCE="$SCRIPT_DIR"
else
  MARKETPLACE_SOURCE="${GITHUB_OWNER}/${GITHUB_REPO}"
fi

# ─── Sanity: claude CLI present ───
require_claude_cli() {
  if ! command -v claude >/dev/null 2>&1; then
    cat >&2 <<'EOF'
Error: `claude` CLI not found in PATH.

pdlc-skills is a Claude Code plugin and requires the Claude Code CLI for install.
Get Claude Code: https://docs.anthropic.com/claude-code
EOF
    exit 1
  fi
}

usage() {
  cat <<EOF
pdlc-skills installer for Claude Code

Usage:
  bash install.sh --global                       Install for current user
  bash install.sh --project /path/to/my-project  Install scoped to one project
  bash install.sh --upgrade                      Update to the latest version
  bash install.sh --uninstall                    Remove the plugin
  bash install.sh --version                      Show installed and latest versions
  bash install.sh --help                         Show this message
  bash install.sh                                Interactive mode

  bash install.sh --target codex                 Install pdlc as Codex CLI prompts
  bash install.sh --target codex --uninstall     Remove the Codex prompts

After install, restart Claude Code and type \`/pdlc-\`. You should see 36
sub-commands like /pdlc-feature, /pdlc-prd, /pdlc-tdd, ...

--target codex builds the platform-neutral adapter (see
docs/decisions/0003-multi-platform-adapters.md) and installs 34 /pdlc-*
prompts into ~/.codex/prompts/ (the 2 Claude Code-only skills are skipped).
Requires a local clone + python3.

Remote (no clone) install one-liner:
  curl -fsSL https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/main/install.sh | bash -s -- --global

Equivalent native commands:
  claude plugin marketplace add ${GITHUB_OWNER}/${GITHUB_REPO}
  claude plugin install ${PLUGIN_NAME}@${MARKETPLACE_NAME}
EOF
}

# ─── Subcommand: --version ───
do_version() {
  local installed_ver="not installed"
  if command -v claude >/dev/null 2>&1; then
    installed_ver=$(
      claude plugin list 2>/dev/null \
        | awk '/'"${PLUGIN_NAME}@${MARKETPLACE_NAME}"'/{found=1; next} found && /Version:/{print $2; exit}'
    )
    [[ -z "$installed_ver" ]] && installed_ver="not installed"
  fi

  local latest_ver=""
  if command -v curl >/dev/null 2>&1; then
    latest_ver=$(curl -fsSL --max-time 5 "$GITHUB_RAW_VERSION_URL" 2>/dev/null | head -1 || true)
  fi
  : "${latest_ver:=unable to fetch}"

  echo "pdlc-skills version status"
  echo "──────────────────────────────────────"
  if [[ "$IS_LOCAL_CLONE" -eq 1 ]]; then
    echo "  Local clone:  $(head -1 "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"
  fi
  echo "  Installed:    ${installed_ver}"
  echo "  Latest:       ${latest_ver}"
  echo ""

  if [[ "$latest_ver" != "unable to fetch" \
        && "$installed_ver" != "not installed" \
        && "$installed_ver" != "$latest_ver" ]]; then
    echo "⚠️  Installed (${installed_ver}) is behind latest (${latest_ver})."
    echo "    Upgrade: bash install.sh --upgrade"
  elif [[ "$installed_ver" == "not installed" ]]; then
    echo "ℹ️  Not installed yet."
    echo "    Install: bash install.sh --global"
  else
    echo "✅ Up to date."
  fi
}

# ─── Target: codex (multi-platform adapter, see docs/decisions/0003) ───
CODEX_PROMPTS_DIR="${HOME}/.codex/prompts"
CODEX_PDLC_DIR="${HOME}/.codex/pdlc"

require_python3() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 not found — required to build the Codex adapter." >&2
    exit 1
  fi
}

do_codex_install() {
  if [[ "$IS_LOCAL_CLONE" -ne 1 ]]; then
    cat >&2 <<EOF
Error: --target codex must run from a local clone of pdlc-skills.
  git clone https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}.git
  cd ${GITHUB_REPO} && bash install.sh --target codex
EOF
    exit 1
  fi
  require_python3

  local build_dir="$SCRIPT_DIR/dist/codex"
  echo "Building Codex adapter from skills/ ..."
  python3 "$SCRIPT_DIR/adapters/build_codex.py" "$build_dir"

  echo ""
  echo "Installing Codex prompts → ${CODEX_PROMPTS_DIR}"
  mkdir -p "$CODEX_PROMPTS_DIR" "$CODEX_PDLC_DIR/templates"
  cp "$build_dir"/prompts/*.md "$CODEX_PROMPTS_DIR"/
  cp "$build_dir"/templates/*  "$CODEX_PDLC_DIR/templates"/
  cp "$build_dir/pdlc-methodology.md" "$CODEX_PDLC_DIR"/

  local n
  n=$(find "$build_dir/prompts" -name '*.md' | wc -l | tr -d ' ')
  echo ""
  echo "✅ Done. ${n} /pdlc-* prompts installed for Codex."
  echo "   In Codex, type /pdlc- to see them (e.g. /pdlc-feature, /pdlc-prd)."
  echo "   Methodology + templates: ${CODEX_PDLC_DIR}"
  echo "   Note: the statusline and the autonomous loop engine are Claude Code-only (not ported)."
}

do_codex_uninstall() {
  # Only ever touches our own namespaced paths under ~/.codex.
  echo "Removing pdlc prompts from ${CODEX_PROMPTS_DIR} ..."
  rm -f "$CODEX_PROMPTS_DIR"/pdlc-*.md
  if [[ "$CODEX_PDLC_DIR" == "${HOME}/.codex/pdlc" && -d "$CODEX_PDLC_DIR" ]]; then
    rm -rf "$CODEX_PDLC_DIR"
  fi
  echo "✅ Removed pdlc from Codex."
}

# ─── Argument parsing ───
ACTION="install"
SCOPE=""
PROJECT=""
TARGET="claude"   # claude (default) | codex

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)      SCOPE="user"; shift ;;
    --project)     SCOPE="project"; PROJECT="${2:-}"; shift 2 ;;
    --target)      TARGET="${2:-}"; shift 2 ;;
    --uninstall)   ACTION="uninstall"; shift ;;
    --upgrade)     ACTION="upgrade"; shift ;;
    --version)     ACTION="version"; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

case "$ACTION" in
  version) do_version; exit 0 ;;
esac

# Codex target bypasses the claude CLI (it copies files, not a plugin install).
if [[ "$TARGET" == "codex" ]]; then
  case "$ACTION" in
    install)   do_codex_install; exit 0 ;;
    uninstall) do_codex_uninstall; exit 0 ;;
    *) echo "Error: --target codex supports install / --uninstall only." >&2; exit 1 ;;
  esac
elif [[ "$TARGET" != "claude" ]]; then
  echo "Error: unknown --target '$TARGET' (supported: claude, codex)." >&2
  exit 1
fi

require_claude_cli

# Interactive scope selection (skipped in non-TTY)
if [[ -z "$SCOPE" && "$ACTION" == "install" ]]; then
  if [[ ! -t 0 ]]; then
    echo "Error: --global or --project <path> required when piped via curl." >&2
    usage
    exit 1
  fi
  echo "Choose install scope:"
  echo "  1) Global (for current user — ~/.claude/plugins/)"
  echo "  2) Project (scoped to one repo — <project>/.claude/plugins/)"
  read -rp "Enter 1 or 2: " choice
  case "$choice" in
    1) SCOPE="user" ;;
    2) SCOPE="project"
       read -rp "Project root path: " PROJECT ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac
fi

# Validate project path early
if [[ "$SCOPE" == "project" ]]; then
  [[ -n "$PROJECT" ]] || { echo "Error: --project requires a path." >&2; exit 1; }
  [[ -d "$PROJECT" ]] || { echo "Error: project directory not found: $PROJECT" >&2; exit 1; }
fi

case "$ACTION" in
  install)
    # Add marketplace (idempotent — claude CLI handles already-added gracefully)
    echo "Adding marketplace: ${MARKETPLACE_SOURCE}"
    claude plugin marketplace add "$MARKETPLACE_SOURCE" 2>&1 | tail -3 || true

    echo ""
    echo "Installing plugin: ${PLUGIN_NAME}@${MARKETPLACE_NAME} (scope: ${SCOPE:-user})"
    if [[ "$SCOPE" == "project" ]]; then
      (cd "$PROJECT" && claude plugin install "${PLUGIN_NAME}@${MARKETPLACE_NAME}" --scope project)
    else
      claude plugin install "${PLUGIN_NAME}@${MARKETPLACE_NAME}" --scope user
    fi

    echo ""
    echo "✅ Done."
    echo ""
    echo "Restart Claude Code, then type /pdlc- to see all 36 sub-commands."
    ;;
  upgrade)
    echo "Updating ${PLUGIN_NAME}@${MARKETPLACE_NAME}..."
    claude plugin update "${PLUGIN_NAME}@${MARKETPLACE_NAME}"
    echo ""
    echo "✅ Updated. Restart Claude Code to apply."
    ;;
  uninstall)
    echo "Uninstalling ${PLUGIN_NAME}@${MARKETPLACE_NAME}..."
    claude plugin uninstall "${PLUGIN_NAME}@${MARKETPLACE_NAME}"
    echo ""
    echo "✅ Uninstalled."
    ;;
esac
