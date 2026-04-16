#!/usr/bin/env bash
# =============================================================================
# build_image.sh — 构建并推送支持 linux/amd64 + linux/arm64 的多架构镜像
#
# 用法：
#   ./build_image.sh [OPTIONS]
#
# 选项：
#   -r <registry>   镜像仓库地址（默认: registry.example.com/your-namespace）
#   -n <name>       镜像名称（默认: demo-agentscope-skills-sandbox）
#   -t <tag>        镜像 tag（默认: latest）
#   -h              显示帮助
#
# 示例：
#   ./build_image.sh
#   ./build_image.sh -t v1.0.0
#   ./build_image.sh -r registry.example.com/myns -n my-skills-sandbox -t v1.0.0
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------
# 默认值
# --------------------------------------------------------------------------
DEFAULT_REGISTRY="registry.example.com/your-namespace"
DEFAULT_NAME="demo-agentscope-skills-sandbox"
DEFAULT_TAG="latest"

REGISTRY="$DEFAULT_REGISTRY"
IMAGE_NAME="$DEFAULT_NAME"
TAG="$DEFAULT_TAG"

# --------------------------------------------------------------------------
# 参数解析
# --------------------------------------------------------------------------
usage() {
    sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while getopts "r:n:t:h" opt; do
    case $opt in
        r) REGISTRY="$OPTARG" ;;
        n) IMAGE_NAME="$OPTARG" ;;
        t) TAG="$OPTARG" ;;
        h) usage ;;
        *) echo "未知选项: -$OPTARG"; usage ;;
    esac
done

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================="
echo "  镜像全名: ${FULL_IMAGE}"
echo "  平台:     linux/amd64, linux/arm64"
echo "  上下文:   ${SCRIPT_DIR}"
echo "=================================================="

# --------------------------------------------------------------------------
# 检查并准备 buildx builder
# --------------------------------------------------------------------------
BUILDER_NAME="multiarch-builder"

if ! docker buildx inspect "$BUILDER_NAME" &>/dev/null; then
    echo "[INFO] 创建 buildx builder: ${BUILDER_NAME}"
    docker buildx create \
        --name "$BUILDER_NAME" \
        --driver docker-container \
        --bootstrap
else
    echo "[INFO] 复用已有 builder: ${BUILDER_NAME}"
fi

docker buildx use "$BUILDER_NAME"

# --------------------------------------------------------------------------
# 构建并推送
# --------------------------------------------------------------------------
echo "[INFO] 开始构建并推送多架构镜像..."
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --file "${SCRIPT_DIR}/Dockerfile" \
    --tag "${FULL_IMAGE}" \
    --provenance=false \
    --push \
    "${SCRIPT_DIR}"

echo ""
echo "[OK] 构建完成: ${FULL_IMAGE}"
echo ""
echo "验证 manifest（确认包含两个架构）："
echo "  docker buildx imagetools inspect ${FULL_IMAGE}"
