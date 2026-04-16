# OpenClaw AgentScope 沙箱集成

将 [OpenClaw](https://github.com/openclaw-ai/openclaw) 与 AgentScope 沙箱服务集成。零修改 OpenClaw 源码，纯插件方式实现。

通过 sandbox-manager 的 AgentScope HTTP API 实现沙箱操作。与 [E2B 集成](../openclaw-e2b-integration/) 并列（E2B 是一种开源沙箱协议，详见[预备知识](../agent-integration-docs/prerequisites.md#沙箱后端)），如需同时支持两种后端，请参考 [统一沙箱后端](../openclaw-unified-sandbox/)。

> **预备知识**：本文档涉及 Agent Runtime 平台的 Agent、ToolServer、Agent CR、sandbox-manager 等概念，请先阅读 [预备知识](../agent-integration-docs/prerequisites.md)。

## 前提条件

1. Kubernetes 集群已被阿里云 Agent Runtime 产品纳管
2. 在 Agent Runtime 平台中已预定义 AgentScope 沙箱工具（ToolServer `allinone-sandbox`）
3. 构建环境需要：Node.js 22+、npm、Docker

## 文件结构

```
openclaw-agentscope-integration/
├── agentscope-sandbox-plugin/          # AgentScope Sandbox 插件源码
│   ├── index.ts                        #   插件入口 — 注册 "agentscope" sandbox backend
│   ├── src/backend.ts                  #   核心实现 — Factory/Manager/Handle
│   ├── src/config.ts                   #   配置解析
│   ├── bin/agentscope-exec.mjs         #   exec helper 脚本
│   ├── build-plugin.mjs                #   esbuild 编译脚本
│   ├── openclaw.plugin.json            #   插件元数据
│   └── package.json
├── build.sh                            # 一键构建脚本（支持本地/clone 两种模式）
├── Dockerfile.agentscope               # Docker 构建文件
├── dockerignore.openclaw-agentscope    # Docker ignore
├── entrypoint.sh                       # 容器启动脚本（从环境变量生成配置）
├── openclaw-config-template.json       # 配置模板（__PLACEHOLDER__ 风格）
├── openclaw-agent-cr.yaml              # Agent CR 部署 YAML
├── test-openclaw-agentscope.sh         # E2E 集成测试脚本（5 项）
└── README.md
```

## 与 E2B 集成的区别

两种后端的基础对比见[预备知识](../agent-integration-docs/prerequisites.md#沙箱后端)。以下是插件实现层面的差异：

| 维度 | E2B 插件 | AgentScope 插件 |
|------|---------|----------------|
| 后端 ID | `e2b` | `agentscope` |
| 客户端 | E2B JS SDK | 原生 fetch → sandbox-manager HTTP API |
| 沙箱创建 | `Sandbox.create()` | `POST /create_from_pool` |
| 命令执行 | `sb.commands.run()` | `POST /call_tool` (run_shell_command) |
| 文件操作 | `sb.files.*` | shell 命令 (createRemoteShellSandboxFsBridge) |
| 依赖 | `e2b` npm 包 | 无外部依赖 |
| 配置 | apiUrl, sandboxUrl, apiKey, template | managerUrl, managerToken, sandboxType |

## 构建

构建脚本需要 OpenClaw 源码作为构建上下文：

```bash
# Clone 模式（推荐首次使用，自动 clone OpenClaw 源码并构建）
./build.sh -t latest --push --clone

# Clone 模式，复用上次 clone 的源码
./build.sh -t latest --push --skip-clone

# 本地模式（使用 ../openclaw/ 已构建的目录，需提前 clone 并 npm install && npm run build）
./build.sh -t latest --push
```

> ⚠️ 不加 `--clone` 参数时默认使用本地模式，要求 `../openclaw/` 目录已存在且已构建（含 `dist/`）。首次使用请加 `--clone`。

## 部署

通过 kubectl 部署（集群需已纳管）：

```bash
# 1. 确保 allinone-sandbox ToolServer 已部署
kubectl get toolserver allinone-sandbox -n default

# 2. 编辑 openclaw-agent-cr.yaml，填写 spec.cluster.id（从控制台「集群详情」页获取）

# 3. 部署 Agent CR
kubectl apply -f openclaw-agent-cr.yaml
```

也可通过 Agent Runtime Console 界面创建 Agent，填写相同的镜像地址和环境变量即可。

## 环境变量

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `LLM_BASE_URL` | 是 | - | LLM API 地址 |
| `LLM_API_KEY` | 是 | - | LLM API Key |
| `SANDBOX_MANAGER_TOKEN` | 是 | - | sandbox-manager Bearer Token（从控制台「集群详情」页获取） |
| `LLM_PROVIDER` | 否 | `dashscope` | LLM 提供商 |
| `LLM_MODEL_ID` | 否 | `qwen3-coder-plus` | 模型 ID |
| `LLM_MODEL_NAME` | 否 | `Qwen3 Coder Plus` | 模型显示名 |
| `SANDBOX_MANAGER_URL` | 否 | `http://sandbox-manager-service.agent-runtime-system.svc:8000` | sandbox-manager 地址（集群内部署时使用默认值即可） |
| `SANDBOX_TYPE` | 否 | `allinone-sandbox` | ToolServer 名称 |
| `GATEWAY_TOKEN` | 否 | `default-token` | Agent 网关鉴权令牌（客户端调用时需携带） |

## 测试

```bash
# 设置环境变量（从控制台获取）
export GATEWAY_IP=<网关入口 IP>
export HOST_HEADER=<Agent 域名，从控制台 Agent 详情页查看>
export AUTH_TOKEN=<GATEWAY_TOKEN 的值>

# 运行所有测试
bash test-openclaw-agentscope.sh

# 指定单个测试
bash test-openclaw-agentscope.sh --test code
```

测试项：
1. 健康检查
2. 基础对话（不涉及沙箱）
3. 沙箱代码执行（PID + 随机数验证）
4. 文件写入/读取（随机标记验证）
5. 多步骤任务（UUID 验证）

## 浏览器访问

部署完成后可通过浏览器访问 OpenClaw Control UI。需配置 `/etc/hosts` 将 Agent 域名指向网关 IP：

```
<GATEWAY_IP>  <Agent 域名>
```

域名和 IP 均可从控制台 Agent 详情页获取。
