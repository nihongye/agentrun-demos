#!/bin/bash
# OpenClaw AgentScope 集成 — 一键构建脚本
#
# 两种构建模式：
#   1. 本地模式（默认）：使用 ../openclaw/ 目录作为构建上下文
#   2. Clone 模式：从远程 clone OpenClaw 源码并构建
#
# 用法:
#   ./build.sh -t latest --push              # 本地模式（推荐）
#   ./build.sh -t latest --push --clone      # Clone 模式
#   ./build.sh -t latest --push --skip-clone # Clone 模式，复用上次源码
#
# 环境变量:
#   OPENCLAW_SRC    本地 OpenClaw 目录 (默认: ../openclaw)
#   OPENCLAW_REPO   远程仓库地址 (clone 模式)
#   OPENCLAW_REF    远程分支/tag (clone 模式)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/_build"

# 默认值
REGISTRY="registry.example.com/your-namespace"
IMAGE_NAME="openclaw-agentscope"
TAG="latest"
PUSH=false
CLONE_MODE=false
SKIP_CLONE=false
OPENCLAW_SRC="${OPENCLAW_SRC:-${SCRIPT_DIR}/../openclaw}"
OPENCLAW_REPO="${OPENCLAW_REPO:-https://github.com/openclaw-ai/openclaw.git}"
OPENCLAW_REF="${OPENCLAW_REF:-main}"

# 解析参数
while [[ $# -gt 0 ]]; do
  case $1 in
    -r|--registry) REGISTRY="$2"; shift 2 ;;
    -n|--name)     IMAGE_NAME="$2"; shift 2 ;;
    -t|--tag)      TAG="$2"; shift 2 ;;
    --push)        PUSH=true; shift ;;
    --clone)       CLONE_MODE=true; shift ;;
    --skip-clone)  CLONE_MODE=true; SKIP_CLONE=true; shift ;;
    -h|--help)
      echo "用法: $0 [-r registry] [-n name] [-t tag] [--push] [--clone] [--skip-clone]"
      echo ""
      echo "模式:"
      echo "  默认        使用 ../openclaw/ 本地目录构建"
      echo "  --clone     从远程 clone OpenClaw 后构建"
      echo "  --skip-clone  复用上次 clone 的源码"
      exit 0 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  OpenClaw AgentScope 集成 — 镜像构建"
echo "  镜像: ${FULL_IMAGE}"
if [[ "$CLONE_MODE" == "true" ]]; then
  echo "  模式: Clone (${OPENCLAW_REPO}@${OPENCLAW_REF})"
else
  echo "  模式: 本地 (${OPENCLAW_SRC})"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$CLONE_MODE" == "true" ]]; then
  # ── Clone 模式 ──
  if [[ "$SKIP_CLONE" != "true" ]]; then
    echo "[1/4] Clone OpenClaw..."
    rm -rf "${BUILD_DIR}/openclaw"
    mkdir -p "${BUILD_DIR}"
    git clone --depth 1 --branch "${OPENCLAW_REF}" "${OPENCLAW_REPO}" "${BUILD_DIR}/openclaw"
  else
    echo "[1/4] 跳过 clone，使用: ${BUILD_DIR}/openclaw"
    [[ -d "${BUILD_DIR}/openclaw" ]] || { echo "错误: 目录不存在"; exit 1; }
  fi
  OPENCLAW_DIR="${BUILD_DIR}/openclaw"

  echo "[2/4] 构建 OpenClaw..."
  (cd "${OPENCLAW_DIR}" && npm install && npm run build)
  (cd "${OPENCLAW_DIR}" && node scripts/ui.js build)

  echo "[3/4] 安装 AgentScope 插件..."
  mkdir -p "${OPENCLAW_DIR}/extensions/agentscope-sandbox"
  cp -r "${SCRIPT_DIR}/agentscope-sandbox-plugin/"* "${OPENCLAW_DIR}/extensions/agentscope-sandbox/"

  # 编译插件
  if [[ -f "${OPENCLAW_DIR}/extensions/agentscope-sandbox/build-plugin.mjs" ]]; then
    (cd "${OPENCLAW_DIR}" && node extensions/agentscope-sandbox/build-plugin.mjs)
  fi

  # 复制构建辅助文件
  E2B_DIR="${SCRIPT_DIR}/../openclaw-e2b-integration"
  [[ -f "${E2B_DIR}/patch-sandbox-map.mjs" ]] && cp "${E2B_DIR}/patch-sandbox-map.mjs" "${OPENCLAW_DIR}/"
  cp "${SCRIPT_DIR}/Dockerfile.agentscope" "${OPENCLAW_DIR}/"
  cp "${SCRIPT_DIR}/dockerignore.openclaw-agentscope" "${OPENCLAW_DIR}/.dockerignore"
  cp "${SCRIPT_DIR}/agentscope-sandbox-plugin/bin/agentscope-exec.mjs" "${OPENCLAW_DIR}/agentscope-exec.mjs"
  cp "${SCRIPT_DIR}/openclaw-config-template.json" "${OPENCLAW_DIR}/openclaw-config-template.agentscope.json"
  cp "${SCRIPT_DIR}/entrypoint.sh" "${OPENCLAW_DIR}/entrypoint.agentscope.sh"
else
  # ── 本地模式 ──
  OPENCLAW_DIR="$(cd "${OPENCLAW_SRC}" && pwd)"
  echo "[1/4] 使用本地 OpenClaw: ${OPENCLAW_DIR}"
  [[ -d "${OPENCLAW_DIR}/dist" ]] || { echo "错误: dist/ 不存在，请先构建 OpenClaw"; exit 1; }

  echo "[2/4] 同步插件源码..."
  mkdir -p "${OPENCLAW_DIR}/extensions/agentscope-sandbox"
  cp -r "${SCRIPT_DIR}/agentscope-sandbox-plugin/"* "${OPENCLAW_DIR}/extensions/agentscope-sandbox/"

  # 编译插件（如果 build-plugin.mjs 存在）
  if [[ -f "${OPENCLAW_DIR}/build-agentscope-plugin.mjs" ]]; then
    echo "  编译插件..."
    (cd "${OPENCLAW_DIR}" && node build-agentscope-plugin.mjs)
  elif [[ -f "${OPENCLAW_DIR}/extensions/agentscope-sandbox/build-plugin.mjs" ]]; then
    (cd "${OPENCLAW_DIR}" && node extensions/agentscope-sandbox/build-plugin.mjs)
  fi

  echo "[3/4] 同步构建辅助文件..."
  cp "${SCRIPT_DIR}/agentscope-sandbox-plugin/bin/agentscope-exec.mjs" "${OPENCLAW_DIR}/agentscope-exec.mjs"
  cp "${SCRIPT_DIR}/openclaw-config-template.json" "${OPENCLAW_DIR}/openclaw-config-template.agentscope.json"
  cp "${SCRIPT_DIR}/entrypoint.sh" "${OPENCLAW_DIR}/entrypoint.agentscope.sh"
fi

# ── 构建 Docker 镜像 ──
echo "[4/4] 构建 Docker 镜像: ${FULL_IMAGE}"

PLATFORM_FLAG=""
if [[ "$(uname -m)" == "arm64" ]] || [[ "$(uname -m)" == "aarch64" ]]; then
  echo "  ARM 架构，拉取 amd64 基础镜像..."
  docker pull --platform linux/amd64 node:22-slim 2>/dev/null || true
  PLATFORM_FLAG="--platform linux/amd64"
fi

DOCKER_BUILDKIT=0 docker build ${PLATFORM_FLAG} \
  -f "${OPENCLAW_DIR}/Dockerfile.agentscope" \
  -t "${FULL_IMAGE}" \
  "${OPENCLAW_DIR}"

echo ""
echo "✅ 镜像构建成功: ${FULL_IMAGE}"

if [[ "$PUSH" == "true" ]]; then
  echo "推送镜像..."
  docker push "${FULL_IMAGE}"
  echo "✅ 推送成功: ${FULL_IMAGE}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  构建完成: ${FULL_IMAGE}"
echo "  部署: kubectl apply -f openclaw-agent-cr.yaml --kubeconfig=kubeconfig.txt"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
