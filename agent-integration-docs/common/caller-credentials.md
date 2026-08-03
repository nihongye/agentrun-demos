# 访问凭证与鉴权

平台上的 Agent / 工具(Tool) / 模型运行时(ModelRuntime) 由网关统一鉴权。本文档说明调用方如何获取并携带凭证访问这些服务。

---

## 凭证模型

调用方只需携带**自己身份**的凭证，网关根据授权策略决定是否放行——无需获取目标服务的任何密钥。

```
调用方 ──携带自己的凭证──▶ 网关（认证 + 授权）──▶ 目标服务
```

- 凭证代表"你是谁"（身份），能否访问由"角色 + 策略"决定
- 一个凭证可用于调用所有被授权的服务，无需为每个目标单独管理密钥
- 拒绝(Deny)策略始终优先于允许(Allow)

---

## 平台内互调（Agent / Tool / ModelRuntime）

平台实体的身份凭证（JWT）已**自动挂载**到 Pod 中，业务代码直接读取即可，无需任何配置。

```
凭证文件：$AGENT_IDENTITY_TOKEN_PATH
         （默认 /var/run/agentruntime/credentials/identity/token）
自身身份：$AGENT_IDENTITY
         （如 agent://t1/c1/default/my-agent）
```

**Python**

```python
import os
import httpx

token_path = os.environ.get(
    "AGENT_IDENTITY_TOKEN_PATH",
    "/var/run/agentruntime/credentials/identity/token",
)
headers = {}
try:
    # 每次调用前重新读取，为凭证轮转做好准备
    headers["Authorization"] = f"Bearer {open(token_path).read().strip()}"
except OSError:
    pass  # 读不到则不携带，由网关鉴权模式决定是否放行

response = httpx.post("https://{{endpoint}}/compatible-mode/v1/responses",
                      headers=headers, json={...})
```

**Go**

```go
req, _ := http.NewRequest("POST", "https://{{endpoint}}/compatible-mode/v1/responses", body)
if data, err := os.ReadFile(os.Getenv("AGENT_IDENTITY_TOKEN_PATH")); err == nil {
    req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(data)))
}
```

**Node.js**

```javascript
const fs = require('fs');
const headers = {};
try {
  const tokenPath = process.env.AGENT_IDENTITY_TOKEN_PATH
    || '/var/run/agentruntime/credentials/identity/token';
  headers['Authorization'] = `Bearer ${fs.readFileSync(tokenPath, 'utf8').trim()}`;
} catch { /* 读不到则不携带 */ }
```

---

## 外部应用接入

外部系统（企业应用、第三方服务）需先在「访问控制 → 身份管理 → 外部身份」注册身份，获得凭证。支持两种凭证模式：

### 方式一：API Key（简单长期）

注册时选择 **API Key** 模式，获得 `art_ak_` 开头的密钥（仅在创建/轮转时显示一次，请妥善保存）。

调用时在请求头携带：

```bash
curl -X POST "https://{{endpoint}}/compatible-mode/v1/responses" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: art_ak_xxxxxxxx" \
  -d '{"input": "你好", "model": "friday"}'
```

> 注意：API Key 推荐使用 `X-API-Key` 请求头携带；也兼容放在 `Authorization: Bearer art_ak_xxxxxxxx` 中（网关对非 JWT 格式的 Bearer 凭证自动按 API Key 处理），方便只支持 Bearer 头的客户端 SDK（如 E2B SDK）直接接入。

### 方式二：OAuth2 Client Credentials（短期令牌）

注册时选择 **OAuth2** 模式，获得 `client_id`（`app_` 开头）与 `client_secret`（`sec_` 开头）。

先用凭证换取短期访问令牌（有效期 1 小时）：

```bash
curl -X POST "https://<console-address>/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=app_xxxxxxxx" \
  -d "client_secret=sec_xxxxxxxx"

# 响应：{"access_token": "<jwt>", "token_type": "Bearer", "expires_in": 3600}
```

再携带令牌调用：

```bash
curl -X POST "https://{{endpoint}}/compatible-mode/v1/responses" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <access_token>" \
  -d '{"input": "你好", "model": "friday"}'
```

> 令牌过期后需重新调用 `/oauth/token` 获取。建议客户端缓存令牌并在过期前刷新。

### 两种模式如何选择

| | API Key | OAuth2 |
|---|---------|--------|
| 适用场景 | 服务端到服务端、运行环境可控 | 对凭证泄露面有要求、需要短期凭证 |
| 有效期 | 长期（可设过期时间、可轮转） | 令牌 1 小时，过期需重新获取 |
| 接入成本 | 一个请求头即可 | 需实现换令牌逻辑 |

---

## 授权前提：凭证 ≠ 权限

携带有效凭证只解决"你是谁"。能否访问目标服务，取决于该身份是否被**授权**：

1. 在「访问控制 → 角色管理」创建角色并关联策略（策略定义允许/拒绝访问哪些资源）
2. 在「访问控制 → 身份管理」将角色分配给调用方身份

未授权时网关返回 **403**（凭证有效但无权限）。

> 平台身份默认绑定租户默认角色（TenantDefaultRole），可访问平台基础组件；外部身份默认无任何权限，必须显式授权。

---

## 匿名访问

若目标服务的访问模式设置为「匿名访问（AllowAnonymous）」，调用方无需携带任何凭证，直接请求即可。

> 匿名模式下网关不会注入调用方身份，目标服务无法区分调用者，请仅用于无需鉴权的场景。

### 免鉴权 URL（部分路径放行）

如果不想整体关闭鉴权，只想放行少数路径（如静态资源、自带凭证的下载链接），可以在目标服务的「网关访问设置」中配置**免鉴权 URL**——命中这些路径的请求跳过网关鉴权，其余路径照常校验凭证。

- 逗号分隔，支持三种写法：`*.js`（后缀匹配）、`/filesystem/*`（前缀匹配）、`/download`（精确匹配）
- 免鉴权路径不会注入调用方身份，也不会携带后端鉴权头
- 零码 Agent 创建时默认将 `/download` 配为免鉴权 URL（文件下载链接自带加密 token，无需也不应再要求请求头凭证）

---

## 鉴权模式对调用方的影响

每个集群可独立配置鉴权模式（「访问控制 → 鉴权模式」），它决定了凭证缺失或未授权时的行为：

| 模式 | 无凭证 | 有凭证但未授权 |
|------|--------|---------------|
| 观察（audit） | 放行，仅记录审计日志 | 放行，仅记录审计日志 |
| 认证（permissive） | **401** | 放行（命中显式 Deny 仍拒绝） |
| 管控（enforcing） | **401** | **403** |

---

## 常见问题

**401 与 403 的区别？**

- `401`：认证失败——凭证缺失、格式错误、已过期或已被吊销。检查凭证是否正确携带、是否在有效期内
- `403`：授权失败——凭证有效，但该身份未被授予目标资源的访问权限。需在访问控制中为身份配置角色/策略

**API Key 可以放在 Authorization: Bearer 里吗？**

可以。网关对 `Authorization: Bearer` 中非 JWT 格式的凭证会自动按 API Key 处理，与放在 `X-API-Key` 请求头效果相同。推荐使用 `X-API-Key`（语义更明确）；`Authorization: Bearer` 方式适合只支持 Bearer 头的客户端 SDK。

**凭证泄露了怎么办？**

在「访问控制 → 身份管理」中对该身份执行「轮转」（生成新凭证，旧凭证可设宽限期）或「吊销」（立即失效）。
