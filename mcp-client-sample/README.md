# MCP Client Samples

基于 [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk) 的示例客户端，演示如何通过 streamable HTTP 协议连接 MCP 服务。

## 目录结构

```
mcp-client-sample/
├── list_tools.py      # 列出 MCP 服务提供的所有工具，格式化 JSON 输出
├── requirements.txt   # Python 依赖
└── README.md
```

## 安装依赖

```bash
pip install -r requirements.txt
```

## 命令行参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--endpoint` | MCP 服务地址 | `$MCP_URL` 或 `http://localhost:80/mcp` |
| `--token` | Bearer Token，附加到 `Authorization` 请求头 | 无 |
| `--session-id` | `x-agentrun-session-id` 请求头的值，整个会话保持不变 | 自动生成 UUID |
| `--insecure` / `-k` | 跳过 SSL 证书验证（自签名证书场景） | 关闭 |
| `--host` | 覆盖 Host 请求头（代理路由场景） | 无 |

## 用法

```bash
# 列出可用工具
python list_tools.py
python list_tools.py --endpoint http://localhost:80/mcp
python list_tools.py --endpoint https://mcp.example.com/mcp --token <bearer-token>

# 跳过 SSL 验证
python list_tools.py --endpoint https://mcp.example.com/mcp --insecure
```
