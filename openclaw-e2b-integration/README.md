# OpenClaw E2B 沙箱集成

将 [OpenClaw](https://github.com/openclaw-ai/openclaw) 与自建 E2B 兼容沙箱服务集成。零修改 OpenClaw 源码，纯插件方式实现。

与 [AgentScope 集成](../openclaw-agentscope-integration/) 并列，如需同时支持两种后端，请参考 [统一沙箱后端](../openclaw-unified-sandbox/)。

> **预备知识**：本文档涉及 Agent Runtime 平台的 Agent、ToolServer、Agent CR、sandbox-manager 等概念，请先阅读 [预备知识](../agent-integration-docs/prerequisites.md)。

## 前提条件

1. Kubernetes 集群已被阿里云 Agent Runtime 产品纳管
2. 在 Agent Runtime 平台中已预定义 E2B 沙箱工具（ToolServer `e2b-sandbox`）
3. 构建环境需要：Node.js 22+、npm、Docker

> 两种沙箱后端的对比见[预备知识](../agent-integration-docs/prerequisites.md#沙箱后端)，插件实现层面的差异见 [AgentScope 集成 README](../openclaw-agentscope-integration/README.md#与-e2b-集成的区别)。

## 文件结构

```
openclaw-e2b-integration/
├── e2b-sandbox-plugin/                 # E2B Sandbox 插件源码
│   ├── index.ts                        #   插件入口 — 注册 "e2b" sandbox backend
│   ├── src/backend.ts                  #   核心实现 — Factory/Manager/Handle
│   ├── src/config.ts                   #   配置解析
│   ├── bin/e2b-exec.mjs                #   exec 工具 helper 脚本
│   ├── openclaw.plugin.json            #   插件元数据
│   └── package.json
├── build.sh                            # 一键构建脚本
├── Dockerfile.e2b                      # Docker 构建文件
├── dockerignore.openclaw-e2b           # Docker ignore
├── entrypoint.sh                       # 容器启动脚本（从环境变量生成配置）
├── openclaw-config-template.json       # 配置模板（__PLACEHOLDER__ 风格）
├── patch-sandbox-map.mjs               # esbuild Map 分裂修复（构建时使用）
├── openclaw-agent-cr-v2.yaml           # Agent CR 部署 YAML
├── e2b-sandbox-toolserver-with-probe.yaml  # ToolServer 部署 YAML
├── test-openclaw-e2b.sh                # 集成测试脚本
└── README.md
```

## 构建

构建脚本会自动 clone OpenClaw 源码、安装 E2B 插件并构建 Docker 镜像：

```bash
# 一键构建（推荐首次使用）
./build.sh -t latest --push

# 跳过 clone（复用上次源码）
./build.sh -t latest --push --skip-clone
```

> 构建脚本会优先使用本地 E2B SDK（如果存在），否则自动从 GitHub clone 官方 E2B SDK。

## 部署

通过 kubectl 部署（集群需已纳管）：

```bash
# 1. 编辑 e2b-sandbox-toolserver-with-probe.yaml，填写 spec.cluster.id 和 authentication 中的 secret 名称

# 2. 部署 ToolServer（沙箱模板）
kubectl apply -f e2b-sandbox-toolserver-with-probe.yaml

# 3. 编辑 openclaw-agent-cr-v2.yaml，填写 spec.cluster.id（从控制台「集群详情」页获取）

# 4. 部署 Agent CR
kubectl apply -f openclaw-agent-cr-v2.yaml
```

也可通过 Agent Runtime Console 界面创建 Agent 和 ToolServer，填写相同的镜像地址和环境变量即可。

## 环境变量

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `LLM_BASE_URL` | 是 | - | LLM API 地址 |
| `LLM_API_KEY` | 是 | - | LLM API Key |
| `E2B_API_KEY` | 是 | - | sandbox-manager Token（从控制台「集群详情」页获取） |
| `LLM_PROVIDER` | 否 | `dashscope` | LLM 提供商 |
| `LLM_MODEL_ID` | 否 | `qwen3-coder-plus` | 模型 ID |
| `LLM_MODEL_NAME` | 否 | `Qwen3 Coder Plus` | 模型显示名 |
| `E2B_API_URL` | 否 | 集群内 sandbox-manager `/e2b` 地址 | E2B 管控面地址（集群内部署时使用默认值即可） |
| `E2B_SANDBOX_URL` | 否 | 集群内 sandbox-manager 地址 | E2B 数据面地址（集群内部署时使用默认值即可） |
| `E2B_TEMPLATE` | 否 | `e2b-sandbox` | E2B 沙箱模板（即 ToolServer 名称） |
| `GATEWAY_TOKEN` | 否 | `default-token` | Agent 网关鉴权令牌（客户端调用时需携带） |

## 测试

```bash
# 设置环境变量（从控制台获取）
export GATEWAY_IP=<网关入口 IP>
export HOST_HEADER=<Agent 域名，从控制台 Agent 详情页查看>
export AUTH_TOKEN=<GATEWAY_TOKEN 的值>

# 运行所有测试
bash test-openclaw-e2b.sh

# 指定单个测试
bash test-openclaw-e2b.sh --test code
```

测试项：
1. 基础对话（不涉及沙箱）
2. 流式对话（SSE）
3. 沙箱代码执行（PID + hostname 验证）
4. 文件写入/读取（随机标记验证）
5. 流式 + 沙箱代码执行（UUID 验证）
6. 沙箱环境验证（工作目录、hostname）
7. /v1/responses 端点
8. 会话上下文（x-openclaw-session-key）

## 浏览器访问

部署完成后可通过浏览器访问 OpenClaw Control UI。需配置 `/etc/hosts` 将 Agent 域名指向网关 IP：

```
<GATEWAY_IP>  <Agent 域名>
```

域名和 IP 均可从控制台 Agent 详情页获取。

## 用户文档

面向用户的集成文档：[`agent-integration-docs/toolserver/code/e2b.md`](../agent-integration-docs/toolserver/code/e2b.md)
