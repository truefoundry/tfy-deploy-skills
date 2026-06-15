# Cron Setup

How the scheduled sync runs in GitHub Actions.

## The workflow

Lives at `.github/workflows/skill-sync.yml`. Trigger:

```yaml
on:
  schedule:
    - cron: "0 9 * * 1"   # Mondays 09:00 UTC
  workflow_dispatch: {}   # also runnable manually from the Actions tab
```

The job checks out the repo, installs `jq`, `yq`, `gh`, runs the sync, and (only if there are candidates) opens or updates a PR.

## Secrets required

| Secret | Scope | Purpose |
|---|---|---|
| `TFY_API_KEY` | TrueFoundry tenant the maintainer team uses for staging | Lets the sync hit `/api/svc/v1/*` for sanity checks (optional — see "Without TFY_API_KEY" below) |
| `TFY_BASE_URL` | Repository variable, not secret | Base URL of the same tenant |
| `GITHUB_TOKEN` | Default action token | Pushes branches and creates PRs |

The default `${{ secrets.GITHUB_TOKEN }}` is sufficient for branch push and PR open in this repo. If branch protection requires a different identity, swap in a fine-grained PAT with:
- `contents: write` on this repo
- `pull-requests: write` on this repo
- No other scope

Do **not** grant `workflows: write` — the sync skill is explicitly excluded from editing `.github/workflows/`.

## Without TFY_API_KEY

The OpenAPI fetch hits `https://docs.truefoundry.com/openapi.json` and does NOT require an API key. The docs crawl is also unauthenticated. Sessions are read from the local checkout (which doesn't apply on a fresh runner — see "Session mining in CI" below).

So the bare-minimum cron run is: OpenAPI + docs, no sessions, no API sanity checks. That's fine — most useful drift is in OpenAPI vs docs.

## Session mining in CI

Session transcripts live on contributors' machines, not in CI. The cron run therefore skips session mining unless `SESSION_LOG_DIR` is mounted from an artifact (none of the maintainers do this today; mentioned for completeness). To get session-derived candidates into the PR, contributors run `bash skills/skill-sync/scripts/run-sync.sh` locally and the resulting PR is updated additively.

## Idempotency

The branch name is `skill-sync/YYYY-MM-DD` (UTC). Two runs the same day:
1. First run creates the branch and opens the PR.
2. Second run force-updates the branch with the new candidate set and edits the PR body in place.

Different UTC days produce different branches. The cron schedule (`0 9 * * 1`) hits once a week, so day-collision in CI is rare.

## What the workflow does NOT do

- Does not push to `main`.
- Does not auto-merge.
- Does not approve its own PR.
- Does not run on every push — only on the cron and on manual `workflow_dispatch`.
- Does not send notifications anywhere; GitHub's PR-opened email is the notification surface.

## Disabling

To pause the cron: comment out the `schedule:` block in `.github/workflows/skill-sync.yml`. The skill remains manually invocable via `workflow_dispatch` or local CLI.

To delete the workflow entirely: remove `.github/workflows/skill-sync.yml`. The skill itself stays usable from local checkouts.
