#!/usr/bin/env bash
# Stop hook: blocks Claude from completing if a deployment was made
# in this session and hasn't reached a verified terminal state.
#
# Exit 0 = allow stop (no unverified deploys).
# Non-zero with JSON output = block stop with reason.

set -euo pipefail

# --- Check if any deploys happened this session ---
STATE_DIR=$(cat "${TMPDIR:-/tmp}/tfy-plugin-state-dir" 2>/dev/null || echo "")

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
    http_code=$(curl -sf -o /dev/null -w '%{http_code}' \
      --connect-timeout 5 --max-time 10 \
      "https://$endpoint/" 2>/dev/null || echo "000")

    if [[ "$http_code" = "000" ]]; then
      echo "Deployment of $app_name reports success, but the endpoint (https://$endpoint/) is not responding."
      echo "The service may still be starting up. Verify it's reachable before finishing."
      exit 1
    fi
  fi

  # Deploy succeeded and endpoint is reachable (or no endpoint to check)
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
