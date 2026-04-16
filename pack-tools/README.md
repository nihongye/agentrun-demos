# pack-tools — 离线打包工具

将 Python / Node.js 应用打包为可在 Linux 环境直接运行的离线压缩包（`.tar.gz`），用于在 Agent Runtime 管控台上传部署。

## 为什么需要离线打包

云上环境通常无法访问外部网络（npm / pip），且目标系统为 Linux。本工具通过 Docker 在目标 Linux 平台容器内安装依赖，确保 C 扩展 / 原生模块与目标系统二进制兼容，打出的包解压即可运行。

## 工具列表

| 脚本 | 用途 | 环境要求 |
|------|------|----------|
| `pack-python.sh` | Python 应用打包（支持 requirements.txt / pyproject.toml / setup.py） | Docker、Python |
| `pack-nodejs.sh` | Node.js 应用打包（支持 tsx 调试模式和编译生产模式） | Docker、Node.js |

## 用法

```bash
# Python 应用
./pack-python.sh -s /path/to/python-app

# Node.js 应用
./pack-nodejs.sh -s /path/to/nodejs-app

# 指定目标架构（默认 amd64）
./pack-python.sh -s /path/to/python-app -a arm64
./pack-nodejs.sh -s /path/to/nodejs-app -a arm64
```

脚本为交互式，运行后会依次确认：依赖安装方式、待复制文件列表、启动命令、Docker 镜像、pip 镜像源（Python）等。

## 打包产物

```
<app-name>-<timestamp>.tar.gz
└── <app-name>/
    ├── start.sh          # 启动脚本
    ├── lib/ 或 node_modules/  # 全部依赖
    └── ...               # 源代码
```

解压后运行：

```bash
tar -xzf <app-name>-<timestamp>.tar.gz
cd <app-name>
./start.sh
```

## 在管控台部署

1. 使用打包工具生成 `.tar.gz` 压缩包
2. 登录 Agent Runtime 管控台
3. 创建 Agent 或 ToolServer 时选择「上传压缩包」
4. 上传压缩包，平台会自动解压并通过 `start.sh` 启动
