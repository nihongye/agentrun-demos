#!/bin/bash
# OpenClaw E2B 集成 — 一键构建脚本
# 指定 OpenClaw 源码目录 → 安装插件 → 构建镜像
#
# 用法:
#   ./build.sh                                    # 交互式输入 OpenClaw 目录
#   ./build.sh -t v1.1.0                          # 指定镜像标签
#   ./build.sh -r registry.example.com/ns         # 指定镜像仓库
#   ./build.sh --openclaw-dir /path/to/openclaw   # 指定 OpenClaw 目录
#   ./build.sh -t v1.1.0 --push                   # 构建并推送
#
# 环境变量:
#   OPENCLAW_DIR    OpenClaw 源码目录
#   E2B_SDK_REPO    E2B SDK git 仓库地址 (默认: 使用 workspace 中的 E2B/)
#   E2B_SDK_REF     E2B SDK git 分支/tag (默认: main)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/_build"

# 默认值
REGISTRY="registry.example.com/your-namespace"
IMAGE_NAME="openclaw-e2b"
TAG="latest"
PUSH=false
OPENCLAW_DIR="${OPENCLAW_DIR:-}"

# 解析参数
while [[ $# -gt 0 ]]; do
  case $1 in
    -r|--registry)    REGISTRY="$2"; shift 2 ;;
    -n|--name)        IMAGE_NAME="$2"; shift 2 ;;
    -t|--tag)         TAG="$2"; shift 2 ;;
    --openclaw-dir)   OPENCLAW_DIR="$2"; shift 2 ;;
    --push)           PUSH=true; shift ;;
    -h|--help)
      echo "用法: $0 [-r registry] [-n name] [-t tag] [--openclaw-dir PATH] [--push]"
      exit 0 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  OpenClaw E2B 集成 — 镜像构建"
echo "  镜像: ${FULL_IMAGE}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Step 1: 指定 OpenClaw 源码目录 ──
echo ""
echo "[1/5] 指定 OpenClaw 源码目录..."

if [[ -z "${OPENCLAW_DIR}" ]]; then
  read -r -p "  请输入 OpenClaw 源码目录: " OPENCLAW_DIR
fi

# 展开 ~ 路径
OPENCLAW_DIR="${OPENCLAW_DIR/#\~/$HOME}"

if [[ ! -d "${OPENCLAW_DIR}" ]]; then
  echo "错误: 目录不存在: ${OPENCLAW_DIR}"
  exit 1
fi
echo "  使用: ${OPENCLAW_DIR}"

# ── Step 2: 构建 E2B SDK (fork) ──
echo ""
echo "[2/5] 构建 E2B SDK (fork)..."

# 查找 E2B SDK：优先用 workspace 中的，否则 clone
E2B_SDK_DIR=""
WORKSPACE_E2B="$(cd "${SCRIPT_DIR}/../.." && pwd)/E2B/packages/js-sdk"
if [[ -d "${WORKSPACE_E2B}" ]]; then
  echo "  使用 workspace 中的 E2B SDK: ${WORKSPACE_E2B}"
  E2B_SDK_DIR="${WORKSPACE_E2B}"
else
  echo "  workspace 中未找到 E2B SDK，clone..."
  E2B_SDK_REPO="${E2B_SDK_REPO:-https://github.com/e2b-dev/E2B.git}"
  rm -rf "${BUILD_DIR}/e2b-sdk"
  git -c credential.helper= clone --depth 1 --branch "${E2B_SDK_REF:-main}" "${E2B_SDK_REPO}" "${BUILD_DIR}/e2b-sdk"
  E2B_SDK_DIR="${BUILD_DIR}/e2b-sdk/packages/js-sdk"
fi

# 构建 SDK 并复制到 OpenClaw node_modules
(cd "${E2B_SDK_DIR}" && npm install --legacy-peer-deps 2>/dev/null && npm run build) || {
    echo "  警告: E2B SDK 构建失败，尝试继续..."
  }
echo "  复制 E2B SDK dist 到 OpenClaw node_modules..."
mkdir -p "${OPENCLAW_DIR}/node_modules/e2b"
cp -r "${E2B_SDK_DIR}/dist" "${OPENCLAW_DIR}/node_modules/e2b/"
cp "${E2B_SDK_DIR}/package.json" "${OPENCLAW_DIR}/node_modules/e2b/"

# ── Step 3: 构建 OpenClaw ──
echo ""
echo "[3/5] 构建 OpenClaw..."

# 检测包管理器
PKG_MGR=$(node -e "try{process.stdout.write(require('${OPENCLAW_DIR}/package.json').packageManager||'')}catch(e){}" 2>/dev/null)
if [[ "${PKG_MGR}" == pnpm* ]]; then
  echo "  检测到 pnpm (${PKG_MGR})"
  (cd "${OPENCLAW_DIR}" && pnpm install && pnpm build)
else
  echo "  使用 npm"
  (cd "${OPENCLAW_DIR}" && npm install --legacy-peer-deps && npm run build)
fi

echo "  构建 Control UI..."
(cd "${OPENCLAW_DIR}" && node scripts/ui.js build)

# ── Step 4: 安装 E2B 插件 ──
echo ""
echo "[4/5] 安装 E2B Sandbox 插件..."
mkdir -p "${OPENCLAW_DIR}/extensions/e2b-sandbox"
cp -r "${SCRIPT_DIR}/e2b-sandbox-plugin/"* "${OPENCLAW_DIR}/extensions/e2b-sandbox/"
(cd "${OPENCLAW_DIR}/extensions/e2b-sandbox" && npm install)

# ── Step 5: 构建 Docker 镜像 ──
echo ""
echo "[5/5] 构建 Docker 镜像: ${FULL_IMAGE}"

# 复制构建上下文文件
cp "${SCRIPT_DIR}/patch-sandbox-map.mjs" "${OPENCLAW_DIR}/"
cp "${SCRIPT_DIR}/Dockerfile.e2b" "${OPENCLAW_DIR}/"
cp "${SCRIPT_DIR}/dockerignore.openclaw-e2b" "${OPENCLAW_DIR}/.dockerignore"
cp "${SCRIPT_DIR}/e2b-sandbox-plugin/bin/e2b-exec.mjs" "${OPENCLAW_DIR}/e2b-exec.mjs"

# macOS arm64 交叉编译 amd64
PLATFORM_FLAG=""
if [[ "$(uname -m)" == "arm64" ]] || [[ "$(uname -m)" == "aarch64" ]]; then
  echo "  检测到 ARM 架构，拉取 amd64 基础镜像..."
  docker pull --platform linux/amd64 apaas-registry.cn-hangzhou.cr.aliyuncs.com/agentrun/node:22-slim
  PLATFORM_FLAG="--platform linux/amd64"
fi

DOCKER_BUILDKIT=0 docker build ${PLATFORM_FLAG} \
  -f "${OPENCLAW_DIR}/Dockerfile.e2b" \
  -t "${FULL_IMAGE}" \
  "${OPENCLAW_DIR}"

echo ""
echo "✅ 镜像构建成功: ${FULL_IMAGE}"

# ── 推送（可选）──
if [[ "$PUSH" == "true" ]]; then
  echo ""
  echo "推送镜像..."
  docker push "${FULL_IMAGE}"
  echo "✅ 推送成功: ${FULL_IMAGE}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  构建完成"
echo "  镜像: ${FULL_IMAGE}"
echo "  下一步: 修改 openclaw-agent-cr-v2.yaml 中的镜像地址，然后 kubectl apply"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
