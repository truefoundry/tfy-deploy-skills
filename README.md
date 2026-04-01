# TrueFoundry Deploy Skills

[![CI](https://github.com/truefoundry/tfy-deploy-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/truefoundry/tfy-deploy-skills/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Agent skills for deploying, monitoring, and managing ML infrastructure on [TrueFoundry](https://truefoundry.com). Follows the [Agent Skills](https://agentskills.io) open format.

Works with Claude Code, Cursor, Codex, OpenCode, Windsurf, Cline, and Roo Code.

## Prerequisite: Install TrueFoundry CLI First

Install the `tfy` CLI before using these skills (skills use CLI first with API fallback):

```bash
uv tool install --python 3.12 truefoundry
tfy --version
```

If you must use Python 3.14, install with the current pydantic beta workaround:

```bash
python3 -m pip install -U truefoundry "pydantic==2.13.0b1"
```

## Install

```bash
npx skills add truefoundry/tfy-deploy-skills -g -a claude,cursor,codex -s '*' -y
```

This installs all skills globally for Claude Code, Cursor, and Codex. To install for other agents or customize:

```bash
# All agents
npx skills add truefoundry/tfy-deploy-skills --all

# Specific agents
npx skills add truefoundry/tfy-deploy-skills -g -a claude,windsurf -s '*' -y

# Project-local install (instead of global -g)
npx skills add truefoundry/tfy-deploy-skills -a claude,cursor,codex -s '*' -y
```

`--all` installs all skills for all agents without interactive selection prompts.

Or with curl:

```bash
curl -fsSL https://raw.githubusercontent.com/truefoundry/tfy-deploy-skills/main/scripts/install.sh | bash
```

## Setup

Set credentials via env vars or a `.env` file in your project root:

```bash
export TFY_BASE_URL=https://your-org.truefoundry.cloud
export TFY_API_KEY=tfy-...
export TFY_WORKSPACE_FQN=your-org/your-workspace
```

`TFY_WORKSPACE_FQN` is required. Set it explicitly for the target workspace.

No account yet? Run `uv run tfy register` to sign up.

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
