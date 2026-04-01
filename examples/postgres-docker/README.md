# Postgres Docker Example

Deploy a PostgreSQL 16 instance on TrueFoundry using the official Docker image.

## Configuration

Set these environment variables (use TrueFoundry secrets in production):

- `POSTGRES_DB` - Database name
- `POSTGRES_USER` - Username
- `POSTGRES_PASSWORD` - Password (use a TrueFoundry secret!)

## Deploy to TrueFoundry

```bash
tfy deploy --file truefoundry.yaml
```

## Notes

- The `init.sql` file can be mounted as a volume to `/docker-entrypoint-initdb.d/` for automatic initialization.
- In production, always use TrueFoundry secrets for `POSTGRES_PASSWORD`.
