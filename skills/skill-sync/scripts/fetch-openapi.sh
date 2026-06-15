#!/usr/bin/env bash
# Fetch the TrueFoundry OpenAPI spec, normalize it into a candidate list, emit JSON on stdout.
# Output schema: {source: "openapi", fetched_at, items: [{op_id, method, path, summary, tags, request_required_fields, response_codes}, ...]}.
set -euo pipefail

URL="${TFY_OPENAPI_URL:-https://docs.truefoundry.com/openapi.json}"
OUT_DIR="${OUT_DIR:-/tmp/skill-sync}"
mkdir -p "$OUT_DIR"

if ! command -v jq >/dev/null 2>&1; then
  echo '{"error":"jq not found in PATH"}' >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo '{"error":"curl not found in PATH"}' >&2
  exit 1
fi

raw="$OUT_DIR/openapi.raw.json"
if ! curl -fsSL --max-time 60 "$URL" -o "$raw"; then
  echo "{\"error\":\"failed to fetch OpenAPI spec from $URL\"}" >&2
  exit 1
fi

# Normalize: walk paths × methods, emit one item per operation.
# Drop deprecated operations. Resolve required fields from inline request bodies only
# (full $ref resolution is left to the diff stage where it has more context).
jq -n --arg url "$URL" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --slurpfile spec "$raw" '
  ($spec[0]) as $s
  | {
      source: "openapi",
      fetched_at: $ts,
      url: $url,
      info: ($s.info // {}),
      items: [
        ($s.paths // {})
        | to_entries[]
        | .key as $p
        | .value
        | to_entries[]
        | select(.key | IN("get","post","put","patch","delete"))
        | {
            method: (.key | ascii_upcase),
            path: $p,
            op_id: (.value.operationId // null),
            summary: (.value.summary // ""),
            tags: (.value.tags // []),
            deprecated: (.value.deprecated // false),
            request_required: (
              .value.requestBody.content["application/json"].schema.required // []
            ),
            response_codes: ((.value.responses // {}) | keys)
          }
        | select(.deprecated == false)
      ]
    }
'
