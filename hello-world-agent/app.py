# -*- coding: utf-8 -*-
"""
Hello World Agent — 最简 Agent 示例
=====================================

基于 AgentScope ReActAgent + agentscope-runtime AgentApp 的最简 demo。
不依赖沙箱、不接 MCP 工具，纯对话模式，展示 Agent Runtime 平台的基本接入方式。

启动：python app.py
接口：POST /process（SSE 流式）、GET /health
"""

import argparse
import os
import uuid

from agentscope.agent import ReActAgent
from agentscope.memory import InMemoryMemory
from agentscope.pipeline import stream_printing_messages

from agentscope_runtime.engine import AgentApp
from agentscope_runtime.engine.schemas.agent_schemas import AgentRequest

SYS_PROMPT = "你是一个友好的 AI 助手，请简洁地回答用户问题。"

# 会话内存缓存
_memories: dict[str, InMemoryMemory] = {}


def _build_model():
    """根据环境变量构建模型。"""
    from agentscope.model import OpenAIChatModel
    from agentscope.formatter import OpenAIChatFormatter

    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key:
        raise EnvironmentError("请设置环境变量 OPENAI_API_KEY")

    return OpenAIChatModel(
        api_key=api_key,
        model_name=os.environ.get("OPENAI_MODEL_NAME", "qwen-plus"),
        client_args={"base_url": os.environ.get(
            "OPENAI_API_BASE",
            "https://dashscope.aliyuncs.com/compatible-mode/v1",
        )},
        stream=True,
    ), OpenAIChatFormatter()


agent_app = AgentApp(
    app_name="Hello World Agent",
    app_description="最简 Agent 示例，纯对话模式。",
)


@agent_app.query(framework="agentscope")
async def query_func(self, msgs, request: AgentRequest = None, **kwargs):
    session_id = request.session_id if request else str(uuid.uuid4())

    if session_id not in _memories:
        _memories[session_id] = InMemoryMemory()

    model, formatter = _build_model()
    agent = ReActAgent(
        name="HelloAgent",
        sys_prompt=SYS_PROMPT,
        model=model,
        formatter=formatter,
        memory=_memories[session_id],
        max_iters=1,
    )

    async for msg, last in stream_printing_messages(
        agents=[agent],
        coroutine_task=agent(msgs),
    ):
        yield msg, last


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--host", default=os.getenv("HOST", "0.0.0.0"))
    p.add_argument("--port", type=int, default=int(os.getenv("PORT", "8080")))
    args = p.parse_args()
    agent_app.run(host=args.host, port=args.port)
