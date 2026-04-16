# 通过 curl 调用 Agent

本文档演示如何通过 `curl` 向兼容 OpenAI 协议的 Agent 发起对话请求。

---

## 接口说明

| 字段 | 说明 |
|------|------|
| **Endpoint** | Agent 的访问地址，格式为 `https://<endpoint>/compatible-mode/v1/responses` |
| `x-agentrun-session-id` | 平台会话 ID，用于会话亲和与流量隔离。同一会话期间保持一致，可使用任意 UUID |
| `Authorization` | 访问凭证（Bearer Token）。若 Agent 未绑定凭证，则无需携带此 Header |
| `input` | 对话内容（用户消息） |
| `model` | 模型名称，可任意指定（如 `friday`） |
| `stream` | 是否启用流式响应，`true` / `false` |
| `user` / `language` / `city` | 对应 OpenAI 协议的 `extra_body` 字段，可作为额外上下文参数，例如关联当前用户信息、所在城市等 |

---

## 示例一：携带访问凭证

适用于 Agent 已绑定访问凭证的场景。

> **注意**：请将 `YOUR_TOKEN_HERE` 替换为实际的访问凭证。

```bash
curl -X POST "https://{{endpoint}}/compatible-mode/v1/responses" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "x-agentrun-session-id: {{uuid}}" \
  -d '{
    "input": "你好",
    "model": "friday",
    "stream": false,
    "user": "xiaoming",
    "language": "en",
    "city": "shenzhen"
  }'
```

---

## 示例二：无访问凭证

适用于 Agent 未绑定访问凭证的场景，省略 `Authorization` Header 即可。

```bash
curl -X POST "https://{{endpoint}}/compatible-mode/v1/responses" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "x-agentrun-session-id: {{uuid}}" \
  -d '{
    "input": "你好",
    "model": "friday",
    "stream": false,
    "user": "xiaoming",
    "language": "en",
    "city": "shenzhen"
  }'
```

---

## 补充说明

- **`{{endpoint}}`**：渲染时会自动替换为实际的 Agent Endpoint 地址，例如 `latest-my-demo.default.${GATEWAY_DOMAIN}`。
- **`x-agentrun-session-id`**：建议在客户端生成随机 UUID 并在整个会话期间复用，平台依赖此字段进行流量路由与会话隔离。
- **`extra_body` 参数**：`user`、`language`、`city` 等字段会作为附加上下文透传给 Agent，可按实际业务需要增减字段。
