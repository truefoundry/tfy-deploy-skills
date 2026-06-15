---
name: truefoundry-skill-sync
description: Self-update flow for this deploy-skills repo. Diffs the skills against three sources of truth (the TrueFoundry OpenAPI spec, the public docs site, and recent Claude session transcripts), classifies each candidate change by confidence, applies safe edits (typos, new enum values, new endpoints), and proposes risky edits in a pull request for human review. **Manual invocation ONLY** — never runs on a schedule. Use ONLY when a human explicitly asks to "sync skills", "update skills from docs", or "run skill-sync", or manually triggers the GitHub Actions workflow.
license: MIT
compatibility: Requires Bash, curl, jq, git, and a checkout of truefoundry/tfy-deploy-skills
metadata:
  disable-model-invocation: "true"
allowed-tools: Bash(*/tfy-api.sh *) Bash(curl *) Bash(jq *) Bash(git *) Bash(yq *) Bash(diff *) Bash(grep *) Bash(find *) Bash(awk *) Bash(./skills/skill-sync/scripts/*.sh*) Bash(gh *)
---

> **HARD RULE — no `kubectl` / `helm` CLI / `argocd`.** Use only TrueFoundry skills and APIs. See [`references/no-kubectl.md`](references/no-kubectl.md) for the intent→skill mapping. Cluster-level commands are blocked by the plugin's PreToolUse hook.
>
> Routing note: For ambiguous user intents, use the shared clarification templates in [references/intent-clarification.md](references/intent-clarification.md).

<objective>

# Skill Sync — Keep deploy-skills aligned with the platform

This is a **meta-skill**. It does not deploy anything. It maintains the other 22 skills so they stay accurate as the TrueFoundry platform evolves.

The skills drift quietly: endpoints rename, new fields appear in the manifest schema, GPU types get added, sessions surface failure modes the docs don't yet cover. Without periodic reconciliation, the skills slowly lose authority and people start working around them. This skill closes the loop by reading the canonical sources, diffing them against the repo, and shipping the safe parts as a PR.

## When to Use

- The user says "sync skills", "update skills from docs", "check for skill drift", or "run skill-sync".
- A maintainer manually triggers the GitHub Actions workflow from the Actions tab (`workflow_dispatch`). There is no cron — this skill is intentionally **never** invoked on a schedule.
- After a major TrueFoundry platform release, when a maintainer wants the deploy-skills updated against the new API.

> **Manual-invocation rule:** this skill rewrites docs and reference files in this repo. It MUST NOT run unattended. No cron, no PR auto-trigger, no scheduled workflow. Every run starts with a human clicking something.

## When NOT to Use

- Day-to-day deploy work — the regular deploy/helm/llm-deploy skills cover that.
- Creating a new skill from scratch — this skill maintains existing skills, it doesn't generate new ones.
- Anything outside the `truefoundry/tfy-deploy-skills` repo — this skill assumes it is running inside a checkout of that repo.

## What it does NOT touch

Hard exclusions — even if the sources say the file should change, this skill skips them:

- `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, `README.md` — human-curated; propose, never auto-edit.
- `hooks/`, `plugin-scripts/block-*.sh`, `plugin-scripts/pre-tool-secret-scan.sh` — security and policy boundaries.
- `skills/skill-sync/` (this skill) — no self-modification.
- The `disable-model-invocation` flag on any skill — that's a deliberate policy choice.

</objective>

<instructions>

## Inputs (three sources of truth)

| Source | Where | Diffed against |
|---|---|---|
| TrueFoundry OpenAPI spec | `https://docs.truefoundry.com/openapi.json` (or wherever the user configures via `TFY_OPENAPI_URL`) | `skills/_shared/references/api-endpoints.md`, `rest-api-manifest.md`, `manifest-schema.md` |
| TrueFoundry public docs | `https://docs.truefoundry.com` — crawled per-section (GPUs, build specs, manifest fields, …) | The matching shared references (`gpu-reference.md`, `container-versions.md`, `manifest-schema.md`, etc.) |
| Recent session transcripts | `~/.claude/projects/**/*.jsonl` (last 45 days, filtered to TrueFoundry-related work) | Surfaces *behavioral* drift the docs don't show — repeated user corrections, repeated `tfy apply` validation errors, repeated kubectl escapes the hook didn't catch |

See `references/sync-sources.md` for the exact fetch commands and filter rules.

## Confidence tiers

Every candidate change is graded **before** any file is written. The grade decides what happens to it.

| Tier | Confidence signal | Action |
|---|---|---|
| **Tier 1 — auto-apply** | Single-file textual edit, fully reversible, agrees with ≥2 sources, doesn't change semantics. Examples: typos, new enum value (new GPU type), new endpoint added to `api-endpoints.md`, new container version. | Commit to the PR branch, include in the PR body's "Auto-applied" section. |
| **Tier 2 — propose in PR body** | Semantic change to a workflow doc, default value flip, new HARD RULE, new section in a `SKILL.md`, removal of guidance. | Render as a unified diff in the PR body's "Proposed (needs human review)" section. **Do not commit.** |
| **Tier 3 — drift report only** | One-source signal, conflicting signals between sources, suspected breaking change, anything touching files on the hard-exclusion list. | List in the PR body's "Drift detected — needs human judgment" section with a one-line summary. **Do not commit, do not propose a patch.** |

The detailed rules — including the per-file confidence table and the validators that must pass before Tier 1 is applied — are in `references/confidence-rules.md`. Read it before running.

## The flow

1. **Pre-flight.** `git status --porcelain` must be clean. `tfy --version` and `gh --version` must succeed. `TFY_API_KEY` and `GITHUB_TOKEN` (or `gh auth status` OK) must be set. Working directory must be the repo root (`scripts/` and `skills/` both present).

2. **Fetch sources** in parallel:
   ```bash
   bash skills/skill-sync/scripts/fetch-openapi.sh > /tmp/skill-sync/openapi.json &
   bash skills/skill-sync/scripts/fetch-docs.sh    > /tmp/skill-sync/docs.json &
   bash skills/skill-sync/scripts/mine-sessions.sh > /tmp/skill-sync/sessions.json &
   wait
   ```
   Each script writes a normalized JSON blob `{source, fetched_at, items: [...]}`. If any script fails, abort and report; do not partial-sync.

3. **Diff and classify.** For each source, compare against the in-repo references. Emit a list of candidates, each tagged with `{tier, file, summary, diff?, evidence: [source: snippet, ...]}`. Cap the candidate list at 100 per run — beyond that means too much has changed and a human should look.

4. **Apply Tier 1.** For each Tier 1 candidate, apply the edit, then run the full validator chain:
   ```bash
   ./scripts/validate-skills.sh           # frontmatter, sync, doc consistency
   ./scripts/validate-skill-security.sh   # security policy
   ./scripts/test-tfy-api.sh              # tfy-api.sh unit tests
   shellcheck scripts/*.sh hooks/auto-approve-tfy-api.sh skills/_shared/scripts/tfy-api.sh plugin-scripts/*.sh skills/skill-sync/scripts/*.sh
   ```
   If any validator fails, **revert that edit** and downgrade the candidate to Tier 2 with the validator error attached. Never push a state that fails validation.

5. **Sync shared files.** After Tier 1 edits, run `./scripts/sync-shared.sh` so per-skill copies match `_shared/`.

6. **Open or update the PR.** Branch name: `skill-sync/YYYY-MM-DD` (deterministic per UTC day so a re-run updates instead of duplicating). Title: `chore(skills): manual sync — YYYY-MM-DD`. Body: see `references/pr-template.md`.

7. **Hands off.** This skill never merges. It never approves. The PR sits for human review.

## Safety boundaries (non-negotiable)

- **Never auto-merge.** Even all-green Tier 1.
- **Never push to `main`.** Always to the `skill-sync/...` branch.
- **Never bypass validators.** A red validator means downgrade to Tier 2, not push-anyway.
- **Never touch the hard-exclusion list** (above).
- **Per-run diff cap:** if Tier 1+Tier 2 candidates together would change more than 20% of total skill content (by file count or by line count), abort and report. Something big upstream needs a human look.
- **Never run kubectl, helm, or argocd.** Same rule as every other skill — the hook enforces it anyway.
- **Never commit secrets.** The session-mining script is paranoid about this; see `scripts/mine-sessions.sh` for the redaction rules.

## Manual invocation

```bash
# Dry-run (no PR opened, no commits — prints the candidate list to stdout)
DRY_RUN=1 bash skills/skill-sync/scripts/run-sync.sh

# Full run (opens or updates the PR)
bash skills/skill-sync/scripts/run-sync.sh

# Restrict to one source
SOURCES=openapi bash skills/skill-sync/scripts/run-sync.sh

# Restrict to one skill (for debugging)
SKILL=volumes bash skills/skill-sync/scripts/run-sync.sh
```

Environment variables the run-sync script honors:

| Variable | Default | Effect |
|---|---|---|
| `DRY_RUN` | `0` | If `1`, print candidates and exit; do not edit files or push. |
| `SOURCES` | `openapi,docs,sessions` | Comma-separated list of sources to use this run. |
| `SKILL` | `(all)` | Restrict diff/apply to a single skill subdirectory. |
| `TFY_OPENAPI_URL` | `https://docs.truefoundry.com/openapi.json` | Override OpenAPI source URL. |
| `TFY_DOCS_BASE_URL` | `https://docs.truefoundry.com` | Override docs base URL for the crawler. |
| `SESSION_LOG_DIR` | `~/.claude/projects` | Override location of session transcripts. |
| `SESSION_LOOKBACK_DAYS` | `45` | How far back to mine sessions. |
| `MAX_CANDIDATES` | `100` | Abort the run if more candidates than this. |
| `MAX_CHANGE_PERCENT` | `20` | Per-run diff cap (percent of skill content). |

## Manual GitHub Actions invocation

`.github/workflows/skill-sync.yml` exposes a `workflow_dispatch` trigger so a maintainer can run the skill from the Actions tab without checking out the repo. There is **no `schedule:` block** — it never runs unattended. Inputs:

- `dry_run` (boolean, default `false`) — when true, prints the drift report to the action log instead of opening a PR.

To trigger: GitHub → Actions → `skill-sync` → "Run workflow" → choose `dry_run` → "Run workflow". The job uses the default `${{ secrets.GITHUB_TOKEN }}` to push the branch and open the PR; no extra secrets needed for the OpenAPI + docs sources (both unauthenticated).

See `references/manual-invocation.md` for the full list of invocation paths and what each one is good for.

## How this skill is used by other skills

It isn't, intentionally. This is the only skill in the repo with `disable-model-invocation: "true"` AND no composability links from other skills. It runs only because a human explicitly asks — either through the chat or through the GitHub Actions "Run workflow" button. That keeps it from being invoked accidentally mid-deploy.

## Composability

- **Reads**: every other skill's `SKILL.md` and `references/*.md`.
- **Writes**: same files (Tier 1 only), plus the PR.
- **Never modifies**: `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, `README.md`, `hooks/`, `plugin-scripts/block-*.sh`, itself.

</instructions>

<success_criteria>

- A PR `skill-sync/YYYY-MM-DD` exists on GitHub when changes were detected.
- The PR body has three sections: "Auto-applied (Tier 1)", "Proposed (Tier 2)", "Drift detected (Tier 3)".
- `validate-skills.sh`, `validate-skill-security.sh`, `test-tfy-api.sh`, and `shellcheck` all pass on the PR's HEAD.
- Per-run diff cap was not exceeded.
- No file on the hard-exclusion list was modified.
- The user can re-run the same day and the existing PR is **updated**, not duplicated.

</success_criteria>

<references>

| Reference | Contents |
|---|---|
| `references/sync-sources.md` | Where each input comes from, fetch URLs, filter rules |
| `references/confidence-rules.md` | Per-file confidence table; which signals upgrade or downgrade a candidate |
| `references/pr-template.md` | The PR body template (Tier 1 / Tier 2 / Tier 3 sections) |
| `references/manual-invocation.md` | The two ways to trigger this skill (local CLI, GitHub Actions `workflow_dispatch`); required secrets and scope |
| `references/no-kubectl.md` | Shared no-kubectl policy |
| `references/cli-version-compat.md` | Shared CLI compatibility doc |

</references>

<troubleshooting>

### `validate-skills.sh` fails after a Tier 1 edit

The skill reverts the edit and downgrades to Tier 2 automatically. Inspect the PR body's "Proposed" section to see what was downgraded and why.

### The PR is empty (no candidates)

That's success. The repo agrees with all three sources. Re-run with `DRY_RUN=1` to see the full diff log if you want to verify.

### Per-run cap was exceeded

The script aborts before opening the PR and prints which source produced how many candidates. Investigate upstream — usually means a major release on the platform side. After investigating, re-run with `MAX_CANDIDATES=200` if you're confident.

### "Why isn't this on a schedule?"

By design. This skill rewrites docs in this repo. Letting it run unattended means one upstream platform change could land in `main` (via Tier 1 auto-apply) before any human reads the proposed edit. Manual-only invocation forces a maintainer to be in the loop for every run.

### Session-mining can't find any transcripts

Set `SESSION_LOG_DIR` to point at the right path. On non-Claude-Code agents the location differs; on macOS Claude Code it's `~/.claude/projects/`.

### "GitHub token missing required scope"

The PR-creation step needs `repo` scope (or `contents:write + pull-requests:write` if using a fine-grained PAT). See `references/manual-invocation.md`.

</troubleshooting>
