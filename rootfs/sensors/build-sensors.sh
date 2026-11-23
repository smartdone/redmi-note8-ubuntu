#!/bin/bash
# Runs inside the rootfs chroot (scripts/build-rootfs.sh): builds and installs
# libssc, hexagonrpc and iio-sensor-proxy (with SSC support) from the source
# tarballs unpacked in /tmp/sensors, then removes the build dependencies.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
cd /tmp/sensors

RUNTIME="libqmi-glib5 libmbim-glib4 libqrtr-glib0 libprotobuf-c1 libgudev-1.0-0
         libpolkit-gobject-1-0"
BUILD="build-essential ninja-build pkg-config cmake python3-dev protobuf-compiler
       protobuf-c-compiler libglib2.0-dev libqrtr-glib-dev libqmi-glib-dev
       libmbim-glib-dev libprotobuf-c-dev libgudev-1.0-dev libpolkit-gobject-1-dev
       libsystemd-dev systemd-dev"
apt-get install -y --no-install-recommends $RUNTIME $BUILD
MESON="python3 /tmp/sensors/meson-1.7.2/meson.py"

(cd libssc && $MESON setup build --prefix=/usr --buildtype=release &&
 ninja -C build && ninja -C build install)
(cd hexagonrpc-0.5.0 && $MESON setup build --prefix=/usr --buildtype=release &&
 ninja -C build && ninja -C build install)
# hexagonrpc puts generic units under the multiarch libdir (not a systemd
# path); ginkgo has its own unit with the -R directory.
rm -rf /usr/lib/aarch64-linux-gnu/systemd
(cd iio-sensor-proxy-3.9 &&
 patch -p1 < ../iio-sensor-proxy-3.9-claim-during-startup.patch &&
 $MESON setup build --prefix=/usr --sysconfdir=/etc -Dssc-support=enabled \
     -Dgtk-tests=false -Dtests=false &&
 ninja -C build && ninja -C build install)
ldconfig

apt-mark manual $RUNTIME >/dev/null
apt-get purge -y $BUILD
apt-get autoremove -y --purge
apt-get clean
