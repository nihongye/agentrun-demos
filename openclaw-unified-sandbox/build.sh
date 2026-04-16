#!/bin/bash
# OpenClaw 统一沙箱后端 — 一键构建脚本
# 合并 E2B + AgentScope 两个插件到一个镜像
#
# 两种构建模式：
#   1. 本地模式（默认）：使用 ../openclaw/ 目录作为构建上下文
#   2. Clone 模式：从远程 clone OpenClaw 源码并构建
#
# 用法:
#   ./build.sh -t latest --push              # 本地模式（推荐）
#   ./build.sh -t latest --push --clone      # Clone 模式
#   ./build.sh -t latest --push --skip-clone # Clone 模式，复用上次源码

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/_build"

# 默认值
REGISTRY="apaas-registry.cn-hangzhou.cr.aliyuncs.com/agentrun"
IMAGE_NAME="openclaw-unified"
TAG="latest"
PUSH=false
CLONE_MODE=false
SKIP_CLONE=false
OPENCLAW_SRC="${OPENCLAW_SRC:-${SCRIPT_DIR}/../openclaw}"
OPENCLAW_REPO="${OPENCLAW_REPO:-https://github.com/openclaw-ai/openclaw.git}"
OPENCLAW_REF="${OPENCLAW_REF:-main}"

# 现有集成目录（只读引用）
E2B_INTEGRATION="${SCRIPT_DIR}/../openclaw-e2b-integration"
AS_INTEGRATION="${SCRIPT_DIR}/../openclaw-agentscope-integration"

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
echo "  OpenClaw 统一沙箱后端 — 镜像构建"
echo "  镜像: ${FULL_IMAGE}"
if [[ "$CLONE_MODE" == "true" ]]; then
  echo "  模式: Clone (${OPENCLAW_REPO}@${OPENCLAW_REF})"
else
  echo "  模式: 本地 (${OPENCLAW_SRC})"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 验证现有集成目录存在
echo ""
echo "[0/5] 验证依赖目录..."
[[ -d "${E2B_INTEGRATION}/e2b-sandbox-plugin" ]] || { echo "错误: ${E2B_INTEGRATION}/e2b-sandbox-plugin/ 不存在"; exit 1; }
[[ -d "${AS_INTEGRATION}/agentscope-sandbox-plugin" ]] || { echo "错误: ${AS_INTEGRATION}/agentscope-sandbox-plugin/ 不存在"; exit 1; }
[[ -f "${E2B_INTEGRATION}/patch-sandbox-map.mjs" ]] || { echo "错误: patch-sandbox-map.mjs 不存在"; exit 1; }
echo "  ✓ E2B 插件目录存在"
echo "  ✓ AgentScope 插件目录存在"
echo "  ✓ patch-sandbox-map.mjs 存在"

if [[ "$CLONE_MODE" == "true" ]]; then
  # ── Clone 模式 ──
  if [[ "$SKIP_CLONE" != "true" ]]; then
    echo ""
    echo "[1/5] Clone OpenClaw..."
    rm -rf "${BUILD_DIR}/openclaw"
    mkdir -p "${BUILD_DIR}"
    git clone --depth 1 --branch "${OPENCLAW_REF}" "${OPENCLAW_REPO}" "${BUILD_DIR}/openclaw"
  else
    echo ""
    echo "[1/5] 跳过 clone，使用: ${BUILD_DIR}/openclaw"
    [[ -d "${BUILD_DIR}/openclaw" ]] || { echo "错误: 目录不存在"; exit 1; }
  fi
  OPENCLAW_DIR="${BUILD_DIR}/openclaw"

  echo "[2/5] 构建 OpenClaw..."
  (cd "${OPENCLAW_DIR}" && npm install && npm run build)
  (cd "${OPENCLAW_DIR}" && node scripts/ui.js build)
else
  # ── 本地模式 ──
  OPENCLAW_DIR="$(cd "${OPENCLAW_SRC}" && pwd)"
  echo ""
  echo "[1/5] 使用本地 OpenClaw: ${OPENCLAW_DIR}"
  [[ -d "${OPENCLAW_DIR}/dist" ]] || { echo "错误: dist/ 不存在，请先构建 OpenClaw"; exit 1; }
  echo "[2/5] 跳过构建（本地模式）"
fi

# ── Step 3: 安装两个插件到构建上下文 ──
echo ""
echo "[3/5] 安装两个沙箱插件..."

# E2B 插件 — 源码复制到 extensions/，编译结果在 dist/extensions/
echo "  复制 E2B 插件..."
mkdir -p "${OPENCLAW_DIR}/extensions/e2b-sandbox"
cp -r "${E2B_INTEGRATION}/e2b-sandbox-plugin/"* "${OPENCLAW_DIR}/extensions/e2b-sandbox/"
if [[ "$CLONE_MODE" == "true" ]]; then
  (cd "${OPENCLAW_DIR}/extensions/e2b-sandbox" && npm install 2>/dev/null) || true
fi

# AgentScope 插件
echo "  复制 AgentScope 插件..."
mkdir -p "${OPENCLAW_DIR}/extensions/agentscope-sandbox"
cp -r "${AS_INTEGRATION}/agentscope-sandbox-plugin/"* "${OPENCLAW_DIR}/extensions/agentscope-sandbox/"
if [[ "$CLONE_MODE" == "true" ]]; then
  if [[ -f "${OPENCLAW_DIR}/extensions/agentscope-sandbox/build-plugin.mjs" ]]; then
    (cd "${OPENCLAW_DIR}" && node extensions/agentscope-sandbox/build-plugin.mjs) || true
  fi
fi

# ── Step 4: 复制构建辅助文件 ──
echo ""
echo "[4/5] 复制构建辅助文件..."

# patch 脚本 — 使用统一增强版（扫描 dist/ 顶层 + plugin-sdk/ 子目录）
cp "${SCRIPT_DIR}/patch-sandbox-map-unified.mjs" "${OPENCLAW_DIR}/patch-sandbox-map-unified.mjs"

# exec helpers
cp "${E2B_INTEGRATION}/e2b-sandbox-plugin/bin/e2b-exec.mjs" "${OPENCLAW_DIR}/e2b-exec.mjs"
cp "${AS_INTEGRATION}/agentscope-sandbox-plugin/bin/agentscope-exec.mjs" "${OPENCLAW_DIR}/agentscope-exec.mjs"

# 配置模板和 entrypoint（从统一目录复制）
cp "${SCRIPT_DIR}/openclaw-config-e2b.json" "${OPENCLAW_DIR}/openclaw-config-e2b.json"
cp "${SCRIPT_DIR}/openclaw-config-agentscope.json" "${OPENCLAW_DIR}/openclaw-config-agentscope.json"
cp "${SCRIPT_DIR}/entrypoint.sh" "${OPENCLAW_DIR}/entrypoint.sh"

# 准备 dist-plugins/ — 只包含编译后的 .js + 元数据，不含 .ts 源码
# OpenClaw 会优先加载 .ts，但 .ts 依赖 plugin-sdk 路径在容器中不存在
echo "  准备 dist-plugins/（仅编译后文件）..."
rm -rf "${OPENCLAW_DIR}/dist-plugins"
mkdir -p "${OPENCLAW_DIR}/dist-plugins/e2b-sandbox"
mkdir -p "${OPENCLAW_DIR}/dist-plugins/agentscope-sandbox"

# E2B: 编译结果在 dist/extensions/e2b-sandbox/
if [[ -f "${OPENCLAW_DIR}/dist/extensions/e2b-sandbox/index.js" ]]; then
  cp "${OPENCLAW_DIR}/dist/extensions/e2b-sandbox/index.js" "${OPENCLAW_DIR}/dist-plugins/e2b-sandbox/"
  cp "${OPENCLAW_DIR}/dist/extensions/e2b-sandbox/openclaw.plugin.json" "${OPENCLAW_DIR}/dist-plugins/e2b-sandbox/"
  cp "${OPENCLAW_DIR}/dist/extensions/e2b-sandbox/package.json" "${OPENCLAW_DIR}/dist-plugins/e2b-sandbox/"
elif [[ -f "${OPENCLAW_DIR}/extensions/e2b-sandbox/index.js" ]]; then
  cp "${OPENCLAW_DIR}/extensions/e2b-sandbox/index.js" "${OPENCLAW_DIR}/dist-plugins/e2b-sandbox/"
  cp "${OPENCLAW_DIR}/extensions/e2b-sandbox/openclaw.plugin.json" "${OPENCLAW_DIR}/dist-plugins/e2b-sandbox/"
  cp "${OPENCLAW_DIR}/extensions/e2b-sandbox/package.json" "${OPENCLAW_DIR}/dist-plugins/e2b-sandbox/"
else
  echo "错误: 找不到 E2B 插件编译结果 (index.js)"
  exit 1
fi

# AgentScope: 编译结果在 extensions/agentscope-sandbox/
if [[ -f "${OPENCLAW_DIR}/extensions/agentscope-sandbox/index.js" ]]; then
  cp "${OPENCLAW_DIR}/extensions/agentscope-sandbox/index.js" "${OPENCLAW_DIR}/dist-plugins/agentscope-sandbox/"
  cp "${OPENCLAW_DIR}/extensions/agentscope-sandbox/openclaw.plugin.json" "${OPENCLAW_DIR}/dist-plugins/agentscope-sandbox/"
  cp "${OPENCLAW_DIR}/extensions/agentscope-sandbox/package.json" "${OPENCLAW_DIR}/dist-plugins/agentscope-sandbox/"
elif [[ -f "${OPENCLAW_DIR}/dist/extensions/agentscope-sandbox/index.js" ]]; then
  cp "${OPENCLAW_DIR}/dist/extensions/agentscope-sandbox/index.js" "${OPENCLAW_DIR}/dist-plugins/agentscope-sandbox/"
  cp "${OPENCLAW_DIR}/dist/extensions/agentscope-sandbox/openclaw.plugin.json" "${OPENCLAW_DIR}/dist-plugins/agentscope-sandbox/"
  cp "${OPENCLAW_DIR}/dist/extensions/agentscope-sandbox/package.json" "${OPENCLAW_DIR}/dist-plugins/agentscope-sandbox/"
else
  echo "错误: 找不到 AgentScope 插件编译结果 (index.js)"
  exit 1
fi

echo "  ✓ dist-plugins/e2b-sandbox/ ($(ls ${OPENCLAW_DIR}/dist-plugins/e2b-sandbox/))"
echo "  ✓ dist-plugins/agentscope-sandbox/ ($(ls ${OPENCLAW_DIR}/dist-plugins/agentscope-sandbox/))"

# Dockerfile 和 dockerignore
cp "${SCRIPT_DIR}/Dockerfile" "${OPENCLAW_DIR}/Dockerfile.unified"
cp "${SCRIPT_DIR}/dockerignore.unified" "${OPENCLAW_DIR}/.dockerignore" 2>/dev/null || true

echo "  ✓ patch-sandbox-map.mjs"
echo "  ✓ e2b-exec.mjs + agentscope-exec.mjs"
echo "  ✓ 两个配置模板"
echo "  ✓ entrypoint.sh"

# ── Step 5: 构建 Docker 镜像 ──
echo ""
echo "[5/5] 构建 Docker 镜像: ${FULL_IMAGE}"

PLATFORM_FLAG=""
if [[ "$(uname -m)" == "arm64" ]] || [[ "$(uname -m)" == "aarch64" ]]; then
  echo "  ARM 架构，拉取 amd64 基础镜像..."
  docker pull --platform linux/amd64 node:22-slim 2>/dev/null || true
  PLATFORM_FLAG="--platform linux/amd64"
fi

DOCKER_BUILDKIT=0 docker build ${PLATFORM_FLAG} \
  -f "${OPENCLAW_DIR}/Dockerfile.unified" \
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
