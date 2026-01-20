FROM ubuntu:24.04

ARG LLVM_VERSION=21

RUN apt-get update -y && apt-get install -y --no-install-recommends sudo git

COPY install-dependencies.sh /tmp/install-dependencies.sh
RUN LLVM_VERSION=${LLVM_VERSION} /tmp/install-dependencies.sh

RUN git clone https://github.com/sched-ext/scx.git /scx-src

