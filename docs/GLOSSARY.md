<!-- artifact_type: surface -->

# Glossary

Canonical vocabulary for the PDLC plugin. This is a **surface artifact**: edited in place, never versioned into `glossary-v2.md`. History lives in `git log docs/GLOSSARY.md`.

| Term | Definition |
|------|------------|
| **PDLC** | Product Development Life Cycle — the staged workflow this plugin encodes (PRD → design → TDD → implement → review → ship → deploy → retro). |
| **Skill** | A single Claude Code command, defined by a `SKILL.md` under `skills/<name>/`. Maps to a `/<name>` slash command. |
| **Layer** | Skill tier. Layer 1 = ops/status (read-mostly), Layer 2 = core pipeline (PRD/design/tdd/...), Layer 3 = engineering helpers (arch, changelog, standards, relate). |
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
| **Iron Law** | The five non-negotiable gates every Layer 1/2 producing skill enforces (artifacts on disk, state appended, tests-before-code, mandatory self-audit, single-shot repair). |
