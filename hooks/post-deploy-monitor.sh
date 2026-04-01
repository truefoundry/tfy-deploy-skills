#!/usr/bin/env bash
# PostToolUse hook: After a successful tfy apply/deploy, remind the agent to monitor.
# Reads tool result from stdin (JSON with tool_input.command and tool_result fields).
# Outputs a reminder message to stdout that the agent will see.

set -e

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_result.exitCode // empty' 2>/dev/null || true)

# Only act on successful tfy apply or tfy deploy commands
if [[ "$EXIT_CODE" != "0" ]]; then
  exit 0
fi

# Match tfy apply or tfy deploy (with optional flags)
# shellcheck disable=SC2016
_RE_APPLY='^[[:space:]]*(tfy[[:space:]]+apply|tfy[[:space:]]+deploy)[[:space:]]'
if [[ "$COMMAND" =~ $_RE_APPLY ]]; then
  cat <<'EOF'
MANDATORY POST-DEPLOY ACTION: A deployment command just completed successfully.
You MUST now monitor the deployment to a terminal state. Do NOT end your response.
Do NOT ask the user "should I monitor?" — start polling immediately.

Poll the deployment status using:
  bash $TFY_API_SH GET '/api/svc/v1/apps?workspaceFqn=WORKSPACE_FQN&applicationName=APP_NAME'

Keep polling every 15-30s until state.isTerminalState is true.
On success: report replicas, endpoint URL, run health check.
On failure: fetch logs, diagnose, suggest fix.
EOF
  exit 0
fi

exit 0
