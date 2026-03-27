# TrueFoundry Deployment Agent Skills

[![CI](https://github.com/truefoundry/tfy-deployment-agent-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/truefoundry/tfy-deployment-agent-skills/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Agent skills for deploying, monitoring, and managing ML infrastructure on [TrueFoundry](https://truefoundry.com). Follows the [Agent Skills](https://agentskills.io) open format.

Works with Claude Code, Cursor, Codex, OpenCode, Windsurf, Cline, and Roo Code.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/truefoundry/tfy-deployment-agent-skills/main/scripts/install.sh | bash
```

Restart your agent and start asking. If credentials are not set, your agent will prompt for them. You can also pre-set them via env vars or a `.env` file in your project root:

```bash
export TFY_BASE_URL=https://your-org.truefoundry.cloud
export TFY_HOST=https://your-org.truefoundry.cloud  # CLI host (same as TFY_BASE_URL)
export TFY_API_KEY=tfy-...  # https://docs.truefoundry.com/docs/generate-api-key
```

Do not commit `.env` files or API keys to Git.

If you do not have a TrueFoundry account yet, sign up first with:

```bash
uv run tfy register
```

`tfy register` is interactive. Depending on the registration server configuration, it may open a browser window for CAPTCHA or other human verification before asking you to finish email verification. After registration completes, open the tenant URL returned by the CLI, create a personal access token there, and then set `TFY_API_KEY` for the skills that use the platform API.

## What You Can Do

Just ask your agent in plain English:

- *"deploy my FastAPI app"*
- *"launch a Jupyter notebook with a GPU"*
- *"deploy Postgres with Helm"*
- *"set up a CI/CD pipeline with GitOps"*
- *"deploy an LLM with vLLM"*
- *"show logs for my-service"*
- *"set up a secret for my database password"*
- *"what's my connection status?"*

Your agent picks the right skill based on what you ask. Deployment skills are explicit-only: use wording like "deploy", "helm", or "llm deploy".

## Skills

| Category | Skills |
|----------|--------|
| **Deploy** | [applications](skills/applications), [deploy](skills/deploy), [gitops](skills/gitops), [helm](skills/helm), [jobs](skills/jobs), [llm-deploy](skills/llm-deploy), [ml-repos](skills/ml-repos), [notebooks](skills/notebooks), [service-test](skills/service-test), [ssh-server](skills/ssh-server), [tracing](skills/tracing), [volumes](skills/volumes), [workflows](skills/workflows), [workspaces](skills/workspaces) |
| **Shared** | [access-control](skills/access-control), [access-tokens](skills/access-tokens), [docs](skills/docs), [logs](skills/logs), [onboarding](skills/onboarding), [secrets](skills/secrets), [status](skills/status) |

Each skill is a standalone markdown file (`skills/{name}/SKILL.md`) following the [Agent Skills](https://agentskills.io) open format.

## How It Works

Skills are markdown files with instructions your agent reads at runtime. When you ask a question, your agent matches it to the right skill and follows the instructions — calling TrueFoundry APIs, running CLI commands, or both.

No SDKs to learn, no code to write. Your agent handles everything.

## Development

```bash
# Edit shared files in skills/_shared/, then sync to all skills
./scripts/sync-shared.sh

# Run local validation (including offline security checks)
./scripts/validate-skills.sh
./scripts/validate-skill-security.sh

# Optional: enable pre-push hook so checks run automatically before git push
./scripts/setup-git-hooks.sh

# Install and restart
./scripts/install.sh
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on adding new skills.

## Community

- [Contributing Guide](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)
- [Support](SUPPORT.md)

## License

MIT
