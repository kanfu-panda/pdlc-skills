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

Three layers:

- **Layer 1 — ops** (`pdlc-status`, `pdlc-adopt`, ...): read-mostly, project-wide views.
- **Layer 2 — core pipeline** (`pdlc-prd`, `pdlc-design`, `pdlc-tdd`, `pdlc-implement`, `pdlc-review`, `pdlc-ship`, ...): the staged lifecycle, feature-scoped, state-machine-driven.
- **Layer 3 — engineering helpers** (`pdlc-arch`, `pdlc-changelog`, `pdlc-standard`, `pdlc-relate`, ...): focused tools, not always feature-scoped.

## 3. Shared prompt fragments

Skills inline reusable instruction blocks via `<!-- @include templates/prompts/X.md -->` (paths relative to `references/`). This keeps cross-cutting contracts single-sourced:

- `iron-law.md` — the five non-negotiable gates.
- `pdlc-trace.md` — the document traceability header.
- `state-update.md` — the per-feature state machine schema + update flow.
- `self-audit.md` / `loop-prevention.md` / `handoff.md` — the four-phase skeleton.
- `feature-id.md` / `defect-id.md` — ID allocation.
- `output-language.md` — output language rules.
- `relations.md` — the v1.1 relation-chain definition (six types, five expression sites, validation rules).

The `@include` is a runtime convention interpreted by Claude, not a build-time preprocessor.

## 4. Target-project contract

When applied to a target project, PDLC skills produce and maintain a fixed layout:

```
docs/
├── ARCHITECTURE.md              # surface · whole-system overview (pdlc-arch)
├── GLOSSARY.md                  # surface · project vocabulary (manual, no dedicated skill in v1.1)
├── 00_standards/                # surface · team conventions (pdlc-standard)
│   ├── _index.md
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

## 7. Quality gates

Two automated checks, run locally (no CI by default):

- `tests/frontmatter-check.sh` — required frontmatter fields, layer values, `@include` resolvability, `name == dir`, `next_step` resolves, manifest version sync.
- `tests/install-smoke.sh` — skill / template / fragment counts, manifest fields, key invariants.

