#!/bin/bash
# get-sources.sh: download the exact source versions this project builds from.
#
#   ./get-sources.sh                    download + verify everything into sources/
#   ./get-sources.sh --kernel-tree DIR  also unpack Linux and apply kernel/patches/
#                                       into DIR (a ready-to-build ginkgo kernel tree)
#   ./get-sources.sh --list             print the pinned versions and exit
#
# Every file is checked against a pinned sha256 (see scripts/fetch-sources.sh
# and scripts/fetch-firmware.sh); files already present are only verified.
# ./build.sh calls the same scripts, so running this first is optional; it is
# meant for offline builds and for reading or building the kernel elsewhere.
# Runs on macOS and Linux (needs bash, curl, tar, xz, python3, git, patch).
set -euo pipefail
cd "$(dirname "$0")"

KVER=$(sed 's/^v//' kernel/VERSION)

list() {
    cat <<EOF
Linux                  $KVER          https://cdn.kernel.org/pub/linux/kernel/v${KVER%%.*}.x/linux-$KVER.tar.xz
  + kernel/patches/    $(ls kernel/patches/*.patch | wc -l | tr -d ' ') patches, config fragment kernel/ginkgo.config
AOSP mkbootimg         d2bb0af5ba6d   https://android.googlesource.com/platform/system/tools/mkbootimg
libssc                 0.4.4          https://codeberg.org/DylanVanAssche/libssc
hexagonrpc             0.5.0          https://github.com/linux-msm/hexagonrpc
iio-sensor-proxy       3.9 (+patch)   https://gitlab.freedesktop.org/hadess/iio-sensor-proxy
meson                  1.7.2          https://github.com/mesonbuild/meson
FT8719 touch firmware  v0x09          LineageOS android_kernel_xiaomi_sm6125 @ f5bcc3d7
ath10k firmware-5.bin  WCN3990        linux-firmware @ b142c2e0
Adreno a630_sqe.fw                    linux-firmware @ 75f16899
Ubuntu                 24.04 (noble) arm64, from ports.ubuntu.com at build time
EOF
}

KTREE=
case "${1:-}" in
    --list) list; exit 0 ;;
    --kernel-tree) KTREE=${2:?usage: $0 --kernel-tree DIR} ;;
    "") ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option $1 (see --help)" >&2; exit 1 ;;
esac

bash scripts/fetch-sources.sh
bash scripts/fetch-firmware.sh

if [ -n "$KTREE" ]; then
    if [ -e "$KTREE" ] && [ -n "$(ls -A "$KTREE" 2>/dev/null)" ]; then
        echo "!! $KTREE exists and is not empty" >&2; exit 1
    fi
    mkdir -p "$KTREE"
    # The kernel has files that differ only in case; the default macOS volume
    # is case-insensitive and would silently merge them.
    probe="$KTREE/.case-probe"
    touch "$probe" && if [ -e "$KTREE/.CASE-PROBE" ]; then
        rm -f "$probe"
        echo "!! $KTREE is on a case-insensitive file system; use a case-sensitive" >&2
        echo "   volume (or Linux), or just run ./build.sh, which builds in Docker" >&2
        exit 1
    fi
    rm -f "$probe"
    echo ">> unpacking linux-$KVER into $KTREE"
    tar -C "$KTREE" --strip-components=1 -xJf "sources/linux-$KVER.tar.xz"
    for p in kernel/patches/*.patch; do
        echo "   applying $(basename "$p")"
        patch -d "$KTREE" -p1 -s --no-backup-if-mismatch < "$p"
    done
    cp kernel/ginkgo.config "$KTREE/ginkgo.config"
    cat <<EOF
>> ginkgo kernel tree ready in $KTREE
   Build it like scripts/build-kernel.sh does (on an x86 host add
   CROSS_COMPILE=aarch64-linux-gnu- to every make):
     cd $KTREE
     make ARCH=arm64 LOCALVERSION= defconfig
     # the stock bootloader has little room for the kernel: Qualcomm only
     for s in \$(grep -oE '^config ARCH_[A-Z0-9_]+' arch/arm64/Kconfig.platforms | cut -d' ' -f2); do
         [ \$s = ARCH_QCOM ] || scripts/config -d \$s; done
     make ARCH=arm64 LOCALVERSION= olddefconfig
     scripts/kconfig/merge_config.sh -m .config ginkgo.config
     make ARCH=arm64 LOCALVERSION= olddefconfig
     make ARCH=arm64 LOCALVERSION= -j\$(nproc) Image.gz modules qcom/sm6125-xiaomi-ginkgo.dtb
   The boot image (initramfs, dtbo, mkbootimg) still comes from ./build.sh boot.
EOF
fi
echo ">> all sources present and verified in sources/"
