# Python 集成 Agent

本文档演示如何通过 Python 以多种协议访问兼容 AgentScope Runtime 的 Agent。

**安装基础依赖：**
```bash
pip install requests
```

**公共变量说明（以下所有示例均使用这些变量）：**

```python
import uuid

# ⚠️  请替换为实际的 Agent Endpoint 地址
ENDPOINT = "https://{{endpoint}}"

# ⚠️  如 Agent 绑定了访问凭证，请替换为实际 Token；未绑定则设为 None
TOKEN = "YOUR_TOKEN_HERE"

# 会话 ID：同一会话期间保持一致，用于会话亲和与流量隔离
SESSION_ID = str(uuid.uuid4())
```

---

## openai 访问

通过 OpenAI Responses API 兼容接口（`/compatible-mode/v1/responses`）访问 Agent。

**安装依赖：**
```bash
pip install openai
```

```python
import uuid
from openai import OpenAI

ENDPOINT = "https://{{endpoint}}"
TOKEN = "YOUR_TOKEN_HERE"   # ⚠️ 替换为实际 Token，无凭证时改为 "dummy"
SESSION_ID = str(uuid.uuid4())

client = OpenAI(
    base_url=f"{ENDPOINT}/compatible-mode/v1",
    api_key=TOKEN,
    default_headers={
        "x-agentrun-session-id": SESSION_ID,
    },
)

# extra_body 可传入额外上下文参数（如用户信息、城市等）
with client.responses.stream(
    model="friday",
    input="你好，请介绍一下你自己",
    extra_body={
        "conversation": SESSION_ID,
        "user": "xiaoming",
        "language": "zh",
        "city": "shenzhen",
    },
) as stream:
    for event in stream:
        if getattr(event, "type", None) == "response.output_text.delta":
            delta = getattr(event, "delta", "")
            if delta:
                print(delta, end="", flush=True)

print()
```

---

## a2a 访问

通过 A2A JSON-RPC 协议（`/a2a`）访问 Agent。

**安装依赖：**
```bash
pip install a2a-sdk httpx
```

```python
import asyncio
import uuid
import httpx
from a2a.client import ClientFactory, ClientConfig
from a2a.client.card_resolver import A2ACardResolver
from a2a.client.helpers import create_text_message_object
from a2a.types import TaskStatusUpdateEvent, Message as A2AMessage, TextPart

ENDPOINT = "https://{{endpoint}}"
TOKEN = "YOUR_TOKEN_HERE"   # ⚠️ 替换为实际 Token，无凭证时删除 Authorization header
SESSION_ID = str(uuid.uuid4())


async def main():
    headers = {"x-agentrun-session-id": SESSION_ID}
    if TOKEN:
        headers["Authorization"] = f"Bearer {TOKEN}"

    async with httpx.AsyncClient(
        headers=headers,
        timeout=httpx.Timeout(connect=10.0, read=600.0, write=300.0, pool=50.0),
    ) as http_client:
        # 获取 Agent Card
        resolver = A2ACardResolver(http_client, ENDPOINT)
        card = await resolver.get_agent_card()
        print(f"Agent: {card.name}")

        client = ClientFactory(ClientConfig(httpx_client=http_client)).create(card)

        # 构建消息，context_id 用于关联会话
        msg = create_text_message_object(content="你好，请介绍一下你自己")
        msg.context_id = SESSION_ID

        async for event in client.send_message(msg):
            if isinstance(event, A2AMessage):
                for part in event.parts:
                    root = part.root
                    if isinstance(root, TextPart) and root.text:
                        print(root.text, end="", flush=True)
            elif isinstance(event, tuple):
                _, update = event
                if (
                    isinstance(update, TaskStatusUpdateEvent)
                    and update.status.message
                ):
                    for part in update.status.message.parts:
                        root = part.root
                        if isinstance(root, TextPart) and root.text:
                            print(root.text, end="", flush=True)

    print()


asyncio.run(main())
```

---

## agui 访问

通过 AG-UI SSE 协议（`/ag-ui`）访问 Agent。

**安装依赖：**
```bash
pip install requests
```

```python
import json
import uuid
import requests

ENDPOINT = "https://{{endpoint}}"
TOKEN = "YOUR_TOKEN_HERE"   # ⚠️ 替换为实际 Token，无凭证时删除 Authorization header
SESSION_ID = str(uuid.uuid4())

headers = {
    "Content-Type": "application/json",
    "x-agentrun-session-id": SESSION_ID,
}
if TOKEN:
    headers["Authorization"] = f"Bearer {TOKEN}"

payload = {
    "threadId": SESSION_ID,
    "runId": str(uuid.uuid4()),
    "messages": [
        {
            "id": str(uuid.uuid4()),
            "role": "user",
            "content": "你好，请介绍一下你自己",
        }
    ],
    "tools": [],
    "context": [],
}

response = requests.post(
    f"{ENDPOINT}/ag-ui",
    json=payload,
    headers=headers,
    stream=True,
    timeout=120,
)
response.raise_for_status()

for line in response.iter_lines():
    if not line:
        continue
    decoded = line.decode("utf-8")
    if not decoded.startswith("data:"):
        continue
    data = json.loads(decoded[5:].strip())
    if data.get("type") == "TEXT_MESSAGE_CONTENT":
        delta = data.get("delta", "")
        if delta:
            print(delta, end="", flush=True)

print()
```

---

## agentscope agent api 访问

通过 AgentScope 原生 Agent API 协议访问 Agent。

> **注意**：agentscope-runtime 框架默认端点为 `/process`，0码 Agent 端点为 `/`。

**安装依赖：**
```bash
pip install requests
```

```python
import json
import uuid
import requests

ENDPOINT = "https://{{endpoint}}"
TOKEN = "YOUR_TOKEN_HERE"   # ⚠️ 替换为实际 Token，无凭证时删除 Authorization header
SESSION_ID = str(uuid.uuid4())

# agentscope-runtime 框架默认端点为 /process，0码 Agent 端点为 /
AGENT_PATH = "/process"  # 0码 Agent 改为 "/"

headers = {
    "Content-Type": "application/json",
    "Accept": "text/event-stream",
    "x-agentrun-session-id": SESSION_ID,
}
if TOKEN:
    headers["Authorization"] = f"Bearer {TOKEN}"

payload = {
    "input": [
        {
            "role": "user",
            "content": [{"type": "text", "text": "你好，请介绍一下你自己"}],
            "type": "message",
        }
    ],
    "stream": True,
    "session_id": SESSION_ID,
    "user_id": SESSION_ID,
    # 可附加额外上下文参数
    "user": "xiaoming",
    "language": "zh",
    "city": "shenzhen",
}

response = requests.post(
    f"{ENDPOINT}{AGENT_PATH}",
    json=payload,
    headers=headers,
    stream=True,
    timeout=120,
)
response.raise_for_status()

# 已通过 delta 打印的消息 ID，用于去重
printed_delta_ids = set()

for line in response.iter_lines():
    if not line:
        continue
    decoded = line.decode("utf-8")
    if not decoded.startswith("data:"):
        continue
    data = json.loads(decoded[5:].strip())

    if data.get("object") == "content" and data.get("type") == "text":
        text = data.get("text", "")
        msg_id = data.get("msg_id")
        is_delta = data.get("delta") is True

        if is_delta and text:
            printed_delta_ids.add(msg_id)
            print(text, end="", flush=True)
        elif not is_delta and data.get("status") == "completed" and text:
            if msg_id not in printed_delta_ids:
                print(text, end="", flush=True)

print()
```
