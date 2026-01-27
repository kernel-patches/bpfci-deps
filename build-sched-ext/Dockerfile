FROM ubuntu:24.04

ARG LINUX_REPO=https://github.com/kernel-patches/bpf.git
ARG LINUX_REVISION=bpf-next
ARG LLVM_VERSION=21

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y && apt-get install -y --no-install-recommends sudo

RUN apt-get install -y --no-install-recommends sudo software-properties-common  && \
    add-apt-repository -y ppa:git-core/ppa                                      && \
    apt-get -y update                                                           && \
    apt-get install -y --no-install-recommends git

RUN git clone --depth=1 --revision $LINUX_REVISION $LINUX_REPO /linux

COPY install-dependencies.sh /tmp/install-dependencies.sh
RUN /tmp/install-dependencies.sh
