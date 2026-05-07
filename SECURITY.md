# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 1.x     | ✅        |

## Reporting an issue

If you find a security issue in this skill — for example, a problem in
`install.sh` that could write outside its declared install target, or a
prompt-injection vector in a command body that could be abused — please
report it privately rather than opening a public GitHub issue.

Preferred channel:

- Open a [private security advisory](https://github.com/kanfu-panda/pdlc-skills/security/advisories/new) on GitHub.

We aim to acknowledge reports within 7 days. After triage we will:

1. Confirm the scope and impact with you.
2. Develop a fix on a private branch.
3. Coordinate disclosure timing.
4. Credit you in the advisory and the changelog (unless you prefer to remain anonymous).

## Out of scope

The following are not considered issues for this project:

- Behaviour of Claude itself — please report to Anthropic.
- Issues in the user's *target project* unrelated to this skill.
- Bugs in third-party tools that this skill calls out to (linters, test runners, package managers, etc.).
