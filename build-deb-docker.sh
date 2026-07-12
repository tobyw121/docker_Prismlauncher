#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/PrismLauncher/PrismLauncher.git}"
BRANCH="${BRANCH:-release-9.x}"
PKG_NAME="${PKG_NAME:-prismlauncher}"
PKG_VERSION="${PKG_VERSION:-auto}"
MAINTAINER="${MAINTAINER:-Local Build <root@localhost>}"
ENABLE_LTO="${ENABLE_LTO:-OFF}"
BUILD_JOBS="${BUILD_JOBS:-}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
DOCKERFILE="${DOCKERFILE:-Dockerfile}"
NO_CACHE="${NO_CACHE:-0}"

mkdir -p "${OUTPUT_DIR}"

build_args=(
  --build-arg "REPO_URL=${REPO_URL}"
  --build-arg "BRANCH=${BRANCH}"
  --build-arg "PKG_NAME=${PKG_NAME}"
  --build-arg "PKG_VERSION=${PKG_VERSION}"
  --build-arg "MAINTAINER=${MAINTAINER}"
  --build-arg "ENABLE_LTO=${ENABLE_LTO}"
  --build-arg "BUILD_JOBS=${BUILD_JOBS}"
)

cache_args=()
if [[ "${NO_CACHE}" == "1" || "${NO_CACHE,,}" == "true" ]]; then
  cache_args+=(--no-cache)
fi

DOCKER_BUILDKIT=1 docker build \
  "${cache_args[@]}" \
  -f "${DOCKERFILE}" \
  --target artifact \
  --output "type=local,dest=${OUTPUT_DIR}" \
  "${build_args[@]}" \
  .

ls -lh "${OUTPUT_DIR}"/*.deb
