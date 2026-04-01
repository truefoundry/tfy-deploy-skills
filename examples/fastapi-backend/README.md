# FastAPI Backend Example

A simple REST API deployed on TrueFoundry.

## Endpoints

- `GET /health` - Health check
- `GET /items` - List all items
- `POST /items` - Create an item
- `GET /items/{name}` - Get an item
- `DELETE /items/{name}` - Delete an item

## Local Development

```bash
pip install -r requirements.txt
uvicorn main:app --reload
```

## Deploy to TrueFoundry

```bash
tfy deploy --file truefoundry.yaml
```
