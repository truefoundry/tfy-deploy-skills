---
name: truefoundry-deploy
description: Deploys applications to TrueFoundry. Handles single HTTP services, async/queue workers, multi-service projects, and declarative manifest apply. Supports `tfy apply`, `tfy deploy`, docker-compose translation, and CI/CD pipelines. Use when deploying apps, applying manifests, shipping services, or orchestrating multi-service deployments.
license: MIT
compatibility: Requires Bash, curl, and access to a TrueFoundry instance
metadata:
  disable-model-invocation: "true"
allowed-tools: Bash(tfy*) Bash(*/tfy-api.sh *) Bash(*/tfy-version.sh *) Bash(docker *) Bash(tfy deploy*) Bash(curl *)
---

> Routing note: For ambiguous user intents, use the shared clarification templates in [references/intent-clarification.md](references/intent-clarification.md).

# Deploy to TrueFoundry

Route user intent to the right deployment workflow. Load only the references you need.

## Intent Router

| User Intent | Action | Reference |
|---|---|---|
| "deploy", "deploy my app", "ship this" | Single HTTP service | [deploy-service.md](references/deploy-service.md) |
| "mount this file", "mount config file", "mount certificate file", "mount key file" | Single service with file mounts (no image rebuild) | [deploy-service.md](references/deploy-service.md) |
| "tfy apply", "apply manifest", "deploy from yaml" | Declarative manifest apply | [deploy-apply.md](references/deploy-apply.md) |
| "deploy everything", "full stack", docker-compose, "docker-compose.yaml", "compose.yaml" | Multi-service: use compose as source of truth | [deploy-multi.md](references/deploy-multi.md) + [compose-translation.md](references/compose-translation.md) |
| "async service", "queue consumer", "worker" | Async/queue service | [deploy-async.md](references/deploy-async.md) |
| "deploy LLM", "serve model" | Model serving intent (may be ambiguous) | Ask user: dedicated model serving (`llm-deploy`) or generic service deploy (`deploy`) |
| "deploy helm chart" | Helm chart intent | Confirm Helm path and collect chart details, then proceed with `helm` workflow |
| "deploy postgres docker", "dockerized postgres", "deploy redis docker", "database in docker/container" | Containerized database intent | Proceed with `deploy` workflow (do not route to Helm) |
| "deploy database", "deploy postgres", "deploy redis" | Ambiguous infra intent | Ask user: Helm chart (`helm`) or containerized service (`deploy`) |

**Load only the reference file matching the user's intent.** Do not preload all references.

## Prerequisites (All Workflows)

```bash
# 1. Check credentials
grep '^TFY_' .env 2>/dev/null || true
env | grep '^TFY_' 2>/dev/null || true

# 2. Derive TFY_HOST for CLI (MUST run before any tfy command)
export TFY_HOST="${TFY_HOST:-${TFY_BASE_URL%/}}"

# 3. Check CLI
tfy --version 2>/dev/null || echo "Install: pip install 'truefoundry==0.5.0'"

# 4. Check for existing manifests
ls tfy-manifest.yaml truefoundry.yaml 2>/dev/null
```

- `TFY_BASE_URL` and `TFY_API_KEY` must be set (env or `.env`).
- **`TFY_HOST` must be set before any `tfy` CLI command.** The export above handles this automatically.
- `TFY_WORKSPACE_FQN` required. **HARD RULE: Never auto-pick a workspace. Always ask the user to confirm, even if only one workspace exists or a preference is saved.** See `references/prerequisites.md` for the full workspace confirmation flow.
- For full credential setup, see `references/prerequisites.md`.

> **WARNING:** Never use `source .env`. The `tfy-api.sh` script handles `.env` parsing automatically. For shell access: `grep KEY .env | cut -d= -f2-`

## CRITICAL: `tfy apply` vs `tfy deploy`

> **HARD RULE: `tfy apply` does NOT support `build_source.type: local`.** If the manifest has a local build source, you MUST use `tfy deploy -f <manifest>`. Using `tfy apply` with a local build source will fail with: `must match exactly one schema in oneOf`.

| Scenario | Command | Works? |
|----------|---------|--------|
| Pre-built image (`image.type: image`) | `tfy apply -f manifest.yaml` | Yes |
| `build_source.type: git` | `tfy apply -f manifest.yaml` | Yes |
| `build_source.type: git` | `tfy deploy -f manifest.yaml` | Yes |
| `build_source.type: local` | `tfy deploy -f manifest.yaml` | Yes |
| `build_source.type: local` | `tfy apply -f manifest.yaml` | **NO — will fail** |

**Before running any deploy command, check the manifest:**
1. If `build_source.type: local` → use `tfy deploy -f`
2. Otherwise → `tfy apply -f` is fine

## Pre-Flight Manifest Validation (MANDATORY)

> **Before attempting any deploy/apply, run these checks. Fix issues before deploying — do not deploy a known-bad manifest.**

### 1. Exposed port requires `host`

If any port has `expose: true`, it **must** have a `host` field. Deploying without it will fail with: `Host must be provided to expose port`.

**Auto-generate the host if missing:**
```bash
TFY_API_SH=~/.claude/skills/truefoundry-deploy/scripts/tfy-api.sh

# Get cluster ID from workspace FQN (format: cluster-id:workspace-name)
CLUSTER_ID=$(echo "$TFY_WORKSPACE_FQN" | cut -d: -f1)

# Discover base domain from cluster manifest
bash $TFY_API_SH GET "/api/svc/v1/clusters/$CLUSTER_ID"
# → Response is at data.manifest.base_domains[] (array of strings)
# → Look for wildcard entry (e.g., "*.ml.example.truefoundry.cloud")
# → Strip "*." to get base domain: "ml.example.truefoundry.cloud"
# → Construct host: "{service-name}-{workspace-name}.{base_domain}"
```

Pattern: `{service-name}-{workspace-name}.{base_domain}`

### 2. Local build source requires `tfy deploy`

If the manifest contains `build_source.type: local`, ensure the deploy command is `tfy deploy -f`, NOT `tfy apply`.

### 3. `capacity_type` compatibility

`spot_fallback_on_demand` is **not supported on all clusters**. If you're unsure, use `on_demand` or omit `capacity_type` entirely to let the platform decide. Valid safe values: `on_demand`, `spot`.

### 4. `build_spec.type` must be exact

Only `dockerfile` and `tfy-python-buildpack` are valid. Do NOT use `docker`, `build`, `python`, or any other value.

## Quick Ops (Inline)

### Apply a manifest (pre-built image or git source)

```bash
# tfy CLI expects TFY_HOST when TFY_API_KEY is set
export TFY_HOST="${TFY_HOST:-${TFY_BASE_URL%/}}"

# Preview changes
tfy apply -f tfy-manifest.yaml --dry-run --show-diff

# Apply
tfy apply -f tfy-manifest.yaml
```

### Deploy from local source

```bash
# tfy CLI expects TFY_HOST when TFY_API_KEY is set
export TFY_HOST="${TFY_HOST:-${TFY_BASE_URL%/}}"

# MUST use tfy deploy (not tfy apply) for local builds
tfy deploy -f truefoundry.yaml --no-wait
```

> **Reminder:** `tfy apply` does NOT support `build_source.type: local`. Use `tfy deploy -f` for local builds.

### Minimal service manifest template

```yaml
name: my-service
type: service
image:
  type: image
  image_uri: docker.io/myorg/my-api:v1.0
ports:
  - port: 8000
    expose: false  # Set true + add host for public access
    app_protocol: http
resources:
  cpu_request: 0.5
  cpu_limit: 1
  memory_request: 512
  memory_limit: 1024
  ephemeral_storage_request: 1000
  ephemeral_storage_limit: 2000
env:
  LOG_LEVEL: info
replicas: 1
workspace_fqn: "WORKSPACE_FQN_HERE"
```

### Public access template (when expose: true)

```yaml
ports:
  - port: 8000
    expose: true
    host: my-service-my-workspace.ml.your-org.truefoundry.cloud  # Auto-generate from cluster discovery
    app_protocol: http
```

> **Host is REQUIRED when `expose: true`.** Auto-generate it: `{service-name}-{workspace-name}.{base_domain}`. Get `base_domain` from cluster discovery (see `cluster-discovery.md`).

### Check deployment status

```bash
TFY_API_SH=~/.claude/skills/truefoundry-deploy/scripts/tfy-api.sh
bash $TFY_API_SH GET '/api/svc/v1/apps?workspaceFqn=WORKSPACE_FQN&applicationName=SERVICE_NAME'
```

Or use the `applications` skill.

## Post-Deploy Monitoring (MANDATORY)

> **HARD RULE: After every successful `tfy apply` or `tfy deploy` command, you MUST monitor the deployment to completion. Do NOT stop after the apply/deploy command returns. Do NOT ask the user "should I monitor?" — just do it. Do NOT say "you can check the status" — YOU check the status. The deployment is not done until you confirm a terminal state.**

### Monitoring procedure

Immediately after deploy/apply succeeds, start polling. Do not wait for the user to ask.

**Poll loop — execute this yourself, do not delegate to the user:**

```bash
TFY_API_SH=~/.claude/skills/truefoundry-deploy/scripts/tfy-api.sh

# Run this in a loop with sleep between checks:
# Every 15s for first 2 min, every 30s for min 2-5, every 60s after that
# Timeout after 10 minutes
bash $TFY_API_SH GET '/api/svc/v1/apps?workspaceFqn=WORKSPACE_FQN&applicationName=SERVICE_NAME'
```

Or use MCP tool call if available:
```
tfy_applications_list(filters={"workspace_fqn": "WORKSPACE_FQN", "application_name": "SERVICE_NAME"})
```

**How to check:** The response is at `data[0].deployment.currentStatus`. Use `state.isTerminalState` as the authoritative check.

**Terminal states** (`state.isTerminalState === true`) — stop polling:
- `DEPLOY_SUCCESS` → report success, replicas, endpoint URL
- `BUILD_FAILED`, `DEPLOY_FAILED`, `FAILED` → fetch logs, diagnose, suggest fix (see below)
- `PAUSED` → report paused
- `CANCELLED` → report cancelled

**Non-terminal states** — keep polling, report progress each time:
- `INITIALIZED` → "Deployment initialized, waiting..."
- `BUILDING` (status) or transition `BUILDING` → "Build in progress..."
- `BUILD_SUCCESS` → "Build succeeded, deploying..."
- `ROLLOUT_STARTED` or transition `DEPLOYING` → "Deploying (X/Y replicas ready)..."
- `DEPLOY_FAILED_WITH_RETRY` → "Deploy failed, retrying..."

### On success

1. Report final status and replicas (e.g., "2/2 ready")
2. Show endpoint URL if service has an exposed port
3. Run a quick HTTP health check if endpoint is available:
   ```bash
   curl -sf -o /dev/null -w '%{http_code}' "https://ENDPOINT_URL" || true
   ```

### On failure

1. Fetch recent logs (last 5 minutes) using `logs` skill or direct API
2. Identify root cause from logs (OOMKilled, CrashLoopBackOff, ImagePullBackOff, port mismatch, probe failure, build error)
3. Follow [deploy-debugging.md](references/deploy-debugging.md) for diagnosis
4. Apply one fix and retry once; if still failed, report to user with summary and log excerpt and stop

### On timeout (10 minutes)

Report current state and elapsed time. Do NOT silently give up — tell the user:
```
Monitoring timed out after 10 minutes. Current status: ROLLOUT_STARTED (transition: DEPLOYING).
The deployment is still in progress. You can re-run monitoring or check the TrueFoundry dashboard.
```

> **NEVER end your response after a deploy/apply command without reporting a terminal deployment status (`state.isTerminalState === true`). If you are about to end your response and you have not confirmed `DEPLOY_SUCCESS`, `DEPLOY_FAILED`, `BUILD_FAILED`, `FAILED`, `PAUSED`, or `CANCELLED`, you are violating this rule — go back and poll.**

## Post-Deploy Configuration (Ask After Success)

> **After deployment succeeds (`DEPLOY_SUCCESS`), ask the user about the following configuration options. Do not silently skip these — present them as a checklist and let the user decide.**

### 1. Public vs Private URL

Ask the user:
```
Your service is deployed. How should it be accessed?
1. **Public URL** — Accessible from the internet (expose: true with a host)
2. **Private/Internal only** — Only accessible within the cluster (expose: false)
```

If the user picks public and the port doesn't already have `expose: true` + `host`, update the manifest and redeploy.

### 2. Authentication

Ask the user:
```
Do you want to add authentication to your service?
1. **No auth** — Anyone with the URL can access it
2. **TrueFoundry login** — Users must log in via TrueFoundry (truefoundry_oauth)
3. **JWT auth** — Verify JWT tokens from a custom identity provider
4. **Basic auth** — Username/password protection
```

If the user picks an auth option, add the appropriate `auth` block to the port configuration and redeploy.

### 3. Auto-shutdown vs Always Running

Ask the user:
```
Should the service auto-shutdown when idle?
1. **Always running** — Keep replicas up at all times (default)
2. **Auto-shutdown after idle** — Scale to zero after no requests for a period (saves cost)
   → Recommended wait_time: 900 seconds (15 min) for dev, longer for staging
```

If the user picks auto-shutdown, add the `auto_shutdown` block to the manifest:
```yaml
auto_shutdown:
  wait_time: 900  # seconds of inactivity before scaling to zero
```

> **Skip these prompts if the user explicitly said they don't want changes, or if this is a redeploy of an existing service that already has these configured.**

### REST API fallback (when CLI unavailable)

See `references/cli-fallback.md` for converting YAML to JSON and deploying via `tfy-api.sh`.

## Auto-Detection: Single vs Multi-Service

**Before creating any manifest, scan the project:**

1. **Check for `docker-compose.yml`, `docker-compose.yaml`, or `compose.yaml` first.** If present (or user mentions docker-compose), treat it as the **primary source of truth**: load [deploy-multi.md](references/deploy-multi.md) and [compose-translation.md](references/compose-translation.md), generate manifests from the compose file, wire services per [service-wiring.md](references/service-wiring.md), then complete deployment. Do not ask the user to manually create manifests when a compose file exists.
2. Look for multiple `Dockerfile` files across the project
3. Check for service directories with their own dependency files in `services/`, `apps/`, `frontend/`, `backend/`

- **Compose file present or user says "docker-compose"** → Multi-service from compose: load `deploy-multi.md` + `compose-translation.md`
- **Single service** → Load `references/deploy-service.md`
- **Multiple services (no compose)** → Load `references/deploy-multi.md`

## Multi-Service Deployment Order (MANDATORY)

> **HARD RULE: When deploying multiple services, you MUST deploy in dependency order, create secrets between tiers, and wire services before deploying dependents. Never deploy all services at once.**

**Tier-by-tier flow:**

```
TIER 0: Infrastructure (DB, Cache, Queue) → deploy → wait for pods ready → create TFY secrets
TIER 1: Backend (APIs, workers) → deploy with secrets + DNS wiring → verify connectivity
TIER 2: Frontend / gateway → deploy with backend URLs → verify end-to-end
```

**Key rules:**
- Create TFY secret groups with infra credentials **between Tier 0 and Tier 1** — never put raw passwords in manifests
- SPA frontends (React, Vue) MUST use backend's **public URL**, not internal DNS
- `DEPLOY_SUCCESS` does NOT mean Helm pods are ready — poll actual readiness
- Present the dependency graph and deploy plan to the user before deploying

For step-by-step orchestration, examples, and common patterns, see [deploy-ordering.md](references/deploy-ordering.md). For dependency graphs, DNS wiring, and compose translation, see [deploy-multi.md](references/deploy-multi.md), [service-wiring.md](references/service-wiring.md), and [dependency-graph.md](references/dependency-graph.md).

## Secrets Handling (MANDATORY: Always Use TFY Secrets)

> **HARD RULE: NEVER put sensitive values directly in the manifest `env` block. ALWAYS create a TrueFoundry secret group first, then reference the secrets using `tfy-secret://` format. This is non-negotiable — even for "quick" or "test" deployments.**

**Workflow for any env var that looks sensitive** (matches `*PASSWORD*`, `*SECRET*`, `*TOKEN*`, `*KEY*`, `*API_KEY*`, `*DATABASE_URL*`, `*CONNECTION_STRING*`, `*CREDENTIALS*`, or any value the user explicitly says is sensitive):

1. **Ask the user for the secret values** (or confirm they want to store them)
2. **Create a secret group** using the `secrets` skill:
   ```bash
   # Use the secrets skill to create a group with the sensitive keys
   # The skill will handle creating the group and individual secrets
   ```
3. **Reference them in the manifest** with `tfy-secret://` format:

```yaml
env:
  LOG_LEVEL: info                                              # plain text OK
  DB_PASSWORD: tfy-secret://my-org:my-service-secrets:DB_PASSWORD  # sensitive — ALWAYS use tfy-secret://
  API_KEY: tfy-secret://my-org:my-service-secrets:API_KEY          # sensitive — ALWAYS use tfy-secret://
```

Pattern: `tfy-secret://<TENANT_NAME>:<SECRET_GROUP_NAME>:<SECRET_KEY>` where TENANT_NAME is the subdomain of `TFY_BASE_URL`.

**If the user provides a raw secret value in the manifest or asks you to put it directly in `env`:**
1. Warn them: "Secrets should not be stored as plain text in manifests."
2. Offer to create a TFY secret group for them
3. Only proceed with raw values if the user explicitly insists after the warning

Use the `secrets` skill for guided secret group creation. For the full workflow, see `references/deploy-service.md` (Secrets Handling section).

## File Mounts (Config, Secrets, Shared Data)

When users ask to mount files into a deployment, prefer manifest `mounts` over Dockerfile edits:

- `type: secret` for sensitive file content (keys, certs, credentials)
- `type: config_map` for non-sensitive config files
- `type: volume` for writable/shared runtime data

See `references/deploy-service.md` (File Mounts section) for the end-to-end workflow.

## Shared References

These references are available for all workflows — load as needed:

| Reference | Contents |
|---|---|
| `manifest-schema.md` | Complete YAML field reference (single source of truth) |
| `manifest-defaults.md` | Per-service-type defaults with YAML templates |
| `cli-fallback.md` | CLI detection and REST API fallback pattern |
| `cluster-discovery.md` | Extract cluster ID, base domains, available GPUs |
| `resource-estimation.md` | CPU, memory, GPU sizing rules of thumb |
| `health-probes.md` | Startup, readiness, liveness probe configuration |
| `gpu-reference.md` | GPU types and VRAM reference |
| `container-versions.md` | Pinned container image versions |
| `prerequisites.md` | Credential setup and .env configuration |
| `rest-api-manifest.md` | Full REST API manifest reference |

## Workflow-Specific References

| Reference | Used By |
|---|---|
| `deploy-api-examples.md` | deploy-service |
| `deploy-errors.md` | deploy-service |
| `deploy-scaling.md` | deploy-service |
| `load-analysis-questions.md` | deploy-service |
| `codebase-analysis.md` | deploy-service |
| `tfy-apply-cicd.md` | deploy-apply |
| `tfy-apply-extra-manifests.md` | deploy-apply |
| `deploy-ordering.md` | deploy-multi (tier-by-tier orchestration) |
| `compose-translation.md` | deploy-multi |
| `dependency-graph.md` | deploy-multi |
| `multi-service-errors.md` | deploy-multi |
| `multi-service-patterns.md` | deploy-multi |
| `service-wiring.md` | deploy-multi |
| `deploy-debugging.md` | All deploy/apply (when status is failed) |
| `async-errors.md` | deploy-async |
| `async-queue-configs.md` | deploy-async |
| `async-python-library.md` | deploy-async |
| `async-sidecar-deploy.md` | deploy-async |

## Composability

- **Find workspace**: Use `workspaces` skill
- **Monitor rollout**: Use `monitor` skill to track deployment progress
- **Check what's deployed**: Use `applications` skill
- **View logs**: Use `logs` skill
- **Manage secrets**: Use `secrets` skill
- **Deploy Helm charts**: Use `helm` skill
- **Deploy LLMs**: Use `llm-deploy` skill
- **Test after deploy**: Use `service-test` skill

## Success Criteria

- User confirmed service name, resources, port, and deployment source before deploying
- Deployment URL and status reported back to the user
- Deployment status verified automatically immediately after apply/deploy (no extra prompt)
- Health probes configured for production deployments
- Secrets stored securely (not hardcoded in manifests)
- For multi-service: all services wired together and working end-to-end
