<!-- artifact_type: surface -->

# Glossary

Canonical vocabulary for pdlc-skills. This is a **surface artifact**: edited in place, never versioned into `glossary-v2.md`. History lives in `git log docs/GLOSSARY.md`.

| Term | Definition |
|------|------------|
| **PDLC** | Product Development Life Cycle — the staged workflow this plugin encodes (PRD → design → TDD → implement → review → ship → deploy → retro). |
| **Skill** | A single Claude Code command, defined by a `SKILL.md` under `skills/<name>/`. Maps to a `/<name>` slash command. |
| **Layer** | Skill tier. Layer 1 (3) = entry points (`feature`/`fix`/`status`), Layer 2 (11) = core pipeline (PRD/design/tdd/implement/review/ship/...), Layer 3 (22) = specialized tools (arch, standards, relate, loop tooling, settings, ...). |
| **`@include`** | Comment-convention directive (`<!-- @include templates/prompts/X.md -->`) telling Claude to inline a shared prompt fragment. Not preprocessed — interpreted at runtime. |
| **Ledger-shaped artifact** | An **event** record: append-only, one file per occurrence, superseded but never edited in place. Example: per-feature PRDs, designs, `F-xxx-arch.md`. |
| **Surface-shaped artifact** | A **state** snapshot: one canonical file, edited in place, history via git. Example: `ARCHITECTURE.md`, `GLOSSARY.md`, `00_standards/`. |
| **`artifact_type`** | SKILL.md frontmatter field marking a skill's output as `surface` or `ledger` (default). Introduced in v1.1. |
| **PDLC-TRACE** | The traceability header comment block every numbered document carries (feature ID, stage, predecessor, timestamp, optional relations). |
| **State machine** | Per-feature JSON at `docs/.pdlc-state/<feature-id>.json` tracking `current_stage`, `history`, and `relations`. |
| **Feature ID** | `F<YYYYMMDD>-<HHMMSS>` identifier (creation-time; e.g. `F20260717-122801`) assigned at PRD/feature start, threaded through all downstream artifacts. Defects use `B<YYYYMMDD>-<HHMMSS>`. Time-based to avoid collisions under parallel/multi-agent work; legacy `-<NN>` sequence IDs still parse. |
| **Relation chain** | The graph of typed edges between features (v1.1). Six types: `extends`, `depends_on`, `supersedes`, `resolves`, `conflicts_with`, `relates_to`. |
| **`_relations.json`** | Auto-generated reverse index of all feature relations, rebuilt by `/pdlc-relate rebuild`. Stores nodes + flat edges + precomputed inbound/outbound per node. |
| **`_graph.md`** | Auto-generated mermaid visualization of the relation chain. Do not hand-edit. |
| **`last_phase_result`** | Top-level state-machine field (v1.2): machine-readable result of the last stage — `ok`, `advanced_to`, objective `checks` (from real command exit codes, not self-audit), `blocked_reason`, `run_mode`. The single source of truth an autonomous loop reads to decide continue / stop / hand back. |
| **`--autonomous` / `run_mode`** | Non-interactive contract (v1.2): with `--autonomous`, procedural confirmations auto-advance and log to `auto_decisions[]`; genuine judgement calls write `blocked_reason` and stop; destructive actions always stay human. |
| **Loop tooling** | `pdlc-loop-next` (prints the next mechanical-convergence command) and `pdlc-loop-run` (convergence engine auto-advancing `tdd → implement → review` to `review_done` or blocked). Release (`ship`/`deploy`) always stays human. Added v1.2. |
| **Statusline segment** | `bin/pdlc-statusline.sh` (v1.4): optional, off-by-default one-line PDLC status for the Claude Code statusline, wired via the interactive `/pdlc-settings`. Reads `docs/.pdlc-state/`, empty outside PDLC projects. |
| **Iron Law** | The six non-negotiable gates every Layer 1/2 producing skill enforces (artifacts on disk, state appended, tests-before-code, mandatory self-audit, single-shot repair, and — added v1.2 — state-must-advance so autonomous loops can't spin on stale state). |
