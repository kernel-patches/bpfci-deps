#!/bin/bash

set -xeuo pipefail

SCRIPT_DIR=$(dirname "$(realpath "$0")")

export LLVM_VERSION=${LLVM_VERSION:-21}
export SCX_REVISION=${SCX_REVISION:-main}
export SCX_BUILD_OUTPUT=${SCX_BUILD_OUTPUT:-${SCRIPT_DIR}/output}

mkdir -p "${SCX_BUILD_OUTPUT}"

docker build \
  --build-arg LLVM_VERSION="${LLVM_VERSION}" \
  -t scx-builder:local \
  -f "${SCRIPT_DIR}/Dockerfile" \
  "${SCRIPT_DIR}"

docker run --rm \
  -v "${SCRIPT_DIR}:/scripts" \
  -v "${SCX_BUILD_OUTPUT}:/output" \
  -e OUTPUT_DIR=/output \
  -e SCX_REVISION="${SCX_REVISION}" \
  --entrypoint /scripts/build-scheds.sh \
  scx-builder:local

sudo chown -R "$(id -u):$(id -g)" "${SCX_BUILD_OUTPUT}"
