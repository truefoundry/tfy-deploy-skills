# TrueFoundry Deploy Skills

[![CI](https://github.com/truefoundry/tfy-deploy-skills/actions/workflows/ci.yml/badge.svg)](https://github.com/truefoundry/tfy-deploy-skills/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Deploy, monitor, and manage ML infrastructure on TrueFoundry using AI coding assistants.

Works as a **plugin** for Claude Code and Codex CLI (with enforced workflows, automatic health verification, and failure diagnosis), and as **rules + skills** for Cursor.

## Quick Start

### Prerequisites

Set your TrueFoundry credentials via environment variables or a `.env` file in your project root:

```bash
export TFY_BASE_URL=https://your-org.truefoundry.cloud
export TFY_API_KEY=tfy-...
```

No account yet? Run `uv run tfy register` to sign up. The `tfy` CLI and workspace selection are handled automatically -- skills install the CLI if missing and list your available workspaces at deploy time.

### Claude Code (Plugin -- Full Enforcement)

Add the marketplace and install the plugin:

```
/plugin marketplace add truefoundry/tfy-deploy-skills
/plugin install truefoundry@truefoundry-deploy-skills
```

Or interactively: `/plugin` → **Discover** tab → select **truefoundry** → **Install now**.

What you get:
- 22 skills loaded automatically
- 2 specialized agents (deploy orchestrator, troubleshoot)
- 5 hooks enforcing safe deployment workflows
- Automatic credential checks on session start
- Post-deploy health verification and failure diagnosis

### Codex CLI (Plugin -- Full Enforcement)

Clone the repo and point Codex at it, or install via the Codex plugin system:

```bash
codex install truefoundry/tfy-deploy-skills
```

Enable hooks in your `config.toml`:

```toml
codex_hooks = true
```

Same hooks and skills as Claude Code. Agents are defined in `AGENTS.md` for Codex.

### Cursor (Rules -- Advisory)

Copy the skills into Cursor's config directory:

```bash
npx skills add truefoundry/tfy-deploy-skills -g -a cursor -s '*' -y
```

What you get:
- 22 skills as context rules
- No hook enforcement (Cursor does not support hooks)
- Skills provide guidance but cannot block unsafe operations

### Standalone Skills (Any Agent)

For any agent that supports the [Agent Skills](https://agentskills.io) open format:

```bash
npx skills add truefoundry/tfy-deploy-skills -g -a claude-code -a cursor -a codex -s '*' -y
```

Or install for all detected agents:

```bash
npx skills add truefoundry/tfy-deploy-skills --all
```

## What You Can Do

Just ask your agent in plain English:

- *"deploy my FastAPI app"*
- *"launch a Jupyter notebook with a GPU"*
- *"deploy Postgres with Helm"*
- *"deploy an LLM with vLLM"*
- *"show logs for my-service"*
- *"what's my connection status?"*

## What's Included

### 22 Skills

| Category | Skills |
|----------|--------|
| **Deploy** | [applications](skills/applications), [deploy](skills/deploy), [gitops](skills/gitops), [helm](skills/helm), [jobs](skills/jobs), [llm-deploy](skills/llm-deploy), [ml-repos](skills/ml-repos), [notebooks](skills/notebooks), [service-test](skills/service-test), [ssh-server](skills/ssh-server), [tracing](skills/tracing), [volumes](skills/volumes), [workflows](skills/workflows), [workspaces](skills/workspaces) |
| **Operate** | [logs](skills/logs), [monitor](skills/monitor), [status](skills/status) |
| **Manage** | [access-control](skills/access-control), [access-tokens](skills/access-tokens), [docs](skills/docs), [onboarding](skills/onboarding), [secrets](skills/secrets) |

Installed skill names are namespaced as `truefoundry-<skill>` (e.g., `truefoundry-deploy`).

### Plugin Hooks (Claude Code and Codex)

| Hook | Type | What It Does |
|------|------|-------------|
| **Session Start** | SessionStart | Verifies credentials, auto-installs/upgrades the `tfy` CLI, tests API connectivity, lists accessible workspaces |
| **Block Deletes** | PreToolUse | Blocks all DELETE API calls -- redirects users to the TrueFoundry dashboard for manual deletion |
| **Auto-Approve API** | PreToolUse | Auto-approves `tfy-api.sh` and `tfy-version.sh` calls so the agent does not prompt for each API request |
| **Secret Scan** | PreToolUse | Blocks commands containing hardcoded API keys, tokens, or credentials -- enforces `tfy-secret://` references |
| **Deploy Monitor** | PostToolUse | Detects `tfy apply`/`tfy deploy` commands, polls deployment status with adaptive intervals, fetches logs on failure, verifies health on success |
| **Verification Gate** | Stop | Prevents the agent from finishing if a deployment is in progress or an endpoint is unreachable |

### Agents (Claude Code)

| Agent | Purpose |
|-------|---------|
| **deploy-orchestrator** | Orchestrates the full deployment lifecycle: credential check, workspace selection, secret creation, manifest validation, deploy, and post-deploy verification. Enforces strict tier ordering for multi-service deployments. |
| **troubleshoot** | Diagnoses deployment failures by fetching status, logs, and pod events. Matches error patterns (OOMKilled, CrashLoopBackOff, ImagePullBackOff, etc.) to root causes and suggests fixes. |

### Safety Guardrails

- **No delete operations** -- all delete requests are blocked and redirected to the dashboard
- **No hardcoded secrets** -- commands with inline credentials are blocked before execution
- **Mandatory workspace confirmation** -- agents always list workspaces and ask you to choose
- **Deployment verification gate** -- the agent cannot finish until deployments reach a terminal state and endpoints are reachable

## Architecture

```
tfy-deploy-skills/
  .claude-plugin/
    plugin.json            # Plugin manifest (name, version, userConfig)
    marketplace.json       # Marketplace metadata
  hooks/
    hooks.json             # Hook definitions (SessionStart, PreToolUse, PostToolUse, Stop)
    auto-approve-tfy-api.sh
  plugin-scripts/          # Hook implementations
    session-start.sh       # Credential + CLI bootstrap
    block-delete-operations.sh
    pre-tool-secret-scan.sh
    post-deploy-monitor.sh # Deployment polling + health checks
    stop-review-gate.sh    # Verification gate
  agents/
    deploy-orchestrator.md
    troubleshoot.md
  skills/
    _shared/               # Canonical copies of shared scripts and references
      scripts/             # tfy-api.sh, tfy-version.sh
      references/          # 13 shared reference docs
    deploy/SKILL.md        # One directory per skill
    monitor/SKILL.md
    ...
  scripts/                 # Dev tooling (lint, validate, sync, install)
```

Shared scripts and references live in `skills/_shared/` and are synced to individual skill directories via `./scripts/sync-shared.sh`. Never edit files in `skills/*/scripts/` or `skills/*/references/` directly.

## Feature Comparison

| Feature | Claude Code | Codex CLI | Cursor | Standalone Skills |
|---------|:-----------:|:---------:|:------:|:-----------------:|
| 22 skills | yes | yes | yes | yes |
| Hook enforcement | yes | yes | no | no |
| Auto credential check | yes | yes | no | no |
| Deploy monitoring | yes | yes | no | no |
| Delete blocking | yes | yes | no | no |
| Secret scan | yes | yes | no | no |
| Verification gate | yes | yes | no | no |
| Specialized agents | yes | no | no | no |
| CLI auto-install | yes | yes | no | no |

## Development

```bash
./scripts/sync-shared.sh              # Sync shared files to all skills
./scripts/validate-skills.sh           # Validate skill structure
./scripts/validate-skill-security.sh   # Offline security checks
./scripts/test-tfy-api.sh             # Unit tests (needs python3 + curl)
./scripts/install.sh                   # Install locally
```

Shell scripts must pass `shellcheck`. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

MIT
