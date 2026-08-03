# agent-auth 改造后的集成文档与 Demo 代码同步说明

本文档记录 agent-runtime-console 侧 agent-auth 凭证模型改造后，本仓库（`agentrun-demos`）同步做的文档与代码修改，供后续核对和排查参考。

## 背景

agent-auth 改造后，凭证模型从"目标绑定的专属 Token"变为"调用方自身身份凭证"：

- 调用方持有**自己的**身份凭证，而不是被调用目标（Agent/ToolServer）绑定的专属密钥
- 身份分两类：
  - **平台内互调**：Agent/ToolServer 容器内，平台自动挂载身份 JWT 到 `$AGENT_IDENTITY_TOKEN_PATH`（默认 `/var/run/agentruntime/credentials/identity/token`），代码直接读取即可，无需手动配置
  - **外部应用**：需先在管控台「访问控制 → 身份管理 → 外部身份」注册一个外部身份，获得两种凭证模式之一：
    - **API Key**（`art_ak_` 开头）：放在 `X-API-Key` 请求头
    - **OAuth2**（`app_`/`sec_` 前缀的 client_id/client_secret）：通过 `POST /oauth/token` 换取 1 小时有效的 JWT，放在 `Authorization: Bearer`

完整说明见 [`agent-integration-docs/common/caller-credentials.md`](agent-integration-docs/common/caller-credentials.md)（本次新增的 hub 文档，从 agent-runtime-console 集成文档模板同步而来）。

## 改动范围

### 1. 集成文档（`agent-integration-docs/`）

从 `agent-runtime-console/src/main/resources/integration-docs/` 同步过来的最新版本，涉及：

- `agent/code/curl.md`、`agent/code/python.md`、`agent/code/zeroCodeAgent.md`
- `toolserver/code/agentscope-runtime.md`、`toolserver/code/e2b.md`、`toolserver/code/langgraph.md`
- `toolserver/mcp/json.md`、`toolserver/mcp/python.md`
- 新增 `common/caller-credentials.md`（访问凭证与鉴权说明，唯一维护点）
- `README.md`、`prerequisites.md` 更新，链接到新凭证文档，并将旧的"sandbox-manager Token"表述改写为"调用方自身凭证"模型

> **未处理**：`toolserver/code/openclaw-sandbox.md`、`toolserver/code/copaw-sandbox.md` 本次未同步——这两个 demo 对应的镜像尚未改造为读取平台挂载 JWT，先改文档会误导用户，待镜像发布后再同步（已在 agent-auth 设计文档的后续任务列表中记录）。

### 2. Demo 代码改动

| Demo | 改动 |
|------|------|
| `agentscope-skills-sandbox` | 新增 `_read_identity_token()`，`init_func` 中优先用平台挂载 JWT，`SANDBOX_MANAGER_TOKEN` 环境变量降级为本地调试可选项（不再必填）；README/.env.example/Dockerfile 同步 |
| `langgraph-sandbox-example` | 同样新增 `read_identity_token()` 并作为 `bearer_token` 的回退值（`SANDBOX_MANAGER_TOKEN` 优先，为空时读取挂载 JWT）；README/.env.example 同步 |
| `dify-e2b-integration` | `API_KEY` 凭证字段语义改为"外部身份 API Key（`art_ak_` 开头）"，因为 Dify 运行在集群外，无法使用平台挂载 JWT；更新 README、`.env.example`、插件 provider yaml 的 credential 说明 |
| `mcp-client-sample` / `code-execution-mcp` / `react-with-sandbox-by-native-mcp` / `agentscope-mcp` | 代码逻辑未变（`--token` / `Authorization: Bearer` 语义本身正确），仅澄清注释和 README：明确这是**调用方自身**凭证，且 API Key 模式（`art_ak_`）必须用 `X-API-Key` 头，不能通过这些 `--token` 参数（只支持 Bearer）传递 |

### 3. 未处理 / 已知限制

- **openclaw / copaw 相关 demo**（`openclaw-agentscope-integration`、`openclaw-e2b-integration`、`openclaw-unified-sandbox`、`copaw-unified-sandbox`、`openclaw/`）本次**均未修改**——这些项目代码结构复杂，且依赖的统一沙箱镜像尚未完成读取挂载 JWT 的改造，改动被判定为超出当前范围，故未处理，留待镜像发布后单独跟进。
- E2B SDK 目前只接受 `X-API-Key` 头传递 API Key，不支持 `Authorization: Bearer` 传 API Key；后续 agent-auth 网关侧 WasmPlugin 计划做兼容（Bearer 中也能识别 API Key hash），降低使用门槛，届时可放宽 e2b.md 和相关 demo 的限制。

## 参考

- Hub 文档：[`agent-integration-docs/common/caller-credentials.md`](agent-integration-docs/common/caller-credentials.md)
- 预备知识：[`agent-integration-docs/prerequisites.md`](agent-integration-docs/prerequisites.md)
