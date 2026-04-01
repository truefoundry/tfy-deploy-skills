# Multi-Service Weather App

A complete weather application with three services deployed on TrueFoundry:

- **ui/** - React frontend for displaying weather data
- **api/** - FastAPI backend with weather endpoints
- **db/** - PostgreSQL database for storing weather data

## Architecture

```
[React UI] → [FastAPI Backend] → [PostgreSQL DB]
```

## Deploy All Services

```bash
# Deploy database first
cd db && tfy deploy --file truefoundry.yaml

# Deploy API (set DATABASE_URL to point to db service)
cd ../api && tfy deploy --file truefoundry.yaml

# Deploy UI (set VITE_API_URL to point to api service)
cd ../ui && tfy deploy --file truefoundry.yaml
```
