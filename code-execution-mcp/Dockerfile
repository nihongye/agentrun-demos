# Code Execution MCP Server — Dockerfile
#
# 多架构构建，支持 linux/amd64 + linux/arm64。
# 使用 build_image.sh 通过 docker buildx 构建并推送：
#   ./build_image.sh
#   ./build_image.sh -r registry.example.com/myns -n demo-code-execution-mcp -t v1.0.0
#
# ---- 启动服务 ----
#   docker run -d --name code-exec-mcp \
#     -p 80:80 \
#     <image>
#
# ---- 挂载自定义 hooks.js（在线修改 pre_hook / post_hook，无需重建镜像）----
#   docker run -d --name code-exec-mcp \
#     -p 80:80 \
#     -v $(pwd)/hooks.js:/app/hooks.js:ro \
#     <image>
#
# ---- 完整环境变量示例 ----
#   docker run -d --name code-exec-mcp \
#     -p 80:80 \
#     -e HOST=0.0.0.0 \
#     -e PORT=80 \
#     -e EXECUTION_TIMEOUT=30 \
#     -e MAX_EXECUTION_TIMEOUT=120 \
#     <image>

# 不设默认值，由 buildx 自动注入（ARG 必须在 FROM 之前声明）
ARG TARGETARCH

FROM apaas-registry.cn-hangzhou.cr.aliyuncs.com/agentrun/node:20-slim_${TARGETARCH}

LABEL maintainer="AgentScope Team"
LABEL description="Code Execution MCP Server — Multi-language code execution over streamable HTTP"

# 基础环境
ENV TZ=Asia/Shanghai \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    NODE_ENV=production

# 服务地址
ENV HOST=0.0.0.0 \
    PORT=80

# 代码执行超时（秒）
ENV EXECUTION_TIMEOUT=30 \
    MAX_EXECUTION_TIMEOUT=120

# 安装语言运行时：python3、Java（OpenJDK）、bash（已内置）
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        default-jdk-headless \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 安装 Node.js 依赖（利用缓存层，先只复制 package 文件）
COPY package*.json ./
RUN npm ci --omit=dev

# 复制构建产物和用户配置文件
COPY dist/ ./dist/
COPY hooks.js ./

# 非 root 用户运行（复用 node 基础镜像内置的 node 用户，UID=1000）
RUN chown -R node:node /app
USER node

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD node -e "require('http').get('http://localhost:' + process.env.PORT + '/health', r => r.statusCode < 500 ? process.exit(0) : process.exit(1)).on('error', () => process.exit(1))" || exit 1

CMD ["node", "dist/index.js"]
