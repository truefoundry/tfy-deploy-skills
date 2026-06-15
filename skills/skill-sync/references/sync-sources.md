# Sync Sources

The three input streams the skill consumes, where each lives, and the filter rules applied before diffing against the repo.

## 1. TrueFoundry OpenAPI spec

**URL:** `${TFY_OPENAPI_URL:-https://docs.truefoundry.com/openapi.json}`

**Fetcher:** `scripts/fetch-openapi.sh`

**Normalization:**
- Parse with `jq`.
- Emit one item per `(path, method)` with the operation summary, request schema, response schema, and tags.
- Resolve `$ref` pointers inline so the diff is self-contained.
- Drop deprecated paths (operation has `"deprecated": true`).

**Diff target:**
- `skills/_shared/references/api-endpoints.md` — every `(method, path)` pair quoted in this file must exist in the spec; every spec endpoint relevant to the skills' surface should be mentioned.
- `skills/_shared/references/rest-api-manifest.md` — manifest field types and required-ness must match the spec's request schemas.
- `skills/_shared/references/manifest-schema.md` — YAML field tables vs OpenAPI component schemas.

**Confidence rules:**
- New endpoint listed in spec, missing from `api-endpoints.md` → Tier 1 (append to the file).
- Endpoint removed from spec, still in `api-endpoints.md` → Tier 3 (drift report — could be a breaking change).
- Field type drift (e.g., `string` → `enum`) → Tier 2 (propose).
- New required field on a request schema → Tier 2 (propose; users have to update their manifests).
- Tag/group rename → Tier 2.

## 2. Public docs

**Base URL:** `${TFY_DOCS_BASE_URL:-https://docs.truefoundry.com}`

**Fetcher:** `scripts/fetch-docs.sh`

The crawler is **section-scoped**, not a full mirror. It pulls a known list of pages relevant to the skills:

| Page | Maps to |
|---|---|
| `/docs/gpus` (or `/docs/supported-gpu-types`) | `gpu-reference.md` |
| `/docs/container-images` (or pinned images page) | `container-versions.md` |
| `/docs/manifests/service`, `/docs/manifests/job`, `/docs/manifests/helm`, `/docs/manifests/volume`, `/docs/manifests/secret-group`, `/docs/manifests/workflow` | corresponding section in `manifest-schema.md` |
| `/docs/build-specs` | manifest-schema.md → BuildSpec section |
| `/docs/cluster-discovery` | `cluster-discovery.md` |
| `/docs/health-probes` | `health-probes.md` |

Each page is normalized to `{title, url, headings: [...], code_blocks: [...], plain_text: "..."}`. The diff compares structured content (headings, code blocks) not raw HTML — small layout changes upstream don't generate noise.

**Confidence rules:**
- New GPU type appears in `gpus` page → Tier 1 (append to enum tables in `gpu-reference.md` and `manifest-schema.md`).
- New container image version pinned → Tier 1 (update `container-versions.md`).
- New manifest field appears in a docs page table → Tier 2 (propose).
- Field deprecation notice on docs page → Tier 2.
- Whole new manifest type → Tier 3 (needs a new section in `manifest-schema.md` and a possible new SKILL).

## 3. Session transcripts

**Directory:** `${SESSION_LOG_DIR:-~/.claude/projects}`

**Lookback:** `${SESSION_LOOKBACK_DAYS:-45}` days.

**Fetcher:** `scripts/mine-sessions.sh`

The script filters JSONL session logs to TrueFoundry-related work (anything that mentions `tfy-api.sh`, `truefoundry-`, `tfy apply`, `tfy deploy`, `TFY_*`, `.truefoundry.cloud`, or invokes a `kubectl`/`helm`/`argocd` command — the latter because those are the escape-hatch attempts we want to surface).

For each session, it scans for **patterns** rather than reading every line:

| Pattern | Signal |
|---|---|
| Repeated `must have required property '<X>'` errors across ≥3 sessions | Missing required field documentation |
| Repeated `must match exactly one schema in oneOf` errors | Schema drift or undocumented variant |
| Repeated `No such command '<X>'` from `tfy` CLI | CLI surface drift |
| `kubectl` invocations that the block-kubectl hook did NOT catch (pre-hook sessions or future bypass attempts) | Hook gap |
| User correcting the assistant mid-session ("no, the workspace should be...", "stop using kubectl", "that field doesn't exist") | Behavioral drift the docs don't show |
| 401/403 responses with a specific endpoint | Auth scope drift |

**Redaction (applied before anything is written to disk):**
- Drop any string longer than 40 chars that looks like a bearer token (`[A-Za-z0-9_-]{40,}`).
- Drop any string matching `tfy_[A-Za-z0-9_-]{20,}` (TrueFoundry token prefix).
- Drop `Authorization: Bearer ...` header values.
- Drop email addresses except `@truefoundry.com` (kept for context — staff email is not sensitive in our threat model; user emails are).
- Drop fully-qualified hostnames that aren't `truefoundry.cloud` or `truefoundry.com`.
- Drop the contents of any `.env` file fragment that appears in the transcript.

The redacted output goes to `/tmp/skill-sync/sessions.json`. **Never** to a tracked path.

**Confidence rules:**
- ≥3 sessions hit the same `must have required property` error → Tier 2 (propose schema doc update).
- ≥3 sessions hit the same CLI subcommand-not-found → Tier 1 update to `cli-version-compat.md`.
- Single kubectl bypass attempt that the hook missed → Tier 2 (propose hook regex extension; never auto-edit a hook).
- Repeated user correction on the same topic → Tier 3 (drift report; needs a human to decide what to do with it).

## What the fetchers DON'T do

- They do not paginate through the entire TrueFoundry API for every tenant. The OpenAPI spec is one URL.
- They do not crawl docs recursively. The page list is explicit and grows by hand.
- They do not read session transcripts outside `SESSION_LOG_DIR`.
- They do not send any data anywhere. All outputs are local files in `/tmp/skill-sync/`. The only network calls are the spec fetch and the doc page fetches, both to TrueFoundry-controlled domains.
