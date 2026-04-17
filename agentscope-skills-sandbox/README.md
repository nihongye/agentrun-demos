# AgentScope Skills Sandbox Demo

基于 [AgentScope](https://github.com/modelscope/agentscope) + [agentscope-runtime](https://runtime.agentscope.io) 的 AI 助手 Demo，展示 **Agent Skills** 与 **All-in-One 沙箱**的集成能力。

## 你将学到什么

通过阅读和运行本 Demo，你可以了解：

- 如何将 Agent Skills 与 All-in-One 沙箱集成，实现具备代码执行、文件操作、浏览器控制能力的 AI 助手
- 如何实现 per-session 沙箱隔离：每个会话独立沙箱，天然隔离用户数据
- 如何将本地 skills 目录打包上传到远程沙箱，并通过沙箱内路径注册到 Agent
- 如何通过 `async_sandbox_adapter` 将沙箱方法适配为 AgentScope Toolkit 工具
- 如何实现基于 HMAC-SHA256 签名的安全文件下载机制

## 代码阅读指引

建议按以下顺序阅读源码：

1. **`config.py`** — 配置入口，了解 SYS_PROMPT、skills 目录配置、禁用 skills 等
2. **`system-prompt.md`** — Agent 的系统提示词，定义了 skills 使用策略与执行规则
3. **`all_in_one_sandbox_async.py`** — 沙箱定义，重点关注：
   - `AllInOneSandboxAsync` 类：通过多重继承组合 GUI、文件系统、浏览器能力
   - `register_template_name()` — 将平台沙箱模板名注册到 SandboxRegistry
4. **`async_sandbox_adapter.py`** — 工具适配层，如何将沙箱方法转换为 AgentScope `ToolResponse`
5. **`app.py`** — Web 服务入口，重点关注：
   - `_init_session()` — session 初始化：创建沙箱 → 上传 skills → 注册工具方法到 Toolkit
   - `query_func()` — 请求生命周期：获取/复用 session → 构建 Agent → 流式响应
   - `_get_download_secret()` / `_create_download_token()` — 文件下载签名机制
   - `download_handler()` — 流式文件下载端点

## 请求示例

请求示例参见 [curl 调用 Agent](../agent-integration-docs/agent/code/curl.md)。

---

## 功能特性

- **Agent Skills**：支持加载开源 skills（PDF/Excel/PPT/Word 处理、前端设计、网页测试、系统调试等），启动时自动上传到沙箱
- **All-in-One 沙箱**：每个会话独立的沙箱实例，提供 Python/IPython 代码执行、Shell 命令、文件读写、浏览器操作等全套工具
- **per-session 隔离**：每次对话创建独立沙箱，请求结束自动释放，天然隔离用户数据
- **多轮对话**：同一 session_id 的请求共享对话历史
- **流式响应**：SSE 实时推送 Agent 推理与工具调用过程

## 获取 Skills

本项目不内置 skills，请从以下开源项目获取并放置到 `skills/` 目录：

- [anthropics/skills](https://github.com/anthropics/skills) — PDF/Excel/PPT/Word 处理、前端设计、算法艺术等
- [obra/superpowers](https://github.com/obra/superpowers) — TDD、系统性调试、头脑风暴、计划执行等

将 skill 目录放入 `skills/` 后，启动时会自动上传到沙箱。可根据实际使用的 skills 集合重新定义 `system-prompt.md` 中的可用 Skills 速览表。

## 工作原理

```
首次请求（新 session）
  ├─ 1. 创建 AllInOneSandboxAsync 实例（per-session），启动沙箱
  ├─ 2. 上传 skills/ 目录到沙箱 /workspace/skills/
  ├─ 3. 将沙箱方法（run_ipython_cell、read_file 等）注册为 Toolkit 工具
  ├─ 4. 注册 skills（dir 指向沙箱内路径 /workspace/skills/<name>）
  │       LLM 调用沙箱 read_file 读取 SKILL.md，而非本地工具
  ├─ 5. 注册 generate_download_url 工具（闭包绑定 session_id）
  └─ 6. 缓存 SessionState（sandbox + toolkit + memory）

后续请求（同一 session_id）
  ├─ 1. 复用已缓存的沙箱与 Toolkit
  ├─ 2. 检查 skills 目录是否仍存在（沙箱可能因 idle timeout 重启）
  └─ 3. ReActAgent 处理请求，流式响应

应用关闭时统一释放所有缓存的沙箱实例。
```

## 设计说明

### Session 生命周期与沙箱复用

沙箱实例按 `session_id` 缓存在内存中（`_sessions` 模块级字典），同一会话的多次请求复用同一个沙箱，不会在请求结束时关闭。这样做有两个好处：一是避免每次请求都重新创建沙箱的开销，二是让沙箱内的文件、进程状态在多轮对话之间保持连续。应用关闭时统一释放所有缓存的沙箱实例。

`_sessions` 同时作为 `GET /download` 路由的数据源——该路由不经过 AgentApp runner，直接通过模块级引用访问沙箱，从而支持文件流式下载。

### Skills 的幂等上传

每次请求时会检查沙箱内 `/workspace/skills` 目录是否存在。若存在则跳过，若不存在（如沙箱因 idle timeout 重启）则重新打包上传。上传流程为：本地打包成 `tar.gz` → 上传单个压缩包到沙箱 → 在沙箱内解压 → 删除压缩包。相比逐文件上传，单包传输显著减少请求次数。

Skills 的元数据（name、description）在本地从 `SKILL.md` frontmatter 中解析，注册到 Toolkit 时 `dir` 指向沙箱内路径。LLM 需要了解某个 skill 的详细用法时，通过沙箱的 `read_file` 工具读取沙箱内的 `SKILL.md`，而非在本地读取。

### 工具注册架构

沙箱方法通过 `async_sandbox_tool_adapter` 包装后注册到 Toolkit。该适配器的作用是将沙箱方法的原始返回值（`dict`、`str`、MCP `CallToolResult` 等）统一转换为 AgentScope 要求的 `ToolResponse` 对象，同时通过 `functools.wraps` 保留原方法签名和 docstring，使 Toolkit 能正确生成 JSON Schema 暴露给 LLM。

### 文件下载

Agent 通过调用 `generate_download_url(path)` 工具获取签名下载链接。该工具是一个闭包，在 session 初始化时绑定 `session_id`，调用时生成包含 `session_id` 和过期时间戳的 HMAC-SHA256 签名 token，拼接成 `/download?token=...&path=...` 格式的 URL。

`GET /download` 端点收到请求后验证 token 签名与有效期，通过 `session_id` 定位缓存的沙箱实例，调用 `sandbox.fs.read_async(path, fmt="stream")` 以流式方式将文件内容返回给客户端。token 有效期 7 天，签名密钥通过 `DOWNLOAD_SECRET` 环境变量配置。

### 日志钩子

通过 `ReActAgent.register_class_hook` 在类级别注册了两个日志钩子：`post_reasoning` 记录模型推理文本与计划调用的工具，`post_acting` 记录工具执行完成情况。类级别注册对所有 ReActAgent 实例生效，无需在每次创建 agent 时重复注册。

## 快速开始

### 环境要求

- Python 3.12+
- 可访问的沙箱管理器（agentscope-runtime 平台）

### 安装依赖

```bash
pip install -r requirements.txt
```

### 启动服务

```bash
# 基础启动（OpenAI 兼容接口 + 沙箱管理器）
export OPENAI_API_KEY=sk-xxxx
export SANDBOX_MANAGER_URL=http://sandbox-manager.example.com
python app.py

# 指定端口
python app.py --port 9090

# DashScope 原生 SDK
export MODEL_PROVIDER=dashscope
export DASHSCOPE_API_KEY=sk-xxxx
export SANDBOX_MANAGER_URL=http://sandbox-manager.example.com
python app.py
```

## 环境变量参考

### 沙箱配置

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `ALL_IN_ONE_SANDBOX_NAME` | 是 | `all-in-one` | 平台沙箱模板名称，与 `sandBoxTemplate.name` 对齐 |
| `SANDBOX_MANAGER_URL` | 是* | — | 沙箱管理器地址（留空则以 embedded 模式启动本地沙箱） |
| `SANDBOX_MANAGER_TOKEN` | 否 | — | 沙箱管理器访问凭证 |

### 服务地址

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `HOST` | `0.0.0.0` | 监听地址 |
| `PORT` | `8080` | 监听端口 |

### 模型配置

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MODEL_PROVIDER` | `openai` | `openai` 或 `dashscope` |
| `OPENAI_API_KEY` | — | OpenAI 兼容接口 API Key（必填） |
| `OPENAI_API_BASE` | `https://dashscope.aliyuncs.com/compatible-mode/v1` | 接口地址 |
| `OPENAI_MODEL_NAME` | `qwen-plus` | 模型名称 |
| `DASHSCOPE_API_KEY` | — | DashScope API Key（MODEL_PROVIDER=dashscope 时必填） |
| `DASHSCOPE_MODEL_NAME` | `qwen-plus` | 模型名称 |
| `MODEL_STREAM` | `true` | 是否启用流式输出 |

### Agent 行为

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MAX_ITERS` | `20` | ReAct 最大循环次数 |
| `PARALLEL_TOOL_CALLS` | `false` | 是否并行工具调用 |
| `LOG_LEVEL` | `INFO` | 日志级别：DEBUG/INFO/WARNING/ERROR |

## 在线调试

`config.py` 是最方便的调试入口，支持挂载覆盖无需重建镜像：

```bash
docker run -d --name skills-sandbox \
  -p 8080:8080 \
  -e OPENAI_API_KEY=sk-xxxx \
  -e SANDBOX_MANAGER_URL=http://sandbox-manager.example.com \
  -v $(pwd)/config.py:/app/config.py:ro \
  <image>
```

可调整项：

- **`SYS_PROMPT`**：修改 Agent 人设、行为风格、回答范围
- **`DISABLED_SKILLS`**：禁用不需要的 skills，减少 system prompt 长度
- **`SANDBOX_SKILLS_DIR`**：调整 skills 在沙箱内的挂载路径

## 构建镜像

```bash
# 构建并推送多架构镜像（linux/amd64 + linux/arm64）
./build_image.sh

# 自定义仓库与 tag
./build_image.sh -r registry.example.com/myns -n my-skills-sandbox -t v1.0.0
```

## 接口说明

遵循 [AgentScope Runtime 协议](https://runtime.agentscope.io/en/protocol.html)：

| 接口 | 说明 |
|------|------|
| `POST /process` | 主对话接口，SSE 流式返回 |
| `GET  /health`  | 健康检查 |
| `GET  /`        | 服务信息 |

## 与 agentscope-mcp 的对比

| | agentscope-mcp | agentscope-skills-sandbox |
|--|--|--|
| 工具来源 | 外部 MCP 服务（用户配置） | All-in-One 沙箱内置工具 |
| Agent Skills | 无 | 支持加载开源 skills |
| 沙箱隔离 | 无 | per-session 独立沙箱 |
| 代码执行 | 取决于 MCP 服务 | 沙箱 IPython + Shell |
| 文件操作 | 取决于 MCP 服务 | 沙箱文件系统 |
| 浏览器 | 取决于 MCP 服务 | 沙箱内置 Playwright |

---

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
| `SANDBOX_MANAGER_URL` | 沙箱管理器地址（从集群详情页获取） |

完整环境变量列表见上方[环境变量参考](#环境变量参考)。
