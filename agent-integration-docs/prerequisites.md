# 预备知识

本文档介绍 Agent Runtime 平台的核心概念。各 demo 的 README 会引用此文档，不再重复解释。

---

## Agent Runtime 平台

Agent Runtime 是阿里云提供的 AI Agent 托管运行平台。它将用户的 Kubernetes 集群纳管后，提供 Agent 部署、沙箱管理、工具服务、流量网关等能力。

核心流程：纳管 K8s 集群 → 在平台上创建工具和 Agent → 平台自动完成调度、扩缩容、网关路由。

---

## 核心概念

### Agent

Agent 是平台的基本部署单元。每个 Agent 对应一个容器镜像，平台负责将其调度到纳管集群中运行，并自动配置网关路由和访问地址。

创建方式：
- **Console**：在 Agent Runtime 控制台「Agent」页面，填写镜像地址、端口、环境变量等信息
- **kubectl**：编写 `Agent` CR（Custom Resource）YAML，通过 `kubectl apply` 提交到纳管集群

两种方式等价，Console 更直观，kubectl 适合 GitOps 流程。

### ToolServer（工具服务）

ToolServer 是平台托管的工具容器。沙箱（sandbox）就是一种 ToolServer —— 每个沙箱实例是一个独立的 K8s Pod，提供代码执行、文件操作等能力。

创建方式：
- **Console**：在控制台「工具服务」页面创建
- **kubectl**：编写 `ToolServer` CR YAML（`apiVersion: agentruntime.alibabacloud.com/v1alpha1, kind: ToolServer`），通过 `kubectl apply` 提交

Agent 通过环境变量引用 ToolServer 名称来使用沙箱。

### 沙箱后端

平台提供两种沙箱后端，功能等价，协议不同：

| 后端 | 协议 | 典型 ToolServer 名称 | 说明 |
|------|------|---------------------|------|
| E2B | [E2B](https://e2b.dev) 兼容协议（REST + Connect RPC） | `e2b-sandbox` | 适合已有 E2B 代码的项目，使用 E2B SDK 交互 |
| AgentScope | AgentScope Runtime HTTP API | `allinone-sandbox` | 原生 HTTP 调用，无外部 SDK 依赖 |

两种后端共用同一个 sandbox-manager 服务，只是 API 路径和协议不同。

### Agent CR

Agent CR 是 Agent Runtime 的 Kubernetes 自定义资源，定义如下：

```yaml
apiVersion: agentruntime.alibabacloud.com/v1alpha1
kind: Agent
```

它描述了 Agent 的镜像、端口、环境变量、资源配额、扩缩容策略等。提交后平台的 controller 会自动创建 Deployment、Service、Ingress 等 K8s 资源。

CR 中的 `spec.cluster.id` 字段为纳管集群的 ID，可从控制台「集群详情」页面获取。

### sandbox-manager

sandbox-manager 是平台在纳管集群中自动部署的内部服务，负责沙箱的生命周期管理（创建、销毁、健康检查）。Agent 容器通过集群内地址与其通信：

```
http://sandbox-manager-service.agent-runtime-system.svc:8000
```

用户通常不需要直接操作 sandbox-manager，只需在 Agent 环境变量中配置 Token 即可。

### sandbox-manager Token

sandbox-manager Token 用于 Agent 与 sandbox-manager 之间的鉴权。可从控制台「集群详情」页面获取。

在不同的 demo 中，这个 Token 使用不同的环境变量名，但值是同一个：

| 环境变量名 | 使用场景 |
|-----------|---------|
| `E2B_API_KEY` | E2B 后端（E2B SDK 要求此变量名） |
| `SANDBOX_MANAGER_TOKEN` | AgentScope 后端 |

### GATEWAY_TOKEN

GATEWAY_TOKEN 是 Agent 自身的网关鉴权令牌，用于保护 Agent 的 HTTP 端点（如 `/v1/chat/completions`）。客户端调用 Agent 时需在 `Authorization: Bearer <token>` 中携带此值。

它与 sandbox-manager Token 是两个独立的凭证，方向不同：
- **sandbox-manager Token**：Agent → sandbox-manager，用于创建和操作沙箱
- **GATEWAY_TOKEN**：客户端 → Agent，用于访问 Agent 的 API

---

## 访问地址

Agent 部署后，平台会自动分配访问地址。地址格式取决于集群的网关配置，通常为：

```
http://<GATEWAY_IP>
```

其中：
- `GATEWAY_IP`：纳管集群的网关入口 IP，可从控制台「集群详情」页面获取
- 请求时需携带 `Host` header，值为平台分配的域名（格式因环境而异，可从控制台 Agent 详情页查看）

测试脚本中的 `GATEWAY_IP`、`HOST_HEADER` 等变量均需根据实际环境填写。
