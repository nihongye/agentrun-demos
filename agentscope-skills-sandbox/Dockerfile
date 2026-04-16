# AgentScope Skills Sandbox Demo — Dockerfile
#
# 多架构构建，支持 linux/amd64 + linux/arm64。
# 使用 build_image.sh 通过 docker buildx 构建并推送：
#   ./build_image.sh
#   ./build_image.sh -r registry.example.com/myns -n demo-skills-sandbox -t v1.0.0
#
# ---- 启动 Web 服务 ----
#   docker run -d --name skills-sandbox \
#     -p 8080:8080 \
#     -e OPENAI_API_KEY=sk-xxxx \
#     -e SANDBOX_MANAGER_URL=http://sandbox-manager.example.com \
#     <image>
#
# ---- 挂载自定义 config.py（在线修改 SYS_PROMPT / DISABLED_SKILLS，无需重建镜像）----
#   docker run -d --name skills-sandbox \
#     -p 8080:8080 \
#     -e OPENAI_API_KEY=sk-xxxx \
#     -e SANDBOX_MANAGER_URL=http://sandbox-manager.example.com \
#     -v $(pwd)/config.py:/app/config.py:ro \
#     <image>

# 不设默认值，由 buildx 自动注入正确的目标架构
ARG TARGETARCH

FROM apaas-registry.cn-hangzhou.cr.aliyuncs.com/agentrun/python:3.12-slim_${TARGETARCH}

LABEL maintainer="AgentScope Team"
LABEL description="AgentScope Skills Sandbox Demo — Agent Skills + All-in-One 沙箱集成"

# 基础环境
ENV TZ=Asia/Shanghai \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# 服务地址
ENV HOST=0.0.0.0 \
    PORT=8080

# 模型 provider（openai 或 dashscope）
ENV MODEL_PROVIDER=openai

# OpenAI 兼容接口配置（MODEL_PROVIDER=openai 时使用）
# ENV OPENAI_API_KEY=       # 必填，请通过 -e 传入，不要写入镜像
ENV OPENAI_API_BASE=https://dashscope.aliyuncs.com/compatible-mode/v1 \
    OPENAI_MODEL_NAME=qwen-plus

# DashScope 原生 SDK 配置（MODEL_PROVIDER=dashscope 时使用）
# ENV DASHSCOPE_API_KEY=    # 必填，请通过 -e 传入，不要写入镜像
ENV DASHSCOPE_MODEL_NAME=qwen-plus

# 沙箱管理器配置
# ENV SANDBOX_MANAGER_URL=  # 必填，请通过 -e 传入
# ENV SANDBOX_MANAGER_TOKEN=  # 可选，请通过 -e 传入

# Agent 行为
ENV MAX_ITERS=20 \
    PARALLEL_TOOL_CALLS=false \
    MODEL_STREAM=true

# 日志
ENV LOG_LEVEL=INFO

WORKDIR /app

# 安装 Python 依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 复制应用代码
COPY app.py config.py async_sandbox_adapter.py all_in_one_sandbox_async.py system-prompt.md ./

# 复制 skills 目录（打包进镜像，启动时上传到沙箱）
COPY skills/ ./skills/

# 非 root 用户运行
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request, os; urllib.request.urlopen('http://localhost:' + os.environ.get('PORT','8080') + '/health')" || exit 1

CMD ["python", "app.py"]
