# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-06-04

Two RFCs landed: ledger/surface artifact separation (#5) and the feature relation chain (#6). 31 → 33 skills.

### Added

- **`/pdlc-standard`** (Layer 3) — manage `00_standards/` team conventions as **surface** artifacts: in-place edit, `_changelog.md` sidecar, git-log audit trail. Hard rule against `coding-style-v2.md`-style ledger detours.
- **`/pdlc-relate`** (Layer 3) — manage the feature relation chain. Six relation types (`extends`, `depends_on`, `supersedes`, `resolves`, `conflicts_with`, `relates_to`). Commands `set` / `query` / `impact` / `orphans` / `rebuild` / `validate`. The `impact <fid>` command reports a change's blast radius (direct / transitive / historical).
- `docs/ARCHITECTURE.md` and `docs/GLOSSARY.md` — surface artifacts; the repo now dogfoods both.
- New templates: `architecture-overview-template.md` (surface, whole-system) and `glossary-template.md`.
- New shared fragment `relations.md` — single source of truth for the six relation types and five expression sites.
- `artifact_type: surface | ledger` frontmatter field (optional, default `ledger`).
- State machine gains an optional `relations` block; `docs/.pdlc-state/_relations.json` (reverse index) and `_graph.md` (mermaid) are produced by `/pdlc-relate`.
- PDLC-TRACE header gains an optional `关系:` line; PRD template gains §6.1 relations table.

### Changed / Breaking

- **`/pdlc-arch`** now writes `docs/ARCHITECTURE.md` **in place** (surface) instead of accumulating dated `YYYYMMDD-arch-analysis.md` files. Legacy files are detected and moved to `docs/.archive/architecture/`. The three previously-inconsistent output paths (`02_design/architecture`, `07_reviews/design`, dated analysis) are reconciled to one.
- `/pdlc-bootstrap` adds legacy `*-arch-analysis.md` detection; per-feature `F-xxx-arch.md` (ledger) is retained and clarified vs the surface overview.
- Standards-reading skills (`pdlc-prd`, `pdlc-design`, `pdlc-tdd`, `pdlc-implement`, `pdlc-code-gen`, `pdlc-review`, `pdlc-onboard`) now hint `consider /pdlc-standard add` on lookup miss.
- `/pdlc-status` gains a relation-tree view (Phase 2: included in the default overview).

> Migration is automatic (legacy detect + archive), so this ships as a minor version. Existing projects without relations or surface docs stay valid — both subsystems are additive.

### Fixed

- Plugin author metadata corrected to `kanfu-panda` (was a placeholder) in `plugin.json`, `marketplace.json`, and both READMEs.

## [1.0.0] - 2026-05-07

Initial public release of **PDLC** — a Claude Code plugin that gives Claude a
complete Product Development Life Cycle workflow.

### Features

- **31 standardized stages** exposed as slash commands `/pdlc-feature`,
  `/pdlc-prd`, `/pdlc-tdd`, ..., `/pdlc-onboard`, organized in three layers:
  - **Layer 1** entry points (3): `pdlc-feature`, `pdlc-fix`, `pdlc-status`
  - **Layer 2** stages (11): `pdlc-prd`, `pdlc-design`, `pdlc-tdd`,
    `pdlc-implement`, `pdlc-review`, `pdlc-e2e`, `pdlc-refactor`, `pdlc-ship`,
    `pdlc-deploy`, `pdlc-retro`, `pdlc-task`
  - **Layer 3** tools (17): `pdlc-ui-design`, `pdlc-ui-design-pro`,
    `pdlc-db-design`, `pdlc-arch`, `pdlc-lint`, `pdlc-perf`, `pdlc-security`,
    `pdlc-code-gen`, `pdlc-add-service`, `pdlc-add-app`, `pdlc-api-mock`,
    `pdlc-db-migrate`, `pdlc-i18n`, `pdlc-changelog`, `pdlc-bootstrap`,
    `pdlc-adopt`, `pdlc-onboard`
- **9 user-facing document templates** (PRD, API design, architecture, DB
  design, DB migration, test plan, deployment manual, changelog, legacy-
  project adoption report).
- **9 reusable prompt fragments** under `references/templates/prompts/`:
  IRON LAW, feature/defect ID assignment, PDLC-TRACE header, handoff
  format, self-audit, state-update, loop-prevention, output-language.
- **IRON LAW invariants** enforced on every Layer 1/2 stage that
  produces artifacts:
  1. artifacts must be persisted to disk;
  2. the state machine must be updated on every stage transition;
  3. tests must exist (and be red) before implementation;
  4. a self-check must run before handoff;
  5. auto-repair runs at most once.
- **Per-feature state machine** at `docs/.pdlc-state/<feature-id>.json`,
  recording stage history, self-audit counts, and the next recommended
  stage.
- **Output language follows the user's conversation language** by
  default — Chinese conversation produces Chinese artifacts, English
  produces English. Users can explicitly override per artifact.

### Distribution

PDLC is shipped as a Claude Code **plugin** registered through the standard
`claude plugin install` mechanism. The repo doubles as a single-plugin
marketplace.

- **One-line remote install** — no clone required:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/kanfu-panda/pdlc-skills/main/install.sh \
    | bash -s -- --global
  ```
- Equivalent native commands:
  ```bash
  claude plugin marketplace add kanfu-panda/pdlc-skills
  claude plugin install pdlc@pdlc-skills
  ```
- **Local clone install** — for contributors and template customization.
- Installer flags: `--global`, `--project <path>`, `--upgrade`, `--uninstall`,
  `--version`, plus an interactive mode.

### Target-project contract

Stages read and write this structure inside the user's project:

```
docs/00_standards/coding/                              # coding standards (read-only)
docs/01_requirements/prd/                              # PRDs
docs/02_design/{api,database,architecture,ui-ux}/      # technical design
docs/03_development/                                   # developer manuals
docs/04_testing/{unit-tests,e2e-tests,defects,security,perf}/
docs/05_deployment/                                    # deployment docs
docs/06_tasks/                                         # task tracking
docs/07_reviews/{doc,code,design,retro}/               # review records
docs/.pdlc-state/<feature-id>.json                     # per-feature state machine
```

### Engineering

- **CI**: frontmatter validation, install smoke test, shellcheck.
- **Secret scan**: gitleaks workflow with project-specific allowlist.
- **Release automation**: tag push triggers a clean GitHub Release.
- **Dependabot**: weekly auto-update for GitHub Actions.
- **Defensive `.gitignore`** + comprehensive secrets policy in
  `CONTRIBUTING.md`.

[Unreleased]: https://github.com/kanfu-panda/pdlc-skills/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/kanfu-panda/pdlc-skills/releases/tag/v1.0.0
