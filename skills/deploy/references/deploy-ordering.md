# Multi-Service Deployment Ordering

Detailed step-by-step orchestration for deploying multi-service projects in the correct dependency order with secrets wiring between tiers.

## Step-by-Step Orchestration

### 1. Build the dependency graph

Classify services and compute topological sort (see `dependency-graph.md`). Present the plan to the user and get confirmation before deploying anything.

### 2. Deploy Tier 0: Infrastructure

Deploy databases, caches, and queues first (as Helm charts). These have no dependencies.

```
Deploy: db, redis, rabbitmq (can be parallel)
Wait:   Poll until pods are actually ready (DEPLOY_SUCCESS alone is not enough for Helm charts)
```

> **CRITICAL:** After infra is deployed and healthy, **create a TFY secret group** containing all infrastructure credentials (DB passwords, Redis passwords, etc.) BEFORE deploying anything that depends on them.

```bash
# Example: create secrets for the DB and cache credentials
# Use the `secrets` skill to create a group like "myapp-infra-secrets"
# with keys: DB_PASSWORD, REDIS_PASSWORD, etc.
```

### 3. Deploy Tier 1: Backend services

Deploy backends/workers that depend on infrastructure. Their manifests MUST reference:
- Infrastructure via Kubernetes DNS (e.g., `myapp-db-postgresql.{ns}.svc.cluster.local:5432`)
- Credentials via `tfy-secret://` references to the secret group created in step 2

```yaml
# Backend manifest env example — DNS + secrets are pre-wired
env:
  DATABASE_URL: postgresql://postgres:tfy-secret://my-org:myapp-infra-secrets:DB_PASSWORD@myapp-db-postgresql.NAMESPACE.svc.cluster.local:5432/myapp
  REDIS_URL: redis://:tfy-secret://my-org:myapp-infra-secrets:REDIS_PASSWORD@myapp-cache-redis-master.NAMESPACE.svc.cluster.local:6379/0
```

```
Deploy: backend, worker (can be parallel if no inter-dependency)
Wait:   Monitor each to DEPLOY_SUCCESS
Verify: Check logs for connection errors (Connection refused, Auth failed)
```

### 4. Deploy Tier 2: Frontend / gateway

Deploy frontends last. Wire them to backend services using internal DNS or public URLs.

```yaml
# Frontend manifest env example — points to backend
env:
  API_URL: http://myapp-backend.NAMESPACE.svc.cluster.local:8000
  # OR public URL if frontend runs in-browser (SPA):
  VITE_API_URL: https://myapp-backend-ws.BASE_DOMAIN
```

> **SPA frontends (React, Vue, etc.) run in the browser, NOT in the cluster.** They CANNOT use internal DNS. They MUST use the backend's **public URL**. Server-rendered apps (Next.js SSR, Django templates) CAN use internal DNS.

```
Deploy: frontend
Wait:   Monitor to DEPLOY_SUCCESS
Verify: curl the frontend URL, check it can reach the backend
```

### 5. Final verification and summary

After all tiers are deployed:
- Check logs across all services for connection errors
- Hit the frontend URL to verify the full stack works
- Present the deployment summary with all URLs and wiring map

## Common Deployment Orders

| Project Type | Tier 0 (Infra) | Tier 1 (Backend) | Tier 2 (Frontend) |
|-------------|----------------|-------------------|--------------------|
| **Full-stack web app** | PostgreSQL | Backend API | React/Vue frontend |
| **Backend + DB** | PostgreSQL, Redis | Backend API, Worker | — |
| **RAG application** | Vector DB, PostgreSQL | RAG API, LLM service | Chat frontend |
| **Microservices** | PostgreSQL, Redis, RabbitMQ | Service A, Service B, Worker | API Gateway, Frontend |
| **AI Agent** | PostgreSQL | Agent API, Tool server, LLM | Agent UI |

## What NOT to Do

- **Do NOT deploy all services at once** — dependents will fail if their dependencies aren't ready
- **Do NOT put raw passwords in manifests** — always create TFY secrets first, then reference them
- **Do NOT skip DNS wiring** — a backend pointing to `localhost:5432` instead of the Helm DNS will fail
- **Do NOT deploy frontend before backend** — even if frontend deploys successfully, it won't work
- **Do NOT assume DEPLOY_SUCCESS means ready** — Helm chart pods (DB, Redis) may still be initializing
