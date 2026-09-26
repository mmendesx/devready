#!/usr/bin/env python3
import asyncio
import os
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def check(command):
    env = dict(os.environ, LAYA_PRELOAD="0", HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1",
               PYTHONDONTWRITEBYTECODE="1")
    async with stdio_client(StdioServerParameters(command=command, env=env)) as streams:
        async with ClientSession(*streams) as session:
            await session.initialize()
            tools = await session.list_tools()
            if "laya_status" not in {tool.name for tool in tools.tools}:
                raise RuntimeError("Laya MCP did not expose laya_status")
            print("MCP handshake and Laya tool discovery passed.")


if __name__ == "__main__":
    try:
        asyncio.run(asyncio.wait_for(check(sys.argv[1]), timeout=30))
    except Exception as error:
        print(f"MCP check failed: {error}", file=sys.stderr)
        sys.exit(1)
