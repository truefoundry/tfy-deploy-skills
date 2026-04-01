# Redis Helm Example

Deploy Redis on TrueFoundry using the Bitnami Helm chart.

## Configurations

- `truefoundry.yaml` - Standalone Redis for development
- `values-production.yaml` - Replicated Redis for production

## Deploy to TrueFoundry

```bash
# Development (standalone)
tfy deploy --file truefoundry.yaml

# Production (with overrides)
tfy deploy --file truefoundry.yaml --values values-production.yaml
```

## Connecting

Once deployed, connect using:
```
redis-cli -h <service-host> -p 6379 -a <password>
```
