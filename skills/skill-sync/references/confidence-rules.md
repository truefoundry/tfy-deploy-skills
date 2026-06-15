# Confidence Rules

The per-file table that decides which tier a candidate change lands in. Read this before changing anything in `run-sync.sh`.

## Per-file tier table

| File (or glob) | Max auto-apply tier | Notes |
|---|---|---|
| `skills/_shared/references/gpu-reference.md` | Tier 1 (auto) | New enum rows allowed; renames/removals → Tier 2. |
| `skills/_shared/references/container-versions.md` | Tier 1 | Version-pin bumps allowed when ≥2 sources agree. |
| `skills/_shared/references/api-endpoints.md` | Tier 1 (append-only) | New endpoint rows allowed; deletions → Tier 3. |
| `skills/_shared/references/manifest-schema.md` | Tier 2 | Schema is load-bearing; never auto-edit. New enum values can be Tier 1 if ≥2 sources agree. |
| `skills/_shared/references/rest-api-manifest.md` | Tier 2 | Same as manifest-schema.md. |
| `skills/_shared/references/cli-version-compat.md` | Tier 1 | New subcommand-not-found notes allowed. CLI version pin bumps → Tier 2. |
| `skills/_shared/references/cluster-discovery.md` | Tier 2 | |
| `skills/_shared/references/health-probes.md` | Tier 2 | |
| `skills/_shared/references/manifest-defaults.md` | Tier 2 | |
| `skills/_shared/references/no-kubectl.md` | **Tier 3 only** | Policy doc. Never auto-edit. |
| `skills/_shared/references/prerequisites.md` | **Tier 3 only** | Includes the workspace gate. Never auto-edit. |
| `skills/_shared/references/cli-fallback.md` | Tier 2 | |
| `skills/_shared/references/tfy-api-setup.md` | Tier 2 | |
| `skills/_shared/references/resource-estimation.md` | Tier 1 | Rule-of-thumb tables; safe to refine. |
| `skills/_shared/references/intent-clarification.md` | **Tier 3 only** | UX-sensitive; needs human review. |
| `skills/*/SKILL.md` | **Tier 3 only** | The skills' contracts. Never auto-edit. |
| `skills/*/references/*.md` (per-skill, non-shared) | Tier 2 | Local refs may be edited as proposals; not auto-applied. |
| `skills/*/scripts/*.sh` | Tier 3 (never) | Always synced from `_shared/` by `sync-shared.sh`. |
| `skills/_shared/scripts/*.sh` | Tier 3 (never) | Code, not docs. Out of scope for sync. |
| `hooks/`, `plugin-scripts/`, `.claude-plugin/`, `.codex-plugin/` | **excluded** | Hard-excluded. Not even Tier 3. |
| `CLAUDE.md`, `AGENTS.md`, `README.md`, `.cursorrules` | **excluded** | Human-curated. |
| `scripts/`, `.github/workflows/` | **excluded** | Build/CI surface. |
| `skills/skill-sync/**` | **excluded** | No self-modification. |

## Tier escalation triggers

A candidate's tier starts at the table value above, then gets **downgraded** (more conservative) if any of these conditions hit:

| Trigger | Downgrade |
|---|---|
| Only one source supports the change | Downgrade by one tier |
| Sources conflict (OpenAPI says X, docs say Y) | Downgrade to Tier 3, attach both quotes |
| The change touches an `expose`, `auth`, `permissions`, `collaborators`, or `delete` keyword | Downgrade by one tier (security-adjacent) |
| The change removes content (vs adding or modifying) | Downgrade by one tier (removals are riskier) |
| The candidate's diff is >100 lines | Downgrade to Tier 3 |
| A validator (`validate-skills.sh`, `validate-skill-security.sh`, `test-tfy-api.sh`) fails after applying | Downgrade to Tier 2, revert the edit, attach validator output |

Tiers never **upgrade** automatically — only the table value and downgrades count. If you want a more aggressive policy, edit the table; do not add upgrade rules to the runtime.

## Multi-source agreement

A candidate is "multi-source agreement" when at least two of {OpenAPI, docs, sessions} produce the same suggested edit. The agreement check is:

- For schema/endpoint changes: exact string match on the changed identifier (field name, endpoint path).
- For container/GPU version bumps: exact match on the version string.
- For session-derived candidates: never counts as multi-source on its own (sessions are *behavioral* signal, not authoritative); they only escalate confidence on edits sourced from OpenAPI or docs.

## Per-run cap

| Limit | Default | Behavior on breach |
|---|---|---|
| `MAX_CANDIDATES` (total candidates across all sources) | 100 | Abort the run; print summary by source. |
| `MAX_CHANGE_PERCENT` (lines changed / total lines under management) | 20% | Abort the run; print top 10 candidates. |
| Single-file diff size | 200 lines | Downgrade that candidate to Tier 3. |

These exist to catch upstream breaking changes early — a 40% diff usually means the platform shipped a new manifest format, not that the repo drifted hard.

## The "agrees with hard-exclusion list" check

Before applying Tier 1, the runtime re-checks the candidate's file path against the hard-exclusion list. This is belt-and-suspenders against future bugs in the diff classifier — if anything routes a Tier 1 edit at an excluded file, the runtime refuses and emits a loud error to the PR body.

## What "Tier 3 only" actually does

Tier 3 candidates appear in the PR body's "Drift detected — needs human judgment" section as a one-line summary plus the source evidence (quoted snippets). They do NOT include a proposed patch. The human reviewer decides what to do.

This is intentional: for files like `intent-clarification.md` and `SKILL.md` workflows, the right edit usually requires understanding several files at once. A unified diff suggestion would be misleading more often than helpful.
