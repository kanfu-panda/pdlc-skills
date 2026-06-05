# Contributing to PDLC

Thanks for your interest! This project is MIT-licensed and community contributions are welcome.

## How to contribute

### Ask a question / discuss an idea

For "how do I..." questions, design discussions, or anything where you're not yet sure whether the issue is a bug — please use [GitHub Discussions](https://github.com/kanfu-panda/pdlc-skills/discussions) first. Issues are reserved for confirmed bugs and concrete feature requests.

### Report a bug / request a feature

- Open an [Issue](https://github.com/kanfu-panda/pdlc-skills/issues)
- Pick the right template (Bug Report / Feature Request)
- Include repro steps, expected behavior, and actual behavior

### Submit a pull request

1. Fork the repo and create a branch (`feat/xxx`, `fix/xxx`, `docs/xxx`)
2. Edit sources under `skills/` or `references/templates/` — **never** edit the installed copies in `~/.claude/plugins/cache/`
3. Run the tests + shellcheck locally
4. Open a PR against `main` and describe the motivation

## Local development

### Directory layout

- `.claude-plugin/plugin.json` — plugin manifest (name, version, description, ...)
- `.claude-plugin/marketplace.json` — marketplace manifest (so the repo itself is a marketplace)
- `skills/pdlc-<name>/SKILL.md` — 33 sub-skill specs. Each becomes the slash command `/pdlc-<name>`.
- `references/templates/prompts/*.md` — shared prompt fragments referenced via `<!-- @include templates/prompts/<x>.md -->` from skill bodies
- `references/templates/*-template.md` — user-facing document templates
- `install.sh` — curl-based installer wrapping `claude plugin marketplace add` + `claude plugin install`
- `docs/usage-guide.md` — single user manual

### Run the tests

```bash
# Required frontmatter fields on every sub-skill
bash tests/frontmatter-check.sh

# End-to-end install + plugin layout verification
bash tests/install-smoke.sh

# Bash linting
shellcheck install.sh tests/*.sh
```

All three run automatically via GitHub Actions on every PR.

### Try your changes locally

From a fresh clone (or after edits):

```bash
# Register the local repo as a marketplace and install the plugin
claude plugin marketplace add /path/to/pdlc-skills
claude plugin install pdlc@pdlc-skills

# Or use the curl installer (calls the same commands under the hood)
bash install.sh --global
```

Then restart Claude Code and verify `/pdlc-` autocomplete shows all 33 sub-commands.

To uninstall: `claude plugin uninstall pdlc@pdlc-skills`.

## Coding conventions

### Required frontmatter fields

Every file under `skills/pdlc-<name>/SKILL.md` must declare: `name`, `description`, `argument-hint`, `allowed-tools`, `layer`, `stage`. The `name` field MUST equal the directory name (e.g. `name: pdlc-feature` for `skills/pdlc-feature/`).

If you add a new required field, also update `required_fields` in `tests/frontmatter-check.sh`.

### IRON LAW invariants

Every Layer 1 / Layer 2 sub-skill **that produces artifacts** must `@include templates/prompts/iron-law.md` to enforce:

- Artifacts persisted to disk
- State machine updated on every stage transition
- Tests exist (and fail) before implementation
- Self-check runs before handoff
- Auto-repair runs at most once

Read-only stages (e.g. `pdlc-status` with `produces: []`) are exempt.

### Shared prompt fragments

Put new shared prompts under `references/templates/prompts/` and reference them from skill bodies as:

```markdown
<!-- @include templates/prompts/<fragment-name>.md -->
```

The `templates/prompts/` prefix is a stable contract — don't rename it. The path is relative to `references/`.

### Naming new sub-skills

When adding a new sub-skill:

1. Create `skills/pdlc-<name>/SKILL.md` (directory name MUST start with `pdlc-`)
2. Set frontmatter `name: pdlc-<name>` (matches dir)
3. If the sub-skill has a successor stage, set `next_step: pdlc-<successor>`
4. Update README's stage catalog and `docs/usage-guide.md`'s Layer table

### Versioning

`VERSION` (canonical) and `.claude-plugin/plugin.json`'s `version` field must match. `tests/frontmatter-check.sh` asserts this.

## Keep docs in sync

Any change to the target-project contract (e.g. paths under `docs/01_requirements/`, `docs/02_design/`, etc.) must land in **both**:

1. The relevant skill bodies under `skills/pdlc-*/SKILL.md`
2. The `Target-project contract` section in README + `docs/usage-guide.md`

## Commit messages

Please use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat: add pdlc-xxx sub-skill`
- `fix: handle macOS path quirks in install.sh`
- `docs: refresh usage-guide`
- `test: add cases for frontmatter validation`

## Language

The project accepts contributions in **English or Chinese**. For maximum reach, English is preferred for:

- `README.md`, `plugin.json` description, `CONTRIBUTING.md`
- Issue / PR titles and descriptions
- Commit messages

Skill bodies and `docs/usage-guide.md` may remain in Chinese — Claude handles both languages transparently at runtime.

## Security & secrets policy

**Never commit secrets.** This project should contain only public, reviewable content — skill specs, document templates, prompt fragments, and the installer. Anything that resembles a credential is a hard line:

- API keys, OAuth tokens, GitHub PATs (`ghp_`, `gho_`, `github_pat_`), Slack tokens (`xox*`), AWS keys (`AKIA…`, `aws_secret_access_key`), `.pem` / `.key` / `.p12` files, `id_rsa`, JWTs, database connection strings with embedded passwords — never commit any of these.
- `.env` files (other than `.env.example` with placeholders) — never commit.
- `.claude/settings.local.json` — already in `.gitignore`; never commit.
- Internal hostnames, internal IPs, or anything that identifies private infrastructure — keep out of the repo.

**Defenses in place:**

1. `.gitignore` excludes the common credential filename patterns (see the file).
2. `.github/workflows/secret-scan.yml` runs [gitleaks](https://github.com/gitleaks/gitleaks) on every push to `main` and every PR. CI fails if a leak is detected.
3. `.gitleaks.toml` allowlists legitimate placeholders (e.g. `DB_PASSWORD: ****` in deploy templates) so the scanner stays signal-only.

**If you find a security issue or accidentally leak something:**

- See [SECURITY.md](./SECURITY.md) for the private disclosure path.
- If a secret was committed, treat it as compromised immediately — rotate it before requesting any history rewrite. Removing from history alone is not enough; assume any committed-and-pushed secret has been exposed.

## Code of conduct

Be respectful and constructive. We want this project to be a good place to hang out. See [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md).
