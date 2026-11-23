#!/bin/bash
# Fetch device firmware that is not in linux-firmware. Runs inside the build
# container or on the host (get-sources.sh); results go to sources/firmware
# (not tracked in git).
#
# FT8719 touch (Huaxing panel): the controller has no flash, the driver
# downloads this image at every probe. Xiaomi ships it as a C array in the
# GPL vendor kernel; convert it back to a binary.
set -euo pipefail

FW=${FW_DIR:-$(cd "$(dirname "$0")/.." && pwd)/sources/firmware}
# GNU sha256sum (Linux), otherwise shasum (macOS: its own sha256sum lacks --status)
if sha256sum --version 2>/dev/null | grep -q GNU; then SHA256="sha256sum"; else SHA256="shasum -a 256"; fi
sha256() { $SHA256 "$@"; }
mkdir -p "$FW/focaltech"

TOUCH_BIN="$FW/focaltech/ft8719_huaxing.bin"
TOUCH_SHA=7406fbcd395a3ef8dcab098377938bc3ad83096db1979798d49902926b995dfc
TOUCH_URL=https://raw.githubusercontent.com/LineageOS/android_kernel_xiaomi_sm6125/f5bcc3d7a0243bd5f850617074157735b242e460/drivers/input/touchscreen/ft8719_spi_c3j/include/firmware/fw_huaxing_v09.i

if ! echo "$TOUCH_SHA  $TOUCH_BIN" | sha256 -c --status 2>/dev/null; then
    echo ">> fetching FT8719 touch firmware"
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/fw.i" "$TOUCH_URL"
    python3 -I - "$tmp/fw.i" "$TOUCH_BIN" <<'EOF'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
data = bytes(int(x, 16) for x in re.findall(r"0[xX]([0-9a-fA-F]{1,2})", open(src).read()))
n = (data[0x100] << 8) | data[0x101]
if n + ((data[0x102] << 8) | data[0x103]) != 0xFFFF:
    sys.exit("bad FT8719 firmware header")
open(dst, "wb").write(data)
EOF
    rm -rf "$tmp"
    echo "$TOUCH_SHA  $TOUCH_BIN" | sha256 -c --quiet
fi
# WCN3990 Wi-Fi (ath10k): firmware feature container from linux-firmware.
# The board data (board.bin) and the modem/WLAN firmware come from the phone's
# own modem partition at boot (see ginkgo-modem-firmware in build-rootfs.sh).
ATH_BIN="$FW/ath10k/WCN3990/hw1.0/firmware-5.bin"
ATH_SHA=fef6539e0127579536bc977be57a90d018b83f2931fedc3a8870fbe38d6c4127
ATH_URL="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/ath10k/WCN3990/hw1.0/firmware-5.bin?id=b142c2e0229bc89b44ac527f4f3c3def063bcbc6"
if ! echo "$ATH_SHA  $ATH_BIN" | sha256 -c --status 2>/dev/null; then
    echo ">> fetching ath10k WCN3990 firmware-5.bin"
    mkdir -p "$(dirname "$ATH_BIN")"
    curl -fsSL -o "$ATH_BIN" "$ATH_URL"
    echo "$ATH_SHA  $ATH_BIN" | sha256 -c --quiet
fi

# Adreno 610 (msm): command processor microcode from linux-firmware. The zap
# shader (a610_zap.*) is signed for this phone and comes from its vendor
# partition at boot (ginkgo-firmware in build-rootfs.sh).
SQE_BIN="$FW/qcom/a630_sqe.fw"
SQE_SHA=1c21b527d9183487cc550dabbb3f43e555df5a977a461934fc61f0635a9aa90c
SQE_URL="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/qcom/a630_sqe.fw?id=75f16899bd8e2137635091b766122e984c6e0a65"
if ! echo "$SQE_SHA  $SQE_BIN" | sha256 -c --status 2>/dev/null; then
    echo ">> fetching Adreno a630_sqe.fw"
    mkdir -p "$(dirname "$SQE_BIN")"
    curl -fsSL -o "$SQE_BIN" "$SQE_URL"
    echo "$SQE_SHA  $SQE_BIN" | sha256 -c --quiet
fi

echo ">> firmware ready in sources/firmware"
