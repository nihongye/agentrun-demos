# E2B 沙箱集成文档

平台提供 E2B 兼容的沙箱服务，每个沙箱是独立的 K8s Pod，支持代码执行、文件操作和进程管理。

> 如需了解 Agent 框架（OpenClaw、CoPaw）如何集成沙箱，请参阅 openclaw-sandbox.md 和 copaw-sandbox.md。

---

## 1. 使用平台 E2B 沙箱

E2B SDK 默认连接官方云服务，通过环境变量即可切换到平台自建服务：

```bash
export E2B_API_URL=http://<sandbox-manager-address>/e2b      # 管控面（沙箱 CRUD）
export E2B_SANDBOX_URL=http://<sandbox-manager-address>       # 数据面（代码执行、文件操作）
export E2B_API_KEY=<调用方自身凭证：外部身份 API Key（art_ak_...）>
```

> - 域名从控制台「集群详情」页面获取，管控面和数据面必须同时配置。
> - `E2B_API_KEY` 为**调用方自身**的身份凭证：在「访问控制 → 身份管理 → 外部身份」注册身份（API Key 模式）获得，且该身份需已被授予沙箱服务的访问权限，详见「访问凭证」文档。

### Python

```bash
pip install e2b
```

```python
from e2b import Sandbox

sandbox = Sandbox(template="e2b-sandbox")

result = sandbox.commands.run("echo 'Hello from sandbox!'")
print(result.stdout)

sandbox.files.write("/home/user/test.txt", "hello world")
print(sandbox.files.read("/home/user/test.txt"))

sandbox.kill()
```

### JavaScript

```bash
npm install e2b
```

```javascript
import { Sandbox } from 'e2b';

const sandbox = await Sandbox.create({ template: 'e2b-sandbox' });

const result = await sandbox.commands.run('echo "Hello from sandbox!"');
console.log(result.stdout);

await sandbox.files.write('/home/user/test.txt', 'hello world');
console.log(await sandbox.files.read('/home/user/test.txt'));

await sandbox.kill();
```

> SDK 会自动读取上述环境变量，代码中无需重复指定地址。

---

## 2. 环境变量速查

| 变量 | 说明                                                                       |
|------|--------------------------------------------------------------------------|
| `E2B_API_URL` | 管控面地址（集群详情页获取）                                                    |
| `E2B_SANDBOX_URL` | 数据面地址（集群详情页获取） |
| `E2B_API_KEY` | 调用方自身凭证：外部身份 API Key（art_ak_），「访问控制 → 身份管理」注册获得 |
