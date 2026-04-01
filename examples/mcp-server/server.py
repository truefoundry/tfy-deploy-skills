import os
from mcp.server.fastmcp import FastMCP

mcp = FastMCP(os.environ.get("MCP_SERVER_NAME", "example-mcp-server"))


@mcp.tool()
def get_weather(city: str) -> str:
    """Get the current weather for a city."""
    # Stub implementation
    return f"Weather in {city}: 22°C, partly cloudy"


@mcp.tool()
def calculate(expression: str) -> str:
    """Evaluate a mathematical expression."""
    try:
        result = eval(expression, {"__builtins__": {}}, {})
        return str(result)
    except Exception as e:
        return f"Error: {e}"


if __name__ == "__main__":
    mcp.run(transport="streamable-http", host="0.0.0.0", port=8000)
