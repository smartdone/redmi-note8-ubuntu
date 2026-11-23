FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential bc bison flex libssl-dev libelf-dev libncurses-dev \
        git ca-certificates curl wget xz-utils zstd lz4 cpio kmod rsync file \
        python3 python3-pip device-tree-compiler \
        debootstrap e2fsprogs android-sdk-libsparse-utils busybox-static \
        sudo gnupg ubuntu-keyring \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu's mkbootimg package is broken (missing gki module); use AOSP's,
# pinned snapshot from sources/ (see sources/README.md).
COPY sources/mkbootimg-d2bb0af.tar.gz /tmp/
RUN tar -C /opt -xzf /tmp/mkbootimg-d2bb0af.tar.gz && rm /tmp/mkbootimg-d2bb0af.tar.gz \
    && ln -s /opt/mkbootimg/mkbootimg.py /usr/local/bin/mkbootimg \
    && ln -s /opt/mkbootimg/unpack_bootimg.py /usr/local/bin/unpack_bootimg \
    && mkbootimg --help >/dev/null

WORKDIR /src
