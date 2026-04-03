#!/usr/bin/env bash
# PreToolUse hook for Bash: scans commands for hardcoded secrets/credentials.
# Blocks execution if a likely API key or token is found inline.
#
# Exit 0 = approve (no secrets detected).
# Exit 2 = no opinion (not a command we care about).
# Non-zero (1) with message = block with reason.

set -e

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

if [[ -z "$COMMAND" ]]; then
  exit 2
fi

# Only scan commands that could contain deploy manifests or API calls
# Skip simple read-only commands
if [[ "$COMMAND" =~ ^[[:space:]]*(ls|cat|head|tail|grep|find|echo|pwd|cd|which|tfy[[:space:]]--version) ]]; then
  exit 2
fi

# --- Pattern matching for likely hardcoded secrets ---
# Match common secret patterns that should use tfy-secret:// or env vars instead
blocked=false
reason=""

# TrueFoundry API keys (tfy-* pattern, typically 40+ chars)
# Use -E (extended regex) instead of -P (Perl regex) for macOS/BSD compatibility
if echo "$COMMAND" | grep -qE '(TFY_API_KEY|api.key|api_key)[[:space:]]*[=:][[:space:]]*["\x27]?tfy-[A-Za-z0-9]{20,}'; then
  blocked=true
  reason="Hardcoded TFY_API_KEY detected. Use environment variable or .env file instead."
fi

# Generic long tokens in manifest YAML/JSON (env var values that look like secrets)
# Match: value: "sk-..." or "token-..." or base64-like strings 40+ chars in env sections
if echo "$COMMAND" | grep -qE 'value:[[:space:]]*["\x27][A-Za-z0-9+/=_-]{40,}["\x27]'; then
  # Check if this is in a deploy/apply context
  if echo "$COMMAND" | grep -qE '(tfy[[:space:]]+(apply|deploy)|/api/svc/v1/apps)'; then
    blocked=true
    reason="Hardcoded secret value detected in deployment manifest. Use tfy-secret:// references instead. See the secrets skill for how to create and reference secrets."
  fi
fi

# AWS/GCP/Azure credential patterns in deploy commands
if echo "$COMMAND" | grep -qE '(AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35})'; then
  blocked=true
  reason="Cloud provider credential detected in command. Store in TrueFoundry secrets and use tfy-secret:// references."
fi

if $blocked; then
  echo "$reason"
  exit 1
fi

# No secrets detected — defer to other hooks (exit 2 = no opinion)
exit 2
