# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-05-02

Initial public release of PDLC Skill — a Claude Code skill that gives Claude a
complete Product Development Life Cycle workflow.

### Added

- **31 standardized commands** organized in three layers:
  - **Layer 1** entry points (3): `feature`, `fix`, `status`
  - **Layer 2** stages (11): `prd`, `design`, `tdd`, `implement`, `review`, `e2e`, `refactor`, `ship`, `deploy`, `retro`, `task`
  - **Layer 3** tools (17): design, quality, engineering, project lifecycle
- **9 user-facing document templates** under `references/templates/`: PRD, API design, architecture, database design, database migration, test plan, deployment manual, changelog, legacy-project adoption report.
- **8 reusable prompt fragments** under `references/templates/prompts/`: IRON LAW, feature/defect ID assignment, PDLC-TRACE header, handoff format, self-audit, state-update, loop-prevention.
- **IRON LAW invariants** enforced on every Layer 1/2 command:
  1. artifacts must be persisted to disk;
  2. the state machine must be updated on every stage transition;
  3. tests must exist (and be red) before implementation;
  4. a self-check must run before handoff;
  5. auto-repair runs at most once.
- **Per-feature state machine** at `docs/.pdlc-state/<feature-id>.json`, recording stage history, self-audit counts, and the next recommended command.
- **Standard target-project layout** under `docs/01_requirements/`, `docs/02_design/`, `docs/04_testing/`, `docs/05_deployment/`, `docs/06_tasks/`, `docs/07_reviews/`.
- **`install.sh`** with `--global`, `--project <path>`, `--upgrade`, `--uninstall`, and an interactive mode.
- **Automated tests**: `tests/frontmatter-check.sh` (frontmatter schema, layer/IRON-LAW/`@include` validation) and `tests/install-smoke.sh` (end-to-end install layout), run on every PR via GitHub Actions.

[Unreleased]: https://github.com/kanfu-panda/pdlc-skills/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/kanfu-panda/pdlc-skills/releases/tag/v1.0.0
