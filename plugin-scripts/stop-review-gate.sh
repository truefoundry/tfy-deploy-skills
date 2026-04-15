#!/usr/bin/env bash
# Stop hook: blocks Claude from completing if a deployment was made
# in this session and hasn't reached a verified terminal state.
#
# Exit 0 = allow stop (no unverified deploys).
# Non-zero with JSON output = block stop with reason.

set -euo pipefail

# --- Check if any deploys happened this session ---
SESSION_KEY="${CLAUDE_SESSION_ID:-${PPID:-$$}}"
STATE_DIR=$(cat "${TMPDIR:-/tmp}/tfy-plugin-state-${SESSION_KEY}" 2>/dev/null || echo "")

if [[ -z "$STATE_DIR" || ! -d "$STATE_DIR" ]]; then
  # No session state — no deploys to verify
  exit 0
fi

if [[ ! -s "$STATE_DIR/deployments.jsonl" ]]; then
  # No deploys recorded this session
  exit 0
fi

# --- Check last deployment status ---
last_deploy="$STATE_DIR/last-deploy.json"

if [[ ! -f "$last_deploy" ]]; then
  # Deploy was recorded but monitoring never completed (or is still running).
  # Block the stop — the PostToolUse hook may still be polling.
  echo "A deployment was started in this session but monitoring has not completed yet."
  echo "Wait for the deployment monitor to finish, or check the deployment status manually."
  exit 1
fi

status=$(jq -r '.status // "UNKNOWN"' "$last_deploy" 2>/dev/null || echo "UNKNOWN")
app_name=$(jq -r '.app // "unknown"' "$last_deploy" 2>/dev/null || echo "unknown")
endpoint=$(jq -r '.endpoint // ""' "$last_deploy" 2>/dev/null || echo "")

# --- Terminal success: verify endpoint is actually reachable ---
if [[ "$status" = "DEPLOY_SUCCESS" ]]; then
  if [[ -n "$endpoint" ]]; then
    http_code=$(curl -s -o /dev/null -w '%{http_code}' \
      --connect-timeout 5 --max-time 10 \
      "https://$endpoint/" 2>/dev/null) || true

    if [[ -z "$http_code" || "$http_code" = "000" ]]; then
      # Warn but don't block — the service may be internal-only (no public endpoint),
      # still starting up, or only reachable from within a private network.
      echo "Note: $app_name deployed successfully but https://$endpoint/ is not responding from this machine."
      echo "If this is an internal service, this is expected. Verify reachability from within your network."
    fi
  fi

  # Deploy succeeded (endpoint check is advisory only for internal services)
  exit 0
fi

# --- Terminal failure: allow stop but make sure diagnosis was provided ---
if [[ "$status" =~ ^(BUILD_FAILED|DEPLOY_FAILED|FAILED|CANCELLED)$ ]]; then
  # Failure is a valid terminal state — allow stop.
  # The PostToolUse hook already fetched logs and reported the failure.
  exit 0
fi

# --- Non-terminal state: block stop ---
echo "Deployment of $app_name is in state: $status (not yet terminal)."
echo "Continue monitoring until the deployment reaches a terminal state."
exit 1
