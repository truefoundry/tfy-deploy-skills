# MCP Server Example

A simple Model Context Protocol (MCP) server deployed on TrueFoundry.

## Tools

- `get_weather` - Get weather for a city (stub)
- `calculate` - Evaluate math expressions

## Local Development

```bash
pip install -r requirements.txt
python server.py
```

## Deploy to TrueFoundry

```bash
tfy deploy --file truefoundry.yaml
```
