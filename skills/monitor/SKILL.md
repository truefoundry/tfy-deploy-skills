---
name: truefoundry-monitor
description: Monitors TrueFoundry deployment rollouts after deploy/apply. Polls status, checks pod health and readiness, fetches logs on failure, and reports a final summary. Use after deploying or applying a manifest to track rollout progress.
license: MIT
compatibility: Requires Bash, curl, and access to a TrueFoundry instance
allowed-tools: Bash(*/tfy-api.sh *)
---

> Routing note: For ambiguous user intents, use the shared clarification templates in [references/intent-clarification.md](references/intent-clarification.md).

<objective>

# Monitor Deployment

Track a TrueFoundry deployment rollout to completion, reporting status at each stage and diagnosing failures automatically.

## When to Use

- After `tfy apply` or `tfy deploy` to track rollout progress
- User says "monitor", "watch deployment", "is my deploy done", "check rollout"
- Called automatically by the `deploy` skill after a successful apply/deploy

## When NOT to Use

- User wants to deploy → prefer `deploy` skill; ask if the user wants another valid path
- User wants to list all apps → prefer `applications` skill; ask if the user wants another valid path
- User wants to read historical logs → prefer `logs` skill; ask if the user wants another valid path

</objective>

<instructions>

## CRITICAL BEHAVIOR RULES

> **RULE 1: Once monitoring starts, you MUST poll until a terminal state or timeout. Do NOT stop early. Do NOT ask the user "should I keep checking?" — just keep checking.**
>
> **RULE 2: Do NOT end your response while the deployment is in a non-terminal state (BUILDING, INITIALIZED, ROLLOUT_STARTED). If you are about to stop and the status is non-terminal, you are violating this rule — continue polling.**
>
> **RULE 3: Between each poll, briefly tell the user what you're waiting for. Do NOT silently loop, but also do NOT ask for permission to continue.**

## Required Information

Before monitoring, you need:
1. **Workspace FQN** (`TFY_WORKSPACE_FQN`) — **HARD RULE: Never auto-pick. Always ask the user to confirm.**
2. **Application name** — the service or job name being deployed

If invoked right after a deploy, both should already be known from the deploy context.

## Execution Priority

For all status checks, use MCP tool calls first:
```
tfy_applications_list(filters={"workspace_fqn": "WORKSPACE_FQN", "application_name": "APP_NAME"})
```

If MCP tool calls are unavailable, fall back to direct API via `tfy-api.sh`.

When using direct API, set `TFY_API_SH` to the full path of this skill's `scripts/tfy-api.sh`. See `references/tfy-api-setup.md` for paths per agent.

## Monitoring Flow

### Step 1: Initial Status Check

```bash
TFY_API_SH=~/.claude/skills/truefoundry-monitor/scripts/tfy-api.sh
bash $TFY_API_SH GET '/api/svc/v1/apps?workspaceFqn=WORKSPACE_FQN&applicationName=APP_NAME'
```

Extract from the response at `data[0]` (the application object):
- `deployment.currentStatus.status` — the deployment status enum
- `deployment.currentStatus.transition` — current transition (e.g., `BUILDING`, `DEPLOYING`)
- `deployment.currentStatus.state.isTerminalState` — boolean, most reliable terminal check
- `deployment.currentStatus.state.display` — human-readable state

### Step 2: Poll Until Terminal State

The API response has two key fields: `status` (the deployment status) and `transition` (what's happening now). Use `state.isTerminalState` as the authoritative check for whether to stop polling.

**Status values** (from `deployment.currentStatus.status`):

| Status | Terminal? | Action |
|--------|-----------|--------|
| `INITIALIZED` | No | Report "Deployment initialized, waiting...", continue polling |
| `BUILDING` | No | Report "Build in progress", continue polling |
| `BUILD_SUCCESS` | No | Report "Build succeeded, deploying...", continue polling |
| `BUILD_FAILED` | Yes | Fetch build logs, report failure |
| `ROLLOUT_STARTED` | No | Report "Rollout started", continue polling |
| `DEPLOY_SUCCESS` | Yes | Report success with endpoint URL |
| `DEPLOY_FAILED` | Yes | Fetch pod logs, diagnose failure |
| `DEPLOY_FAILED_WITH_RETRY` | No | Report "Deploy failed, retrying...", continue polling |
| `PAUSED` | Yes | Report paused/stopped |
| `FAILED` | Yes | Report general failure |
| `CANCELLED` | Yes | Report cancelled |

**Transition values** (from `deployment.currentStatus.transition`):

| Transition | Meaning |
|------------|---------|
| `BUILDING` | Image build is in progress |
| `DEPLOYING` | Pods are being created/updated |
| `REUSING_EXISTING_BUILD` | Skipping build, reusing cached image |
| `COMPONENTS_DEPLOYING` | Multi-component deployment in progress |
| `WAITING` | Waiting for resources |

> **Best practice:** Always check `deployment.currentStatus.state.isTerminalState === true` to decide whether to stop polling, rather than matching individual status strings. The `state.display` field gives a human-friendly label.

**Polling schedule:**
- First 2 minutes: check every 15 seconds
- Minutes 2-5: check every 30 seconds
- After 5 minutes: check every 60 seconds
- **Timeout after 10 minutes** — report current state and suggest the user check manually

**Between polls, tell the user what you're waiting for.** Do not silently loop. Do NOT ask "should I continue?" — just continue.

### Step 3: On Success

When `state.isTerminalState` is `true` and status is `DEPLOY_SUCCESS`:

1. Report the final status
2. Show replicas ready (e.g., "2/2 replicas ready")
3. Show the endpoint URL if the service has an exposed port
4. Optionally run a quick health check on the endpoint:

```bash
# Only if the service exposes an HTTP port
curl -sf -o /dev/null -w '%{http_code}' "https://ENDPOINT_URL/health" || true
```

Report the HTTP status code. Do not fail the monitor if the health check fails — just report it.

### Step 4: On Failure

When status is `BUILD_FAILED`, `DEPLOY_FAILED`, `FAILED`, or `CANCELLED`:

1. **Fetch recent logs** using the `logs` skill or direct API:

```bash
# Get the app ID first from the status response
TFY_API_SH=~/.claude/skills/truefoundry-monitor/scripts/tfy-api.sh

# Fetch recent logs (last 5 minutes)
bash $TFY_API_SH GET '/api/svc/v1/logs/WORKSPACE_ID/download?applicationFqn=APP_FQN&startTs=START_TS&endTs=END_TS'
```

2. **Identify the failure cause** from the logs (OOMKilled, CrashLoopBackOff, ImagePullBackOff, port mismatch, etc.)
3. **Suggest a fix** based on the error:

| Error Pattern | Suggested Fix |
|---------------|---------------|
| `OOMKilled` | Increase `memory_limit` in manifest |
| `CrashLoopBackOff` | Check startup command and logs for crash reason |
| `ImagePullBackOff` | Verify image URI and registry credentials |
| Port mismatch | Ensure manifest port matches what the app listens on |
| `Readiness probe failed` | Check health probe path and startup time |
| Build error | Check Dockerfile and build logs |

4. **Report summary** with: error type, relevant log excerpt (max 20 lines), and suggested fix
5. **Do NOT auto-retry.** Present the diagnosis and let the user decide next steps.

## Presenting Status Updates

Use a consistent format for each status update:

```
Monitoring: my-service in cluster:workspace
Status: ROLLOUT_STARTED | Transition: DEPLOYING
Display: Deploying (1/2 replicas ready)
Elapsed: 45s
Next check in 15s...
```

Final summary on success:

```
Deployment complete: my-service
Status: DEPLOY_SUCCESS
Replicas: 2/2 ready
Endpoint: https://my-service-ws.example.com
Health check: 200 OK
Total time: 1m 32s
```

Final summary on failure:

```
Deployment failed: my-service
Status: DEPLOY_FAILED
Error: CrashLoopBackOff — container exited with code 1
Log excerpt:
  > ModuleNotFoundError: No module named 'flask'
Suggested fix: Add 'flask' to requirements.txt and redeploy
```

</instructions>

<success_criteria>

## Success Criteria

- Deployment status is tracked from current state to a terminal state
- User sees clear progress updates at each polling interval
- On success: replicas, endpoint URL, and optional health check are reported
- On failure: logs are fetched, root cause is identified, and a fix is suggested
- Monitor times out gracefully after 10 minutes with a status summary
- The user is never left waiting without feedback

</success_criteria>

<references>

## Composability

- **Before monitoring**: Use `deploy` skill to deploy, then monitor
- **On failure**: Use `logs` skill for deeper log analysis
- **Check app details**: Use `applications` skill for full app info
- **Fix and redeploy**: Use `deploy` skill to apply fixes

</references>

<troubleshooting>

## Error Handling

### Application Not Found
```
Application "APP_NAME" not found in workspace "WORKSPACE_FQN".
Check:
- Application name is spelled correctly
- The deploy/apply command completed successfully
- You're checking the correct workspace
```

### Timeout
```
Monitoring timed out after 10 minutes.
Current status: ROLLOUT_STARTED | Transition: DEPLOYING
The deployment is still in progress. Check manually:
- TrueFoundry dashboard: TFY_BASE_URL
- Or run this skill again to resume monitoring
```

### Permission Denied
```
Cannot access this application. Check your API key permissions for this workspace.
```

</troubleshooting>
