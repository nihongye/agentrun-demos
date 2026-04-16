"""
example_client.py — Code Execution MCP Server 使用示例（MCP Python SDK）

依赖：mcp（pip install mcp）

用法：
    python example_client.py
    python example_client.py --endpoint http://localhost:80/mcp
    python example_client.py --endpoint https://mcp.example.com/mcp --token <bearer-token>
    python example_client.py --endpoint https://mcp.example.com/mcp --token <bearer-token> --session-id <uuid>

启动服务：
    cd code-execution-mcp
    npm start
"""

import argparse
import asyncio
import os
import uuid
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client


DEFAULT_ENDPOINT = os.environ.get("MCP_URL", "http://localhost:80/mcp")


def build_headers(token: str | None, session_id: str) -> dict[str, str]:
    headers: dict[str, str] = {"x-agentrun-session-id": session_id}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


async def run_example(session: ClientSession, language: str, code: str, timeout: int = 60):
    print(f"\n{'=' * 50}")
    print(f"  Language: {language}")
    print(f"  Code:\n{code}")
    print("=" * 50)

    result = await session.call_tool(
        "execute_code",
        {"language": language, "code": code, "timeout": timeout},
    )

    text = result.content[0].text if result.content else ""
    status = "ERROR" if result.isError else "OK"
    print(f"[{status}]\n{text}")


async def main(endpoint: str, token: str | None, session_id: str):
    headers = build_headers(token, session_id)

    print(f"Endpoint:   {endpoint}")
    print(f"Session ID: {session_id}")

    async with streamablehttp_client(endpoint, headers=headers, timeout=60) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()

            tools = await session.list_tools()
            print(f"Available tools: {[t.name for t in tools.tools]}")

            await run_example(session, "python", """\
import sys
print("Hello from Python!")
print(f"Python version: {sys.version.split()[0]}")
""")

            await run_example(session, "javascript", """\
const nums = [1, 2, 3, 4, 5];
const sum = nums.reduce((a, b) => a + b, 0);
console.log(`Sum of ${JSON.stringify(nums)} = ${sum}`);
""")

            await run_example(session, "typescript", """\
interface Point { x: number; y: number; }
const distance = (a: Point, b: Point): number =>
    Math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2);

const p1: Point = { x: 0, y: 0 };
const p2: Point = { x: 3, y: 4 };
console.log(`Distance: ${distance(p1, p2)}`);
""")

            await run_example(session, "shell", """\
echo "OS: $(uname -s)"
echo "Current dir: $(pwd)"
""")

            await run_example(session, "java", """\
public class Main {
    public static void main(String[] args) {
        int[] arr = {5, 3, 8, 1, 9, 2};
        int max = arr[0];
        for (int n : arr) if (n > max) max = n;
        System.out.println("Array max: " + max);
        System.out.printf("Java version: %s%n", System.getProperty("java.version"));
    }
}
""")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Code Execution MCP Server example client")
    parser.add_argument(
        "--endpoint",
        default=DEFAULT_ENDPOINT,
        help=f"MCP server endpoint (default: {DEFAULT_ENDPOINT})",
    )
    parser.add_argument(
        "--token",
        default=None,
        help="Bearer token for Authorization header",
    )
    parser.add_argument(
        "--session-id",
        default=None,
        dest="session_id",
        help="x-agentrun-session-id value (default: auto-generated UUID)",
    )
    args = parser.parse_args()

    session_id = args.session_id or str(uuid.uuid4())
    asyncio.run(main(args.endpoint, args.token, session_id))
