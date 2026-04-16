# OpenClaw 统一沙箱后端

将 [OpenClaw](https://github.com/openclaw-ai/openclaw)（Python AI Agent 框架）与平台沙箱服务集成。一个 Docker 镜像同时包含 E2B 和 AgentScope 两个沙箱插件，通过 `SANDBOX_BACKEND` 环境变量在运行时切换后端。

> **预备知识**：本文档涉及 Agent Runtime 平台的 Agent、ToolServer、Agent CR、sandbox-manager 等概念，请先阅读 [预备知识](../agent-integration-docs/prerequisites.md)。

## 与独立集成的关系

| 目录 | 说明 |
|---|---|
| [`openclaw-e2b-integration/`](../openclaw-e2b-integration/) | E2B 独立集成（保持不变，只读引用插件源码） |
| [`openclaw-agentscope-integration/`](../openclaw-agentscope-integration/) | AgentScope 独立集成（保持不变，只读引用插件源码） |
| `openclaw-unified-sandbox/` | **本目录** — 统一镜像，合并两个插件 |

如果只需要一种沙箱后端，可以使用对应的独立集成。

## 前提条件

1. Kubernetes 集群已被阿里云 Agent Runtime 产品纳管
2. 在 Agent Runtime 平台中已预定义对应的沙箱工具：
   - E2B 后端：ToolServer `e2b-sandbox`
   - AgentScope 后端：ToolServer `allinone-sandbox`
3. 构建环境需要：Node.js 22+、npm、Docker
4. 构建依赖同级目录下的两个独立集成目录，目录布局需如下：
   ```
   <workspace>/
   ├── openclaw-agentscope-integration/   # 必须存在
   ├── openclaw-e2b-integration/          # 必须存在
   └── openclaw-unified-sandbox/          # 本目录
   ```

## 构建

构建脚本会从两个独立集成目录引用插件源码，合并到一个镜像中：

```bash
# 本地模式（推荐，使用 ../openclaw/ 已构建目录）
./build.sh -t latest

# 构建并推送到镜像仓库
./build.sh -t latest --push

# Clone 模式（从远程 clone OpenClaw 源码）
./build.sh -t latest --push --clone
```

## 部署

通过 kubectl 部署（集群需已纳管）：

```bash
# 部署到集群（默认 E2B 后端）
kubectl apply -f openclaw-agent-cr.yaml

# 等待 Pod 就绪
kubectl get agent openclaw-unified-sandbox
```

也可通过 Agent Runtime Console 界面创建 Agent，填写相同的镜像地址和环境变量即可。

## 环境变量

### 通用参数

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `SANDBOX_BACKEND` | 否 | `e2b` | 沙箱后端：`e2b` 或 `agentscope` |
| `LLM_BASE_URL` | 是 | - | LLM API 地址 |
| `LLM_API_KEY` | 是 | - | LLM API 密钥 |
| `LLM_PROVIDER` | 否 | `dashscope` | LLM 提供商 |
| `LLM_MODEL_ID` | 否 | `qwen3-coder-plus` | 模型 ID |
| `LLM_MODEL_NAME` | 否 | `Qwen3 Coder Plus` | 模型显示名 |
| `GATEWAY_TOKEN` | 否 | `default-token` | Agent 网关鉴权令牌（客户端调用时需携带） |

### E2B 后端参数（SANDBOX_BACKEND=e2b）

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `E2B_API_KEY` | 是 | - | sandbox-manager Token（从控制台「集群详情」页获取） |
| `E2B_API_URL` | 否 | 集群内 sandbox-manager `/e2b` 地址 | E2B 管控面地址 |
| `E2B_SANDBOX_URL` | 否 | 集群内 sandbox-manager 地址 | E2B 数据面地址 |
| `E2B_TEMPLATE` | 否 | `e2b-sandbox` | E2B 沙箱模板 |

### AgentScope 后端参数（SANDBOX_BACKEND=agentscope）

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `SANDBOX_MANAGER_TOKEN` | 是 | - | sandbox-manager Bearer Token（从控制台「集群详情」页获取） |
| `SANDBOX_MANAGER_URL` | 否 | 集群内 sandbox-manager 地址 | sandbox-manager 地址 |
| `SANDBOX_TYPE` | 否 | `allinone-sandbox` | ToolServer 名称 |

## 切换后端

修改 `SANDBOX_BACKEND` 环境变量并填写对应后端的连接参数即可，无需重新构建镜像。

通过 Console：在 Agent 详情页修改环境变量，重新部署。

通过 kubectl：
1. 编辑 `openclaw-agent-cr.yaml` 中 `SANDBOX_BACKEND` 的值
2. 填写对应后端的连接参数
3. 重新部署：
```bash
kubectl apply -f openclaw-agent-cr.yaml
```

## 测试

```bash
# 设置环境变量（从控制台获取）
export GATEWAY_IP=<网关入口 IP>
export HOST_HEADER=<Agent 域名，从控制台 Agent 详情页查看>
export AUTH_TOKEN=<GATEWAY_TOKEN 的值>

# 测试 E2B 后端
./test-unified.sh --backend e2b

# 测试 AgentScope 后端
./test-unified.sh --backend agentscope

# 只跑特定测试
./test-unified.sh --backend e2b --test code
```

可用测试：`health`、`basic`、`code`、`file`、`stream`、`streamcode`、`env`、`multi`、`responses`、`all`

## 浏览器访问

部署完成后可通过浏览器访问 OpenClaw Control UI。需配置 `/etc/hosts` 将 Agent 域名指向网关 IP：

```
<GATEWAY_IP>  <Agent 域名>
```

域名和 IP 均可从控制台 Agent 详情页获取。
