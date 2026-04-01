# Deploy Error Handling

Common deployment errors and how to resolve them.

## CLI Errors

### tfy: command not found

```
The TrueFoundry CLI is not installed.
Install it with: pip install 'truefoundry==0.5.0'
Then verify: tfy --version
```

### tfy apply validation errors

```
YAML manifest validation failed. Check:
- Required fields are present: name, type, image, resources, workspace_fqn
- YAML syntax is valid (proper indentation, no tabs)
- Field names match the schema (see references/manifest-schema.md)
- workspace_fqn format is correct: "cluster-id:workspace-name"
```

### tfy apply --dry-run shows unexpected diff

```
The diff shows changes you didn't expect. This usually means:
- An existing deployment has different values than your manifest
- Default values are being applied that differ from the current state
Review the diff carefully before applying.
```

## TFY_HOST Not Set (CLI auth failure)

```
tfy apply/deploy fails with authentication or "host not found" errors even though
TFY_BASE_URL and TFY_API_KEY are set.

Cause: The tfy CLI expects TFY_HOST (not TFY_BASE_URL) when using API key auth.

Fix: Always set TFY_HOST before running any tfy CLI command:
  export TFY_HOST="${TFY_HOST:-${TFY_BASE_URL%/}}"

This is the #1 env-var mistake. The .env may have TFY_BASE_URL but the CLI
reads TFY_HOST. The tfy-api.sh script auto-resolves aliases, but the CLI does not.
```

## Invalid `build_spec.type` Value

```
tfy apply/deploy fails with a validation error when build_spec.type is set to
an invalid value like "docker", "build", or "python".

Valid values:
  - "dockerfile"           — for Dockerfile-based builds
  - "tfy-python-buildpack" — for Python projects without a Dockerfile

Common mistake: using "docker" instead of "dockerfile".

Fix: Check manifest-schema.md → BuildSpec section for the exact type strings.
```

## TFY_WORKSPACE_FQN Not Set

```
TFY_WORKSPACE_FQN is required. Get it from:
- TrueFoundry dashboard -> Workspaces
- Or run: tfy_workspaces_list (if tool server is available)
Do not auto-pick a workspace.
```

## Host Not Configured in Cluster

```
"Provided host is not configured in cluster"
The host you specified doesn't match any base_domains on the cluster.
Fix: Look up cluster base domains:
  GET /api/svc/v1/clusters/CLUSTER_ID -> base_domains
Use the wildcard domain (e.g., *.ml.your-org.truefoundry.cloud)
and construct: {service}-{workspace}.{base_domain}
```

## Git Build Failed

```
The remote build from Git failed. Check:
- Git repo URL is accessible (public or credentials configured in TrueFoundry)
- Branch/ref exists
- Dockerfile path is correct relative to build context
- Check build logs in TrueFoundry dashboard
```

## Build Failed

```
Build failed on TrueFoundry. Check the dashboard for build logs.
Common issues:
- Missing dependencies in Dockerfile
- Wrong port configuration
- Dockerfile CMD not matching the app's start command
```

## No Dockerfile

```
No Dockerfile found. Options:
1. Create a Dockerfile for your app
2. Use TrueFoundry Python Buildpack in the manifest (no Dockerfile needed):
   image:
     type: build
     build_source:
       type: git
       repo_url: https://github.com/user/repo
       branch_name: main
     build_spec:
       type: tfy-python-buildpack
       command: uvicorn main:app --host 0.0.0.0 --port 8000
       python_version: "3.12"
       python_dependencies:
         type: pip
         requirements_path: requirements.txt
```

## `tfy apply` Fails with "must match exactly one schema in oneOf"

```
This error occurs when using `tfy apply` with a build_source (git or local).
`tfy apply` only supports pre-built images (image.type: image).

Fix: Use `tfy deploy -f truefoundry.yaml --no-wait` for source-based deployments.
This is the most common deploy skill mistake — always check the image type before
choosing the command.
```

## `tfy apply` Fails with Missing `ref` Field

```
If git build_source is rejected for missing a `ref` field, this is another reason
to prefer `tfy deploy -f` for source-based deployments. `tfy deploy` handles
git refs automatically. If you must use `tfy apply`, add a `ref` field to
build_source with the commit SHA or tag.
```

## Cluster API Returns 403 Forbidden

```
The user's API key does not have permission to access the cluster API.
Fallback steps:
1. Check .env for TFY_CLUSTER_FQN
2. List existing apps in the workspace and extract domain from ports[].host
3. Ask the user for the base domain directly
4. For internal-only services, skip domain discovery (set expose: false)
See references/cluster-discovery.md for details.
```

## Replicas Format Rejected

```
If `replicas: { min: N, max: M }` is rejected, try block-style YAML:

replicas:
  min: 2
  max: 5

Or fall back to a fixed integer:

replicas: 2

Some tfy CLI versions may not accept inline object notation for replicas.
```

## "Host must be provided to expose port"

```
HTTP 400 when deploying a service with expose: true but no host field on the port.

Cause: The TrueFoundry API requires a hostname when a port is externally exposed.

Fix:
1. Run cluster discovery to get the base domain:
   GET /api/svc/v1/clusters/CLUSTER_ID → data.manifest.base_domains[]
2. Pick the wildcard entry (e.g., *.ml.example.truefoundry.cloud), strip "*."
3. Set host in the port config:
   host: {service-name}-{workspace-name}.{base_domain}

Prevention: Always run cluster discovery BEFORE generating manifests when
expose: true is needed. See the deploy skill's pre-flight validation.
```

## "must have required property 'ephemeral_storage_request'"

```
Validation error when ephemeral_storage_request or ephemeral_storage_limit
is missing from the resources section.

Cause: Both fields are REQUIRED for all service, job, and async-service types.

Fix: Add both fields to resources. Safe defaults:
  ephemeral_storage_request: 1000
  ephemeral_storage_limit: 2000

Note: These are always required — the API will reject any deployment without them.
```

## "Helm: must have required property 'source'"

```
Validation error when using a top-level `chart` key instead of `source` in a Helm manifest.

WRONG:
  chart:
    repo: https://charts.bitnami.com/bitnami
    name: redis
    version: "19.6.0"

CORRECT:
  source:
    type: helm-repo
    repo_url: https://charts.bitnami.com/bitnami
    chart: redis
    version: "19.6.0"

Also valid (OCI):
  source:
    type: oci-repo
    oci_chart_url: oci://registry-1.docker.io/bitnamicharts/redis
    version: "19.6.0"
```

## Build Fails with Empty/Tiny Archive (< 1 KB)

```
tfy deploy uploads source code but the build fails immediately. The archive
is only 55 bytes or similar tiny size.

Cause: Source files are excluded by .gitignore. tfy deploy respects .gitignore
when archiving source code.

Diagnosis:
1. Check tfy deploy output for "Code archive size" — if < 1 KB, files are excluded
2. Run: git check-ignore -v Dockerfile requirements.txt main.py
3. Check if a PARENT directory is gitignored (e.g., examples/ in root .gitignore)

Fix:
- Remove the directory from .gitignore
- Or move source code outside the gitignored directory
- Or switch to git-based build_source with a repo URL

CRITICAL: Git rule — once a parent directory is excluded in .gitignore,
child .gitignore files CANNOT re-include files under it.
```

## Probe Validation Error: "config must have property 'path'"

```
Health probe validation fails when using command/exec probe type.

Cause: Some API versions only accept HTTP probes through the service manifest
path. Command probes may be rejected even though the schema documents them.

Fix:
- For HTTP services: use HTTP probe (type: http) with path and port
- For non-HTTP services (databases, caches): use TCP probe (type: tcp) with port
- Fallback: omit probes entirely (container runs with default liveness)

Example TCP probe for a database:
  readiness_probe:
    config:
      type: tcp
      port: 5432
    initial_delay_seconds: 5
    period_seconds: 10
```

## REST API Fallback Errors

### 401 Unauthorized

```
TFY_API_KEY is invalid or expired.
Check: echo $TFY_API_KEY (should be set)
Regenerate from TrueFoundry dashboard -> Settings -> API Keys
```

### 404 Workspace Not Found

```
The workspace FQN does not exist.
List available workspaces: GET /api/svc/v1/workspaces
```
