#!/usr/bin/env bash
# PDLC Skill installer
# Copies this directory into ~/.claude/skills/pdlc/ (--global)
#                       or  <project>/.claude/skills/pdlc/ (--project <path>)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="pdlc"
GITHUB_RAW_VERSION_URL="https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/VERSION"

command -v rsync >/dev/null 2>&1 || {
  echo "Error: rsync not found. Please install rsync before running this script." >&2
  exit 1
}

usage() {
  cat <<EOF
PDLC Skill installer

Usage:
  bash install.sh --global                       Install to ~/.claude/skills/pdlc/
  bash install.sh --project /path/to/my-project  Install to <project>/.claude/skills/pdlc/
  bash install.sh --upgrade   --global
  bash install.sh --upgrade   --project /path/to/my-project
  bash install.sh --uninstall --global
  bash install.sh --uninstall --project /path/to/my-project
  bash install.sh --version                      Show installed and latest versions
  bash install.sh --self-update                  Pull latest source (requires git clone)
  bash install.sh                                Interactive mode

Run with no arguments to enter interactive mode.
EOF
}

# ─── Subcommand: --version ───
do_version() {
  local script_ver global_ver project_ver latest_ver
  script_ver="$(head -1 "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"

  if [[ -f "$HOME/.claude/skills/$SKILL_NAME/VERSION" ]]; then
    global_ver="$(head -1 "$HOME/.claude/skills/$SKILL_NAME/VERSION")"
  else
    global_ver="not installed"
  fi

  latest_ver=""
  if command -v curl >/dev/null 2>&1; then
    latest_ver="$(curl -fsSL --max-time 5 "$GITHUB_RAW_VERSION_URL" 2>/dev/null | head -1 || true)"
  fi
  : "${latest_ver:=unable to fetch}"

  echo "PDLC Skill version status"
  echo "──────────────────────────────────────"
  echo "  Local clone:         $script_ver"
  echo "  Installed (global):  $global_ver"
  if [[ -n "${PROJECT:-}" ]]; then
    if [[ -f "$PROJECT/.claude/skills/$SKILL_NAME/VERSION" ]]; then
      project_ver="$(head -1 "$PROJECT/.claude/skills/$SKILL_NAME/VERSION")"
    else
      project_ver="not installed"
    fi
    echo "  Installed (project): $project_ver"
  fi
  echo "  Latest on GitHub:    $latest_ver"
  echo ""

  if [[ "$latest_ver" != "unable to fetch" && "$latest_ver" != "$script_ver" ]]; then
    echo "⚠️  Your local clone ($script_ver) is behind GitHub ($latest_ver)."
    echo "    To upgrade:"
    if [[ -d "$SCRIPT_DIR/.git" ]]; then
      echo "      cd $SCRIPT_DIR && git pull"
    else
      echo "      Re-download the latest archive from https://github.com/kanfu-panda/pdlc-skills"
    fi
    echo "      bash install.sh --upgrade --global"
    echo "      bash install.sh --upgrade --project /path/to/my-project"
  elif [[ "$global_ver" != "not installed" && "$global_ver" != "$script_ver" ]]; then
    echo "ℹ️  Installed version ($global_ver) differs from local clone ($script_ver)."
    echo "    Reinstall: bash install.sh --upgrade --global"
  else
    echo "✅ Up to date."
  fi
}

# ─── Subcommand: --self-update ───
do_self_update() {
  if [[ ! -d "$SCRIPT_DIR/.git" ]]; then
    echo "Error: $SCRIPT_DIR is not a git repository." >&2
    echo "Self-update requires a git clone. Re-download from:" >&2
    echo "  https://github.com/kanfu-panda/pdlc-skills" >&2
    exit 1
  fi
  command -v git >/dev/null 2>&1 || {
    echo "Error: git not found." >&2
    exit 1
  }

  echo "Pulling latest source from origin..."
  git -C "$SCRIPT_DIR" fetch --quiet
  git -C "$SCRIPT_DIR" pull --ff-only

  echo ""
  echo "✅ Source updated. To apply to your installs:"
  echo "    bash install.sh --upgrade --global"
  echo "    bash install.sh --upgrade --project /path/to/my-project"
}

# ─── Argument parsing ───
ACTION="install"
SCOPE=""
PROJECT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)      SCOPE="global"; shift ;;
    --project)     SCOPE="project"; PROJECT="${2:-}"; shift 2 ;;
    --uninstall)   ACTION="uninstall"; shift ;;
    --upgrade)     ACTION="upgrade"; shift ;;
    --version)     ACTION="version"; shift ;;
    --self-update) ACTION="self-update"; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

# Subcommands that don't need scope/project
case "$ACTION" in
  version)     do_version; exit 0 ;;
  self-update) do_self_update; exit 0 ;;
esac

# Interactive scope selection
if [[ -z "$SCOPE" ]]; then
  echo "Choose install scope:"
  echo "  1) Global (~/.claude/skills/pdlc/)"
  echo "  2) Project (<project>/.claude/skills/pdlc/)"
  read -rp "Enter 1 or 2: " choice
  case "$choice" in
    1) SCOPE="global" ;;
    2) SCOPE="project"
       read -rp "Project root path: " PROJECT ;;
    *) echo "Invalid choice"; exit 1 ;;
  esac
fi

# Resolve install destination
if [[ "$SCOPE" == "global" ]]; then
  DEST="$HOME/.claude/skills/$SKILL_NAME"
else
  if [[ -z "$PROJECT" ]]; then
    echo "Error: --project requires a path." >&2
    exit 1
  fi
  if [[ ! -d "$PROJECT" ]]; then
    echo "Error: project directory not found: $PROJECT" >&2
    exit 1
  fi
  DEST="$PROJECT/.claude/skills/$SKILL_NAME"
fi

case "$ACTION" in
  uninstall)
    if [[ -d "$DEST" ]]; then
      rm -rf "$DEST"
      echo "✅ Uninstalled: $DEST"
    else
      echo "⚠️  Nothing to uninstall at: $DEST"
    fi
    ;;
  install|upgrade)
    if [[ -d "$DEST" && "$ACTION" == "install" ]]; then
      echo "⚠️  Target already exists: $DEST"
      read -rp "Overwrite? (y/N) " yn
      [[ "$yn" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
      rm -rf "$DEST"
    elif [[ -d "$DEST" && "$ACTION" == "upgrade" ]]; then
      rm -rf "$DEST"
    fi
    mkdir -p "$(dirname "$DEST")"
    rsync -a \
      --exclude='.git' \
      --exclude='.github' \
      --exclude='.editorconfig' \
      --exclude='install.sh' \
      --exclude='tests' \
      --exclude='CONTRIBUTING.md' \
      --exclude='CHANGELOG.md' \
      --exclude='CLAUDE.md' \
      --exclude='CODE_OF_CONDUCT.md' \
      --exclude='SECURITY.md' \
      "$SCRIPT_DIR/" "$DEST/"
    echo "✅ Installed to: $DEST"
    echo ""
    echo "Next steps:"
    echo "  Open Claude Code and describe a task, e.g."
    echo '    "Use PDLC to build a user login feature"'
    ;;
esac
