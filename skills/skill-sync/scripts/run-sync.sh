#!/usr/bin/env bash
# Orchestrator for skill-sync. Fetches the three sources, builds a candidate list,
# applies Tier-1 edits, runs validators, opens or updates a PR.
#
# This is the *scaffolding* — the per-rule diff logic between candidates and the
# in-repo references is implemented incrementally by future runs. The first
# version reports drift only (DRY_RUN-ish behavior) until each diff rule lands.
#
# Env vars honored: DRY_RUN, SOURCES, SKILL, TFY_OPENAPI_URL, TFY_DOCS_BASE_URL,
# SESSION_LOG_DIR, SESSION_LOOKBACK_DAYS, MAX_CANDIDATES, MAX_CHANGE_PERCENT.
set -euo pipefail

# ── Pre-flight ──────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -d "skills" || ! -d "scripts" ]]; then
  echo "FATAL: run-sync.sh must execute from the truefoundry/tfy-deploy-skills repo root." >&2
  exit 1
fi

DRY_RUN="${DRY_RUN:-0}"
SOURCES="${SOURCES:-openapi,docs,sessions}"
MAX_CANDIDATES="${MAX_CANDIDATES:-100}"
MAX_CHANGE_PERCENT="${MAX_CHANGE_PERCENT:-20}"
SYNC_DATE_UTC="$(date -u +%Y-%m-%d)"
BRANCH="skill-sync/$SYNC_DATE_UTC"
OUT_DIR="/tmp/skill-sync"
mkdir -p "$OUT_DIR"

for bin in jq curl git; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "FATAL: $bin not found in PATH." >&2
    exit 1
  fi
done

if [[ "$DRY_RUN" != "1" ]]; then
  # Working tree must be clean for non-dry runs.
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    echo "FATAL: working tree is not clean. Commit or stash before running skill-sync." >&2
    exit 1
  fi
fi

log() { printf '[skill-sync] %s\n' "$*" >&2; }

# ── Fetch sources in parallel ───────────────────────────────────────────────
SCRIPTS_DIR="$REPO_ROOT/skills/skill-sync/scripts"

declare -a PIDS=()

if [[ ",$SOURCES," == *,openapi,* ]]; then
  log "fetching OpenAPI..."
  bash "$SCRIPTS_DIR/fetch-openapi.sh" > "$OUT_DIR/openapi.json" 2> "$OUT_DIR/openapi.err" &
  PIDS+=($!)
fi

if [[ ",$SOURCES," == *,docs,* ]]; then
  log "fetching docs..."
  bash "$SCRIPTS_DIR/fetch-docs.sh" > "$OUT_DIR/docs.json" 2> "$OUT_DIR/docs.err" &
  PIDS+=($!)
fi

if [[ ",$SOURCES," == *,sessions,* ]]; then
  log "mining sessions..."
  bash "$SCRIPTS_DIR/mine-sessions.sh" > "$OUT_DIR/sessions.json" 2> "$OUT_DIR/sessions.err" &
  PIDS+=($!)
fi

# Wait for all background fetches; abort if any failed.
fail=0
for pid in "${PIDS[@]}"; do
  if ! wait "$pid"; then
    fail=1
  fi
done
if [[ "$fail" == "1" ]]; then
  log "one or more source fetches failed. See $OUT_DIR/*.err for details."
  exit 1
fi

# ── Build candidate list ────────────────────────────────────────────────────
# v1 (this file): emit a drift summary, do NOT mutate any tracked files yet.
# Each per-rule diff implementation lands as a follow-up PR that adds a
# function here. The first cron run on a green tree will therefore produce
# a PR with only Tier 3 items (drift report). That's intentional — earning
# trust before any auto-apply happens.

TIER1_COUNT=0
TIER2_COUNT=0
TIER3_COUNT=0
TIER3_LIST=""
# TIER1_LIST and TIER2_LIST will appear when per-rule diff logic lands; intentionally
# omitted in v1 so shellcheck doesn't flag unused vars.

# Lightweight summary from the three normalized JSON files, surfaced as Tier 3.
if [[ -f "$OUT_DIR/openapi.json" ]]; then
  endpoint_count=$(jq '.items | length' "$OUT_DIR/openapi.json" 2>/dev/null || echo 0)
  TIER3_LIST+="- OpenAPI: ${endpoint_count} endpoints observed at \`$(jq -r .url "$OUT_DIR/openapi.json")\`. Manual diff against \`skills/_shared/references/api-endpoints.md\` recommended.\n"
  TIER3_COUNT=$((TIER3_COUNT + 1))
fi

if [[ -f "$OUT_DIR/docs.json" ]]; then
  page_count=$(jq '.items | length' "$OUT_DIR/docs.json" 2>/dev/null || echo 0)
  missing=$(jq '[.items[] | select(.missing==true)] | length' "$OUT_DIR/docs.json" 2>/dev/null || echo 0)
  TIER3_LIST+="- Docs: ${page_count} pages crawled, ${missing} missing (404 or unreachable). Manual diff against shared references recommended.\n"
  TIER3_COUNT=$((TIER3_COUNT + 1))
fi

if [[ -f "$OUT_DIR/sessions.json" ]]; then
  pattern_count=$(jq '.items | length' "$OUT_DIR/sessions.json" 2>/dev/null || echo 0)
  if [[ "$pattern_count" -gt 0 ]]; then
    while IFS=$'\t' read -r label count file_count; do
      TIER3_LIST+="- Sessions: pattern \`${label}\` fired ${count} times across ${file_count} transcripts.\n"
      TIER3_COUNT=$((TIER3_COUNT + 1))
    done < <(jq -r '.items[] | [.pattern, .count, .file_count] | @tsv' "$OUT_DIR/sessions.json" 2>/dev/null || true)
  fi
fi

TOTAL_CANDIDATES=$((TIER1_COUNT + TIER2_COUNT + TIER3_COUNT))

if [[ "$TOTAL_CANDIDATES" -gt "$MAX_CANDIDATES" ]]; then
  log "candidate cap exceeded ($TOTAL_CANDIDATES > $MAX_CANDIDATES); aborting."
  exit 2
fi

# ── Print summary if DRY_RUN ────────────────────────────────────────────────
if [[ "$DRY_RUN" == "1" ]]; then
  printf '\n=== SKILL SYNC DRY RUN — %s ===\n' "$SYNC_DATE_UTC"
  printf 'Tier 1 (auto-apply):  %d\n' "$TIER1_COUNT"
  printf 'Tier 2 (propose):     %d\n' "$TIER2_COUNT"
  printf 'Tier 3 (drift only):  %d\n\n' "$TIER3_COUNT"
  printf 'Drift detected:\n'
  printf '%b\n' "$TIER3_LIST"
  exit 0
fi

# ── Apply Tier 1 ────────────────────────────────────────────────────────────
# v1: no Tier 1 rules implemented. Nothing to apply.
log "Tier 1 rules: 0 implemented in this version. Nothing to apply."

# ── Sync shared & validate (always, even if no edits) ───────────────────────
log "running validators..."
VALIDATE_SKILLS_STATUS="pass"
./scripts/validate-skills.sh >/dev/null 2>&1 || VALIDATE_SKILLS_STATUS="fail"
VALIDATE_SECURITY_STATUS="pass"
./scripts/validate-skill-security.sh >/dev/null 2>&1 || VALIDATE_SECURITY_STATUS="fail"
TEST_API_STATUS="pass"
./scripts/test-tfy-api.sh >/dev/null 2>&1 || TEST_API_STATUS="fail"
SHELLCHECK_STATUS="pass"
shellcheck scripts/*.sh hooks/auto-approve-tfy-api.sh skills/_shared/scripts/tfy-api.sh plugin-scripts/*.sh skills/skill-sync/scripts/*.sh >/dev/null 2>&1 || SHELLCHECK_STATUS="fail"

# ── Open / update PR ────────────────────────────────────────────────────────
if [[ "$TOTAL_CANDIDATES" -eq 0 ]]; then
  log "no drift detected. Skipping PR creation."
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  log "gh CLI not present. Printing PR body to stdout instead of opening a PR."
  cat <<EOF
=== PR BODY (no gh available) ===
Tier 1: $TIER1_COUNT
Tier 2: $TIER2_COUNT
Tier 3: $TIER3_COUNT

Tier 3 / drift report:
$(printf '%b' "$TIER3_LIST")
EOF
  exit 0
fi

# Branch already exists? Update; else create.
if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  log "branch $BRANCH exists upstream; updating PR body in place (no new commits)."
else
  git checkout -B "$BRANCH" >/dev/null 2>&1
  # v1: no commits to push (Tier 1 not implemented). Push empty branch is awkward,
  # so we skip the push if nothing changed and instead PR the existing main with the
  # report as the body. Future versions will push real edits here.
  log "no Tier 1 commits to push; PR body will report drift only."
fi

# Compose PR body from template (string substitution; no full templating).
BODY_FILE="$OUT_DIR/pr-body.md"
cat > "$BODY_FILE" <<EOF
## Skill Sync — ${SYNC_DATE_UTC}

This PR was opened by the \`truefoundry-skill-sync\` meta-skill. **Do not auto-merge.**

### Sources
- OpenAPI: $([[ -f "$OUT_DIR/openapi.json" ]] && jq -r '"\(.url) — \(.items | length) endpoints"' "$OUT_DIR/openapi.json" || echo "skipped")
- Docs: $([[ -f "$OUT_DIR/docs.json" ]] && jq -r '"\(.base_url) — \(.items | length) pages"' "$OUT_DIR/docs.json" || echo "skipped")
- Sessions: $([[ -f "$OUT_DIR/sessions.json" ]] && jq -r '"\(.transcripts_scanned // 0) transcripts, \(.items | length) patterns"' "$OUT_DIR/sessions.json" || echo "skipped")

### Auto-applied (Tier 1) — ${TIER1_COUNT}

_None — this version of skill-sync is report-only; per-rule auto-apply lands incrementally._

### Proposed (Tier 2) — ${TIER2_COUNT}

_None in this version._

### Drift detected (Tier 3) — ${TIER3_COUNT}

$(printf '%b' "$TIER3_LIST")

### Validators
- validate-skills.sh: ${VALIDATE_SKILLS_STATUS}
- validate-skill-security.sh: ${VALIDATE_SECURITY_STATUS}
- test-tfy-api.sh: ${TEST_API_STATUS}
- shellcheck: ${SHELLCHECK_STATUS}

### Caps
- MAX_CANDIDATES: ${MAX_CANDIDATES} (used ${TOTAL_CANDIDATES})

🤖 Generated by \`truefoundry-skill-sync\`.
EOF

if gh pr view "$BRANCH" >/dev/null 2>&1; then
  gh pr edit "$BRANCH" --body-file "$BODY_FILE" >/dev/null
  log "updated existing PR for branch $BRANCH."
else
  # If branch doesn't exist remotely, push HEAD as the branch so we can open a PR.
  if ! git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
    git push -u origin "HEAD:$BRANCH" >/dev/null 2>&1 || true
  fi
  gh pr create \
    --base main \
    --head "$BRANCH" \
    --title "chore(skills): scheduled sync — ${SYNC_DATE_UTC}" \
    --body-file "$BODY_FILE" >/dev/null
  log "opened PR for branch $BRANCH."
fi

log "done."
