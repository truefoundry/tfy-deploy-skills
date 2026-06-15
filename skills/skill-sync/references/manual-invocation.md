# Manual Invocation

skill-sync runs only when a human starts it. There is no cron, no PR auto-trigger, no scheduled workflow. This file documents the two supported invocation paths and what each is good for.

## Path 1 — local CLI (recommended for development)

Run from a clean checkout:

```bash
# Preview only — no PR opened, no commits written. Prints drift to stdout.
DRY_RUN=1 bash skills/skill-sync/scripts/run-sync.sh

# Full run — opens or updates a PR for the current UTC day.
bash skills/skill-sync/scripts/run-sync.sh

# Restrict to one source (useful when iterating on a single fetcher).
SOURCES=openapi bash skills/skill-sync/scripts/run-sync.sh
SOURCES=docs    bash skills/skill-sync/scripts/run-sync.sh
SOURCES=sessions bash skills/skill-sync/scripts/run-sync.sh

# Restrict to a single skill (useful when debugging a per-skill rule).
SKILL=volumes bash skills/skill-sync/scripts/run-sync.sh
```

Local runs require:
- `git status` clean (the script refuses to proceed otherwise, unless `DRY_RUN=1`).
- `gh auth status` OK if you want the script to open the PR (otherwise it prints the PR body to stdout).
- Internet access to `docs.truefoundry.com` for the OpenAPI + docs fetchers.

Local runs are the only way to feed session-mined drift into the PR — session transcripts live on contributors' machines, not in CI.

## Path 2 — GitHub Actions `workflow_dispatch` (recommended for maintainers without a checkout)

Go to: GitHub → Actions → `skill-sync` → "Run workflow" → pick `dry_run` (true/false) → "Run workflow".

The workflow runs `bash skills/skill-sync/scripts/run-sync.sh` on a fresh `ubuntu-latest` runner. With `dry_run=true`, the drift report goes to the action log; with `dry_run=false`, the action opens or updates a PR on `skill-sync/YYYY-MM-DD`.

CI runs use:
- `${{ secrets.GITHUB_TOKEN }}` for branch push + PR open.
- No `TFY_API_KEY` (OpenAPI + docs are public — no auth needed).
- Empty `SESSION_LOG_DIR` (no transcripts on CI runners — session mining is silently skipped).

That last point is intentional: session-derived candidates only appear when a contributor runs the skill locally on their machine. The PR is additive across local + CI runs on the same UTC day (same branch name `skill-sync/YYYY-MM-DD`), so a maintainer can trigger a CI run, then later run locally to layer session candidates on top.

## What is NOT supported

- **No `schedule:` trigger.** `.github/workflows/skill-sync.yml` has no `on: schedule` block by design. Adding one would let the skill rewrite docs without a human in the loop — that's the failure mode we're avoiding.
- **No invocation from other skills.** The deploy/helm/llm-deploy skills do not call skill-sync. Nothing in the repo calls it implicitly.
- **No webhook trigger.** Not on PR-opened, not on push, not on issue-comment. Manual button or local CLI only.

## Required GitHub permissions

The workflow needs:
- `contents: write` — push the `skill-sync/YYYY-MM-DD` branch.
- `pull-requests: write` — open or update the PR.

These are declared in the workflow's `permissions:` block and inherited from the default `GITHUB_TOKEN`. No extra PAT is required unless branch protection on `main` mandates a different identity — in which case create a fine-grained PAT with exactly those two scopes (do **not** grant `workflows: write`, since skill-sync is excluded from editing the workflow file).

## Disabling the workflow entirely

To remove even the manual button: delete `.github/workflows/skill-sync.yml`. The skill remains usable from local CLI; only the CI button goes away.

## How re-runs interact

Both invocation paths use the same branch name `skill-sync/YYYY-MM-DD` (UTC). Multiple runs on the same UTC day update the same branch and PR rather than duplicating. To start a fresh PR, delete the existing branch (`git push origin --delete skill-sync/YYYY-MM-DD`) and re-run; the script will create a new branch with the same name.
