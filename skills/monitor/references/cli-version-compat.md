# `tfy` CLI Version Compatibility

The skills are tested against a pinned CLI version. Newer or older CLI versions may rename or reorganize subcommands. When in doubt, fall back to `tfy-api.sh` — the REST API is the platform's stable surface and is documented in [`api-endpoints.md`](api-endpoints.md).

## Pinned Version

| Skill set version | `tfy` CLI version |
|---|---|
| current (this repo) | **`truefoundry==0.5.0`** |

`prerequisites.md` installs this exact version via `pip install 'truefoundry==0.5.0'` / `uv tool install --python 3.12 'truefoundry==0.5.0'`. Do not silently bump it — if you suspect a CLI bug, fall back to the REST API rather than upgrading mid-session.

## Subcommand Surface (0.5.0)

| Group | Subcommand | Used by |
|---|---|---|
| `tfy apply -f manifest.yaml` | Declarative apply for services, jobs, helm, volumes, secret groups, agents, prompts, MCP servers, etc. | deploy, helm, llm-deploy, jobs, secrets, notebooks, ssh-server, volumes |
| `tfy deploy -f manifest.yaml` | Build + apply for `build_source.type: local` (or git when convenient). | deploy, llm-deploy |
| `tfy deploy workflow --name N --file F.py --workspace_fqn FQN` | Deploys a Flyte workflow. | workflows |
| `tfy apps` | List applications. (Also supported: `tfy applications` as an alias on some versions — prefer `apps`.) | applications, monitor |
| `tfy logs APP_FQN` | Stream logs. | logs |
| `tfy --version` | Print CLI version. | prerequisites |
| `tfy register` | Interactive new-account onboarding. | onboarding |

## Known CLI Subcommand Pitfalls

- **`tfy applications` may not exist on 0.5.0** — use `tfy apps` (or the REST API `/api/svc/v1/apps`). Sessions have failed with `No such command 'applications'`.
- **`tfy apply` does NOT accept stdin** — `tfy apply -f -` fails with `File '-' does not exist`. Always pass a real file path. If you want to apply a manifest constructed on the fly, write it to a tempfile first:
  ```bash
  TMP=$(mktemp --suffix .yaml)
  cat > "$TMP" <<'YAML'
  name: my-app
  type: service
  ...
  YAML
  tfy apply -f "$TMP"
  rm -f "$TMP"
  ```
- **`tfy apply` does NOT support `build_source.type: local`** — fails with `must match exactly one schema in oneOf`. Use `tfy deploy -f` for local builds. (See [`manifest-schema.md`](manifest-schema.md) → BuildSource.)
- **`TFY_HOST` must be set before any `tfy` CLI command.** The CLI reads `TFY_HOST`, not `TFY_BASE_URL`. Skills do `export TFY_HOST="${TFY_HOST:-${TFY_BASE_URL%/}}"` as a prerequisite.
- **Workflow `workspace_fqn` is a CLI flag**, not a manifest field. Pass `--workspace_fqn` to `tfy deploy workflow` (or `--workspace-fqn` to `tfy apply` for workflow manifests).
- **No `tfy delete` is supported by this plugin** — delete operations are blocked by `block-delete-operations.sh`. Redirect the user to the TrueFoundry dashboard.

## When the CLI Disagrees with the API

If a `tfy` command behaves unexpectedly (missing subcommand, schema validation error you can't explain, hangs), fall back to `tfy-api.sh` against the documented REST endpoints in [`api-endpoints.md`](api-endpoints.md) and report the CLI discrepancy to the user.

```bash
# Equivalent of `tfy apply -f manifest.yaml`:
bash "$TFY_API_SH" PUT /api/svc/v1/apps "$(cat manifest.yaml | yq -o json)"
```

(Requires `yq` for YAML→JSON. Most platforms ship it; install with `brew install yq` or `pip install yq`.)

## Detecting Drift

Each skill that shells out to `tfy` should first run `tfy --version` and abort with a clear message if the major.minor differs from the pinned version. Example pattern:

```bash
PINNED="0.5.0"
INSTALLED=$(tfy --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [[ -n "$INSTALLED" && "$INSTALLED" != "$PINNED" ]]; then
  echo "warn: tfy CLI is $INSTALLED, skills are tested with $PINNED. Falling back to REST API on subcommand errors."
fi
```

This belongs in `prerequisites.md`'s install step; do not silently install a newer version when the pin doesn't match.
