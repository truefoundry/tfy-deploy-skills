# TrueFoundry Deploy Skills

[![CI](https://github.com/truefoundry/tfy-deploy-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/truefoundry/tfy-deploy-skills/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Agent skills for deploying, monitoring, and managing ML infrastructure on [TrueFoundry](https://truefoundry.com). Follows the [Agent Skills](https://agentskills.io) open format.

Works with Claude Code, Cursor, Codex, OpenCode, Windsurf, Cline, and Roo Code.

## Install

```bash
npx skills add truefoundry/tfy-deploy-skills -g -a claude-code -a cursor -a codex -s '*' -y
```

This installs all skills globally for Claude Code, Cursor, and Codex. To install for other agents:

```bash
npx skills add truefoundry/tfy-deploy-skills --all
```

## Setup

Set your TrueFoundry credentials via env vars or a `.env` file in your project root:

```bash
export TFY_BASE_URL=https://your-org.truefoundry.cloud
export TFY_API_KEY=tfy-...
```

No account yet? Run `uv run tfy register` to sign up.

The `tfy` CLI and workspace selection are handled automatically — skills install the CLI if missing and list your available workspaces for you to choose from at deploy time.

## What You Can Do

Just ask your agent in plain English:

- *"deploy my FastAPI app"*
- *"launch a Jupyter notebook with a GPU"*
- *"deploy Postgres with Helm"*
- *"deploy an LLM with vLLM"*
- *"show logs for my-service"*
- *"what's my connection status?"*

## Skills

| Category | Skills |
|----------|--------|
| **Deploy** | [applications](skills/applications), [deploy](skills/deploy), [gitops](skills/gitops), [helm](skills/helm), [jobs](skills/jobs), [llm-deploy](skills/llm-deploy), [ml-repos](skills/ml-repos), [notebooks](skills/notebooks), [service-test](skills/service-test), [ssh-server](skills/ssh-server), [tracing](skills/tracing), [volumes](skills/volumes), [workflows](skills/workflows), [workspaces](skills/workspaces) |
| **Shared** | [access-control](skills/access-control), [access-tokens](skills/access-tokens), [docs](skills/docs), [logs](skills/logs), [onboarding](skills/onboarding), [secrets](skills/secrets), [status](skills/status) |

Installed skill names are namespaced as `truefoundry-<skill>` (for example, `truefoundry-deploy`) to avoid collisions with generic skill names.

Each skill is a standalone markdown file (`skills/{name}/SKILL.md`) following the [Agent Skills](https://agentskills.io) open format.

## Development

```bash
./scripts/sync-shared.sh              # Sync shared files to all skills
./scripts/validate-skills.sh           # Validate skill structure
./scripts/validate-skill-security.sh   # Offline security checks
./scripts/install.sh                   # Install locally
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

MIT
