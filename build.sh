#!/bin/bash
# Entry point on the Mac host. Everything runs inside Docker.
#   ./build.sh kernel    build kernel + dtb + modules
#   ./build.sh rootfs    build Ubuntu rootfs image (needs kernel first)
#   ./build.sh boot      build initramfs + boot.img
#   ./build.sh all       all of the above
#   ./build.sh shell     shell in the build container
set -euo pipefail
cd "$(dirname "$0")"

IMAGE=${IMAGE:-ginkgo-build}
VOLUME=${VOLUME:-ginkgo-work}

# Everything the build downloads lives in sources/ (see sources/README.md).
bash scripts/fetch-sources.sh

# Build context is the repo root (for sources/mkbootimg-*.tar.gz); .dockerignore
# keeps everything else out of it.
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker build -t "$IMAGE" -f docker/Dockerfile .
docker volume inspect "$VOLUME" >/dev/null 2>&1 || docker volume create "$VOLUME" >/dev/null

# SSH public key that may log in to the phone.
if [ ! -s config/authorized_keys ]; then
    mkdir -p config
    for k in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub; do
        [ -f "$k" ] && { cp "$k" config/authorized_keys; echo ">> using $k for phone SSH login"; break; }
    done
fi

# The kernel tree is unpacked from sources/ into the case-sensitive docker
# volume (macOS file systems are case-insensitive; the kernel has files that
# differ only in case). The volume is a cache: `docker volume rm ginkgo-work`
# and the next build recreates it from sources/.
if ! docker run --rm -v "$VOLUME:/work" "$IMAGE" test -f /work/linux/Makefile; then
    KVER=$(sed 's/^v//' kernel/VERSION)
    docker run --rm -v "$VOLUME:/work" -v "$PWD/sources:/sources:ro" "$IMAGE" bash -c "
        set -e; mkdir -p /work/linux
        tar -C /work/linux --strip-components=1 -xJf /sources/linux-$KVER.tar.xz
        rm -f /work/kbuild/.applied-*"
fi

run() {
    # --privileged is needed for debootstrap/mount/loop when building the rootfs
    docker run --rm -i --privileged \
        -e DESKTOP="${DESKTOP:-1}" -e JOBS="${JOBS:-}" -e DISPLAY_MODE="${DISPLAY_MODE:-msm}" \
        -v "$PWD:/src" -v "$VOLUME:/work" "$IMAGE" "$@"
}

case "${1:-all}" in
    kernel) run bash /src/scripts/build-kernel.sh ;;
    rootfs) run bash /src/scripts/build-rootfs.sh ;;
    boot)   run bash /src/scripts/build-boot.sh ;;
    all)    run bash -c "bash /src/scripts/build-kernel.sh && bash /src/scripts/build-rootfs.sh && bash /src/scripts/build-boot.sh" ;;
    shell)  docker run --rm -it --privileged -v "$PWD:/src" -v "$VOLUME:/work" "$IMAGE" bash ;;
    *) echo "usage: $0 {kernel|rootfs|boot|all|shell}"; exit 1 ;;
esac
