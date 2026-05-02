# PDLC Skill

**English** · **[中文](./README.zh-CN.md)**

[![CI](https://github.com/kanfu-panda/pdlc-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/kanfu-panda/pdlc-skills/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Version](https://img.shields.io/badge/version-1.1.0-blue)](./CHANGELOG.md)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-skill-orange)](https://docs.anthropic.com/)

> Author: **LEO**
> Repo: [github.com/kanfu-panda/pdlc-skills](https://github.com/kanfu-panda/pdlc-skills)
> License: [MIT](./LICENSE)

**PDLC Skill** is a [Claude Skill](https://docs.anthropic.com/) that gives Claude Code a complete Product Development Life Cycle workflow — 31 standardized commands covering **PRD → Design → TDD → Implement → Review → Ship → Deploy → Retro**.

Instead of remembering which command to run, you just describe what you want ("build a login feature", "fix the pagination crash", "release the next version"), and Claude picks the right command, enforces the engineering discipline (tests before code, state-machine tracking, self-check gates), and writes real files to disk.

Currently **Claude Code only**. The skill is distributed as a single `SKILL.md` entry file plus a `references/` tree that Claude reads on demand.

---

## Why PDLC

Without this skill, an AI assistant working on a feature typically:

- Says it built the feature, but the PRD lives only in the chat transcript.
- Writes code without writing tests first.
- Skips the design step, which means architectural drift accumulates silently.
- Has no memory between sessions of which stage a feature is in.

**PDLC Skill turns those soft conventions into hard contracts:**

| Hard contract | What it gives you |
|---|---|
| Every artifact lands on disk under `docs/` | You can `git diff` what the AI did |
| Every stage updates a per-feature state machine | `pdlc-status` always knows where you are |
| Tests must exist (and fail) before implementation | Real TDD red-light gate, not a suggestion |
| Each command runs a self-check before handing off | Catch drift at stage boundary, not in review |
| Auto-repair runs at most once | No infinite "fix → check → fix" loops |
| Each command declares its `next_step` | Multi-stage flows are command-driven, not memorized |

---

## Quick demo

A typical end-to-end flow looks like this:

```text
$ # In Claude Code:
$ /pdlc-feature add phone-number verification to user login

→ Allocating feature ID F20260502-01 (user-auth-phone)
→ Stage 1: writing PRD
   ✓ docs/01_requirements/prd/F20260502-01-user-auth-phone-prd.md
   ✓ self-check 8/8 passed
→ Stage 2: technical design
   ✓ docs/02_design/api/F20260502-01-user-auth-phone-api.md
   ✓ docs/02_design/database/F20260502-01-user-auth-phone-db.md
→ Stage 3: TDD red light
   ✓ 14 tests written, all failing as expected
→ Stage 4: implementation
   ✓ 14/14 tests now passing
→ Stage 5: code review + auto-repair
   ✓ 3 lint issues auto-fixed
   ✓ docs/07_reviews/code/F20260502-01-user-auth-phone-review.md
→ Stage 6: handoff
   📦 docs/.pdlc-state/F20260502-01.json updated
   👉 Next: /pdlc-ship
```

Every artifact above is a real file you can `git diff`. Run `/pdlc-status` any time to see where each feature stands.

---

## Install

> One-liner — no clone needed. Pulls the latest published release from GitHub.

```bash
# Global (~/.claude/skills/pdlc/)
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --global

# Project-scoped (<project>/.claude/skills/pdlc/)
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --project /path/to/my-project
```

That's it. The installer downloads the matching release tarball, extracts it, and copies only the skill files to your `.claude/skills/pdlc/` directory.

### Upgrade

Same one-liner — every invocation fetches the latest release:

```bash
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --upgrade --global
```

### Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --uninstall --global
```

### Pin to a specific version

```bash
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --global --ref v1.0.0
```

`--ref main` installs from the development branch (not recommended for end users).

### Check your version

```bash
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --version
```

Sample output:

```text
PDLC Skill version status
──────────────────────────────────────
  Installed (global):  1.0.0
  Latest on GitHub:    1.1.0

⚠️  Installed version (1.0.0) is behind latest (1.1.0).
    Upgrade:
      curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh | bash -s -- --upgrade --global
```

### For contributors / template customization

If you want to edit command bodies or document templates locally before installing:

```bash
git clone https://github.com/kanfu-panda/pdlc-skills.git
cd pdlc-skills
# edit references/templates/*.md or references/commands/*.md
bash install.sh --global
```

In a clone, `bash install.sh --self-update` runs `git pull` for you, and `bash install.sh --version` shows local-clone vs installed vs latest.

---

## Usage

After install, just talk to Claude Code in natural language:

```
Use the PDLC flow to build user login
Fix the pagination crash when the list is empty
Show me the current PDLC status
```

Claude reads `SKILL.md`, matches your intent to a command spec under `references/commands/<name>.md`, and follows the workflow defined there.

---

## Command catalog (three layers)

### Layer 1 · Entry points (3)

Start here if you're new — one-sentence prompts drive the whole chain.

| Command | Purpose |
|---|---|
| `feature` | End-to-end new feature (PRD → Design → TDD → Implement → Review → Ship) |
| `fix` | End-to-end bug fix (locate → reproduce → fix → test → document) |
| `status` | Show the project's PDLC state at a glance |

### Layer 2 · Stages (11)

Use when you want fine-grained control over one stage.

| Command | Purpose |
|---|---|
| `prd` | Author a PRD |
| `design` | Technical design |
| `tdd` | Write failing tests first |
| `implement` | Implement code against the design |
| `review` | Code + doc review |
| `e2e` | End-to-end tests |
| `refactor` | Refactor code |
| `ship` | Release workflow (tests → VERSION → CHANGELOG → tag → CI) |
| `deploy` | Deployment doc |
| `retro` | Iteration retrospective with trend comparison |
| `task` | In-stage task tracking |

### Layer 3 · Tools (17)

Specialized commands you can stack on top of the stages.

- **🎨 Design (4):** `ui-design` / `ui-design-pro` / `db-design` / `arch`
- **🔍 Quality (3):** `lint` / `perf` / `security`
- **🔧 Engineering (7):** `code-gen` / `add-service` / `add-app` / `api-mock` / `db-migrate` / `i18n` / `changelog`
- **🏗️ Project lifecycle (3):** `bootstrap` / `adopt` / `onboard`

---

## 3-step quick start

1. **Install:** `curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh | bash -s -- --project /path/to/my-project`
2. **Ship a feature:** tell Claude "use PDLC to add a captcha to login"
3. **Fix a bug:** tell Claude "use PDLC to fix the pagination crash on empty lists"

Check progress anytime: "show me PDLC status".

---

## Target-project contract

When a command runs, it reads and writes these paths in your project:

```
docs/01_requirements/prd/
docs/02_design/{api,database,architecture}/
docs/04_testing/{unit-tests,e2e-tests}/
docs/05_deployment/
docs/06_tasks/
docs/07_reviews/{doc,code}/
docs/.pdlc-state/<feature-id>.json   # one state-machine file per feature (e.g. F20260419-01.json)
```

---

## Document templates

`references/templates/` ships 9 standard document templates that Claude fills in per feature:

- `prd-template.md` — Product Requirements Document
- `api-design-template.md` — API design
- `arch-design-template.md` — Architecture design
- `db-design-template.md` — Database schema design
- `db-migrate-template.md` — DB migration script
- `test-plan-template.md` — Test plan
- `deploy-doc-template.md` — Deployment manual
- `changelog-template.md` — Changelog entry
- `adopt-report-template.md` — Legacy-project adoption report

---

## The Iron Law

Every Layer 1 / Layer 2 command enforces five invariants (via `references/templates/prompts/iron-law.md`):

1. **Persist to disk** — every artifact is a real file, not just chat output
2. **Update the state machine** — every completed stage writes `docs/.pdlc-state/<feature-id>.json`
3. **Tests first** — code cannot be implemented until a failing test exists (TDD red light)
4. **Self-check** — every stage runs a self-audit before handing off
5. **One-shot repair** — auto-fix loops run at most once; stubborn failures get flagged for humans

---

## Verify the install

```bash
ls ~/.claude/skills/pdlc/              # global
ls <project>/.claude/skills/pdlc/      # project-scoped
```

Then ask Claude Code to list available skills — you should see `pdlc`.

---

## Questions / discussion

For usage questions, design discussions, or "is this a bug or am I holding it wrong" — please use [GitHub Discussions](https://github.com/kanfu-panda/pdlc-skills/discussions) rather than opening an Issue.

For confirmed bugs and feature requests, open an [Issue](https://github.com/kanfu-panda/pdlc-skills/issues) with the bundled templates.

For private security concerns, see [SECURITY.md](./SECURITY.md).

---

## Development

Run the tests locally:

```bash
bash tests/frontmatter-check.sh   # validate required frontmatter fields on every command
bash tests/install-smoke.sh       # end-to-end install + layout checks
```

See [CONTRIBUTING.md](./CONTRIBUTING.md) for PR workflow and coding conventions.

Architecture deep-dive: [docs/reference.md](./docs/reference.md) · Everyday usage: [docs/usage-guide.md](./docs/usage-guide.md) · Release notes: [CHANGELOG.md](./CHANGELOG.md).

---

## License

[MIT](./LICENSE) — use it, fork it, ship it.
