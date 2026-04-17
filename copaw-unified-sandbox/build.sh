#!/bin/bash
# CoPaw 统一沙箱后端 — 一键构建脚本
# 合并 E2B + AgentScope 两个沙箱 SDK 到一个镜像
#
# 用法:
#   ./build.sh -t latest --push              # 构建并推送
#   ./build.sh                               # 本地构建

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

REGISTRY="registry.example.com/your-namespace"
IMAGE_NAME="copaw-unified"
TAG="latest"
PUSH=false
SKIP_BUILD="${SKIP_BUILD:-0}"
COPAW_SRC="${COPAW_SRC:-$(cd "${SCRIPT_DIR}/../copaw" && pwd)}"

while [[ $# -gt 0 ]]; do
  case $1 in
    -r|--registry)   REGISTRY="$2"; shift 2 ;;
    -n|--name)       IMAGE_NAME="$2"; shift 2 ;;
    -t|--tag)        TAG="$2"; shift 2 ;;
    --push)          PUSH=true; shift ;;
    --skip-build)    SKIP_BUILD=1; shift ;;
    -h|--help)
      echo "用法: $0 [-r registry] [-n name] [-t tag] [--push] [--skip-build]"
      exit 0 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  CoPaw 统一沙箱后端 — 镜像构建"
echo "  镜像:       ${FULL_IMAGE}"
echo "  CoPaw 源码: ${COPAW_SRC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ ! -f "${COPAW_SRC}/pyproject.toml" ]]; then
  echo "❌ 错误: 未找到 CoPaw 源码（${COPAW_SRC}/pyproject.toml 不存在）"
  exit 1
fi
echo "[0/3] ✅ CoPaw 源码: ${COPAW_SRC}"

if [[ "$SKIP_BUILD" == "1" ]]; then
  echo "[跳过构建] 使用已有镜像: ${FULL_IMAGE}"
else
  PLATFORM_FLAG=""
  BUILD_CMD="docker build"

  if [[ "$(uname -m)" == "arm64" ]] || [[ "$(uname -m)" == "aarch64" ]]; then
    echo "[1/3] 检测到 ARM 架构，使用 DOCKER_BUILDKIT=0 + --platform linux/amd64..."
    PLATFORM_FLAG="--platform linux/amd64"
    export DOCKER_BUILDKIT=0
  else
    echo "[1/3] x86_64 架构，直接构建..."
  fi

  echo ""
  echo "[2/3] 构建 Docker 镜像: ${FULL_IMAGE}"
  echo "      Dockerfile: ${SCRIPT_DIR}/Dockerfile"
  echo ""

  docker build ${PLATFORM_FLAG} \
    -f "${SCRIPT_DIR}/Dockerfile" \
    -t "${FULL_IMAGE}" \
    "${COPAW_SRC}"

  echo "✅ 镜像构建成功: ${FULL_IMAGE}"

  if [[ "$PUSH" == "true" ]]; then
    echo "[3/3] 推送镜像..."
    docker push "${FULL_IMAGE}"
    echo "✅ 推送成功: ${FULL_IMAGE}"
  fi
fi

if [[ "$SKIP_BUILD" == "1" && "$PUSH" == "true" ]]; then
  echo "[3/3] 推送镜像..."
  docker push "${FULL_IMAGE}"
  echo "✅ 推送成功: ${FULL_IMAGE}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  构建完成: ${FULL_IMAGE}"
echo "  部署: kubectl apply -f copaw-agent-cr.yaml"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
