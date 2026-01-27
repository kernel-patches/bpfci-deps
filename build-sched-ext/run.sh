#!/bin/bash

set -xeuo pipefail

export LINUX_REPO=${LINUX_REPO:-https://github.com/kernel-patches/bpf.git}
export LINUX_REVISION=${LINUX_REVISION:-bpf-next}
export LLVM_VERSION=${LLVM_VERSION:-21}
export SCX_REVISION=${SCX_REVISION:-main}

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <output_dir>"
  exit 1
fi
export SCX_BUILD_OUTPUT=${1}

SCRIPT_DIR=$(dirname "$(realpath "$0")")

mkdir -p "${SCX_BUILD_OUTPUT}"

docker build \
  --build-arg LINUX_REPO="${LINUX_REPO}" \
  --build-arg LINUX_REVISION="${LINUX_REVISION}" \
  --build-arg LLVM_VERSION="${LLVM_VERSION}" \
  -f "${SCRIPT_DIR}/Dockerfile" \
  -t scx-builder:local \
  "${SCRIPT_DIR}"

docker run --rm \
  -v "${SCRIPT_DIR}:/scripts" \
  -v "${SCX_BUILD_OUTPUT}:/output" \
  -e OUTPUT_DIR=/output \
  -e SCX_REVISION="${SCX_REVISION}" \
  --entrypoint /scripts/build-scheds.sh \
  scx-builder:local
