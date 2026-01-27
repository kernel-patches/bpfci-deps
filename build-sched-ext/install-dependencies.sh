#!/bin/bash

set -xeuo pipefail

export LINUX_SRC=${LINUX_SRC:-/linux}

sudo -E apt-get update -y

# Install LLVM
sudo -E apt-get --no-install-recommends -y install curl gnupg lsb-release wget
wget https://apt.llvm.org/llvm.sh
chmod +x llvm.sh
sudo -E ./llvm.sh ${LLVM_VERSION}
rm llvm.sh

sudo update-alternatives --install \
    /usr/bin/clang clang /usr/bin/clang-${LLVM_VERSION} 10
sudo update-alternatives --set clang /usr/bin/clang-${LLVM_VERSION}
sudo update-alternatives --install \
    /usr/bin/llvm-strip llvm-strip /usr/bin/llvm-strip-${LLVM_VERSION} 10
sudo update-alternatives --set llvm-strip /usr/bin/llvm-strip-${LLVM_VERSION}
sudo update-alternatives --install \
    /usr/bin/llvm-ar llvm-ar /usr/bin/llvm-ar-${LLVM_VERSION} 10
sudo update-alternatives --set llvm-ar /usr/bin/llvm-ar-${LLVM_VERSION}
# sudo update-alternatives --install \
#     /usr/bin/ld.lld ld.lld /usr/bin/ld.lld-${LLVM_VERSION} 10
# sudo update-alternatives --set ld.lld /usr/bin/ld.lld-${LLVM_VERSION}
# sudo update-alternatives --install \
#     /usr/bin/llvm-config llvm-config /usr/bin/llvm-config-${LLVM_VERSION} 10
# sudo update-alternatives --set llvm-config /usr/bin/llvm-config-${LLVM_VERSION}

# System dependencies of libbpf, bpftool and sched-ext
sudo -E apt-get --no-install-recommends -y install \
    build-essential libssl-dev libelf-dev libzstd-dev libseccomp-dev \
    libbfd-dev libcap-dev jq pkg-config protobuf-compiler

# Install libbpf and bpftool from the linux tree
cd ${LINUX_SRC}/tools/lib/bpf
make -j$(nproc) install
cd -

cd ${LINUX_SRC}/tools/bpf/bpftool
make -j$(nproc) install
cd -

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
