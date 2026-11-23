#!/bin/bash
# Make sure every build input is present in sources/ (runs on the host,
# macOS or Linux; called by build.sh and get-sources.sh).
# Already present files are only verified; missing ones are downloaded.
# See sources/README.md for what each file is and where it comes from.
set -euo pipefail
cd "$(dirname "$0")/.."
S=sources
mkdir -p "$S"

# GNU sha256sum (Linux), otherwise shasum (macOS: its own sha256sum lacks --status)
if sha256sum --version 2>/dev/null | grep -q GNU; then SHA256="sha256sum"; else SHA256="shasum -a 256"; fi
sha256() { $SHA256 "$@"; }
sha_ok() { echo "$1  $2" | sha256 -c --status 2>/dev/null; }

# ---- Linux kernel (stable tarball, identical to git tag v7.3.5) -------------
KVER=$(sed 's/^v//' kernel/VERSION)
KTAR="$S/linux-$KVER.tar.xz"
# Checksum pinned here for the version in kernel/VERSION; for another version
# it is taken from kernel.org's sha256sums.asc.
case "$KVER" in
    7.3.5) echo "8f293f83d54f0b7b9be56863ebc5e4ea79d73e530b4ae55c572be97ef39f0990  linux-$KVER.tar.xz" > "$S/linux.sha256" ;;
esac
if [ ! -f "$S/linux.sha256" ] || ! grep -q " linux-$KVER.tar.xz$" "$S/linux.sha256"; then
    curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v${KVER%%.*}.x/sha256sums.asc" \
        | grep " linux-$KVER.tar.xz$" > "$S/linux.sha256"
fi
if ! (cd "$S" && sha256 -c --status linux.sha256 2>/dev/null); then
    echo ">> downloading linux-$KVER.tar.xz"
    curl -fL -o "$KTAR" "https://cdn.kernel.org/pub/linux/kernel/v${KVER%%.*}.x/linux-$KVER.tar.xz"
    (cd "$S" && sha256 -c linux.sha256)
fi

# ---- AOSP mkbootimg (pinned commit) ----------------------------------------
MKB_COMMIT=d2bb0af5ba6d3198a3e99529c97eda1be0b5a093
MKB="$S/mkbootimg-${MKB_COMMIT:0:7}.tar.gz"
if [ ! -f "$MKB" ]; then
    echo ">> fetching AOSP mkbootimg $MKB_COMMIT"
    tmp=$(mktemp -d)
    git clone -q https://android.googlesource.com/platform/system/tools/mkbootimg "$tmp/mkbootimg"
    git -C "$tmp/mkbootimg" archive --prefix=mkbootimg/ -o "$PWD/$MKB" "$MKB_COMMIT"
    rm -rf "$tmp"
fi

# ---- sensor stack, built in the rootfs (build-rootfs.sh) -------------------
# libssc (SSC over QMI), hexagonrpc (FastRPC file server for the ADSP sensor
# PD), iio-sensor-proxy with SSC support (noble's 3.5 has none), and a newer
# meson than noble's 1.3 (libssc needs >= 1.5).
fetch_pinned() {   # file sha256 url
    if ! sha_ok "$2" "$S/$1"; then
        echo ">> downloading $1"
        curl -fL -o "$S/$1" "$3"
        sha_ok "$2" "$S/$1" || { echo "!! checksum mismatch: $1" >&2; exit 1; }
    fi
}
fetch_pinned libssc-v0.4.4.tar.gz \
    716d6bd6b34d2d753060c6b54c9a87e34fae75b724c763bf9ef487efa3621587 \
    https://codeberg.org/DylanVanAssche/libssc/archive/v0.4.4.tar.gz
fetch_pinned hexagonrpc-v0.5.0.tar.gz \
    2173985932ab68d8ac593f9954357123bdbbbe9ba5f1b17a098d9cbcec22c5d5 \
    https://github.com/linux-msm/hexagonrpc/archive/refs/tags/v0.5.0.tar.gz
fetch_pinned iio-sensor-proxy-3.9.tar.gz \
    af5edd307dcfa52dc3a242d13b7cc756e90a71640caf332efbad960e21649ae4 \
    https://gitlab.freedesktop.org/hadess/iio-sensor-proxy/-/archive/3.9/iio-sensor-proxy-3.9.tar.gz
fetch_pinned meson-1.7.2.tar.gz \
    4d40d63aa748a9c139cc41ab9bffe43edd113c5639d78bde81544ca955aea890 \
    https://github.com/mesonbuild/meson/releases/download/1.7.2/meson-1.7.2.tar.gz

# ---- Wi-Fi userspace debs (also installed by apt in build-rootfs.sh) --------
# Kept for installing on a running phone without internet:
#   scp sources/debs/*.deb phone: && sudo dpkg -i *.deb
# rootfs-base-noble.tar is created by build-rootfs.sh (debootstrap) if missing.

echo ">> sources/ complete"
