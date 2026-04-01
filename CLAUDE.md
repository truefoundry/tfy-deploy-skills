# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Repository: `truefoundry/tfy-deploy-skills`

A collection of 21 AI agent skills (markdown + shell scripts) following the [Agent Skills](https://agentskills.io) open format. Skills let AI assistants deploy, monitor, and manage ML infrastructure on TrueFoundry. This is a content/tooling repo — no application servers, databases, or Docker containers.

Install: `npx skills add truefoundry/tfy-deploy-skills --all`

## Commands

| Task | Command |
|------|---------|
| Lint shell scripts | `shellcheck scripts/*.sh hooks/auto-approve-tfy-api.sh hooks/post-deploy-monitor.sh skills/_shared/scripts/tfy-api.sh` |
| Lint skill scripts | `find skills -mindepth 2 -name '*.sh' -print0 \| xargs -0 -r shellcheck` |
| Validate skills | `./scripts/validate-skills.sh` |
| Security checks | `./scripts/validate-skill-security.sh` |
| Security (changed only) | `./scripts/validate-skill-security.sh --changed` |
| Unit tests | `./scripts/test-tfy-api.sh` |
| Sync shared files | `./scripts/sync-shared.sh` |
| Install locally | `./scripts/install.sh` |
| Pre-push hook setup | `./scripts/setup-git-hooks.sh` |

Tests require `python3` and `curl` (mock HTTP server on ephemeral port, fully offline).

## Architecture

### Skill layout
Each of the 21 skills lives in `skills/{name}/SKILL.md` with YAML frontmatter (name, description, allowed-tools). Shared scripts and references live in `skills/_shared/` and are synced to individual skill directories via `./scripts/sync-shared.sh`.

### Core shared files
- `skills/_shared/scripts/tfy-api.sh` — authenticated REST API helper (reads `.env` safely, handles auth, retries, validation)
- `skills/_shared/scripts/tfy-version.sh` — version helper
- `skills/_shared/references/` — 13 shared markdown reference docs included by skills

### Explicit-only skills
Three skills have `disable-model-invocation: "true"` and require explicit user intent: **deploy**, **helm**, **llm-deploy**. If CLAUDE.md is tracked in git, `validate-skills.sh` checks that these three skill names appear in it.

## Critical Rules

- **Never edit files in `skills/*/scripts/` or `skills/*/references/` directly** — edit the canonical copy in `skills/_shared/` then run `./scripts/sync-shared.sh`
- **Never auto-pick `TFY_WORKSPACE_FQN`** — always ask the user to confirm, even if only one workspace exists
- **Adding a new skill** requires adding its name to the `SKILL_NAMES` array in `scripts/install.sh`
- **Shell scripts must pass shellcheck** (CI enforces this)
- **CLI-first with API fallback** — every skill should work with CLI when available, falling back to `tfy-api.sh`
