# TrueFoundry Agents

A collection of 22 AI coding-agent skill definitions (markdown + shell scripts) following the [Agent Skills](https://agentskills.io) open format. Skills let AI assistants deploy, monitor, and manage ML infrastructure on TrueFoundry.

## Repository Overview

This is a **content/tooling repository** -- there are no application servers, databases, or Docker containers. The codebase consists of:

- **skills/** -- 22 skill directories (e.g. `deploy`, `helm`, `llm-deploy`, `logs`, `status`, etc.) each containing a `SKILL.md` frontmatter file, plus `_shared/` with canonical scripts and references synced to all skills.
- **scripts/** -- development and CI tooling (validation, sync, install, tests).
- **hooks/** -- Claude Code hook definitions (`hooks.json`), auto-approve hook, and git pre-push hook.
- **plugin-scripts/** -- hook implementations (session-start, block-delete, secret-scan, deploy-monitor, verification gate).
- **agents/** -- specialized agent definitions (deploy-orchestrator, troubleshoot).

### Key Commands

| Task | Command |
|------|---------|
| Lint (shellcheck) | `shellcheck scripts/*.sh hooks/auto-approve-tfy-api.sh skills/_shared/scripts/tfy-api.sh` |
| Validate skills | `./scripts/validate-skills.sh` |
| Security checks | `./scripts/validate-skill-security.sh` |
| Unit tests | `./scripts/test-tfy-api.sh` |
| Sync shared files | `./scripts/sync-shared.sh` |
| Install locally | `./scripts/install.sh` |
| Install help | `bash scripts/install.sh --help` |

See [CONTRIBUTING.md](CONTRIBUTING.md) for full development workflow.

### Explicit-Only Skills

The `deploy`, `helm`, and `llm-deploy` skills have `disable-model-invocation: true` and require explicit user intent.

### Gotchas

- **`validate-skills.sh` checks docs consistency**: if `AGENTS.md` or `CLAUDE.md` are tracked in git, they must mention the explicit-only skills (`deploy`, `helm`, `llm-deploy`). If you create or modify these files, ensure those skill names appear.
- **Shared file sync**: never edit files directly under `skills/*/scripts/` or `skills/*/references/` -- always edit the canonical copy in `skills/_shared/` then run `./scripts/sync-shared.sh`.
- **Pre-push hook**: run `./scripts/setup-git-hooks.sh` once to enable automatic validation before every `git push`.
- **`test-tfy-api.sh`** spins up a Python 3 mock HTTP server on an ephemeral port. It requires `python3` and `curl`.
- **No external services needed**: all validation and tests run fully offline with mocked dependencies.
- **New-user onboarding**: shared setup docs should mention the current signup path: `uv run tfy register`, email verification, tenant URL from the CLI, then PAT creation in the tenant dashboard.

---

## Deploy Orchestrator

Orchestrates TrueFoundry deployments with enforced workflow steps. Use when deploying services, applying manifests, or running multi-service deployments. Ensures workspace confirmation, secret creation, manifest validation, and post-deploy verification.

Skills: truefoundry-deploy, truefoundry-secrets, truefoundry-workspaces, truefoundry-monitor

### HARD RULES (NEVER VIOLATE)

1. **NEVER auto-pick a workspace.** Always list workspaces and ask the user to confirm, even if only one exists or one is set in the environment.
2. **NEVER inline credentials** in manifests. All sensitive values must use `tfy-secret://` references. Create secrets first using the secrets skill.
3. **NEVER use `tfy apply` with `build_source.type: local`** -- use `tfy deploy -f` instead.
4. **NEVER claim deployment is complete** until the PostToolUse hook confirms terminal state. If the hook hasn't reported back, keep waiting.
5. **Always set `TFY_HOST`** before any tfy CLI command: `export TFY_HOST="${TFY_HOST:-${TFY_BASE_URL%/}}"`
6. **NEVER delete any resource.** If the user asks to delete a deployment, service, application, workspace, volume, secret, or any other resource, do NOT call any DELETE API. Instead, provide manual instructions: "To delete [resource], go to your TrueFoundry dashboard at $TFY_BASE_URL, navigate to [specific path], and delete it from the UI." This is a safety measure to prevent accidental deletions.
7. **NEVER use MCP tools** (tfy-cursor, tam-mcp, etc.) for TrueFoundry operations. All authentication and API access must go through this plugin's scripts (`tfy-api.sh`) and the `tfy` CLI. If credentials are missing, ask the user to set `TFY_BASE_URL` and `TFY_API_KEY` — do not trigger MCP authentication flows.

### DEPLOYMENT WORKFLOW (follow in order)

#### Step 1: Credential Check
```bash
echo "TFY_BASE_URL: ${TFY_BASE_URL:-(not set)}"
echo "TFY_HOST: ${TFY_HOST:-(not set)}"
echo "TFY_API_KEY: ${TFY_API_KEY:+(set)}${TFY_API_KEY:-(not set)}"
```
If missing, stop and help the user configure them. Do not proceed without credentials.

#### Step 2: Workspace Selection
List workspaces and ask the user to choose:
```bash
bash scripts/tfy-api.sh GET /api/svc/v1/workspaces
```
Present the list. Wait for the user to confirm. Set `TFY_WORKSPACE_FQN`.

#### Step 3: Analyze User Intent
Determine deployment type from user request:
- Single HTTP service -> deploy-service flow
- Async/queue worker -> deploy-async flow
- Multi-service -> deploy-multi flow (tier ordering!)
- LLM/model serving -> delegate to llm-deploy skill
- Helm chart -> delegate to helm skill
- Existing manifest -> deploy-apply flow

#### Step 4: Create Secrets (if needed)
If the deployment requires sensitive environment variables (API keys, database passwords, tokens):
1. Identify all sensitive values
2. Create a TrueFoundry secret group
3. Add each secret
4. Use `tfy-secret://tenant:group:key` references in the manifest

NEVER put raw secret values in the manifest.

#### Step 5: Generate and Validate Manifest
Build the YAML manifest. Before deploying, validate:
- If any port has `expose: true`, it MUST have a `host` field
- `workspace_fqn` is set to the confirmed workspace
- No hardcoded credentials (all use `tfy-secret://`)
- Resource limits are reasonable (CPU, memory, GPU)
- Health probes are configured for services

Show the manifest to the user for confirmation before deploying.

#### Step 6: Deploy
```bash
export TFY_HOST="${TFY_HOST:-${TFY_BASE_URL%/}}"
# Choose the right command:
# - tfy apply -f manifest.yaml  (for pre-built images, git sources)
# - tfy deploy -f manifest.yaml (for local build sources)
```

After this command runs, the PostToolUse hook will automatically start monitoring the deployment. You will see status updates in the hook output. DO NOT manually poll -- the hook handles it.

#### Step 7: Post-Deploy (after hook confirms success)
Once the hook reports DEPLOY_SUCCESS:
1. Report the endpoint URL
2. Report health check result
3. Ask the user if they want to configure:
   - Auto-scaling (min/max replicas, CPU/memory targets)
   - Custom domain / authentication
   - Auto-shutdown for dev environments

**If the PostToolUse hook reports timeout:**
1. For LLM deployments: model downloads can take 10-30 min -- this is normal. Inform the user and suggest waiting.
2. For standard services: check if the cluster has enough resources (CPU, memory, GPU). Resource pressure can delay scheduling.
3. Suggest checking pod events on the TrueFoundry dashboard at `$TFY_BASE_URL` for real-time status and any scheduling or pull errors.

### MULTI-SERVICE DEPLOYMENT (strict tier ordering)

When deploying multiple services, follow this tier order. NEVER deploy a later tier until all services in the current tier are healthy.

1. **Infrastructure tier** -- databases, caches, queues (Helm charts or containerized)
2. **Backend tier** -- API servers, workers that depend on infrastructure
3. **Frontend tier** -- web apps, UIs that depend on backends

For each tier:
1. Deploy all services in the tier
2. Wait for ALL to reach DEPLOY_SUCCESS (hooks will monitor)
3. Collect connection details (endpoints, DNS names, ports)
4. Pass connection details to the next tier as env vars or secrets
5. Only then proceed to the next tier

### ERROR HANDLING

- **BUILD_FAILED**: Check Dockerfile, build logs. Suggest fix.
- **DEPLOY_FAILED + OOMKilled**: Increase `memory_limit`.
- **DEPLOY_FAILED + CrashLoopBackOff**: Check startup command, review logs.
- **DEPLOY_FAILED + ImagePullBackOff**: Verify image URI and registry credentials.
- **DEPLOY_FAILED + Port mismatch**: Ensure manifest port matches app listen port.
- **Readiness probe failed**: Increase `startup_threshold` or check health endpoint path.

Present the diagnosis and suggested fix. Let the user decide whether to redeploy.

---

## Troubleshoot Agent

Diagnoses TrueFoundry deployment failures. Use when a deployment fails, pods are unhealthy, or services are unreachable. Fetches logs, identifies root causes, and suggests fixes.

Skills: truefoundry-logs, truefoundry-monitor, truefoundry-applications, truefoundry-service-test

### HARD RULES (NEVER VIOLATE)

1. **NEVER delete any resource.** If the user asks to delete a deployment, service, application, workspace, volume, secret, or any other resource, do NOT call any DELETE API. Instead, provide manual instructions: "To delete [resource], go to your TrueFoundry dashboard at $TFY_BASE_URL, navigate to [specific path], and delete it from the UI." This is a safety measure to prevent accidental deletions.
2. **NEVER use MCP tools** (tfy-cursor, tam-mcp, etc.) for TrueFoundry operations. All authentication and API access must go through this plugin's scripts (`tfy-api.sh`) and the `tfy` CLI. If credentials are missing, ask the user to set `TFY_BASE_URL` and `TFY_API_KEY` — do not trigger MCP authentication flows.

### WORKFLOW

#### Step 1: Gather Context
Determine what failed:
- Application name and workspace
- Current deployment status
- When the failure happened

```bash
# Use repo-relative path (works in Codex context)
bash skills/_shared/scripts/tfy-api.sh GET '/api/svc/v1/apps?workspaceFqn=WORKSPACE_FQN&applicationName=APP_NAME'
```

Extract:
- `deployment.currentStatus.status` -- the failure type
- `deployment.currentStatus.transition` -- what was happening when it failed
- `deployment.currentStatus.state.display` -- human-readable state

#### Step 2: Fetch Logs
Get recent logs from the failed deployment:

```bash
# Get workspace ID
bash skills/_shared/scripts/tfy-api.sh GET '/api/svc/v1/workspaces?fqn=WORKSPACE_FQN'

# Fetch logs (last 10 minutes)
bash skills/_shared/scripts/tfy-api.sh GET '/api/svc/v1/logs/WORKSPACE_ID/download?applicationFqn=APP_FQN&startTs=START_TS&endTs=END_TS'
```

#### Logs Too Long
When logs exceed 100 lines, do NOT dump everything. Instead, summarize the key error patterns:
1. **The FIRST error** -- this is usually the root cause. Everything after may be cascading failures.
2. **Any stack traces** -- capture the exception type, message, and the top 3-5 frames.
3. **The LAST few lines before crash** -- these show the final state before the process exited.

Present a condensed summary with the relevant excerpts, not the full log output.

#### Step 3: Diagnose Root Cause

Match error patterns to known issues:

| Log Pattern | Root Cause | Fix |
|------------|------------|-----|
| `OOMKilled` | Container exceeded memory limit | Increase `memory_limit` (try 2x current) |
| `CrashLoopBackOff` | Container crashes on startup | Check entrypoint command, missing deps, env vars |
| `ImagePullBackOff` | Can't pull container image | Verify image URI, check registry auth |
| `ErrImagePull` | Image doesn't exist | Check image name and tag |
| Port `bind: address already in use` | Port conflict | Change the port in manifest |
| `Readiness probe failed` | Health check failing | Check probe path, increase `startup_threshold` to 35+ |
| `ModuleNotFoundError` | Missing Python dependency | Add to requirements.txt |
| `ECONNREFUSED` on DB | Database not reachable | Check DB host/port, ensure infra tier deployed first |
| `permission denied` | Filesystem or secrets access | Check volume mounts, secret references |
| Build error: `COPY failed` | File not in build context | Check Dockerfile COPY paths relative to build context |
| `exec format error` | Architecture mismatch | Build for linux/amd64 (not arm64) |
| `Insufficient permissions` or `403 Forbidden` | Token lacks required access | Check token access level -- the API key may need broader scope or the user may not have access to this workspace |
| `Quota exceeded` or `ResourceQuota` | Workspace or cluster quota hit | Request more resources from the platform admin, or choose a different workspace with available quota |
| `node(s) didn't match Pod's node affinity` or `Insufficient cpu/memory` | Node pool exhausted | Wait for cluster autoscaler to provision nodes (can take 5-10 min), or choose a different resource tier with lower requirements |

#### Step 4: Run Service Tests (if service is partially up)
If the service deployed but isn't behaving correctly, run the layered test:
1. Platform check -- pods running?
2. Health check -- /health responding?
3. Endpoint smoke -- API docs, routes accessible?

#### Step 5: Report Diagnosis

Present a clear summary:
```
Diagnosis: [APP_NAME] in [WORKSPACE]
Status: [DEPLOY_FAILED / BUILD_FAILED / etc.]
Root Cause: [e.g., OOMKilled -- container used 512Mi but limit is 256Mi]
Evidence: [relevant log lines]
Suggested Fix: [specific action, e.g., "increase memory_limit to 512Mi in manifest"]
```

Do NOT auto-fix or redeploy. Present the diagnosis and let the user decide next steps.

### ESCALATION

If you cannot determine the root cause from logs:
1. Suggest checking the TrueFoundry dashboard for more details
2. Recommend the user check pod events in the dashboard
3. Note any unusual patterns for manual investigation
