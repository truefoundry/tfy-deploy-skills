# No `kubectl` / `helm` / `argocd` — Use the Skills

> **HARD RULE: Never shell out to `kubectl`, `helm` (CLI), or `argocd`. Always use a TrueFoundry skill or the REST API via `tfy-api.sh`. There is no escape hatch — if no skill covers the intent, stop and ask the user.**

Why: raw cluster access bypasses TrueFoundry's audit log, RBAC, dashboard state, and the platform's safeguards (including the plugin's `block-delete-operations` hook). Sessions that drop to `kubectl` end up creating resources the platform doesn't know about, deleting resources the user shouldn't be deleting, and producing diagnoses based on raw pod state that don't match what the platform is showing the user.

This rule is enforced by the plugin via `plugin-scripts/block-kubectl.sh` (PreToolUse Bash hook). If a `kubectl`/`helm`/`argocd` invocation is blocked, do not work around it — use the mapping below.

## Intent → Skill / API mapping

| If you were about to run... | Do this instead |
|---|---|
| `kubectl get pod`, `get deploy`, `get sts`, `get rs` | `truefoundry-status` or `truefoundry-applications` (`GET /api/svc/v1/apps?workspaceFqn=...&applicationName=...`); read `data[0].deployment.currentStatus` |
| `kubectl get pod -l ...` (find pods for an app) | `truefoundry-applications` → response includes pods + replicas + ready count |
| `kubectl logs pod/...`, `logs -f`, `logs --previous` | `truefoundry-logs` (uses the platform's log API; respects RBAC) |
| `kubectl describe pod ...` (debug crash) | `truefoundry-logs` for recent logs + `truefoundry-status` for events; see `references/deploy-debugging.md` |
| `kubectl exec ... -- bash` (shell into a pod) | `truefoundry-ssh-server` skill — deploy a sidecar SSH server alongside the app. There is no skill-supported `exec` into a running service pod. |
| `kubectl exec deploy/db -- psql ...` (one-off SQL/cmd) | Run the SQL via a `truefoundry-jobs` one-shot job, or use `truefoundry-service-test` to call the service's HTTP endpoint, or shell in via `truefoundry-ssh-server` |
| `kubectl port-forward svc/...` | Expose the port in the manifest (`ports[].expose: true` with a `host`) and call the public URL — use `truefoundry-service-test` for the test call |
| `kubectl get svc`, `get ingress`, `get virtualservice` | `truefoundry-applications` — endpoint URL is on `data[0].deployment.currentStatus.endpoint` (and in manifest under `ports[].host`) |
| `kubectl get pvc`, `kubectl get volume` | `truefoundry-volumes` (`GET /api/svc/v1/apps?workspaceFqn=...&type=volume`) |
| `kubectl get events`, `events -w` | `truefoundry-status` + `truefoundry-logs` — platform surfaces the same events through its deployment timeline |
| `kubectl create secret ...`, `kubectl apply -f secret.yaml` | `truefoundry-secrets` — creates the secret group via the platform secret store integration |
| `kubectl delete pod/pvc/secret/...` | **Blocked.** Delete operations are forbidden. Redirect the user to the dashboard. See `block-delete-operations.sh`. |
| `kubectl apply -f deployment.yaml` | `truefoundry-deploy` (`tfy apply -f manifest.yaml` or `tfy deploy -f manifest.yaml` per the manifest schema) |
| `kubectl rollout status / restart / undo` | `truefoundry-monitor` for status, or trigger a redeploy via `truefoundry-deploy` |
| `kubectl scale deploy/...` | Edit `replicas` in the manifest and `tfy apply` again — autoscaling lives in the manifest, not in raw scale commands |
| `kubectl edit deploy/...` | Edit the manifest and `tfy apply` again — direct cluster edits drift from the platform's source of truth |
| `kubectl get applications.argoproj.io` (Argo CD apps for Helm releases) | `truefoundry-applications` with `type=helm` filter — the platform tracks Helm releases the same way |
| `helm install/upgrade/rollback/list/uninstall` | `truefoundry-helm` — chart releases are platform resources, not raw Helm releases |
| `helm get values <release>` | `truefoundry-applications` → response includes the rendered `values` block |
| `argocd app sync/diff/get` | `truefoundry-status` + `truefoundry-monitor` — Argo is an implementation detail; the platform exposes the same state |
| `kubectl auth can-i ...` | `truefoundry-access-control` skill or dashboard — platform RBAC is what governs access, not raw RBAC bindings |
| `kubectl get nodes / top nodes` (cluster capacity) | `truefoundry-workspaces` and cluster discovery (`GET /api/svc/v1/clusters/$CLUSTER_ID`) — `base_domains`, available GPU types, capacity types |

## What to do when no skill seems to fit

1. **Stop. Do not invent a workaround.** Do not try `tfy run kubectl`, raw `curl` to the kube-apiserver, or any other escape.
2. **Re-read the intent.** Most "I need kubectl" thoughts map to a skill above. Common confusions:
   - "I need to debug a pod" → `truefoundry-logs` + `truefoundry-status`, not exec
   - "I need to test the service" → `truefoundry-service-test`, not port-forward
   - "I need to run a one-off command" → `truefoundry-jobs` (one-shot job manifest)
3. **If nothing fits, ask the user.** Tell them which platform feature is missing and let them decide. Do not "just this once" reach for kubectl.

## How the rule is enforced

- **Documentation:** every `SKILL.md` references this file.
- **Hook:** `plugin-scripts/block-kubectl.sh` (PreToolUse on Bash) returns `decision: block` for any command that invokes `kubectl`, `helm `, or `argocd `. The block reason explains where to go instead.
- **Delete operations** are caught by both this hook and `block-delete-operations.sh` — even a non-kubectl delete is forbidden.

If the user explicitly insists on running kubectl, escalate the rule to them — do not bypass the hook. The user can always run kubectl themselves outside the agent.
