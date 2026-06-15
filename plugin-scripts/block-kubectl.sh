#!/usr/bin/env bash
# PreToolUse hook: block direct cluster access via kubectl / helm CLI / argocd.
# The TrueFoundry plugin must achieve all goals via the platform skills and APIs.
# Raw cluster access bypasses the audit log, RBAC, dashboard state, and the
# block-delete hook.
#
# Reads hook JSON from stdin (has tool_input.command).
# Exit 1 = block the command. Exit 2 = no opinion (non-blocked commands).

set -e

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

if [[ -z "$COMMAND" ]]; then
  exit 2
fi

BLOCKED=false
TOOL=""
HINT=""

# Strip a single leading "sudo " for matching, so `sudo kubectl ...` is caught.
NORMALIZED="${COMMAND#sudo }"

# Match kubectl/oc/helm/argocd as a separate token at the start of the command
# or after a shell separator (`;`, `&&`, `||`, `|`, `(`, newline). This avoids
# false positives on words that merely contain the substring (e.g. "kubectl-info"
# in a file path, "helm" inside an OCI URL, "argocd" mentioned in a log line).
if echo "$NORMALIZED" | grep -qE '(^|[[:space:];&|()`])kubectl([[:space:]]|$)'; then
  BLOCKED=true
  TOOL="kubectl"
  HINT="Use the TrueFoundry skills (truefoundry-status, truefoundry-logs, truefoundry-applications, truefoundry-secrets, truefoundry-ssh-server, truefoundry-service-test) or tfy-api.sh."
elif echo "$NORMALIZED" | grep -qE '(^|[[:space:];&|()`])oc([[:space:]]|$)' && echo "$NORMALIZED" | grep -qE '(get|describe|logs|exec|apply|delete|edit|patch|scale|rollout|port-forward|create)[[:space:]]'; then
  # OpenShift `oc` overlaps with kubectl semantics. We match `oc` only when
  # followed by a kubectl-like subcommand to avoid hitting unrelated `oc` binaries.
  BLOCKED=true
  TOOL="oc"
  HINT="Use the TrueFoundry skills or tfy-api.sh — the platform manages OpenShift state."
elif echo "$NORMALIZED" | grep -qE '(^|[[:space:];&|()`])helm[[:space:]]+(install|upgrade|uninstall|delete|rollback|list|ls|get|status|history|template|repo|push|pull|search|registry|show)([[:space:]]|$)'; then
  # Block helm subcommands that manage releases. Allow `helm version` / `helm env`
  # which are read-only and harmless. The TrueFoundry CLI command `tfy apply -f`
  # for `type: helm` manifests is NOT a `helm ` invocation, so it is untouched.
  BLOCKED=true
  TOOL="helm"
  HINT="Use the truefoundry-helm skill — chart releases are platform resources, not raw Helm releases. See skills/_shared/references/no-kubectl.md."
elif echo "$NORMALIZED" | grep -qE '(^|[[:space:];&|()`])argocd([[:space:]]|$)'; then
  BLOCKED=true
  TOOL="argocd"
  HINT="Use truefoundry-status / truefoundry-monitor — Argo is an implementation detail; the platform exposes the same state."
fi

if [[ "$BLOCKED" == "true" ]]; then
  reason="Direct \`$TOOL\` invocations are not allowed by the TrueFoundry plugin. $HINT"
  if command -v jq &>/dev/null; then
    jq -n --arg reason "$reason" \
      '{"decision":"block","reason":$reason}'
  else
    safe_reason="${reason//\"/}"
    echo "{\"decision\":\"block\",\"reason\":\"${safe_reason}\"}"
  fi
  exit 1
fi

exit 2
