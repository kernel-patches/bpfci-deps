#!/bin/bash

set -euo pipefail

export SCX_ROOT=${SCX_ROOT:-}
export SCX_REVISION=${SCX_REVISION:-main}

if [[ -z "$SCX_ROOT" ]]; then
    export SCX_ROOT=$(mktemp -d /tmp/scx.XXXX)
    git clone --reference-if-able /scx-src \
              --branch=main \
              https://github.com/sched-ext/scx.git \
              $SCX_ROOT
    pushd $SCX_ROOT
    git reset --hard $SCX_REVISION
    popd
fi

pushd $SCX_ROOT

rm -rf $OUTPUT_DIR/bpf
rm -rf $OUTPUT_DIR/c-build
rm -rf $OUTPUT_DIR/rust-build
mkdir -p $OUTPUT_DIR/bpf

extract_bpf_progs() {
    build_dir=$1
    pattern=$2
    bpf_dir=$3
    find "${build_dir}" -type f -name "$pattern" -printf '%P\0' | \
    while IFS= read -r -d '' prog; do
        obj_name=$(echo "${prog}" | tr / _)
        cp -v "${build_dir}/${prog}" "${bpf_dir}/${obj_name}"
    done
}

# build C scheds
# .SECONDARY prevents make from deleting the intermediate .bpf.o files
echo '.SECONDARY:' >> scheds/c/Makefile
make all -j$(nproc)
mv build $OUTPUT_DIR/c-build
extract_bpf_progs $OUTPUT_DIR/c-build/scheds "*.bpf.o" $OUTPUT_DIR/bpf

# build Rust scheds
. $HOME/.cargo/env
cargo build --release
mv target/release/build $OUTPUT_DIR/rust-build
extract_bpf_progs $OUTPUT_DIR/rust-build "bpf.bpf.o" $OUTPUT_DIR/bpf

# We only care about loadable BPF objects here, so remove everything else
rm -r $OUTPUT_DIR/c-build
rm -r $OUTPUT_DIR/rust-build

popd
