# TrueFoundry API Endpoints Reference

Base URL: `$TFY_BASE_URL` (e.g. `https://your-org.truefoundry.cloud`)
Auth: `Authorization: Bearer $TFY_API_KEY` (read from env; never hardcode or print token values in logs)

## Applications
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/svc/v1/apps` | List applications (query: workspaceFqn, applicationName, clusterId). Returns `{"data": [{"id", "name", "status" (string), "url", "activeDeployment", "manifest"}], "pagination": {...}}` |
| GET | `/api/svc/v1/apps/{appId}` | Get application by ID. Returns single app object (same shape as `data[]` element above) |
| GET | `/api/svc/v1/apps/{appId}/deployments` | List deployments for an app |
| GET | `/api/svc/v1/apps/{appId}/deployments/{deploymentId}` | Get deployment details |
| PUT | `/api/svc/v1/apps` | Create/update application deployment (body: manifest + options) |
| POST | `/api/svc/v1/apps/{appId}/sync` | Sync application state with cluster (refreshes status) |
| POST | `/api/svc/v1/apps/{appId}/deployments/{deploymentId}/promote` | Promote a deployment to active |
| POST | `/api/svc/v1/apps/{appId}/deployments/{deploymentId}/redeploy` | Redeploy using same configuration |

## Workspaces
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/svc/v1/workspaces` | List workspaces (query: clusterId, name, fqn) |
| GET | `/api/svc/v1/workspaces/{id}` | Get workspace by ID |
| GET | `/api/svc/v1/workspaces/{id}/supported-gpus` | List GPUs supported in this workspace |

## Clusters
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/svc/v1/clusters` | List clusters |
| GET | `/api/svc/v1/clusters/{id}` | Get cluster |
| GET | `/api/svc/v1/clusters/{id}/is-connected` | Get cluster connection status |
| GET | `/api/svc/v1/clusters/{id}/get-addons` | List cluster addons |

## Provider Accounts
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/svc/v1/provider-accounts` | List provider accounts (query: type=secret-store for secret integrations) |

## Secrets
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/svc/v1/secret-groups` | List secret groups |
| GET | `/api/svc/v1/secret-groups/{id}` | Get secret group |
| POST | `/api/svc/v1/secret-groups` | Create secret group |
| POST | `/api/svc/v1/secrets` | List secrets in a group (body: secretGroupId, limit, offset) |
| GET | `/api/svc/v1/secrets/{id}` | Get secret by ID |
| PUT | `/api/svc/v1/secret-groups/{id}` | Update secret group (body: secrets array with key/value pairs; omitted secrets are deleted) |
| DELETE | `/api/svc/v1/secret-groups/{id}` | Delete secret group |
| DELETE | `/api/svc/v1/secrets/{id}` | Delete a secret |
| GET | `/api/svc/v1/secrets/{id}/versions` | List version history for a secret |

## Jobs
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/svc/v1/jobs/trigger` | Trigger a job run (body: applicationId) |
| POST | `/api/svc/v1/jobs/terminate` | Terminate a running job |
| GET | `/api/svc/v1/jobs/{jobId}/runs` | List job runs (query: searchPrefix, sortBy) |
| GET | `/api/svc/v1/jobs/{jobId}/runs/{jobRunName}` | Get a specific job run |
| DELETE | `/api/svc/v1/jobs/{jobId}/runs/{jobRunName}` | Delete a job run |
| POST | `/api/svc/v1/jobs/{jobId}/command` | Send command to a job |

## Logs
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/svc/v1/logs` | Get logs (query: applicationId, startTs, endTs, searchString) |
| GET | `/api/svc/v1/logs/{workspaceId}/download` | Download logs |

## Prompts
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/ml/v1/prompts` | List prompts |
| GET | `/api/ml/v1/prompts/{id}` | Get prompt |
| GET | `/api/ml/v1/prompt-versions` | List prompt versions (query: prompt_id) |
| GET | `/api/ml/v1/prompt-versions/{id}` | Get prompt version |
| POST | `/api/ml/v1/prompts` | Create or update prompt (body: ChatPromptManifest) |
| DELETE | `/api/ml/v1/prompts/{id}` | Delete prompt |
| DELETE | `/api/ml/v1/prompt-versions/{id}` | Delete prompt version |

## Tracing
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/svc/v1/tracing-projects` | List tracing projects |
| PUT | `/api/svc/v1/tracing-projects` | Create or update tracing project (body: name) |
| GET | `/api/svc/v1/tracing-projects/{id}` | Get tracing project by ID |
| DELETE | `/api/svc/v1/tracing-projects/{id}` | Delete tracing project |
| GET | `/api/svc/v1/tracing-applications` | List tracing applications |
| POST | `/api/svc/v1/tracing-applications` | Create tracing application (body: name, tracingProjectId) |
| DELETE | `/api/svc/v1/tracing-applications/{id}` | Delete tracing application |

## ML Repos
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/ml/v1/ml-repos` | List ML repos |
| GET | `/api/ml/v1/ml-repos/{id}` | Get ML repo |

## Models
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/ml/v1/models` | List models (query: fqn, ml_repo_id, name) |

## Personal Access Tokens
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/svc/v1/personal-access-tokens` | List PATs |
| POST | `/api/svc/v1/personal-access-tokens` | Create PAT (body: name) |
| DELETE | `/api/svc/v1/personal-access-tokens/{id}` | Delete PAT |

## Model Catalogues
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/svc/v1/model-catalogues/deployment-specs` | Get recommended deployment specs for a HuggingFace model. Query: `huggingfaceHubUrl` (full HF URL), `workspaceId`, `huggingfaceHubTokenSecretFqn` (optional, for gated models), `pipelineTagOverride` (e.g. `text-generation`). Returns GPU, CPU, memory, storage requirements. |

## MCP Servers
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/svc/v1/mcp-servers` | List MCP servers (query: type, name) |
| GET | `/api/svc/v1/mcp-servers/{id}` | Get MCP server by ID |
| POST | `/api/svc/v1/mcp-servers` | Register a new MCP server (body: manifest) |
| DELETE | `/api/svc/v1/mcp-servers/{id}` | Delete an MCP server |

## Roles
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/svc/v1/role/list` | List all roles |
| GET | `/api/svc/v1/role` | Get roles (query: resourceType) |
| PUT | `/api/svc/v1/role` | Create or update a role (body: name, displayName, description, resourceType, permissions) |
| DELETE | `/api/svc/v1/role/{id}` | Delete a role |
| GET | `/api/svc/v1/role/actions` | Get available actions for a resource type (query: resourceType) |

## Teams
| Method | Path | Description |
|--------|------|-------------|
| PUT | `/api/svc/v1/teams` | Create or update a team (body: name, description) |
| GET | `/api/svc/v1/teams/{id}` | Get team by ID |
| DELETE | `/api/svc/v1/teams/{id}` | Delete a team |
| GET | `/api/svc/v1/teams/user` | List teams for the current user |
| GET | `/api/svc/v1/teams/{id}/permissions` | Get team permissions |

## Authorization (Collaborators)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/svc/v1/authorize/{resourceType}/{resourceId}` | List authorized users/collaborators on a resource |
| POST | `/api/svc/v1/authorize/{resourceType}/{resourceId}` | Add collaborator to a resource (body: subject, roleId) |
| PUT | `/api/svc/v1/authorize/{resourceType}/{resourceId}` | Update collaborator role on a resource |
| DELETE | `/api/svc/v1/authorize/{resourceType}/{resourceId}` | Remove collaborator from a resource (body: subject) |
| POST | `/api/svc/v1/authorize/check-access` | Check if a user has access to a resource |
| GET | `/api/svc/v1/authorize/permissions` | Get permissions for a resource |

## Role Bindings
| Method | Path | Description |
|--------|------|-------------|
| PUT | `/api/svc/v1/role-bindings` | Create or update a role binding |
| GET | `/api/svc/v1/role-bindings` | List all role bindings |
| GET | `/api/svc/v1/role-bindings/{id}` | Get role binding by ID |
| DELETE | `/api/svc/v1/role-bindings/{id}` | Delete role binding by ID |
| GET | `/api/svc/v1/role-bindings/exists` | Check if a role binding exists |
| POST | `/api/svc/v1/role-bindings/inline` | Create inline role bindings |

## Guardrails
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/svc/v1/provider-accounts?type=guardrail-config-group` | List guardrail config groups |
| POST | `/api/svc/v1/provider-accounts` | Create guardrail config group (body: manifest with type provider-account/guardrail-config-group) |

## Addons
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/svc/v1/addon/{addonId}` | Get addon details |
| POST | `/api/svc/v1/addon-upgrade/{applicationId}` | Upgrade an addon to latest version |
| GET | `/api/svc/v1/addon/list/components` | List available addon components |

## API Docs
- Full reference: `https://truefoundry.com/docs/api-reference`
- Generating API keys: `https://docs.truefoundry.com/docs/generating-truefoundry-api-keys`
