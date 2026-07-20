# pdlc-skills

**English** · **[中文](./README.zh-CN.md)**

[![CI](https://github.com/kanfu-panda/pdlc-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/kanfu-panda/pdlc-skills/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Version](https://img.shields.io/badge/version-1.5.2-blue)](./CHANGELOG.md)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-orange)](https://docs.anthropic.com/)

> Author: **kanfu-panda**
> Repo: [github.com/kanfu-panda/pdlc-skills](https://github.com/kanfu-panda/pdlc-skills)
> License: [MIT](./LICENSE)

**pdlc-skills** is a [Claude Code plugin](https://docs.anthropic.com/) that gives Claude a complete PDLC (Product Development Life Cycle) workflow — **36 standardized stages** exposed as slash commands `/pdlc-feature`, `/pdlc-prd`, `/pdlc-tdd`, `/pdlc-implement`, `/pdlc-review`, `/pdlc-ship`, etc.

Each stage enforces hard contracts (artifacts persisted to `docs/`, per-feature state machine, tests-before-code, mandatory self-check, single-shot auto-repair) so AI-driven engineering produces real, auditable files instead of chat-only output.

**Claude Code is the first-class citizen** (the plugin lives at `~/.claude/plugins/pdlc/` after install). The PDLC methodology itself is **platform-neutral**, so other AI coding tools can drive it too — **Codex CLI** via a native adapter today; Cursor / Windsurf / Copilot planned. See [Multi-platform](#multi-platform-other-ai-coding-tools).

---

## Why PDLC

Without this plugin, an AI assistant working on a feature typically:

- Says it built the feature, but the PRD lives only in the chat transcript.
- Writes code without writing tests first.
- Skips the design step, which means architectural drift accumulates silently.
- Has no memory between sessions of which stage a feature is in.

**PDLC turns those soft conventions into hard contracts:**

| Hard contract | What it gives you |
|---|---|
| Every artifact lands on disk under `docs/` | You can `git diff` what the AI did |
| Every stage updates a per-feature state machine | `/pdlc-status` always knows where you are |
| Tests must exist (and fail) before implementation | Real TDD red-light gate, not a suggestion |
| Each stage runs a self-check before handing off | Catch drift at stage boundary, not in review |
| Auto-repair runs at most once | No infinite "fix → check → fix" loops |
| Each stage declares its `next_step` | Multi-stage flows are command-driven, not memorized |

---

## Quick demo

A typical end-to-end flow looks like this:

```text
$ # In Claude Code:
$ /pdlc-feature add phone-number verification to user login

→ Allocating feature ID F20260502-090000 (user-auth-phone)
→ Stage 1: writing PRD
   ✓ docs/01_requirements/prd/F20260502-090000-user-auth-phone-prd.md
   ✓ self-check 8/8 passed
→ Stage 2: technical design
   ✓ docs/02_design/api/F20260502-090000-user-auth-phone-api.md
   ✓ docs/02_design/database/F20260502-090000-user-auth-phone-db.md
→ Stage 3: TDD red light
   ✓ 14 tests written, all failing as expected
→ Stage 4: implementation
   ✓ 14/14 tests now passing
→ Stage 5: code review + auto-repair
   ✓ 3 lint issues auto-fixed
   ✓ docs/07_reviews/code/F20260502-090000-user-auth-phone-review.md
→ Stage 6: handoff
   📦 docs/.pdlc-state/F20260502-090000.json updated
   👉 Next: /pdlc-ship
```

Every artifact above is a real file you can `git diff`. Run `/pdlc-status` any time to see where each feature stands. *(Output above is illustrative — actual Claude Code output is markdown, not ASCII.)*

---

## Install

> One-liner — no clone needed. Pulls the latest published release from GitHub.

```bash
# Global (~/.claude/plugins/pdlc/)
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --global

# Project-scoped (<project>/.claude/plugins/pdlc/)
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --project /path/to/my-project
```

That's it. The installer downloads the matching release tarball, extracts it, and copies only the plugin files to your `.claude/plugins/pdlc/` directory.

### Upgrade

```bash
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --upgrade --global
```

### Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --uninstall --global
```

### Check your version

```bash
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --version
```

### Equivalent native commands

If you'd rather call Claude Code's plugin CLI directly:

```bash
claude plugin marketplace add kanfu-panda/pdlc-skills
claude plugin install pdlc@pdlc-skills
```

### For contributors / template customization

```bash
git clone https://github.com/kanfu-panda/pdlc-skills.git
cd pdlc-skills
# edit references/templates/*.md or skills/pdlc-*/SKILL.md
bash install.sh --global   # installs from your local clone
```

---

## Verify the install

```bash
claude plugin list | grep pdlc
# expected: pdlc@pdlc-skills  Version: 1.5.2  Status: ✔ enabled
```

In Claude Code (after restarting the session), type `/` and start typing `pdlc-` — you should see all 36 sub-commands (`/pdlc-feature`, `/pdlc-prd`, `/pdlc-tdd`, ...) in autocomplete.

---

## Multi-platform (other AI coding tools)

Claude Code is the **first-class citizen** — 36 slash commands + statusline + autonomous loop. But the PDLC methodology, state machine, and templates are **platform-neutral**: the same `docs/.pdlc-state/` carries over no matter which tool drives it, so you can switch tools (or share a repo across a team on different tools) without losing PDLC state.

- **Any tool** (Codex, Cursor, Windsurf, Copilot, Cline, …): use the platform-neutral methodology doc [`docs/pdlc-methodology.md`](./docs/pdlc-methodology.md) as your project rules (`AGENTS.md` / `.cursor/rules` / `.github/copilot-instructions.md` / …), then drive PDLC in natural language ("run the PDLC review stage" → the agent follows the doc).
- **Codex** (native skills — for Claude-Code-compatible Codex distributions):
  ```bash
  git clone https://github.com/kanfu-panda/pdlc-skills.git
  cd pdlc-skills && bash install.sh --target codex
  ```
  Builds the adapter and installs 34 pdlc skills into `~/.codex/skills/` (the 2 Claude Code-only skills — statusline config + the autonomous loop engine — are skipped). Codex skills are **description-triggered, not slash commands** — after restarting Codex, drive PDLC in natural language (e.g. `用 pdlc 写个 PRD：<一句话需求>`). Requires a local clone + python3. Remove with `bash install.sh --target codex --uninstall`.
  - **Autonomous convergence** on Codex: `adapters/codex-loop-run.sh <feature-id> --project <dir>` drives `tdd → implement → review` to `review_done` (external Runbook; release stays human). Cleared the state-integrity admission gate on a real run — see [ADR 0004](./docs/decisions/0004-codex-loop-run.md).

Cursor / Windsurf / Copilot native adapters are planned per real demand. Design & roadmap: [ADR 0003](./docs/decisions/0003-multi-platform-adapters.md).

---

## Stage catalog (three layers)

### Layer 1 · Entry points (3)

One-sentence prompts drive the whole chain.

| Slash command | Purpose |
|---|---|
| `/pdlc-feature` | End-to-end new feature (PRD → Design → TDD → Implement → Review → Ship) |
| `/pdlc-fix` | End-to-end bug fix (locate → reproduce → fix → test → document) |
| `/pdlc-status` | Show the project's PDLC state at a glance |

### Layer 2 · Stages (11)

Use when you want fine-grained control over one stage.

| Slash command | Purpose |
|---|---|
| `/pdlc-prd` | Author a PRD |
| `/pdlc-design` | Technical design |
| `/pdlc-tdd` | Write failing tests first |
| `/pdlc-implement` | Implement code against the design |
| `/pdlc-review` | Code + doc review |
| `/pdlc-e2e` | End-to-end tests |
| `/pdlc-refactor` | Refactor code |
| `/pdlc-ship` | Release workflow (tests → VERSION → CHANGELOG → tag → CI) |
| `/pdlc-deploy` | Deployment doc |
| `/pdlc-retro` | Iteration retrospective with trend comparison |
| `/pdlc-task` | In-stage task tracking |

### Layer 3 · Tools (22)

Specialized stages you can invoke explicitly.

- **🎨 Design (4):** `/pdlc-ui-design` · `/pdlc-ui-design-pro` · `/pdlc-db-design` · `/pdlc-arch`
- **🔍 Quality (3):** `/pdlc-lint` · `/pdlc-perf` · `/pdlc-security`
- **🔧 Engineering (7):** `/pdlc-code-gen` · `/pdlc-add-service` · `/pdlc-add-app` · `/pdlc-api-mock` · `/pdlc-db-migrate` · `/pdlc-i18n` · `/pdlc-changelog`
- **🔗 Governance (2):** `/pdlc-standard` · `/pdlc-relate`
- **🏗️ Project lifecycle (3):** `/pdlc-bootstrap` · `/pdlc-adopt` · `/pdlc-onboard`
- **🔁 Loop tooling (2):** `/pdlc-loop-next` (prints the next mechanical-convergence command) · `/pdlc-loop-run` (convergence engine: auto-advances `tdd → implement → review` to `review_done`; release stays human) — [design](./docs/decisions/0001-loop-engineering-integration.md)
- **⚙️ Settings (1):** `/pdlc-settings` (interactive config; currently the optional PDLC statusline — enable/disable/display items) — [design](./docs/decisions/0002-statusline-pdlc-status.md)

---

## 3-step quick start

1. **Install** (one-line, no clone):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh | bash -s -- --global
   ```
2. **Ship a feature:** in Claude Code, run `/pdlc-feature add a captcha to login`
3. **Fix a bug:** `/pdlc-fix the pagination crash on empty lists`

Check progress anytime: `/pdlc-status`.

---

## Target-project contract

When a stage runs, it reads and writes these paths in your project:

```
docs/ARCHITECTURE.md                                        # surface · whole-system overview (pdlc-arch, in-place)
docs/GLOSSARY.md                                            # surface · project vocabulary
docs/00_standards/                                          # surface · team conventions (pdlc-standard; read by prd / implement / tdd / code-gen / onboard)
docs/00_standards/test-commands.yml                        # surface · single source of check commands (unit/coverage/lint/e2e) for tdd / implement / review + loop drivers
```

> The `check` commands in `test-commands.yml` are the objective source of truth for `last_phase_result.checks` (real exit codes, never model self-audit) — the foundation that lets `/pdlc-loop-*` drive PDLC autonomously. See `docs/decisions/0001-loop-engineering-integration.md`.

```
docs/01_requirements/prd/                                   # PRDs
docs/02_design/{api,database,architecture,ui-ux}/           # technical design
docs/03_development/                                        # developer manuals (onboard writes here)
docs/04_testing/{unit-tests,e2e-tests,defects,security,perf}/   # tests & defects
docs/05_deployment/                                         # deployment docs
docs/06_tasks/                                              # in-stage task tracking
docs/07_reviews/{doc,code,design,retro}/                    # review records
docs/.pdlc-state/<feature-id>.json                          # state machine + relations (one per feature, e.g. F20260419-090000.json)
docs/.pdlc-state/_relations.json                            # auto · reverse index of feature relations (pdlc-relate)
docs/.pdlc-state/_graph.md                                  # auto · mermaid relation graph
```

---

## Document templates

`references/templates/` ships 11 standard document templates that Claude fills in per feature:

- `prd-template.md` — Product Requirements Document
- `api-design-template.md` — API design
- `arch-design-template.md` — Architecture design (per-feature, ledger)
- `architecture-overview-template.md` — Whole-system architecture overview (surface)
- `db-design-template.md` — Database schema design
- `db-migrate-template.md` — DB migration script
- `test-plan-template.md` — Test plan
- `deploy-doc-template.md` — Deployment manual
- `changelog-template.md` — Changelog entry
- `glossary-template.md` — Project glossary (surface)
- `adopt-report-template.md` — Legacy-project adoption report

---

## The Iron Law

Every Layer 1 / Layer 2 stage **that produces artifacts** enforces six invariants. Read-only stages (such as `/pdlc-status`) are exempt.

1. **Persist to disk** — every artifact is a real file, not just chat output
2. **Update the state machine** — every completed stage writes `docs/.pdlc-state/<feature-id>.json`
3. **Tests first** — code cannot be implemented until a failing test exists (TDD red light)
4. **Self-check** — every stage runs a self-audit before handing off
5. **One-shot repair** — auto-fix loops run at most once; stubborn failures get flagged for humans
6. **State must advance** — a successful stage must change `current_stage`; a stage that didn't advance fails loudly instead of returning silently (so autonomous loops can't spin on stale state) — the exception is a deliberate human-block, which stays put but records `blocked_reason`

---

## Questions / discussion

For usage questions, design discussions, or "is this a bug or am I holding it wrong" — please use [GitHub Discussions](https://github.com/kanfu-panda/pdlc-skills/discussions) rather than opening an Issue.

For confirmed bugs and feature requests, open an [Issue](https://github.com/kanfu-panda/pdlc-skills/issues) with the bundled templates.

For private security concerns, see [SECURITY.md](./SECURITY.md).

---

## Development

Run the tests locally:

```bash
bash tests/frontmatter-check.sh   # validate every sub-skill's frontmatter
bash tests/install-smoke.sh       # end-to-end install + layout checks
```

See [CONTRIBUTING.md](./CONTRIBUTING.md) for PR workflow and coding conventions.

User manual: [docs/usage-guide.md](./docs/usage-guide.md) · Release notes: [CHANGELOG.md](./CHANGELOG.md).

---

## 💖 Support this project

PDLC is built and maintained in spare time. If it saves you hours (or sanity), consider supporting its development.

**Donation channels:**

- 🇨🇳 **[Afdian (爱发电)](https://afdian.com/a/kanfu-panda)** — for users in China; Alipay / WeChat Pay; native support for monthly tiers and one-time tips.
- 🌍 **[PayPal](https://paypal.me/Leosh980)** — for international users; any amount, one-time.

**Tiers (Afdian — choose monthly or one-time at the same amount):**

| Tier | Afdian | PayPal equivalent | What you get |
|---|---|---|---|
| ☕ Tip | ¥10 one-time | $1+ one-time | Thank-you. Not listed. |
| 🌱 Backer | ¥30/month | $5+ one-time | Your name on [SPONSORS.md](./SPONSORS.md) |
| 🌳 Sponsor | ¥66/month | $20+ one-time | Name + avatar + link on [SPONSORS.md](./SPONSORS.md) |
| 🏢 Enterprise | ¥888/month | $100+/month | Logo + link at the top of `README.md` |

If you donate via PayPal, please drop your GitHub handle in [a SPONSORS issue](https://github.com/kanfu-panda/pdlc-skills/issues/new?title=%5BSponsor%5D%20add%20me%20to%20the%20list) so we can add you to the list. The list is updated monthly — see [SPONSORS.md](./SPONSORS.md).

---

## License

[MIT](./LICENSE) — use it, fork it, ship it.
