"""
list_tools.py — 列出 MCP 服务提供的所有工具

依赖：mcp（pip install mcp）

用法：
    python list_tools.py
    python list_tools.py --endpoint http://localhost:80/mcp
    python list_tools.py --endpoint https://mcp.example.com/mcp --token <bearer-token>
    python list_tools.py --endpoint https://mcp.example.com/mcp --token <bearer-token> --session-id <uuid>
    python list_tools.py --endpoint https://mcp.example.com/mcp --insecure  # 忽略 SSL 证书验证
"""

import argparse
import asyncio
import json
import os
import uuid

import httpx
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client

DEFAULT_ENDPOINT = os.environ.get("MCP_URL", "http://localhost:80/mcp")


def create_insecure_httpx_client(
    headers: dict[str, str] | None = None,
    timeout: httpx.Timeout | None = None,
    auth: httpx.Auth | None = None,
) -> httpx.AsyncClient:
    """Create an httpx client that skips SSL certificate verification."""
    return httpx.AsyncClient(headers=headers, timeout=timeout, auth=auth, verify=False)


def build_headers(token: str | None, session_id: str, host: str | None = None) -> dict[str, str]:
    headers: dict[str, str] = {"x-agentrun-session-id": session_id}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if host:
        headers["Host"] = host
    return headers


async def main(endpoint: str, token: str | None, session_id: str, insecure: bool, host: str | None):
    headers = build_headers(token, session_id, host)

    kwargs = {"headers": headers, "timeout": 60}
    if insecure:
        kwargs["httpx_client_factory"] = create_insecure_httpx_client
    
    async with streamablehttp_client(endpoint, **kwargs) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await session.list_tools()

    tools = [
        {
            "name": t.name,
            "description": t.description,
            "inputSchema": t.inputSchema,
        }
        for t in result.tools
    ]
    print(json.dumps(tools, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="List tools exposed by an MCP server")
    parser.add_argument("--endpoint", default=DEFAULT_ENDPOINT,
                        help=f"MCP server endpoint (default: {DEFAULT_ENDPOINT})")
    parser.add_argument("--token", default=None,
                        help="Bearer token for Authorization header")
    parser.add_argument("--session-id", default=None, dest="session_id",
                        help="x-agentrun-session-id value (default: auto-generated UUID)")
    parser.add_argument("--insecure", "-k", action="store_true",
                        help="Skip SSL certificate verification (for self-signed certs)")
    parser.add_argument("--host", default=None,
                        help="Override Host header (for proxy routing)")
    args = parser.parse_args()

    session_id = args.session_id or str(uuid.uuid4())
    asyncio.run(main(args.endpoint, args.token, session_id, args.insecure, args.host))
