#!/usr/bin/env bash
# PDLC Skill installer
#
# Two ways to run this script:
#
#   1. Remote (no clone needed) — recommended for end users:
#      curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
#        | bash -s -- --global
#
#   2. Local (after `git clone`) — for contributors or template customization:
#      bash install.sh --global
#
set -euo pipefail

SKILL_NAME="pdlc"
GITHUB_OWNER="kanfu-panda"
GITHUB_REPO="pdlc-skills"
GITHUB_RAW_VERSION_URL="https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/main/VERSION"
GITHUB_REPO_URL="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}"

# ─── Detect remote mode ───
# When piped via `curl | bash`, BASH_SOURCE[0] is empty and there's no
# references/ directory adjacent to the script. In that case we'll fetch
# the source tree from GitHub before running install/upgrade.
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
fi
IS_REMOTE_MODE=0
if [[ -z "$SCRIPT_DIR" ]] || [[ ! -d "$SCRIPT_DIR/references" ]]; then
  IS_REMOTE_MODE=1
fi

# ─── Required tools ───
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

Options:
  --ref <tag|main>      In remote mode, install a specific tag (e.g. v1.0.0)
                        or the main branch. Default: latest published release.

Remote (no clone) install:
  curl -fsSL ${GITHUB_RAW_VERSION_URL%/VERSION}/install.sh | bash -s -- --global
EOF
}

# ─── Remote mode: fetch source from GitHub ───
fetch_remote_source() {
  command -v curl >/dev/null 2>&1 || { echo "Error: curl not found." >&2; exit 1; }
  command -v tar  >/dev/null 2>&1 || { echo "Error: tar not found." >&2; exit 1; }

  local target_ref="${REF:-latest}"
  local tarball_url

  if [[ "$target_ref" == "latest" ]]; then
    # Resolve the latest published release tag via GitHub API.
    local tag
    tag="$(curl -fsSL --max-time 10 \
      "https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest" 2>/dev/null \
      | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)" || tag=""

    if [[ -z "$tag" ]]; then
      echo "ℹ️  No published release found, falling back to main branch." >&2
      tarball_url="https://codeload.github.com/${GITHUB_OWNER}/${GITHUB_REPO}/tar.gz/refs/heads/main"
      target_ref="main"
    else
      tarball_url="https://codeload.github.com/${GITHUB_OWNER}/${GITHUB_REPO}/tar.gz/refs/tags/${tag}"
      target_ref="$tag"
    fi
  elif [[ "$target_ref" == "main" ]]; then
    tarball_url="https://codeload.github.com/${GITHUB_OWNER}/${GITHUB_REPO}/tar.gz/refs/heads/main"
  else
    tarball_url="https://codeload.github.com/${GITHUB_OWNER}/${GITHUB_REPO}/tar.gz/refs/tags/${target_ref}"
  fi

  echo "Fetching PDLC Skill source ($target_ref)..."
  REMOTE_TMP="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$REMOTE_TMP'" EXIT

  if ! curl -fsSL --max-time 60 "$tarball_url" | tar -xz -C "$REMOTE_TMP" 2>/dev/null; then
    echo "Error: failed to download or extract source from $tarball_url" >&2
    exit 1
  fi

  local extracted_root
  extracted_root="$(find "$REMOTE_TMP" -maxdepth 1 -mindepth 1 -type d | head -1)"
  if [[ -z "$extracted_root" || ! -d "$extracted_root/references" ]]; then
    echo "Error: extracted archive is malformed (no references/ directory)." >&2
    exit 1
  fi

  SCRIPT_DIR="$extracted_root"
}

# ─── Subcommand: --version ───
do_version() {
  local script_ver="" global_ver project_ver latest_ver

  if [[ "$IS_REMOTE_MODE" -eq 0 ]]; then
    script_ver="$(head -1 "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"
  fi

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
  if [[ "$IS_REMOTE_MODE" -eq 0 ]]; then
    echo "  Local clone:         $script_ver"
  fi
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

  if [[ "$latest_ver" == "unable to fetch" ]]; then
    return 0
  fi

  if [[ "$global_ver" != "not installed" && "$global_ver" != "$latest_ver" ]]; then
    echo "⚠️  Installed version ($global_ver) is behind latest ($latest_ver)."
    echo "    Upgrade:"
    echo "      curl -fsSL ${GITHUB_RAW_VERSION_URL%/VERSION}/install.sh | bash -s -- --upgrade --global"
  elif [[ "$IS_REMOTE_MODE" -eq 0 && -n "$script_ver" && "$script_ver" != "$latest_ver" ]]; then
    echo "⚠️  Local clone ($script_ver) is behind latest ($latest_ver)."
    if [[ -d "$SCRIPT_DIR/.git" ]]; then
      echo "    Update the clone:  cd $SCRIPT_DIR && git pull"
    else
      echo "    Re-download:       $GITHUB_REPO_URL"
    fi
  else
    echo "✅ Up to date."
  fi
}

# ─── Subcommand: --self-update ───
do_self_update() {
  if [[ "$IS_REMOTE_MODE" -eq 1 ]]; then
    echo "ℹ️  Running in remote mode — there is no local clone to update."
    echo "   Each invocation already fetches the latest source from GitHub."
    echo "   To re-apply to your install:"
    echo "      curl -fsSL ${GITHUB_RAW_VERSION_URL%/VERSION}/install.sh | bash -s -- --upgrade --global"
    return 0
  fi

  if [[ ! -d "$SCRIPT_DIR/.git" ]]; then
    echo "Error: $SCRIPT_DIR is not a git repository." >&2
    echo "Self-update requires a git clone. Re-download from:" >&2
    echo "  $GITHUB_REPO_URL" >&2
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
REF=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)      SCOPE="global"; shift ;;
    --project)     SCOPE="project"; PROJECT="${2:-}"; shift 2 ;;
    --uninstall)   ACTION="uninstall"; shift ;;
    --upgrade)     ACTION="upgrade"; shift ;;
    --version)     ACTION="version"; shift ;;
    --self-update) ACTION="self-update"; shift ;;
    --ref)         REF="${2:-}"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

# Subcommands that don't need scope/project or remote source
case "$ACTION" in
  version)     do_version; exit 0 ;;
  self-update) do_self_update; exit 0 ;;
esac

# Remote mode: fetch source for install/upgrade only.
# Uninstall doesn't need network — we just remove the install dir.
if [[ "$IS_REMOTE_MODE" -eq 1 && ("$ACTION" == "install" || "$ACTION" == "upgrade") ]]; then
  fetch_remote_source
fi

# Interactive scope selection (skipped when piping via curl, since stdin is the script)
if [[ -z "$SCOPE" ]]; then
  if [[ ! -t 0 ]]; then
    echo "Error: cannot prompt interactively when piped via curl." >&2
    echo "Pass --global or --project <path> explicitly. See --help for examples." >&2
    exit 1
  fi
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
      if [[ -t 0 ]]; then
        echo "⚠️  Target already exists: $DEST"
        read -rp "Overwrite? (y/N) " yn
        [[ "$yn" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
      fi
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
    installed_ver="$(head -1 "$DEST/VERSION" 2>/dev/null || echo unknown)"
    echo "✅ Installed PDLC Skill v$installed_ver to: $DEST"
    echo ""
    echo "Next steps:"
    echo "  Open Claude Code and describe a task, e.g."
    echo '    "Use PDLC to build a user login feature"'
    ;;
esac
