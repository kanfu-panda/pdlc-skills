<!-- artifact_type: surface -->
<!-- PDLC-TRACE -->
<!-- 功能名称: 架构总览 -->
<!-- 阶段: design -->
<!-- 创建时间: 2026-06-03T00:00:00Z -->

# Architecture

System overview for pdlc-skills. This is a **surface artifact** — edited in place by `/pdlc-arch`, history via `git log docs/ARCHITECTURE.md`. It is also the canonical worked example of the surface pattern this plugin introduced in v1.1.

## 1. What this repo is

pdlc-skills is a **Claude Code plugin** plus a **single-plugin marketplace**. It ships a set of slash-command skills that encode a staged software development lifecycle, where each stage enforces hard contracts (artifacts persisted to disk, a per-feature state machine, tests-before-code, mandatory self-audit, single-shot auto-repair).

Two manifests express the dual nature:

- `.claude-plugin/plugin.json` — the plugin definition (name, version, metadata).
- `.claude-plugin/marketplace.json` — the marketplace wrapper so the repo can be added as a source directly.

## 2. Skill model

Every skill is a directory under `skills/<name>/` containing one `SKILL.md`. The frontmatter is a contract:

```yaml
name: <matches dir>
layer: 1 | 2 | 3
stage: <pipeline stage>
artifact_type: surface | ledger   # optional, default ledger (v1.1+)
produces: [<output globs>]
requires: []
next_step: <next skill | null>
terminal_state: <state | null>
```

Three layers (36 skills total: 3 / 11 / 22):

- **Layer 1 — entry points (3)** (`pdlc-feature`, `pdlc-fix`, `pdlc-status`): one-sentence-driven whole-flow drivers plus the read-only status view.
- **Layer 2 — core pipeline (11)** (`pdlc-prd`, `pdlc-design`, `pdlc-tdd`, `pdlc-implement`, `pdlc-review`, `pdlc-ship`, ...): the staged lifecycle, feature-scoped, state-machine-driven.
- **Layer 3 — specialized tools (22)** (`pdlc-arch`, `pdlc-standard`, `pdlc-relate`, `pdlc-bootstrap`, `pdlc-adopt`, the loop tooling `pdlc-loop-next` / `pdlc-loop-run`, the config command `pdlc-settings`, ...): focused tools, not always feature-scoped.

## 3. Shared prompt fragments

Skills inline reusable instruction blocks via `<!-- @include templates/prompts/X.md -->` (paths relative to `references/`). This keeps cross-cutting contracts single-sourced:

- `iron-law.md` — the six non-negotiable gates (the sixth, *state-must-advance*, added in v1.2).
- `pdlc-trace.md` — the document traceability header.
- `state-update.md` — the per-feature state machine schema + update flow (incl. the v1.2 `last_phase_result`).
- `self-audit.md` / `loop-prevention.md` / `handoff.md` — the four-phase skeleton.
- `feature-id.md` / `defect-id.md` — ID allocation.
- `output-language.md` — output language rules.
- `relations.md` — the v1.1 relation-chain definition (six types, five expression sites, validation rules).
- `noninteractive.md` — the v1.2 `--autonomous` contract (auto-advance procedural confirmations, block on judgement calls, destructive actions always human).

(11 fragments total.) The `@include` is a runtime convention interpreted by Claude, not a build-time preprocessor.

## 4. Target-project contract

When applied to a target project, PDLC skills produce and maintain a fixed layout:

```
docs/
├── ARCHITECTURE.md              # surface · whole-system overview (pdlc-arch)
├── GLOSSARY.md                  # surface · project vocabulary (manual, no dedicated skill in v1.1)
├── 00_standards/                # surface · team conventions (pdlc-standard)
│   ├── _index.md
│   ├── test-commands.yml        # surface · single source of objective check commands (v1.2)
│   └── <category>/<name>.md + _changelog.md
├── 01_requirements/prd/         # ledger · per-feature PRDs
├── 02_design/architecture/      # ledger · per-feature arch decisions (F-xxx-arch.md)
├── 06_tasks/                    # ledger · task breakdowns
├── 07_reviews/                  # ledger · review reports
└── .pdlc-state/
    ├── <feature-id>.json        # per-feature state machine + relations block
    ├── _relations.json          # auto · reverse index of all relations
    └── _graph.md                # auto · mermaid relation graph
```

## 5. Ledger vs surface (v1.1)

The defining v1.1 distinction:

- **Ledger artifacts** record events. They accumulate (one file per occurrence), are never edited in place, and are superseded rather than overwritten. PRDs, designs, and per-feature arch decisions are ledgers — you want the full chain.
- **Surface artifacts** record state. There is exactly one canonical file, edited in place, with history in git. Architecture overview, glossary, and team standards are surfaces — multiple dated copies are noise, not signal.

`/pdlc-arch` (surface) and `docs/02_design/architecture/F-xxx-arch.md` (ledger) are the canonical demonstration: a feature's arch decision is an event (ledger); the resulting system shape is a state (surface, derived).

## 6. Relation subsystem (v1.1)

Features form a typed graph (six relation types: `extends`, `depends_on`, `supersedes`, `resolves`, `conflicts_with`, `relates_to`). Relations are expressed redundantly at five sites (doc header, state block, reverse index, global graph, PRD §6.1) and reconciled by `/pdlc-relate rebuild`. The killer query is `/pdlc-relate impact <fid>` — the blast radius of changing a feature, split into direct / transitive / historical impact.

## 7. Autonomous loop subsystem (v1.2)

PDLC ships the three things loop engineering needs most — a precise spec (PRD/design), a real check (TDD tests), and a machine-readable state machine — so a loop can drive it unattended without burning quota:

- **Objective checks, not self-report.** Each stage writes a top-level `last_phase_result` whose `checks` (`tests_pass` / `coverage_pass` / `lint_clean`) come from **real command exit codes** (commands sourced from `00_standards/test-commands.yml`), never from model self-audit. This is the single field an outer loop reads to decide continue / stop / hand back.
- **`--autonomous` contract** (`noninteractive.md`): procedural confirmations auto-advance and are logged to `history[].auto_decisions[]`; genuine judgement calls write `blocked_reason` and stop; **destructive actions always stay human** (`--autonomous` has no effect on them). `run_mode` mirrors the flag into the state machine.
- **Convergence engine** `pdlc-loop-run`: auto-advances `tdd → implement → review` to `review_done` (or `blocked`), with a built-in iteration cap, fail-stop, and stuck-stop. Terminal state is `review_done` — **it never auto-ships** (`ship`/`deploy` are always human-gated).
- **Loop helper** `pdlc-loop-next`: read-only, prints the next mechanical-convergence command from a strict whitelist for user-written bash loops.

Design: `docs/decisions/0001-loop-engineering-integration.md`.

## 8. Statusline segment (v1.4)

An optional, **off-by-default** one-line PDLC status for the Claude Code statusline:

- `bin/pdlc-statusline.sh` — self-contained shell segment (not a Claude skill, since the statusline runs a shell command). Reads the session JSON from stdin, scans `<cwd>/docs/.pdlc-state/`, prints one line (feature · progress bar · next step · run icon · checks · elapsed; `blocked` rendered most-prominent). Empty outside PDLC projects; degrades silently without `jq`; bash 3.2 compatible.
- `pdlc-settings` (Layer 3, interactive) wires it up: a stable-path symlink `~/.claude/pdlc-statusline` (upgrade-safe) **appended** idempotently to the single `statusLine.command` (never overwrites an existing HUD). Editing global `~/.claude/settings.json` is backup+diff+confirm-gated and degrades gracefully to "here's the line, paste it" when the security layer blocks the write.

Design: `docs/decisions/0002-statusline-pdlc-status.md`.

## 9. Quality gates

Automated checks, run locally (no CI by default):

- `tests/frontmatter-check.sh` — required frontmatter fields, layer values, `@include` resolvability, `name == dir`, `next_step` resolves, manifest version sync.
- `tests/install-smoke.sh` — skill / template / fragment counts, manifest fields, key invariants.
- `tests/statusline-check.sh` — `pdlc-statusline.sh` render scenarios (interactive / autonomous / blocked / terminal / multi-feature pick / non-PDLC empty).

## 10. Platform-neutral core (multi-platform, planned)

The PDLC methodology, state-machine contract, doc layout, and objective-check discipline are **tool-agnostic** — nothing in them requires Claude Code. `docs/pdlc-methodology.md` distills this **Tier 1 core** as a self-contained, platform-neutral spec so any AI coding agent (Codex, Cursor, Windsurf, Copilot, Cline, …) can drive PDLC via natural language, with the same `docs/.pdlc-state/` shared across tools.

Claude Code stays the **Tier 2 first-class citizen** (this whole document). **Tier 3** — transpiling the SKILL bodies into each platform's native command files from a single source — is planned per-platform on real demand, starting with Codex.

Design: `docs/decisions/0003-multi-platform-adapters.md`.

