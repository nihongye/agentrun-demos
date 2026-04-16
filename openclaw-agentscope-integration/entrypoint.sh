#!/bin/sh
set -e

# Generate OpenClaw config from template + environment variables.
# Required: LLM_BASE_URL, LLM_API_KEY, SANDBOX_MANAGER_TOKEN
# Optional (with defaults): LLM_PROVIDER, LLM_MODEL_ID, LLM_MODEL_NAME,
#   SANDBOX_MANAGER_URL, SANDBOX_TYPE, GATEWAY_TOKEN

CONFIG_DIR="/root/.openclaw"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"
TEMPLATE_FILE="/app/openclaw-config-template.json"

mkdir -p "${CONFIG_DIR}"

sed \
  -e "s|__LLM_PROVIDER__|${LLM_PROVIDER}|g" \
  -e "s|__LLM_BASE_URL__|${LLM_BASE_URL}|g" \
  -e "s|__LLM_API_KEY__|${LLM_API_KEY}|g" \
  -e "s|__LLM_MODEL_ID__|${LLM_MODEL_ID}|g" \
  -e "s|__LLM_MODEL_NAME__|${LLM_MODEL_NAME}|g" \
  -e "s|__SANDBOX_MANAGER_URL__|${SANDBOX_MANAGER_URL}|g" \
  -e "s|__SANDBOX_MANAGER_TOKEN__|${SANDBOX_MANAGER_TOKEN}|g" \
  -e "s|__SANDBOX_TYPE__|${SANDBOX_TYPE}|g" \
  -e "s|__GATEWAY_TOKEN__|${GATEWAY_TOKEN}|g" \
  "${TEMPLATE_FILE}" > "${CONFIG_FILE}"

exec node openclaw.mjs gateway --bind lan --allow-unconfigured
