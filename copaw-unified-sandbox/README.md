# CoPaw 统一沙箱后端

将 [CoPaw](https://github.com/agentscope-ai/CoPaw)（Python AI Agent 框架）与平台沙箱服务集成。一个 Docker 镜像同时包含 E2B 和 AgentScope 两种沙箱后端支持，通过 `COPAW_CONFIG_JSON` 中的 `sandbox.type` 字段在运行时切换后端。

> **预备知识**：本文档涉及 Agent Runtime 平台的 Agent、ToolServer、Agent CR、sandbox-manager 等概念，请先阅读 [预备知识](../agent-integration-docs/prerequisites.md)。

## 前提条件

1. Kubernetes 集群已被阿里云 Agent Runtime 产品纳管
2. 在 Agent Runtime 平台中已预定义对应的沙箱工具：
   - E2B 后端：ToolServer `e2b-sandbox-copaw`
   - AgentScope 后端：ToolServer `allinone-sandbox`
3. 构建环境需要：Docker
4. 本地 CoPaw 源码（沙箱支持分支）：
   ```bash
   git clone https://github.com/qizhang2612/CoPaw.git ../copaw
   ```
   > 沙箱支持的 PR 尚未合入 [上游仓库](https://github.com/agentscope-ai/CoPaw)，请使用上述 fork。

   构建脚本默认使用 `../copaw/` 作为构建上下文，也可通过 `COPAW_SRC` 环境变量指定其他路径。

## 文件说明

| 文件 | 说明 |
|------|------|
| `Dockerfile` | 统一镜像（pip install e2b + httpx） |
| `build.sh` | 构建脚本（支持交叉编译） |
| `copaw-agent-cr.yaml` | Agent CR（默认 E2B，注释说明切换方法） |
| `test-copaw-unified.sh` | E2E 测试脚本（支持 `--backend` 参数） |

## 构建

```bash
# 本地构建
./build.sh

# 构建并推送
./build.sh -t latest --push

# 指定 CoPaw 源码路径
COPAW_SRC=/path/to/CoPaw ./build.sh -t latest --push
```

## 部署

通过 kubectl 部署（集群需已纳管）：

```bash
# 1. 编辑 copaw-agent-cr.yaml，填写：
#    - spec.cluster.id（从控制台「集群详情」页获取）
#    - 环境变量中的 ${LLM_API_KEY}、${E2B_API_KEY}、${COPAW_API_KEY} 等占位符

# 2. 部署 Agent CR
kubectl apply -f copaw-agent-cr.yaml
```

也可通过 Agent Runtime Console 界面创建 Agent，填写相同的镜像地址和环境变量即可。

## 环境变量

### 通用参数

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `COPAW_API_KEYS` | 是 | - | CoPaw 认证密钥（格式 `用户名:密钥`，如 `alice:<your-api-key>`） |
| `COPAW_PROVIDERS_JSON` | 是 | - | LLM 配置（JSON 格式，见下方示例） |
| `COPAW_CONFIG_JSON` | 否 | E2B 默认配置 | 沙箱配置（通过 `sandbox.type` 切换后端） |

`COPAW_PROVIDERS_JSON` 示例：
```json
{
  "providers": {
    "aliyun": {
      "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
      "api_key": "<your-llm-api-key>"
    }
  },
  "active_llm": {
    "provider_id": "aliyun",
    "model": "qwen3-coder-plus"
  }
}
```

### E2B 后端参数（COPAW_CONFIG_JSON 中无 type 或 type=e2b）

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `E2B_API_KEY` | 是 | - | sandbox-manager Token（从控制台「集群详情」页获取） |
| `E2B_API_URL` | 否 | 集群内 sandbox-manager `/e2b` 地址 | E2B 管控面地址 |
| `E2B_SANDBOX_URL` | 否 | 集群内 sandbox-manager 地址 | E2B 数据面地址 |
| `E2B_DOMAIN` | 否 | - | sandbox-manager 的外部域名（从控制台「集群详情」页获取，集群内部署时可不填） |

`COPAW_CONFIG_JSON` 示例：
```json
{"sandbox":{"enabled":true,"template_id":"e2b-sandbox-copaw"}}
```

### AgentScope 后端参数（COPAW_CONFIG_JSON 中 type=agentscope）

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `SANDBOX_MANAGER_TOKEN` | 是 | - | sandbox-manager Bearer Token（从控制台「集群详情」页获取） |
| `SANDBOX_MANAGER_URL` | 否 | 集群内 sandbox-manager 地址 | sandbox-manager 地址（集群内部署时使用默认值即可） |

`COPAW_CONFIG_JSON` 示例：
```json
{"sandbox":{"enabled":true,"type":"agentscope","template_id":"allinone-sandbox"}}
```

> `E2B_API_KEY` 和 `SANDBOX_MANAGER_TOKEN` 是同一个 sandbox-manager Token，只是变量名不同。详见[预备知识](../agent-integration-docs/prerequisites.md#sandbox-manager-token)。

## 切换后端

修改 `COPAW_CONFIG_JSON` 中的 `sandbox.type` 字段并填写对应后端的连接参数即可，无需重新构建镜像。

通过 Console：在 Agent 详情页修改环境变量，重新部署。

通过 kubectl：
1. 编辑 `copaw-agent-cr.yaml` 中 `COPAW_CONFIG_JSON` 的值
2. 填写对应后端的连接参数（E2B 需要 `E2B_API_KEY`，AgentScope 需要 `SANDBOX_MANAGER_TOKEN`）
3. 重新部署：
```bash
kubectl apply -f copaw-agent-cr.yaml
```

## 测试

```bash
# 设置环境变量（从控制台获取）
export GATEWAY_IP=<网关入口 IP>
export HOST_HEADER=<Agent 域名，从控制台 Agent 详情页查看>
export COPAW_API_KEY=<COPAW_API_KEYS 中冒号后面的部分>

# 测试 E2B 后端
./test-copaw-unified.sh --backend e2b

# 测试 AgentScope 后端
./test-copaw-unified.sh --backend agentscope

# 只跑特定测试
./test-copaw-unified.sh --backend e2b --test python
```

测试项：
1. 健康检查
2. 认证校验（错误 Token 被拒绝）
3. Python 代码执行（随机令牌验证）
4. Shell 命令执行（随机令牌验证）
5. Python 计算（随机大数加法）
6. 多行代码执行
7. 文件读取（sandbox_read_file）
8. 文件写入（sandbox_write_file）
9. 列目录（sandbox_list_files）

## 浏览器访问

部署完成后可通过浏览器访问 CoPaw Console 界面。需配置 `/etc/hosts` 将 Agent 域名指向网关 IP：

```
<GATEWAY_IP>  <Agent 域名>
```

域名和 IP 均可从控制台 Agent 详情页获取。
