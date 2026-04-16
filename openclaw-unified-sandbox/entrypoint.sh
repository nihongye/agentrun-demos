#!/bin/sh
set -e

# OpenClaw 统一沙箱后端 — 容器启动脚本
# 根据 SANDBOX_BACKEND 环境变量选择 E2B 或 AgentScope 配置模板，
# 用 sed 替换占位符后生成 /root/.openclaw/openclaw.json。

SANDBOX_BACKEND="${SANDBOX_BACKEND:-e2b}"

CONFIG_DIR="/root/.openclaw"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"

mkdir -p "${CONFIG_DIR}"

case "${SANDBOX_BACKEND}" in
  e2b)
    TEMPLATE_FILE="/app/openclaw-config-e2b.json"
    echo "[entrypoint] 使用 E2B 沙箱后端"
    sed \
      -e "s|__LLM_PROVIDER__|${LLM_PROVIDER:-dashscope}|g" \
      -e "s|__LLM_BASE_URL__|${LLM_BASE_URL}|g" \
      -e "s|__LLM_API_KEY__|${LLM_API_KEY}|g" \
      -e "s|__LLM_MODEL_ID__|${LLM_MODEL_ID:-qwen3-coder-plus}|g" \
      -e "s|__LLM_MODEL_NAME__|${LLM_MODEL_NAME:-Qwen3 Coder Plus}|g" \
      -e "s|__E2B_API_URL__|${E2B_API_URL:-http://sandbox-manager-service.agent-runtime-system.svc:8000/e2b}|g" \
      -e "s|__E2B_SANDBOX_URL__|${E2B_SANDBOX_URL:-http://sandbox-manager-service.agent-runtime-system.svc:8000}|g" \
      -e "s|__E2B_API_KEY__|${E2B_API_KEY}|g" \
      -e "s|__E2B_TEMPLATE__|${E2B_TEMPLATE:-e2b-sandbox}|g" \
      -e "s|__GATEWAY_TOKEN__|${GATEWAY_TOKEN:-default-token}|g" \
      "${TEMPLATE_FILE}" > "${CONFIG_FILE}"
    ;;
  agentscope)
    TEMPLATE_FILE="/app/openclaw-config-agentscope.json"
    echo "[entrypoint] 使用 AgentScope 沙箱后端"
    sed \
      -e "s|__LLM_PROVIDER__|${LLM_PROVIDER:-dashscope}|g" \
      -e "s|__LLM_BASE_URL__|${LLM_BASE_URL}|g" \
      -e "s|__LLM_API_KEY__|${LLM_API_KEY}|g" \
      -e "s|__LLM_MODEL_ID__|${LLM_MODEL_ID:-qwen3-coder-plus}|g" \
      -e "s|__LLM_MODEL_NAME__|${LLM_MODEL_NAME:-Qwen3 Coder Plus}|g" \
      -e "s|__SANDBOX_MANAGER_URL__|${SANDBOX_MANAGER_URL:-http://sandbox-manager-service.agent-runtime-system.svc:8000}|g" \
      -e "s|__SANDBOX_MANAGER_TOKEN__|${SANDBOX_MANAGER_TOKEN}|g" \
      -e "s|__SANDBOX_TYPE__|${SANDBOX_TYPE:-allinone-sandbox}|g" \
      -e "s|__GATEWAY_TOKEN__|${GATEWAY_TOKEN:-default-token}|g" \
      "${TEMPLATE_FILE}" > "${CONFIG_FILE}"
    ;;
  *)
    echo "[entrypoint] 错误: SANDBOX_BACKEND 必须是 'e2b' 或 'agentscope'，当前值: '${SANDBOX_BACKEND}'" >&2
    exit 1
    ;;
esac

echo "[entrypoint] 配置已生成: ${CONFIG_FILE}"
exec node openclaw.mjs gateway --bind lan --allow-unconfigured
