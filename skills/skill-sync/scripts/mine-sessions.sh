#!/usr/bin/env bash
# Mine recent Claude Code session transcripts for behavioral drift signals.
# Output: {source: "sessions", fetched_at, items: [{pattern, count, files, sample_snippet}, ...]}.
# Everything is redacted before any string is written to stdout.
set -euo pipefail

LOG_DIR="${SESSION_LOG_DIR:-$HOME/.claude/projects}"
LOOKBACK_DAYS="${SESSION_LOOKBACK_DAYS:-45}"
OUT_DIR="${OUT_DIR:-/tmp/skill-sync}"
mkdir -p "$OUT_DIR"

if [[ ! -d "$LOG_DIR" ]]; then
  jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    {source: "sessions", fetched_at: $ts, items: [], note: "SESSION_LOG_DIR not present; skipping session mining."}
  '
  exit 0
fi

# Patterns to count, with a one-line label per pattern.
# Add a row to extend; each row is "label|grep -E regex".
PATTERNS=(
  "missing_required_field|must have required property '[^']+'"
  "oneof_validation|must match exactly one schema in oneOf"
  "tfy_cli_unknown_command|No such command '[^']+'"
  "kubectl_invocation|(^|[[:space:];|&])kubectl[[:space:]]"
  "helm_release_invocation|(^|[[:space:];|&])helm[[:space:]]+(install|upgrade|uninstall|delete|rollback|list)"
  "argocd_invocation|(^|[[:space:];|&])argocd[[:space:]]"
  "auth_failed_401|HTTP/[0-9.]+ 401"
  "auth_failed_403|HTTP/[0-9.]+ 403"
  "stdin_apply_attempt|tfy apply -f -"
  "command_not_found|command not found: (curl|head|jq|tfy)"
)

# Collect files modified in the lookback window.
# Use NUL-delimited find + read for portability (bash 3.2 on macOS lacks `mapfile`).
files=()
while IFS= read -r -d '' f; do
  files+=("$f")
done < <(find "$LOG_DIR" -name '*.jsonl' -type f -mtime "-$LOOKBACK_DAYS" -print0 2>/dev/null)

if [[ ${#files[@]} -eq 0 ]]; then
  jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg dir "$LOG_DIR" '
    {source: "sessions", fetched_at: $ts, items: [], note: "no transcripts found in last \(env.SESSION_LOOKBACK_DAYS) days under \($dir)"}
  '
  exit 0
fi

# Redaction helper (sed pipeline). Runs on every captured snippet before stdout.
redact() {
  # 1. Bearer tokens (Authorization headers).
  # 2. tfy_ prefixed tokens.
  # 3. Long opaque token-like strings (40+ chars of base64/hex-ish).
  # 4. Non-truefoundry email addresses.
  # 5. .env content lines (KEY=value where value is non-empty).
  sed -E \
    -e 's/Authorization:[[:space:]]*Bearer[[:space:]]+[^"[:space:]]+/Authorization: Bearer [REDACTED]/gI' \
    -e 's/tfy_[A-Za-z0-9_-]{20,}/[REDACTED_TFY_TOKEN]/g' \
    -e 's/[A-Za-z0-9_-]{40,}/[REDACTED_OPAQUE]/g' \
    -e 's/[A-Za-z0-9._%+-]+@(?!truefoundry\.com)[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[REDACTED_EMAIL]/g' \
    -e 's/^([A-Z_][A-Z0-9_]*)=.+$/\1=[REDACTED_ENV]/'
}

items='[]'
for pattern_row in "${PATTERNS[@]}"; do
  label="${pattern_row%%|*}"
  regex="${pattern_row#*|}"

  # Count matches across all files; capture up to one sample snippet (redacted).
  count=0
  matching_files='[]'
  sample=""
  for f in "${files[@]}"; do
    n=$(grep -c -E "$regex" "$f" 2>/dev/null || echo 0)
    if [[ "$n" -gt 0 ]]; then
      count=$((count + n))
      base=$(basename "$f")
      matching_files=$(echo "$matching_files" | jq --arg b "$base" '. + [$b]')
      if [[ -z "$sample" ]]; then
        sample=$(grep -m1 -E "$regex" "$f" 2>/dev/null | head -c 300 | redact || true)
      fi
    fi
  done

  if [[ "$count" -gt 0 ]]; then
    items=$(echo "$items" | jq \
      --arg label "$label" \
      --argjson count "$count" \
      --argjson files "$matching_files" \
      --arg sample "$sample" \
      '. + [{pattern: $label, count: $count, file_count: ($files | length), sample_snippet: $sample}]')
  fi
done

jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg dir "$LOG_DIR" \
      --argjson lookback "$LOOKBACK_DAYS" \
      --argjson scanned "${#files[@]}" \
      --argjson items "$items" '
  {source: "sessions", fetched_at: $ts, log_dir: $dir, lookback_days: $lookback, transcripts_scanned: $scanned, items: $items}
'
