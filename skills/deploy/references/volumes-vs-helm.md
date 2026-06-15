# Volumes vs Helm-Managed PVCs

When deploying stateful infrastructure (Postgres, Redis, Kafka, MinIO), there are two paths to persistent storage on TrueFoundry. Picking the wrong one creates orphan PVCs the platform can't see, breaks the delete flow, and disconnects the user from secrets / dashboard state.

This file is the routing rule. Read it before deploying any stateful Helm chart.

## TL;DR

| Scenario | Path |
|---|---|
| Single-pod database, you control the manifest (Postgres `service` + volume) | TrueFoundry volume (`type: volume`) + `truefoundry-deploy` |
| Multi-pod replicated database (HA Postgres operator, Kafka cluster) | Helm chart **with values that point at a pre-created TrueFoundry volume**, not the chart's auto-PVC |
| You want to "just deploy postgres" and don't care about ops | Helm chart with `persistence.existingClaim` set to a TrueFoundry volume |
| Quick experiment, you'll throw it away in a day | Helm chart with default PVC — but document the orphan and clean it up |

The rule of thumb: **the TrueFoundry volume should own the PVC lifecycle.** Helm charts that auto-create their own PVCs leak them on uninstall — those PVCs become orphans the platform doesn't manage and the dashboard doesn't show.

## Decision table

| Concern | Helm chart auto-PVC | TFY volume + chart `existingClaim` |
|---|---|---|
| Visibility in TFY dashboard | No — it's a raw K8s PVC | Yes — listed under Volumes |
| Cleanup on uninstall | PVC orphaned; needs cluster-admin to remove | Volume remains under user control; explicit delete via dashboard |
| Secret integration | Chart usually generates its own; bypasses `tfy-secret://` | Service/Helm values reference TFY secrets normally |
| Resizing | Edit PVC directly (no platform API) | `tfy apply` with larger `size` |
| Backup/restore via TFY | Not supported | Supported (snapshot via cloud provider, restore via volume FQN) |
| HA + replication out of the box | Often yes (Bitnami, CloudNativePG, etc.) | Up to you to wire |

## Recommended patterns

### Pattern A — single-pod stateful service (e.g., dev Postgres)

Use `truefoundry-deploy` with a `service` manifest and mount a TFY volume:

```yaml
# 1. Create the volume
name: devrel-postgres-data
type: volume
size: "20Gi"
access_mode: ReadWriteOnce
storage_class: gp3        # or whatever the cluster supports — discover via cluster API
workspace_fqn: cluster-id:workspace-name
```

```yaml
# 2. Deploy postgres as a service, mounting the volume
name: devrel-postgres
type: service
image:
  type: image
  image_uri: postgres:16
ports:
  - port: 5432
    protocol: TCP
    expose: false
    app_protocol: tcp
env:
  POSTGRES_PASSWORD: tfy-secret://my-org:postgres-secrets:POSTGRES_PASSWORD
  PGDATA: /var/lib/postgresql/data/pgdata
resources:
  cpu_request: 0.5
  cpu_limit: 2
  memory_request: 1024
  memory_limit: 4096
  ephemeral_storage_request: 1000
  ephemeral_storage_limit: 2000
mounts:
  - type: volume
    name: devrel-postgres-data
    mount_path: /var/lib/postgresql/data
    read_only: false
workspace_fqn: cluster-id:workspace-name
```

This keeps secrets in TFY, the volume in the TFY dashboard, and the delete path through the dashboard.

### Pattern B — Helm chart that needs a PVC (use `existingClaim`)

Most stateful charts (Bitnami Postgres, Redis, etc.) accept `persistence.existingClaim` (the exact key varies by chart). Create the TFY volume first, then point the chart at it:

```yaml
name: my-redis
type: helm
source:
  type: oci-repo
  oci_chart_url: oci://REGISTRY/redis     # search Artifact Hub for the actual chart
  version: "20.x.x"
values:
  master:
    persistence:
      existingClaim: my-redis-data        # name of the pre-created TFY volume
  auth:
    existingSecret: redis-tfy-secrets     # TFY-managed secret group
workspace_fqn: cluster-id:workspace-name
```

If the chart **doesn't** support `existingClaim` (some don't), you have two options:
1. Pick a different chart that does.
2. Accept the orphan-PVC risk, deploy as-is, and document the cleanup procedure in the user's runbook. Do **not** silently leave the orphan unmentioned.

### Pattern C — what NOT to do

Do not deploy a Helm chart that auto-creates a PVC and then later try to "migrate" data into a TFY volume by `kubectl cp`-ing between PVCs. Past sessions have done this; it works but leaves orphans, breaks RBAC, and the user can't see the original PVC in the dashboard. Plan the storage shape before the first deploy.

## Orphaned PVC recovery

If a previous Helm chart left an orphan (visible from the cluster but not in the TFY dashboard), the cleanup path is:

1. **Confirm the orphan via the platform first.** `bash "$TFY_API_SH" GET "/api/svc/v1/apps?workspaceFqn=$TFY_WORKSPACE_FQN&applicationType=volume"` — if it's not listed, the platform doesn't own it.
2. **Tell the user.** Explain that the PVC was created by a previous Helm chart's StatefulSet template, not by the TFY volumes skill, so it doesn't appear in the dashboard.
3. **Redirect to the platform admin.** Cleanup requires cluster-admin access, which the agent does not have and the no-kubectl rule does not bypass. The admin can remove the orphan in one of two ways:
   - From the TrueFoundry dashboard's cluster view (if the platform exposes orphan PVCs there in your tenant).
   - Direct cloud console (AWS / Azure / GCP) — delete the underlying disk/EFS/Filestore resource. The K8s PVC will then garbage-collect.

Do **not** suggest `kubectl delete pvc` even as a "just for cleanup" exception — it's blocked by the plugin hook and bypasses platform audit.

## When in doubt, ask

If the user wants stateful infra and you can't tell whether they want operator-managed HA or a single-pod simple thing, ask once:

> Two paths for persistent state:
> 1. **Simple single-pod** — TrueFoundry volume + plain service. Easy, no HA. Recommend for dev/staging.
> 2. **Operator-managed HA** — a chart that runs a replicated cluster. More moving parts, but production-grade. Recommend for prod.
>
> Which fits your use case?

Then route per the patterns above.
