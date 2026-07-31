import json


def handler(event, context):
    """Minimal MCP tool stub: echoes back whatever the agent sends it.
    Stands in for a tenant's real business-logic Lambda in this POC."""
    return {
        "status": "ok",
        "echo": event,
    }
