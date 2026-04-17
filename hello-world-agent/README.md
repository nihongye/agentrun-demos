# Hello World Agent

最简 Agent 示例。不依赖沙箱、不接 MCP 工具，纯对话模式，5 分钟跑通 Agent Runtime 平台基本接入。

## 你将学到什么

- 如何用 AgentScope 的 `ReActAgent` 构建最简 AI 对话助手
- 如何用 `agentscope-runtime` 的 `AgentApp` 将 Agent 包装为标准 HTTP 服务
- 如何实现基于 `session_id` 的多会话内存隔离

## 目录结构

```
hello-world-agent/
├── app.py             # 主程序（约 80 行）
├── requirements.txt   # Python 依赖
├── .env.example       # 环境变量模板
└── README.md
```

## 快速开始

```bash
# 1. 安装依赖
pip install -r requirements.txt

# 2. 设置 API Key
export OPENAI_API_KEY=sk-your-api-key

# 3. 启动
python app.py
```

服务启动后：

| 接口 | 说明 |
|------|------|
| `POST /process` | 对话接口（SSE 流式返回） |
| `GET /health` | 健康检查 |

## 测试

```bash
curl -X POST http://localhost:8080/process \
  -H "Content-Type: application/json" \
  -d '{
    "input": {"messages": [{"role": "user", "content": "你好，介绍一下你自己"}]},
    "session_id": "test-001"
  }'
```

## 环境变量

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `OPENAI_API_KEY` | 是 | - | API Key |
| `OPENAI_API_BASE` | 否 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | OpenAI 兼容接口地址 |
| `OPENAI_MODEL_NAME` | 否 | `qwen-plus` | 模型名称 |
| `HOST` | 否 | `0.0.0.0` | 监听地址 |
| `PORT` | 否 | `8080` | 监听端口 |

## 平台部署

### 打包模式

1. 运行打包工具，运行时选择 **Python 3.12**：
   ```bash
   ../pack-tools/pack-python.sh -s .
   ```
2. 在管控台创建 Agent，选择「上传压缩包」，上传生成的 `.tar.gz`
3. 启动命令：`sh start.sh`
4. HTTP 端口：`8080`
5. 健康检查：`/health`

### 必填环境变量

| 变量 | 说明 |
|------|------|
| `OPENAI_API_KEY` | 模型 API Key |

## 下一步

在此基础上可以扩展：

- 接入 MCP 工具 → 参考 [agentscope-mcp](../agentscope-mcp/)
- 接入沙箱 + Skills → 参考 [agentscope-skills-sandbox](../agentscope-skills-sandbox/)
- 通过原生 MCP 连接远程沙箱 → 参考 [react-with-sandbox-by-native-mcp](../react-with-sandbox-by-native-mcp/)
