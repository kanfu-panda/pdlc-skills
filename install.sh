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

  bash install.sh --target codex                 Install pdlc as Codex skills
  bash install.sh --target codex --uninstall     Remove the Codex skills
  bash install.sh --target agents                Install as Agent Skills into ~/.agents/skills/
  bash install.sh --target agents --project DIR  ... into DIR/.agents/skills/
  bash install.sh --target agents --dest DIR     ... into any skills directory (e.g. .cursor/skills)
  bash install.sh --target agents [...] --uninstall   Remove them again

After install, restart Claude Code and type \`/pdlc-\`. You should see 38
sub-commands like /pdlc-feature, /pdlc-prd, /pdlc-tdd, ...

--target codex builds the adapter (see
docs/decisions/0003-multi-platform-adapters.md) and installs the pdlc skills
into ~/.codex/skills/ (all but the 2 Claude Code-only ones). Codex skills
are description-triggered — after restarting Codex, drive PDLC in natural
language ("用 pdlc 写个 PRD"), not slash commands. Requires python3; without a
local clone the installer downloads the main source archive first.

--target agents builds the same Agent Skills standard projection (see
docs/decisions/0007-agent-skills-standard.md). ~/.agents/skills/ and
<project>/.agents/skills/ are read by GitHub Copilot, Gemini CLI, OpenCode,
Amp and Goose; use --dest for tools with their own directory (Cursor,
Windsurf, Kiro, Roo Code). Only pdlc-* directories are ever written or removed.

Remote (no clone) install one-liners:
  curl -fsSL https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/main/install.sh | bash -s -- --global
  curl -fsSL https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/main/install.sh | bash -s -- --target agents

Or with the generic Agent Skills installer (36 skills, any supported tool):
  npx skills add ${GITHUB_OWNER}/${GITHUB_REPO}

Equivalent native commands:
  claude plugin marketplace add ${GITHUB_OWNER}/${GITHUB_REPO}
  claude plugin install ${PLUGIN_NAME}@${MARKETPLACE_NAME}
EOF
}

# ver_lt A B —— A 是否严格小于 B（按 x.y.z 逐段数值比较；1.7.9 < 1.7.10）
ver_lt() {
  local a b i x y
  IFS=. read -r -a a <<< "$1"
  IFS=. read -r -a b <<< "$2"
  for i in 0 1 2; do
    x="${a[$i]:-0}"; y="${b[$i]:-0}"
    x="${x%%[!0-9]*}"; y="${y%%[!0-9]*}"
    (( 10#${x:-0} < 10#${y:-0} )) && return 0
    (( 10#${x:-0} > 10#${y:-0} )) && return 1
  done
  return 1
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
  # 其它工具用的投影由 install.sh --target codex | agents 装，装时写了版本戳
  local f
  for f in "${HOME}/.codex/skills/.pdlc-version:Codex skills" "${HOME}/.agents/skills/.pdlc-version:Agent Skills"; do
    [[ -f "${f%%:*}" ]] && echo "  ${f#*:}: $(head -1 "${f%%:*}")"
  done
  echo ""

  if [[ "$latest_ver" != "unable to fetch" \
        && "$installed_ver" != "not installed" ]] && ver_lt "$installed_ver" "$latest_ver"; then
    echo "⚠️  Installed (${installed_ver}) is behind latest (${latest_ver})."
    echo "    Upgrade: bash install.sh --upgrade"
  elif [[ "$installed_ver" == "not installed" ]]; then
    echo "ℹ️  Not installed yet."
    echo "    Install: bash install.sh --global"
  elif [[ "$latest_ver" == "unable to fetch" ]]; then
    # 查不了就说查不了，不能报「已是最新」
    echo "ℹ️  Couldn't fetch the latest version (offline?), so whether ${installed_ver} is current is unknown."
  else
    echo "✅ Up to date."
  fi
}

# ─── Target: codex (multi-platform adapter, see docs/decisions/0003) ───
# Target Codex is a Claude-Code-compatible distribution: it reads native skills at
# ~/.codex/skills/<name>/SKILL.md (description-triggered, NOT slash commands).
# Verified on real Codex (gpt-5.6-sol matched pdlc-prd by description and ran it).
CODEX_SKILLS_DIR="${HOME}/.codex/skills"
CODEX_PROMPTS_DIR="${HOME}/.codex/prompts"   # legacy (v1.5.0 wrongly installed here) — cleaned on install/uninstall
CODEX_PDLC_DIR="${HOME}/.codex/pdlc"

# install_projection <构建产物的 skills 目录> <目标目录>
# 先拷进目标目录下的暂存目录、核对数量，成功后才删旧换新——拷到一半失败（磁盘满、权限）时用户原有的安装还在。
# 只动 pdlc-* 与版本戳，目标目录里的其它 skill 不碰。
install_projection() {
  local src="$1" dest="$2" stage want got d
  stage="${dest}/.pdlc-staging.$$"
  rm -rf "$stage"
  mkdir -p "$stage"
  if ! cp -R "$src"/pdlc-* "$stage"/; then
    rm -rf "$stage"; echo "Error: copy to ${dest} failed; the existing install was left untouched." >&2; exit 1
  fi
  want=$(find "$src" -mindepth 1 -maxdepth 1 -type d -name 'pdlc-*' | wc -l | tr -d ' ')
  got=$(find "$stage" -mindepth 1 -maxdepth 1 -type d -name 'pdlc-*' | wc -l | tr -d ' ')
  if [[ "$want" -eq 0 || "$want" != "$got" ]]; then
    rm -rf "$stage"; echo "Error: staged ${got} of ${want} skills; the existing install was left untouched." >&2; exit 1
  fi
  rm -rf "${dest:?}"/pdlc-*/
  for d in "$stage"/pdlc-*; do mv "$d" "$dest"/; done
  rmdir "$stage"
  if [[ -f "$SRC_DIR/VERSION" ]]; then head -1 "$SRC_DIR/VERSION" > "$dest/.pdlc-version"; fi
}

require_python3() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 not found — required to build the pdlc skills for this tool." >&2
    exit 1
  fi
}

# 构建投影用的源码目录：在克隆里跑就用克隆；curl 管道跑（没有克隆）就下载 main 的源码包到临时目录。
# 用 main 而不是最新 tag，与 Claude Code 插件市场装的版本一致。
# PDLC_SOURCE_TARBALL 可覆盖下载地址（测试用 file://，也可以指向某个 tag 的源码包）
SRC_DIR=""
SRC_TMP=""
PDLC_SOURCE_TARBALL="${PDLC_SOURCE_TARBALL:-https://codeload.github.com/${GITHUB_OWNER}/${GITHUB_REPO}/tar.gz/refs/heads/main}"

cleanup_src_tmp() {
  if [[ -n "$SRC_TMP" ]]; then rm -rf "$SRC_TMP"; fi
}

ensure_source() {
  if [[ "$IS_LOCAL_CLONE" -eq 1 ]]; then
    SRC_DIR="$SCRIPT_DIR"
    return
  fi
  if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    echo "Error: curl and tar are required to fetch pdlc-skills (or run install.sh from a local clone)." >&2
    exit 1
  fi
  SRC_TMP="$(mktemp -d "${TMPDIR:-/tmp}/pdlc-src.XXXXXX")"
  trap cleanup_src_tmp EXIT
  echo "Fetching pdlc-skills source (${PDLC_SOURCE_TARBALL}) ..."
  if ! curl -fsSL "$PDLC_SOURCE_TARBALL" | tar -xz -C "$SRC_TMP"; then
    echo "Error: could not download or unpack ${PDLC_SOURCE_TARBALL}" >&2
    exit 1
  fi
  # 源码包解开是一层 <仓库名>-<分支或 tag>/ 目录
  SRC_DIR="$(find "$SRC_TMP" -mindepth 2 -maxdepth 2 -path '*/.claude-plugin' -type d | head -1)"
  SRC_DIR="${SRC_DIR%/.claude-plugin}"
  if [[ -z "$SRC_DIR" || ! -f "$SRC_DIR/adapters/build_agent_skills.py" ]]; then
    echo "Error: ${PDLC_SOURCE_TARBALL} does not look like a pdlc-skills source archive." >&2
    exit 1
  fi
}

# projection_dir <产物子目录名> —— 克隆里构建到 dist/ 下（方便贡献者查看），远程安装构建到临时目录
projection_dir() {
  if [[ "$IS_LOCAL_CLONE" -eq 1 ]]; then echo "$SRC_DIR/dist/$1"; else echo "$SRC_TMP/dist/$1"; fi
}

# Remove the v1.5.0 mistaken prompts install so upgraders don't keep dead files.
clean_legacy_codex_prompts() {
  if compgen -G "${CODEX_PROMPTS_DIR}/pdlc-*.md" >/dev/null 2>&1; then
    echo "Cleaning legacy v1.5.0 prompts from ${CODEX_PROMPTS_DIR} ..."
    rm -f "${CODEX_PROMPTS_DIR}"/pdlc-*.md
  fi
}

do_codex_install() {
  require_python3
  ensure_source

  local build_dir
  build_dir="$(projection_dir codex)"
  echo "Building Codex adapter from skills/ ..."
  python3 "$SRC_DIR/adapters/build_codex.py" "$build_dir"

  clean_legacy_codex_prompts

  echo ""
  echo "Installing Codex skills → ${CODEX_SKILLS_DIR}"
  mkdir -p "$CODEX_SKILLS_DIR" "$CODEX_PDLC_DIR"
  # v1.6.4 and earlier copied templates here; each skill now ships its own under assets/.
  rm -rf "${CODEX_PDLC_DIR:?}/templates"
  # Refresh our skill dirs (old copies are replaced wholesale so renamed/removed files don't linger).
  install_projection "$build_dir/skills" "$CODEX_SKILLS_DIR"
  cp "$build_dir/pdlc-methodology.md" "$CODEX_PDLC_DIR"/

  local n
  n=$(find "$build_dir/skills" -maxdepth 1 -type d -name 'pdlc-*' | wc -l | tr -d ' ')
  echo ""
  echo "✅ Done. ${n} pdlc skills installed for Codex."
  echo "   Restart Codex, then drive PDLC in natural language (skills are description-triggered,"
  echo "   NOT slash commands), e.g.:  用 pdlc 写个 PRD：<一句话需求>"
  echo "   Methodology: ${CODEX_PDLC_DIR}"
  echo "   Note: the statusline and the autonomous loop engine are Claude Code-only (not ported)."
  echo ""
  echo "   ⚠️  Scope: this adapter targets Codex distributions that read ~/.codex/skills/"
  echo "       (Claude-Code-compatible ones). Vanilla OpenAI Codex is UNVERIFIED — we have"
  echo "       no such environment to test on. If Codex ignores the skills after a restart,"
  echo "       it does not read that directory; fall back to the platform-neutral route:"
  echo "       append ${CODEX_PDLC_DIR}/pdlc-methodology.md to your project's AGENTS.md"
  echo "       and drive PDLC in natural language. Reports welcome via GitHub issues."
}

do_codex_uninstall() {
  # Only ever touches our own namespaced paths under ~/.codex.
  echo "Removing pdlc skills from ${CODEX_SKILLS_DIR} ..."
  rm -rf "${CODEX_SKILLS_DIR}"/pdlc-*/ "${CODEX_SKILLS_DIR}/.pdlc-version"
  clean_legacy_codex_prompts
  if [[ "$CODEX_PDLC_DIR" == "${HOME}/.codex/pdlc" && -d "$CODEX_PDLC_DIR" ]]; then
    rm -rf "$CODEX_PDLC_DIR"
  fi
  echo "✅ Removed pdlc from Codex. Restart Codex to drop the skills."
}

# ─── Target: agents (Agent Skills open standard, see docs/decisions/0007) ───
# One standard projection for every tool that loads Agent Skills. Destination:
#   --dest DIR      → DIR
#   --project DIR   → DIR/.agents/skills
#   (default)       → ~/.agents/skills
agents_dest() {
  if [[ -n "$DEST" ]]; then
    echo "$DEST"
  elif [[ "$SCOPE" == "project" ]]; then
    echo "$PROJECT/.agents/skills"
  else
    echo "${HOME}/.agents/skills"
  fi
}

do_agents_install() {
  require_python3
  ensure_source
  local dest build_dir n
  dest="$(agents_dest)"
  build_dir="$(projection_dir agent-skills)"
  echo "Building the Agent Skills projection from skills/ ..."
  python3 "$SRC_DIR/adapters/build_agent_skills.py" "$build_dir"
  echo ""
  echo "Installing Agent Skills → ${dest}"
  mkdir -p "$dest"
  # Refresh our own dirs only; other skills in the same directory are left alone.
  install_projection "$build_dir/skills" "$dest"
  n=$(find "$build_dir/skills" -maxdepth 1 -type d -name 'pdlc-*' | wc -l | tr -d ' ')
  echo ""
  echo "✅ Done. ${n} pdlc skills installed in ${dest}"
  echo "   Restart your tool; skills trigger by description, e.g.:  用 pdlc 写个 PRD：<一句话需求>"
  echo "   Verified tools and the ones still unverified are listed in the README (\"Supported platforms\")."
}

do_agents_uninstall() {
  local dest
  dest="$(agents_dest)"
  echo "Removing pdlc skills from ${dest} ..."
  rm -rf "${dest:?}"/pdlc-*/ "${dest:?}/.pdlc-version"
  echo "✅ Removed. Other skills in ${dest} were not touched."
}

# ─── Argument parsing ───
ACTION="install"
SCOPE=""
PROJECT=""
TARGET="claude"   # claude (default) | codex | agents
DEST=""

# 带值的选项：缺值时 set -e 下的 shift 2 会让脚本不声不响地退出，所以先点名报错。
# 下一个参数以 - 开头也算缺值，免得 --dest --uninstall 把选项当成目录
need_value() {
  if [[ -z "${2:-}" || "${2}" == -* ]]; then
    echo "Error: $1 requires a value" >&2
    usage >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)      SCOPE="user"; shift ;;
    --project)     need_value "$1" "${2:-}"; SCOPE="project"; PROJECT="$2"; shift 2 ;;
    --target)      need_value "$1" "${2:-}"; TARGET="$2"; shift 2 ;;
    --dest)        need_value "$1" "${2:-}"; DEST="$2"; shift 2 ;;
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
elif [[ "$TARGET" == "agents" ]]; then
  if [[ "$SCOPE" == "project" && -z "$DEST" ]]; then
    [[ -n "$PROJECT" ]] || { echo "Error: --project requires a path." >&2; exit 1; }
    [[ -d "$PROJECT" ]] || { echo "Error: project directory not found: $PROJECT" >&2; exit 1; }
  fi
  case "$ACTION" in
    install)   do_agents_install; exit 0 ;;
    uninstall) do_agents_uninstall; exit 0 ;;
    *) echo "Error: --target agents supports install / --uninstall only." >&2; exit 1 ;;
  esac
elif [[ "$TARGET" != "claude" ]]; then
  echo "Error: unknown --target '$TARGET' (supported: claude, codex, agents)." >&2
  exit 1
fi
[[ -z "$DEST" ]] || { echo "Error: --dest is only valid with --target agents." >&2; exit 1; }

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
    echo "Restart Claude Code, then type /pdlc- to see all 38 sub-commands."
    echo ""
    echo "⭐ If pdlc helps you ship, a star helps others find it:"
    echo "   https://github.com/kanfu-panda/pdlc-skills"
    ;;
  upgrade)
    # 先刷新 marketplace：否则 plugin update 只看本地缓存的旧目录，可能「升级」到原来的版本
    echo "Refreshing marketplace ${MARKETPLACE_NAME}..."
    claude plugin marketplace update "${MARKETPLACE_NAME}" 2>&1 | tail -3
    echo "Updating ${PLUGIN_NAME}@${MARKETPLACE_NAME}..."
    claude plugin update "${PLUGIN_NAME}@${MARKETPLACE_NAME}"
    echo ""
    echo "✅ Updated. Restart Claude Code to apply."
    echo ""
    echo "⭐ If pdlc helps you ship, a star helps others find it:"
    echo "   https://github.com/kanfu-panda/pdlc-skills"
    ;;
  uninstall)
    echo "Uninstalling ${PLUGIN_NAME}@${MARKETPLACE_NAME}..."
    claude plugin uninstall "${PLUGIN_NAME}@${MARKETPLACE_NAME}"
    echo ""
    echo "✅ Uninstalled."
    ;;
esac
