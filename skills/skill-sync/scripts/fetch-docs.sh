#!/usr/bin/env bash
# Fetch a known list of public docs pages, extract structured content per page, emit JSON on stdout.
# Output: {source: "docs", fetched_at, items: [{url, title, headings: [...], code_blocks: [...]}, ...]}.
# The page list is intentionally explicit — we do not crawl recursively.
set -euo pipefail

BASE="${TFY_DOCS_BASE_URL:-https://docs.truefoundry.com}"
OUT_DIR="${OUT_DIR:-/tmp/skill-sync}"
mkdir -p "$OUT_DIR"

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  echo '{"error":"need jq and curl in PATH"}' >&2
  exit 1
fi

# Explicit page list — extend deliberately, not by crawling.
PAGES=(
  "/docs/supported-gpu-types"
  "/docs/container-images"
  "/docs/manifests/service"
  "/docs/manifests/job"
  "/docs/manifests/helm"
  "/docs/manifests/volume"
  "/docs/manifests/secret-group"
  "/docs/manifests/workflow"
  "/docs/manifests/async-service"
  "/docs/manifests/notebook"
  "/docs/manifests/ssh-server"
  "/docs/build-specs"
  "/docs/cluster-discovery"
  "/docs/health-probes"
  "/docs/autoscaling"
)

items='[]'
fetched_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

for page in "${PAGES[@]}"; do
  url="${BASE}${page}"
  html_file="$OUT_DIR/$(echo "$page" | tr '/' '_').html"

  # Tolerate 404 — page list may drift. Mark page as not-found in the output and continue.
  status=$(curl -fsSL --max-time 30 -w '%{http_code}' "$url" -o "$html_file" || echo "000")
  if [[ "$status" != "200" ]]; then
    items=$(echo "$items" | jq --arg url "$url" --arg s "$status" \
      '. + [{url: $url, status: $s, missing: true}]')
    continue
  fi

  # Heuristic structured extract — no full HTML parser, just grep for the bits we diff against.
  title=$(grep -oE '<title>[^<]*</title>' "$html_file" | head -1 | sed -E 's|</?title>||g')
  # Pull h1/h2/h3 text — strip tags crudely.
  headings=$(grep -oE '<h[1-3][^>]*>[^<]*</h[1-3]>' "$html_file" \
    | sed -E 's|<[^>]*>||g' \
    | jq -R . | jq -s .)
  # Pull <code> blocks (single-line and multi-line both).
  code_blocks=$(awk 'BEGIN{RS="</code>"} /<code/{sub(/.*<code[^>]*>/,""); print}' "$html_file" \
    | jq -R . | jq -s .)

  items=$(echo "$items" | jq \
    --arg url "$url" \
    --arg title "$title" \
    --argjson headings "$headings" \
    --argjson code_blocks "$code_blocks" \
    '. + [{url: $url, title: $title, headings: $headings, code_blocks: $code_blocks, missing: false}]')
done

jq -n --arg base "$BASE" --arg ts "$fetched_at" --argjson items "$items" '
  {source: "docs", fetched_at: $ts, base_url: $base, items: $items}
'
