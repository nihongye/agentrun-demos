# CoPaw 统一沙箱后端 — 同时支持 E2B 和 AgentScope
#
# 通过 COPAW_CONFIG_JSON 中的 sandbox.type 字段切换后端：
#   - 默认/"e2b": 使用 E2B SDK 连接 sandbox-manager
#   - "agentscope": 使用 httpx HTTP 客户端连接 sandbox-manager
#
# Build context: CoPaw source root (contains pyproject.toml, src/, console/)

# Stage 1: build console frontend
FROM node:22-slim AS console-builder
WORKDIR /app
COPY console /app/console
ARG CONSOLE_TOKEN="${COPAW_API_KEY}"
RUN cd /app/console && npm ci --include=dev && TOKEN=${CONSOLE_TOKEN} npm run build

# Stage 2: runtime image
FROM node:22-slim

ENV NODE_ENV=production
ENV WORKSPACE_DIR=/app
ENV COPAW_WORKING_DIR=/app/working
ENV COPAW_SECRET_DIR=/app/working.secret
ENV COPAW_RUNNING_IN_CONTAINER=1
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
ENV COPAW_PORT=8088

ARG COPAW_ENABLED_CHANNELS="console"
ENV COPAW_ENABLED_CHANNELS=${COPAW_ENABLED_CHANNELS}

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --fix-missing \
    curl \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    libssl-dev \
    git \
    supervisor \
    vim \
    gettext-base \
    xvfb \
    chromium \
  && rm -rf /var/lib/apt/lists/* \
  && apt-get clean

WORKDIR ${WORKSPACE_DIR}

RUN python3 -m venv venv
ENV PATH="/app/venv/bin:$PATH"

COPY pyproject.toml setup.py README.md ./
COPY src ./src
COPY --from=console-builder /app/console/dist/ ./src/copaw/console/dist/

# Install CoPaw + BOTH sandbox SDKs (e2b for E2B backend, httpx for AgentScope backend)
RUN pip install --no-cache-dir . \
  && pip install --no-cache-dir "e2b>=1.0.0" "httpx>=0.25.0"

# Init working dir with default config.json and AGENTS.md (build time).
RUN copaw init --defaults --accept-security

COPY deploy/config/supervisord.conf.template /etc/supervisor/conf.d/supervisord.conf.template
COPY deploy/entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

EXPOSE 8088

CMD ["/entrypoint.sh"]
