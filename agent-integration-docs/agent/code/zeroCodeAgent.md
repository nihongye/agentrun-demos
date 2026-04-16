# 0码 Agent 集成指南

本文档介绍如何通过外层 Web 服务集成使用 0码 Agent（Zero Code Agent）。

---

## 概述

0码 Agent 是平台提供的开箱即用的智能助手，具备代码执行、文件操作、浏览器控制等能力。集成 0码 Agent 时，外层 Web 服务主要需实现以下几点：

1. **用户认证与会话管理** — 管理用户身份、会话生命周期
2. **代理调用 0码 Agent 对话服务** — 转发用户请求到 0码 Agent，处理流式响应
3. **长期会话支持（可选）** — 如需跨越 Pod 生命周期的会话持久化，需绑定持久化存储

---

## 架构说明

```
┌──────────────┐      ┌──────────────────┐      ┌────────-──────────┐
│    用户端     │─────▶│   外层 Web 服务   │─────▶│    0码 Agent      │
│  (Browser)   │◀─────│ (认证/会话管理)    │◀─────│   (对话服务)       │
└──────────────┘      └──────────────────┘      └────────┬─────────┘
                                                         │
                                                         ▼
                                                ┌──────────────────┐
                                                │   持久化存储       │
                                                │   (OSS 等)       │
                                                └──────────────────┘
```

---

## 1. 用户认证与会话管理

外层 Web 服务需要实现用户认证逻辑，并为每个用户会话生成唯一标识。

### 会话标识说明

| 标识 | 说明 |
|------|------|
| `user_id` | 用户唯一标识，用于区分不同用户 |
| `session_id` | 会话唯一标识，同一会话期间保持一致 |
| `x-agentrun-session-id` | HTTP Header，用于会话亲和与流量隔离 |

### 示例：会话管理

```python
import uuid
from datetime import datetime, timedelta

class SessionManager:
    def __init__(self):
        self.sessions = {}  # 生产环境建议使用 Redis
    
    def create_session(self, user_id: str) -> str:
        """创建新会话"""
        session_id = str(uuid.uuid4())
        self.sessions[session_id] = {
            "user_id": user_id,
            "created_at": datetime.now(),
            "expires_at": datetime.now() + timedelta(hours=24),
        }
        return session_id
    
    def validate_session(self, session_id: str) -> dict | None:
        """验证会话有效性"""
        session = self.sessions.get(session_id)
        if session and session["expires_at"] > datetime.now():
            return session
        return None
```

---

## 2. 代理调用 0码 Agent 对话服务

外层 Web 服务作为代理，将用户请求转发到 0码 Agent，并处理流式响应返回给用户。

> **说明**：本文档示例使用 AgentScope Agent API 协议访问 0码 Agent。0码 Agent 同时支持 OpenAI Responses API、A2A、AG-UI 等多种协议，详见 'Python 集成 Agent'。

### 0码 Agent API 端点

> **注意**：0码 Agent 的 AgentScope Agent API 端点为 `/`，与 agentscope-runtime 框架默认的 `/process` 不同。

| 端点 | 协议 | 说明 |
|------|------|------|
| `POST /` | AgentScope Agent API | 对话服务（本文档示例使用） |
| `POST /compatible-mode/v1/responses` | OpenAI Responses API | OpenAI 兼容接口 |
| `POST /a2a` | A2A | Agent-to-Agent 协议 |
| `POST /ag-ui` | AG-UI | AG-UI SSE 协议 |
| `GET /sessions/{user_id}/{session_id}` | - | 获取会话数据（对话历史） |
| `GET /sandbox/{user_id}/{session_id}/desktop-url` | - | 获取沙箱桌面 URL |
| `GET /download?token={token}&path={path}` | - | 下载沙箱文件 |

### 示例：代理转发对话请求（AgentScope Agent API）

```python
import json
import httpx
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse

app = FastAPI()

ZERO_CODE_AGENT_URL = "https://your-zero-code-agent.example.com"
ZERO_CODE_AGENT_TOKEN = "your-token"  # 如有访问凭证


async def proxy_to_agent(user_id: str, session_id: str, user_input: str):
    """代理转发请求到 0码 Agent"""
    headers = {
        "Content-Type": "application/json",
        "Accept": "text/event-stream",
        "x-agentrun-session-id": session_id,
    }
    if ZERO_CODE_AGENT_TOKEN:
        headers["Authorization"] = f"Bearer {ZERO_CODE_AGENT_TOKEN}"

    payload = {
        "input": [
            {
                "role": "user",
                "content": [{"type": "text", "text": user_input}],
                "type": "message",
            }
        ],
        "stream": True,
        "session_id": session_id,
        "user_id": user_id,
    }

    async with httpx.AsyncClient(timeout=300) as client:
        async with client.stream(
            "POST",
            f"{ZERO_CODE_AGENT_URL}/",  # 0码 Agent 端点为 /
            json=payload,
            headers=headers,
        ) as response:
            async for line in response.aiter_lines():
                if line.startswith("data:"):
                    yield line + "\n\n"


@app.post("/api/chat")
async def chat(request: Request):
    """对话接口 - 代理转发到 0码 Agent"""
    body = await request.json()
    user_id = body.get("user_id")
    session_id = body.get("session_id")
    user_input = body.get("message")

    # TODO: 验证用户认证和会话有效性

    return StreamingResponse(
        proxy_to_agent(user_id, session_id, user_input),
        media_type="text/event-stream",
    )
```

---

## 3. 0码 Agent 特有 API

0码 Agent 在标准协议之外，额外提供以下 API。

### 获取沙箱桌面 URL

**接口：** `GET /sandbox/{user_id}/{session_id}/desktop-url`

Agent 在执行任务时会启动沙箱环境（含 GUI 桌面）。通过此接口可获取沙箱的可视化桌面访问地址，用于实时观察 Agent 的操作过程。

```python
import requests

ENDPOINT = "https://your-zero-code-agent.example.com"
TOKEN = "YOUR_TOKEN_HERE"   # ⚠️ 替换为实际 Token，无凭证时删除 Authorization header
USER_ID = "user-001"
SESSION_ID = "session-001"

headers = {}
if TOKEN:
    headers["Authorization"] = f"Bearer {TOKEN}"

response = requests.get(
    f"{ENDPOINT}/sandbox/{USER_ID}/{SESSION_ID}/desktop-url",
    headers=headers,
)
response.raise_for_status()
data = response.json()

if data.get("success"):
    for item in data["data"]["desktop_urls"]:
        print(f"沙箱类型: {item['sandbox_type']}")
        print(f"桌面地址: {item['desktop_url']}")
else:
    print(f"获取失败: {data.get('error')}")
```

**响应示例：**
```json
{
  "success": true,
  "data": {
    "desktop_urls": [
      {
        "sandbox_type": "all-in-one",
        "custom_name": "main",
        "desktop_url": "https://sandbox-xxxx.example.com/vnc"
      }
    ]
  }
}
```

### 下载沙箱文件

**接口：** `GET /download?token={token}&path={path}`

Agent 执行完成后，可通过此接口下载沙箱内生成的文件（如 PDF、Excel、图片等）。

- `token`：由 Agent 在回复中提供的加密下载凭证（含会话信息，有效期 7 天）
- `path`：沙箱内文件的绝对路径（如 `/workspace/output/report.pdf`）
- 此接口**无需** `Authorization` 请求头，token 已内含身份信息

Agent 会在回复中直接给出完整的下载链接，格式如下：
```
https://{{endpoint}}/download?token=<encrypted_token>&path=/workspace/output/report.pdf
```

直接访问该链接即可下载，也可通过 Python 下载：

```python
import requests

# ⚠️ 从 Agent 回复中获取完整下载链接
download_url = "https://your-zero-code-agent.example.com/download?token=<token>&path=/workspace/output/report.pdf"

response = requests.get(download_url, stream=True)
response.raise_for_status()

with open("report.pdf", "wb") as f:
    for chunk in response.iter_content(chunk_size=8192):
        f.write(chunk)

print("文件下载完成")
```

### 获取会话数据

**接口：** `GET /sessions/{user_id}/{session_id}`

获取指定会话的对话历史记录。

```python
import requests

ENDPOINT = "https://your-zero-code-agent.example.com"
TOKEN = "YOUR_TOKEN_HERE"
USER_ID = "user-001"
SESSION_ID = "session-001"

headers = {}
if TOKEN:
    headers["Authorization"] = f"Bearer {TOKEN}"

response = requests.get(
    f"{ENDPOINT}/sessions/{USER_ID}/{SESSION_ID}",
    headers=headers,
)
result = response.json()
# 返回格式: {"success": true, "data": {"id": "...", "user_id": "...", "messages": [...]}}
print(result)
```

---

## 4. 长期会话支持（持久化存储）

默认情况下，0码 Agent 的会话数据存储在 Pod 本地。当 Pod 重启或扩缩容时，会话数据会丢失。

如需支持长期会话（跨越 Pod 生命周期），需要在 Agent 配置中绑定持久化存储。

### 配置持久化存储

在平台控制台的 Agent 配置页面，找到「存储配置」部分：

1. **存储类型**：选择 `OSS`（对象存储）
2. **Bucket 名称**：填写存储桶名称
3. ...


### 持久化存储的作用

| 数据类型 | 说明 |
|----------|------|
| 会话历史 | 用户与 Agent 的对话记录 |
| 沙箱文件 | Agent 执行过程中生成的文件 |
| 上下文状态 | Agent 的中间状态和记忆 |

### 注意事项

- 持久化存储会增加响应延迟（读写 OSS）
- 建议根据业务需求选择是否启用
- 短期任务（单次对话）通常不需要持久化

---

## 5. 完整集成示例

以下是一个完整的 FastAPI 外层服务示例：

```python
#!/usr/bin/env python3
"""0码 Agent 外层 Web 服务示例"""

import json
import uuid
from datetime import datetime, timedelta
from typing import Optional

import httpx
from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

app = FastAPI(title="0码 Agent 集成服务")

# ========== 配置 ==========
ZERO_CODE_AGENT_URL = "https://your-zero-code-agent.example.com"
ZERO_CODE_AGENT_TOKEN = "your-token"

# ========== 会话管理（生产环境建议使用 Redis） ==========
sessions = {}


def create_session(user_id: str) -> str:
    session_id = str(uuid.uuid4())
    sessions[session_id] = {
        "user_id": user_id,
        "created_at": datetime.now(),
        "expires_at": datetime.now() + timedelta(hours=24),
    }
    return session_id


def get_session(session_id: str) -> Optional[dict]:
    session = sessions.get(session_id)
    if session and session["expires_at"] > datetime.now():
        return session
    return None


# ========== 请求模型 ==========
class ChatRequest(BaseModel):
    message: str


class CreateSessionRequest(BaseModel):
    user_id: str


# ========== API 接口 ==========
@app.post("/api/session")
async def api_create_session(req: CreateSessionRequest):
    """创建会话"""
    session_id = create_session(req.user_id)
    return {"session_id": session_id, "user_id": req.user_id}


@app.post("/api/chat/{session_id}")
async def api_chat(session_id: str, req: ChatRequest):
    """对话接口"""
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=401, detail="Invalid or expired session")

    async def stream_response():
        headers = {
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
            "x-agentrun-session-id": session_id,
        }
        if ZERO_CODE_AGENT_TOKEN:
            headers["Authorization"] = f"Bearer {ZERO_CODE_AGENT_TOKEN}"

        payload = {
            "input": [
                {
                    "role": "user",
                    "content": [{"type": "text", "text": req.message}],
                    "type": "message",
                }
            ],
            "stream": True,
            "session_id": session_id,
            "user_id": session["user_id"],
        }

        async with httpx.AsyncClient(timeout=300) as client:
            async with client.stream(
                "POST",
                f"{ZERO_CODE_AGENT_URL}/",
                json=payload,
                headers=headers,
            ) as response:
                async for line in response.aiter_lines():
                    if line.startswith("data:"):
                        yield line + "\n\n"

    return StreamingResponse(stream_response(), media_type="text/event-stream")


@app.get("/api/desktop/{session_id}")
async def api_get_desktop_url(session_id: str):
    """获取沙箱桌面 URL"""
    session = get_session(session_id)
    if not session:
        raise HTTPException(status_code=401, detail="Invalid or expired session")

    headers = {}
    if ZERO_CODE_AGENT_TOKEN:
        headers["Authorization"] = f"Bearer {ZERO_CODE_AGENT_TOKEN}"

    async with httpx.AsyncClient() as client:
        response = await client.get(
            f"{ZERO_CODE_AGENT_URL}/sandbox/{session['user_id']}/{session_id}/desktop-url",
            headers=headers,
        )
        return response.json()


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

---

## 环境变量参考

| 变量 | 必填 | 说明 |
|------|------|------|
| `ZERO_CODE_AGENT_URL` | 是 | 0码 Agent 的访问地址 |
| `ZERO_CODE_AGENT_TOKEN` | 否 | 0码 Agent 的访问凭证（如已绑定） |

---

## 相关文档

- Python 集成 Agent — 各协议访问示例（OpenAI、A2A、AG-UI、AgentScope Agent API）
