#!/usr/bin/env bash
# =============================================================================
# build_image.sh — 构建并推送支持 linux/amd64 + linux/arm64 的多架构镜像
#
# 用法：
#   ./build_image.sh [OPTIONS]
#
# 选项：
#   -r <registry>   镜像仓库地址（默认: registry.example.com/your-namespace）
#   -n <name>       镜像名称（默认: agentscope-mcp）
#   -t <tag>        镜像 tag（默认: latest）
#   -h              显示帮助
#
# 示例：
#   ./build_image.sh
#   ./build_image.sh -t v1.0.0
#   ./build_image.sh -r registry.example.com/myns -n my-mcp -t v1.0.0
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------
# 默认值
# --------------------------------------------------------------------------
DEFAULT_REGISTRY="registry.example.com/your-namespace"
DEFAULT_NAME="demo-agentscope-mcp"
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
#
# 默认 builder 通常只支持宿主机本地架构，需要使用 docker-container 驱动
# 的 builder，它在独立容器中运行 BuildKit，通过 QEMU 支持跨架构构建。
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
#
# --platform linux/amd64,linux/arm64
#     BuildKit 为每个平台分别构建，打包为 multi-arch manifest list 推送。
# --push
#     多架构镜像无法加载到本地 docker images，必须推送到仓库。
#     如只需本地测试单架构，可改用 --load 并去掉 --platform 多平台指定。
# --provenance=false
#     禁止生成 SBOM/来源证明，避免在部分旧版仓库产生额外 manifest 条目。
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
