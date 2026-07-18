# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

pdlc-skills is a **Claude Code plugin**. It exposes 35 standardized "Product Development Life Cycle" stages as slash commands (`/pdlc-feature`, `/pdlc-prd`, `/pdlc-tdd`, ..., `/pdlc-onboard`) covering PRD → Design → TDD → Implement → Review → Ship → Deploy → Retro and 21 specialized tools.

The repo is **both a plugin and a single-plugin marketplace** (so `claude plugin marketplace add github:kanfu-panda/pdlc-skills` registers it directly).

This plugin is **Claude Code only** — it relies on Claude Code's plugin / skill mechanism. There's no port to Cursor, Copilot, Cline, etc.

## Repository layout

```
pdlc-skills/
├── .claude-plugin/
│   ├── plugin.json                 ← plugin manifest (name, version, author, ...)
│   └── marketplace.json            ← marketplace manifest (so the repo is also a marketplace)
├── skills/                         ← 35 sub-skills (each = one slash command)
│   ├── pdlc-feature/SKILL.md       → /pdlc-feature
│   ├── pdlc-prd/SKILL.md           → /pdlc-prd
│   ├── pdlc-tdd/SKILL.md           → /pdlc-tdd
│   └── ... (35 dirs total)
├── references/
│   └── templates/
│       ├── *-template.md           ← 9 user-facing document templates
│       └── prompts/*.md            ← 9 shared prompt fragments (iron-law / handoff / ...)
├── install.sh                      ← curl-based one-line installer wrapping `claude plugin install`
├── docs/
│   └── usage-guide.md              ← single user manual (architecture + reference + scenarios)
├── tests/
│   ├── frontmatter-check.sh        ← validates skills/<name>/SKILL.md frontmatter
│   └── install-smoke.sh            ← end-to-end install layout test
└── VERSION                         ← canonical version (mirrored in plugin.json)
```

## Sub-skill naming

Every sub-skill at `skills/pdlc-<name>/SKILL.md` becomes the slash command `/pdlc-<name>` in Claude Code. The `pdlc-` prefix is **part of the skill name**, not a namespace separator. We chose this over the colon namespace `/pdlc:<name>` for two reasons:

1. Visual distinctiveness — typing `/pdlc-` filters cleanly to all 35 PDLC commands; suffix-only names (`/feature`, `/fix`) collide with built-in commands and other plugins.
2. Backwards compatibility — matches the v1 mental model of `/pdlc-feature`.

The full plugin namespace is `pdlc:pdlc-<name>` formally, but Claude Code's autocomplete simplifies to `/pdlc-<name>` since the suffix is unique. Both invocations route to the same skill.

## Common commands

Install / upgrade / uninstall (uses Claude Code's `claude plugin` CLI under the hood):

```bash
# One-line curl install
curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
  | bash -s -- --global

# Or, equivalent native commands
claude plugin marketplace add kanfu-panda/pdlc-skills
claude plugin install pdlc@pdlc-skills
```

For local development from a clone:

```bash
claude plugin marketplace add /Users/me/projects/pdlc-skills
claude plugin install pdlc@pdlc-skills
```

Tests (run via GitHub Actions on every PR; can also be run manually):

```bash
bash tests/frontmatter-check.sh   # validate skills/*/SKILL.md frontmatter
bash tests/install-smoke.sh       # end-to-end install layout assertions
shellcheck install.sh tests/*.sh  # bash linting
```

## How sub-skills compose

Each `skills/pdlc-<name>/SKILL.md` has:

- YAML frontmatter (`name`, `description`, `argument-hint`, `allowed-tools`, plus PDLC-internal fields `layer`, `stage`, `produces`, `requires`, `next_step`, `terminal_state`)
- Markdown body — the workflow Claude follows when the slash command fires
- `<!-- @include templates/prompts/<x>.md -->` directives — shared prompt fragments (IRON LAW, handoff, self-audit, etc.) that Claude inlines from `references/templates/prompts/<x>.md` at runtime

The `@include` mechanism is **not** preprocessed by Claude Code — it relies on Claude reading the comment and following it on demand. This works in practice but is not a documented Claude Code feature.

## Layer structure

Sub-skills are grouped by `layer:` in frontmatter (the 35 names below all carry the `pdlc-` prefix):

- **Layer 1 (3)**: `pdlc-feature`, `pdlc-fix`, `pdlc-status` — one-sentence-driven entry points
- **Layer 2 (11)**: `pdlc-prd`, `pdlc-design`, `pdlc-tdd`, `pdlc-implement`, `pdlc-review`, `pdlc-e2e`, `pdlc-refactor`, `pdlc-ship`, `pdlc-deploy`, `pdlc-retro`, `pdlc-task` — single-stage fine control
- **Layer 3 (21)**: specialized tools (`pdlc-ui-design`, `pdlc-db-design`, `pdlc-arch`, `pdlc-lint`, `pdlc-perf`, `pdlc-security`, `pdlc-code-gen`, `pdlc-add-service`, `pdlc-add-app`, `pdlc-api-mock`, `pdlc-db-migrate`, `pdlc-i18n`, `pdlc-changelog`, `pdlc-standard`, `pdlc-relate`, `pdlc-bootstrap`, `pdlc-adopt`, `pdlc-onboard`, `pdlc-ui-design-pro`, `pdlc-loop-next`, `pdlc-loop-run`)

  `pdlc-loop-next` / `pdlc-loop-run` are loop tooling (Loop 工程 / autonomous drive): `loop-next` prints the next mechanical-convergence command for an outer loop; `loop-run` is the convergence engine that auto-advances `tdd → implement → review` to `review_done` or blocked (release always stays human). See `docs/decisions/0001-loop-engineering-integration.md`.

## Invariants enforced by the skills themselves

Every Layer 1/2 sub-skill **that produces artifacts** (i.e. `produces: []` is empty for read-only stages like `pdlc-status`) `@include`s `templates/prompts/iron-law.md`, which states the IRON LAW:

1. Artifacts must be persisted to disk (not just chat output)
2. The state machine `docs/.pdlc-state/<feature-id>.json` must be updated on every stage transition
3. Tests must exist (and be red) before implementation
4. A self-check runs before handoff
5. Auto-repair runs at most once

Skill bodies follow a four-phase skeleton (execute → self-check → one-shot repair → handoff), with `next_step:` in frontmatter declaring the next stage so multi-stage flows are command-driven, not memorized.

## Target-project contract

When the user invokes a `/pdlc-*` slash command in their project, the skill reads/writes these paths in that project:

- `docs/00_standards/coding/` — coding standards (read by `pdlc-prd` / `pdlc-implement` / `pdlc-tdd` / `pdlc-code-gen` / `pdlc-onboard`; optional)
- `docs/00_standards/test-commands.yml` — single source of the project's objective `check` commands (`unit` / `coverage` / `lint` / `e2e`), read by `pdlc-tdd` / `pdlc-implement` / `pdlc-review` and the loop drivers so `last_phase_result.checks` come from real exit codes, not model self-audit; template at `references/templates/test-commands-template.yml`; optional
- `docs/01_requirements/prd/`
- `docs/02_design/{api,database,architecture,ui-ux}/`
- `docs/03_development/` — developer manuals (`pdlc-onboard` writes here)
- `docs/04_testing/{unit-tests,e2e-tests,defects,security,perf}/`
- `docs/05_deployment/`
- `docs/06_tasks/`
- `docs/07_reviews/{doc,code,design,retro}/`
- `docs/.pdlc-state/<feature-id>.json` — per-feature state machine, ID format `F<YYYYMMDD>-<HHMMSS>` (creation-time, collision-safe under parallel work; legacy `-<NN>` still parses)

Changing this contract requires updating both the relevant `skills/pdlc-*/SKILL.md` bodies AND the `Target-project contract` sections in README and `docs/usage-guide.md`.

## When editing this plugin

- Edit sources under `skills/pdlc-<name>/SKILL.md` (sub-skill bodies), `references/templates/prompts/*.md` (shared fragments), or `references/templates/*-template.md` (user document templates). Don't edit installed copies in `~/.claude/plugins/cache/`.
- New required frontmatter fields → also update `required_fields` in `tests/frontmatter-check.sh`.
- Run both test scripts and shellcheck before committing.
- New shared prompt fragments → put under `references/templates/prompts/` and reference via `<!-- @include templates/prompts/<name>.md -->` (path is relative to `references/`).
- New sub-skill: create `skills/pdlc-<name>/SKILL.md` with the standard frontmatter (`name: pdlc-<name>`, layer/stage, produces/requires, etc.). The `pdlc-` prefix in directory and `name:` is mandatory.

## Bumping versions

`VERSION` and `.claude-plugin/plugin.json`'s `version` field must match. `tests/frontmatter-check.sh` asserts this.

## Notes

- Public-facing entry: `README.md` (English) and `README.zh-CN.md` (Chinese). They mirror each other.
- User manual: `docs/usage-guide.md` — single source containing install, command catalog, contract, scenarios, FAQ.
- This file (`CLAUDE.md`) is contributor-facing only and excluded from the installed plugin.
