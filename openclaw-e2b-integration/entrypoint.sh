#!/bin/sh
set -e

# Generate OpenClaw config from template + environment variables.
# Default values for E2B_API_URL, E2B_SANDBOX_URL, E2B_TEMPLATE, LLM_PROVIDER,
# LLM_MODEL_ID, LLM_MODEL_NAME, GATEWAY_TOKEN are baked into the Docker image.
# Users only need to set: LLM_BASE_URL, LLM_API_KEY, E2B_API_KEY.

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
  -e "s|__E2B_API_URL__|${E2B_API_URL}|g" \
  -e "s|__E2B_SANDBOX_URL__|${E2B_SANDBOX_URL}|g" \
  -e "s|__E2B_API_KEY__|${E2B_API_KEY}|g" \
  -e "s|__E2B_TEMPLATE__|${E2B_TEMPLATE}|g" \
  -e "s|__GATEWAY_TOKEN__|${GATEWAY_TOKEN}|g" \
  "${TEMPLATE_FILE}" > "${CONFIG_FILE}"

exec node openclaw.mjs gateway --bind lan --allow-unconfigured
