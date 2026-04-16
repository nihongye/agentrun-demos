# LangGraph + AgentScope Sandbox 示例

基于 [LangGraph](https://github.com/langchain-ai/langgraph) ReAct Agent +
[agentscope-runtime](https://github.com/modelscope/agentscope-runtime) 沙箱的代码执行示例。

演示如何将 agentscope-runtime 平台托管的沙箱工具（IPython 代码执行、Shell 命令）集成到 LangGraph Agent 中。

## 你将学到什么

通过阅读和运行本 Demo，你可以了解：

- 如何通过 `register_custom_sandbox_type` 将自定义 ToolServer 名称注册到 `SandboxRegistry`
- 如何将沙箱异步方法（`run_ipython_cell`、`run_shell_command`）包装为 LangChain `StructuredTool`
- 如何在 LangGraph `create_react_agent` 中使用沙箱工具完成代码执行任务

## 代码阅读指引

本 Demo 只有一个核心文件 `langgraph_sandbox_agent.py`，建议按以下顺序阅读：

1. **`register_custom_sandbox_type()`** — 自定义 ToolServer 名称注册，了解如何将平台上的沙箱模板名映射到 `SandboxRegistry`
2. **`wrap_sandbox_method()`** — 工具适配层，了解如何将沙箱异步方法包装为 LangChain `StructuredTool`（同时支持同步和异步调用）
3. **`main()`** — 主流程，按顺序完成：
   - 注册自定义沙箱类型 → 创建并启动沙箱
   - 将沙箱方法包装为 LangChain 工具
   - 构建 `ChatOpenAI` 模型 + `create_react_agent`
   - 调用 Agent 执行任务 → 输出结果 → 释放沙箱

## 文件结构

```
langgraph-sandbox-example/
├── langgraph_sandbox_agent.py   # 核心示例代码
├── requirements.txt             # Python 依赖
├── .env.example                 # 环境变量模板
└── README.md                    # 本文档
```

## 快速开始

### 1. 安装依赖

```bash
pip install -r requirements.txt
```

### 2. 设置环境变量

```bash
export SANDBOX_MANAGER_URL=http://sandbox-manager.example.com
export SANDBOX_MANAGER_TOKEN=your-token
export SANDBOX_TYPE=my-base
export OPENAI_API_KEY=your-key
export OPENAI_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1
export OPENAI_MODEL=qwen3.5-plus
```

### 3. 运行

```bash
python langgraph_sandbox_agent.py
```

运行后 Agent 会自动创建沙箱，使用 Python 生成两个大随机数并计算它们的和，最后释放沙箱。

## 环境变量参考

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `SANDBOX_MANAGER_URL` | 是 | `http://localhost:8080` | 沙箱管理器地址 |
| `SANDBOX_MANAGER_TOKEN` | 否 | （空） | 沙箱管理器访问凭证 |
| `SANDBOX_TYPE` | 否 | `my-base` | 平台上 ToolServer 的名称 |
| `OPENAI_API_KEY` | 是 | — | LLM 服务 API Key |
| `OPENAI_BASE_URL` | 否 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | OpenAI 兼容接口地址 |
| `OPENAI_MODEL` | 否 | `qwen3.5-plus` | 模型名称 |
