#!/usr/bin/env bash
# Build the llama.cpp server image for DeepSeek V4 Flash.
# Uses upstream's own .devops/cuda.Dockerfile (no fork, no patches) driven by
# build args. Tags: :b<N>, :<upstream-describe>, :latest.
set -euo pipefail
cd "$(dirname "$0")"

# --- configuration ---------------------------------------------------------
IMAGE="deepseek-v4-flash"
SUBMODULE="llama.cpp"
CUDA_VERSION="13.0.1"      # host driver is 610.43.02 / CUDA 13.3
CUDA_DOCKER_ARCH="120"     # RTX 5090 Blackwell = sm_120, single arch keeps build fast
# ---------------------------------------------------------------------------

[ -f "$SUBMODULE/.devops/cuda.Dockerfile" ] || {
  echo "submodule missing — run: git submodule update --init" >&2; exit 1
}

BUILD_NUMBER=$(( $(cat build.number 2>/dev/null || echo 0) + 1 ))
DESCRIBE=$(git -C "$SUBMODULE" describe --tags 2>/dev/null || git -C "$SUBMODULE" rev-parse --short HEAD)

echo "BUILD_STARTED  $IMAGE b${BUILD_NUMBER}  llama.cpp=${DESCRIBE}  cuda=${CUDA_VERSION}  arch=sm_${CUDA_DOCKER_ARCH}"

DOCKER_BUILDKIT=1 docker build \
  -f "$SUBMODULE/.devops/cuda.Dockerfile" \
  --target server \
  --build-arg CUDA_VERSION="$CUDA_VERSION" \
  --build-arg CUDA_DOCKER_ARCH="$CUDA_DOCKER_ARCH" \
  --build-arg APP_VERSION="$DESCRIBE" \
  -t "${IMAGE}:b${BUILD_NUMBER}" \
  -t "${IMAGE}:${DESCRIBE}" \
  -t "${IMAGE}:latest" \
  "$SUBMODULE"

# Bump + record only on success.
echo "$BUILD_NUMBER" > build.number
printf '%-6s  %-25s  %s\n' "b${BUILD_NUMBER}" "$DESCRIBE" "$(date -Is)" >> build.history
echo "BUILD_SUCCESS  ${IMAGE}:b${BUILD_NUMBER} = ${IMAGE}:latest"
