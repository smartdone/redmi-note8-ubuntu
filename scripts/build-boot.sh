#!/bin/bash
# Build initramfs and an Android boot image (header v2) for the stock ginkgo bootloader.
# Runs inside the ginkgo-build container.
set -euo pipefail

OUT=/src/out
STAGE=/work/initramfs
[ -f "$OUT/Image.gz" ] || { echo "run ./build.sh kernel first"; exit 1; }

# ---- initramfs -------------------------------------------------------------
rm -rf "$STAGE" && mkdir -p "$STAGE"/{bin,sbin,etc,proc,sys,dev,run,tmp,sysroot}
cp /bin/busybox "$STAGE/bin/busybox"
file "$STAGE/bin/busybox" | grep -q 'statically linked' || { echo "busybox is not static"; exit 1; }
install -m 0755 /src/initramfs/init "$STAGE/init"
gcc -static -Os -o "$STAGE/bin/rebootarg" /src/initramfs/rebootarg.c
# Firmware needed by built-in drivers at probe time (before the rootfs).
bash /src/scripts/fetch-firmware.sh
mkdir -p "$STAGE/lib/firmware"
cp -r /src/sources/firmware/. "$STAGE/lib/firmware/"
(cd "$STAGE" && find . | cpio -o -H newc --quiet | gzip -9) > "$OUT/initramfs.gz"

# ---- boot.img --------------------------------------------------------------
# Offsets from the ginkgo BoardConfig: base 0, kernel 0x8000, tags 0x100, page 4096.
# clk_ignore_unused/pd_ignore_unused keep the bootloader's display clocks alive
# for simple-framebuffer until there is a real panel driver.
CMDLINE_BASE="earlycon=qcom_geni,0x4a90000 clk_ignore_unused pd_ignore_unused console=ttyMSM0,115200n8 console=tty0 fbcon=font:TER16x32 loglevel=7"
CMDLINE="$CMDLINE_BASE root=LABEL=ginkgo-root rootwait"

# The stock ABL picks the DTB by qcom,msm-id + qcom,board-id. The upstream DT
# has no board-id. With an invalid (zeroed) dtbo partition ABL skips the
# overlay and must match the boot.img DTB against the board itself, so use the
# board's id 0x22 (the stock board overlay's value), not the stock SoC DTB's <0 0>.
# Same value as the known-good ginkgo mainline image (Xlufoi/willow-mainline-kernel).
cp "$OUT/ginkgo.dtb" /tmp/ginkgo-boot.dtb
fdtput -t x /tmp/ginkgo-boot.dtb / qcom,board-id 0x22 0

# Bring-up: fixed USB peripheral role. With the PMI632 Type-C port in
# dual-role mode a Type-C-to-Type-C link to a computer can end up with the
# phone as host/source, and then no USB network appears. Disable Type-C role
# handling and VBUS output until charging/OTG are worked on.
USB=/soc@0/usb@4ef8800/usb@4e00000
PMIC=/soc@0/spmi@1c40000/pmic@2
fdtput -d /tmp/ginkgo-boot.dtb "$USB" usb-role-switch
fdtput -t s /tmp/ginkgo-boot.dtb "$USB" dr_mode peripheral
fdtput -t s /tmp/ginkgo-boot.dtb "$PMIC/typec@1500" status disabled
fdtput -t s /tmp/ginkgo-boot.dtb "$PMIC/usb-vbus-regulator@1100" status disabled
# DISPLAY=simplefb: fall back to the bootloader framebuffer only (simpledrm).
# The dispcc driver reconfigures disp_cc_pll0 at probe and takes over
# mdss_gdsc, which kills the continuous-splash pipeline, so without the MSM
# DSI display path dispcc (and mdss) must stay disabled.
if [ "${DISPLAY_MODE:-msm}" = simplefb ]; then
    fdtput -t s /tmp/ginkgo-boot.dtb /soc@0/clock-controller@5f00000 status disabled
    fdtput -t s /tmp/ginkgo-boot.dtb /soc@0/display-subsystem@5e00000 status disabled
fi
cp /tmp/ginkgo-boot.dtb "$OUT/ginkgo-boot.dtb"

# The bootloader refuses images whose os_version/patch level is older than the
# installed ROM (rollback protection). Match the ROM currently on the phone.
OS_VERSION=${OS_VERSION:-15.0.0}
OS_PATCH=${OS_PATCH:-2025-06}

mk() {
    mkbootimg --header_version 2 \
        --kernel "$OUT/Image.gz" --ramdisk "$OUT/initramfs.gz" --dtb /tmp/ginkgo-boot.dtb \
        --base 0x00000000 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
        --tags_offset 0x00000100 --dtb_offset 0x01f00000 --pagesize 4096 \
        --os_version "$OS_VERSION" --os_patch_level "$OS_PATCH" \
        --cmdline "$1" -o "$2"
}
mk "$CMDLINE" "$OUT/boot.img"
mk "$CMDLINE_BASE rescue" "$OUT/boot-rescue.img"
mk "$CMDLINE_BASE probe=recovery" "$OUT/boot-probe.img"

ls -lh "$OUT"/boot.img "$OUT"/boot-rescue.img

# ---- dtbo-zero.img ---------------------------------------------------------
# All zeros, exactly the size of the dtbo partition (24 MiB), so nothing of the
# old contents survives: no DTBO header (ABL then skips the overlay) and no
# stale AVB footer at the end of the partition. `fastboot erase dtbo` and a
# small no-op dtbo both got "The system has been destroyed" on this phone.
rm -f "$OUT/dtbo-noop.img" "$OUT/dtbo-zero.img"
truncate -s 25165824 "$OUT/dtbo-zero.img"
echo ">> boot images built"
