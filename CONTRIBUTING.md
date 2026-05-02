# Contributing to PDLC Skill

Thanks for your interest in PDLC Skill! This project is MIT-licensed and community contributions are welcome.

## How to contribute

### Ask a question / discuss an idea

For "how do I..." questions, design discussions, or anything where you're not yet sure whether the issue is a bug — please use [GitHub Discussions](https://github.com/kanfu-panda/pdlc-skills/discussions) first. Issues are reserved for confirmed bugs and concrete feature requests.

### Report a bug / request a feature

- Open an [Issue](https://github.com/kanfu-panda/pdlc-skills/issues)
- Pick the right template (Bug Report / Feature Request)
- Include repro steps, expected behavior, and actual behavior

### Submit a pull request

1. Fork the repo and create a branch (`feat/xxx`, `fix/xxx`, `docs/xxx`)
2. Edit sources under `references/commands/` or `references/templates/` — **never** edit the installed copies
3. Run the tests locally (see below)
4. Open a PR against `main` and describe the motivation

## Local development

### Directory layout

- `SKILL.md` — Claude Skill entry file (frontmatter + index)
- `references/commands/*.md` — 31 command specs (YAML frontmatter + Markdown body, with `@include` directives)
- `references/templates/prompts/*.md` — shared prompt fragments reused across commands
- `references/templates/*-template.md` — user-facing document templates
- `install.sh` — installer (bash, pure `rsync` into `.claude/skills/pdlc/`)

### Run the tests

```bash
# Required frontmatter fields on every command source file
bash tests/frontmatter-check.sh

# End-to-end install + layout verification
bash tests/install-smoke.sh
```

Both tests run automatically via GitHub Actions on PRs.

### Verify your install locally

```bash
bash install.sh --project /tmp/test-project
ls /tmp/test-project/.claude/skills/pdlc/
```

## Coding conventions

### Required frontmatter fields

Every file under `references/commands/*.md` must declare: `name`, `description`, `argument-hint`, `allowed-tools`, `layer`, `stage`.

If you add a new required field, also update `required_fields` in `tests/frontmatter-check.sh`.

### IRON LAW invariants

Layer 1 and Layer 2 commands must `@include templates/prompts/iron-law.md` to guarantee:

- Artifacts are persisted to disk
- The state machine is updated on every stage transition
- Tests exist (and fail) before implementation
- A self-check runs before handoff
- Auto-repair loops run at most once

### Shared prompt fragments

Put new shared prompts under `references/templates/prompts/` and reference them from commands as:

```markdown
<!-- @include templates/prompts/<name>.md -->
```

The `templates/prompts/` prefix is a stable contract — don't rename it.

## Keep docs in sync

Any change to the target-project contract (e.g. `docs/01_requirements/prd/` and related paths) must land in **both**:

1. The relevant command bodies under `references/commands/`
2. `docs/reference.md` (the source of truth for architecture and schema)

## Commit messages

Please use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat: add pdlc-xxx command`
- `fix: handle macOS path quirks in install.sh`
- `docs: refresh reference.md`
- `test: add cases for frontmatter validation`

## Language

The project accepts contributions in **English or Chinese**. For maximum reach, English is preferred for:

- `README.md`, `SKILL.md` frontmatter, `CONTRIBUTING.md`
- Issue / PR titles and descriptions
- Commit messages

Command bodies and internal docs (`docs/usage-guide.md`, `docs/reference.md`) may remain in Chinese — Claude handles both languages transparently at runtime.

## Code of conduct

Be respectful and constructive. We want this project to be a good place to hang out.
