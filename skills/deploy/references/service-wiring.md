# Environment Variable Translation & DNS Wiring

## Table of Contents

- [Translation Rule](#translation-rule)
- [Step-by-Step Wiring Algorithm](#step-by-step-wiring-algorithm)
- [Helm Chart DNS Naming Convention](#helm-chart-dns-naming-convention)
- [Application Service DNS](#application-service-dns)
- [Common Wiring Patterns](#common-wiring-patterns)
- [Public URL Pattern](#public-url-pattern)
- [Secrets for Credentials](#secrets-for-credentials)
- [Validation Checklist](#validation-checklist)

## Namespace Discovery

The namespace equals the workspace name from the workspace FQN:

```
Workspace FQN: tfy-ea-dev-eo-az:sai-ws
                └── cluster ──┘:└ namespace ┘
```

Extract: `NAMESPACE=$(echo "$TFY_WORKSPACE_FQN" | cut -d: -f2)`

Full DNS example: `myapp-db-postgresql.sai-ws.svc.cluster.local:5432`

## Translation Rule

In docker-compose, services reference each other by service name:
```yaml
DATABASE_URL=postgresql://postgres:DB_PASSWORD@db:5432/myapp
REDIS_URL=redis://redis:6379/0
BACKEND_URL=http://backend:8000
```

In TrueFoundry, replace the compose service name with the correct Kubernetes DNS name. The DNS name depends on whether the target is a **Helm chart** or an **application service**.

## Step-by-Step Wiring Algorithm

Follow this algorithm for EVERY environment variable that references another service:

1. **Identify the compose service name** in the env var value (e.g., `db` in `@db:5432`)
2. **Determine the target's deployment type:**
   - Is it a Helm chart (database, cache, queue)? -> Use Helm DNS pattern
   - Is it an application service? -> Use application DNS pattern
3. **Look up the TFY release/app name** you chose for that service (e.g., `myapp-db`)
4. **Construct the DNS name** using the correct pattern (see tables below)
5. **Replace** the compose service name with the full DNS name in the env var

## Helm Chart DNS Naming Convention

Helm charts create Kubernetes services with predictable names. The pattern depends on the chart type:

### CRITICAL: How Helm DNS Names Are Formed

The DNS name is: `{release-name}-{chart-suffix}.{namespace}.svc.cluster.local`

Where `{release-name}` is the `name` field in your TFY manifest, and `{chart-suffix}` is determined by the chart:

| Chart | Chart Suffix | Full DNS Pattern | Default Port |
|-------|-------------|------------------|-------------|
| PostgreSQL | `postgresql` | `{release-name}-postgresql.{ns}.svc.cluster.local` | 5432 |
| Redis | `redis-master` | `{release-name}-redis-master.{ns}.svc.cluster.local` | 6379 |
| MongoDB | `mongodb` | `{release-name}-mongodb.{ns}.svc.cluster.local` | 27017 |
| MySQL | `mysql` | `{release-name}-mysql.{ns}.svc.cluster.local` | 3306 |
| RabbitMQ | `rabbitmq` | `{release-name}-rabbitmq.{ns}.svc.cluster.local` | 5672 |
| Kafka | `kafka` | `{release-name}-kafka.{ns}.svc.cluster.local` | 9092 |
| Elasticsearch | `elasticsearch` | `{release-name}-elasticsearch.{ns}.svc.cluster.local` | 9200 |
| Qdrant | `qdrant` | `{release-name}-qdrant.{ns}.svc.cluster.local` | 6333 |

### Naming Example

If you deploy Redis with `name: myapp-redis` in the TFY manifest:
- Release name = `myapp-redis`
- Chart suffix for Redis = `redis-master`
- **DNS = `myapp-redis-redis-master.{ns}.svc.cluster.local:6379`**

If you deploy PostgreSQL with `name: myapp-db` in the TFY manifest:
- Release name = `myapp-db`
- Chart suffix for PostgreSQL = `postgresql`
- **DNS = `myapp-db-postgresql.{ns}.svc.cluster.local:5432`**

### IMPORTANT: Avoid Redundant Names

To keep DNS names clean, use short release names that do NOT repeat the chart type:

| Good Release Name | Resulting DNS | Clean? |
|-------------------|---------------|--------|
| `myapp-db` | `myapp-db-postgresql.ns.svc...` | Yes |
| `myapp-cache` | `myapp-cache-redis-master.ns.svc...` | Yes |
| `myapp-queue` | `myapp-queue-rabbitmq.ns.svc...` | Yes |

| Bad Release Name | Resulting DNS | Clean? |
|------------------|---------------|--------|
| `myapp-postgresql` | `myapp-postgresql-postgresql.ns.svc...` | No - redundant |
| `myapp-redis` | `myapp-redis-redis-master.ns.svc...` | Acceptable but verbose |

## Application Service DNS

For application services (non-Helm), the DNS is simply the app name:

```
{app-name}.{namespace}.svc.cluster.local:{port}
```

Example: If you deploy a backend service with `name: myapp-backend` on port 8000:
```
myapp-backend.{ns}.svc.cluster.local:8000
```

## Common Wiring Patterns

Given a project prefix `{app}`, compose service name on the left, TFY env var replacement on the right:

| Compose Reference | TFY Release Name | TFY DNS Replacement |
|-------------------|-------------------|---------------------|
| `@db:5432` | `{app}-db` | `@{app}-db-postgresql.{ns}.svc.cluster.local:5432` |
| `redis://redis:6379` | `{app}-cache` | `redis://{app}-cache-redis-master.{ns}.svc.cluster.local:6379` |
| `@mongo:27017` | `{app}-mongo` | `@{app}-mongo-mongodb.{ns}.svc.cluster.local:27017` |
| `amqp://rabbitmq:5672` | `{app}-queue` | `amqp://{app}-queue-rabbitmq.{ns}.svc.cluster.local:5672` |
| `http://backend:8000` | `{app}-backend` | `http://{app}-backend.{ns}.svc.cluster.local:8000` |
| `http://frontend:3000` | `{app}-frontend` | `https://{app}-frontend-{ws}.{base_domain}` (if public) or `http://{app}-frontend.{ns}.svc.cluster.local:3000` (if internal) |
| `http://worker:9000` | `{app}-worker` | `http://{app}-worker.{ns}.svc.cluster.local:9000` |

### With Authentication

When the compose file has credentials in connection strings, translate them too:

```yaml
# Compose
DATABASE_URL=postgresql://postgres:DB_PASSWORD@db:5432/myapp

# TFY (with same password set in Helm values.auth.postgresPassword)
DATABASE_URL=postgresql://postgres:DB_PASSWORD@myapp-db-postgresql.your-workspace.svc.cluster.local:5432/myapp
```

For production, store passwords in TrueFoundry secrets and reference them:
```yaml
DATABASE_URL: "tfy-secret://default:myapp-secrets:database-url"
```

## Public URL Pattern

1. Fetch cluster base domains: `$TFY_API_SH GET /api/svc/v1/clusters/CLUSTER_ID`
2. Pick wildcard domain (e.g., `*.ml.your-org.truefoundry.cloud`), strip `*.` to get base domain
3. Construct host: `{service-name}-{workspace-name}.{base_domain}`

Use public URLs for:
- Frontend services that users access in a browser
- APIs that need to be accessed from outside the cluster
- Webhook endpoints

Use internal DNS for:
- Backend-to-database connections
- Backend-to-cache connections
- Frontend-to-backend connections (when frontend is server-side rendered)
- Any inter-service communication within the cluster

## Frontend Environment Variables (CRITICAL)

Frontend frameworks (React/Vite, Next.js, Create React App) **inline env vars at BUILD TIME, not runtime**. Setting them in `truefoundry.yaml` `env:` has **NO EFFECT** on the compiled JavaScript.

### The Problem

```yaml
# truefoundry.yaml — THIS DOES NOT WORK for frontend env vars
env:
  VITE_API_URL: https://myapp-backend-ws.example.com  # ← Nginx sees this, but JS doesn't
```

The JS bundle was compiled during `npm run build` with whatever env vars were present at that moment. The `truefoundry.yaml` env vars are only available to the container process (e.g., Nginx), not the pre-compiled JS.

### The Fix: Dockerfile ARG/ENV

Set build-time env vars in the Dockerfile BEFORE the build step:

```dockerfile
FROM node:20 AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci

# Set build-time env vars HERE
ARG VITE_API_URL
ENV VITE_API_URL=$VITE_API_URL

COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
```

Then in the TFY manifest, pass the ARG via `build_args`:
```yaml
image:
  type: build
  build_spec:
    type: dockerfile
    build_args:
      VITE_API_URL: "https://myapp-backend-ws.example.com"
```

### Framework-Specific Prefixes

| Framework | Prefix | Access Pattern |
|-----------|--------|----------------|
| Vite | `VITE_*` | `import.meta.env.VITE_*` |
| Create React App | `REACT_APP_*` | `process.env.REACT_APP_*` |
| Next.js (client) | `NEXT_PUBLIC_*` | `process.env.NEXT_PUBLIC_*` |

### Warning: .env and .gitignore

If `.gitignore` excludes `.env` files (common), `tfy deploy` will NOT upload them. Use the Dockerfile ARG approach instead.

## Secrets for Credentials

For passwords shared between infrastructure and services:

1. **Generate strong passwords** -- `openssl rand -base64 24` for each
2. **Store in TrueFoundry secrets** (using `secrets` skill):
   ```bash
   $TFY_API_SH POST /api/svc/v1/secret-groups '{
     "name": "APP_NAME-secrets",
     "secrets": [
       {"key": "db-password", "value": "GENERATED_PASSWORD"},
       {"key": "redis-password", "value": "GENERATED_PASSWORD"}
     ]
   }'
   ```
3. **Reference in env vars**:
   ```python
   env = {
       "DB_PASSWORD": "tfy-secret://DOMAIN:APP_NAME-secrets:db-password",
   }
   ```

## Validation Checklist

After deploying all services, verify wiring is correct:

1. **Check each service's logs** for connection errors:
   - `Connection refused` -- target service not running or wrong port
   - `Name resolution failed` / `getaddrinfo failed` -- wrong DNS name
   - `Authentication failed` -- wrong password in env var vs Helm values
   - `Timeout` -- network policy blocking or service not ready

2. **Verify DNS resolution** -- Each service should be able to resolve its dependencies:
   - Check logs for successful connection messages
   - Look for "connected to database" or similar startup messages

3. **Test endpoints** -- `curl` public URLs to verify HTTP 200 responses

4. **Common mistakes to check:**
   - Namespace mismatch (wrong `{ns}` in DNS)
   - Password mismatch between Helm chart values and service env vars
   - Port mismatch (wrong port in DNS vs what service actually listens on)
   - Missing `-postgresql`, `-redis-master`, `-mongodb` suffix for Helm charts
