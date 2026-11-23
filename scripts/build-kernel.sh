#!/bin/bash
# Build the mainline kernel for ginkgo. Runs inside the ginkgo-build container:
#   /src  = this repository (bind mount)
#   /work = docker volume (case-sensitive, holds the kernel tree)
set -euo pipefail

KSRC=/work/linux
KOUT=/work/kbuild
OUT=/src/out
JOBS=${JOBS:-$(nproc)}

cd "$KSRC"

# Apply our patches (if any) once, tracked by a stamp per patch.
if compgen -G "/src/kernel/patches/*.patch" >/dev/null; then
    for p in /src/kernel/patches/*.patch; do
        stamp="$KOUT/.applied-$(basename "$p")"
        [ -f "$stamp" ] && continue
        echo ">> applying $(basename "$p")"
        git apply "$p"
        mkdir -p "$KOUT" && touch "$stamp"
    done
fi

mkdir -p "$KOUT" "$OUT"
make O="$KOUT" ARCH=arm64 LOCALVERSION= defconfig
# The stock ABL has limited room for the decompressed kernel; drop every
# non-Qualcomm platform (and the drivers that depend on them).
for sym in $(grep -oE '^config ARCH_[A-Z0-9_]+' arch/arm64/Kconfig.platforms | cut -d' ' -f2); do
    [ "$sym" = ARCH_QCOM ] || scripts/config --file "$KOUT/.config" -d "$sym"
done
make O="$KOUT" ARCH=arm64 LOCALVERSION= olddefconfig >/dev/null
scripts/kconfig/merge_config.sh -m -O "$KOUT" "$KOUT/.config" /src/kernel/ginkgo.config
make O="$KOUT" ARCH=arm64 LOCALVERSION= olddefconfig

# Report fragment options that did not end up as requested.
missing=0
while IFS= read -r line; do
    case "$line" in ''|\#*) continue;; esac
    sym=${line%%=*}; val=${line#*=}
    if [ "$val" = "n" ]; then
        grep -q "^$sym=" "$KOUT/.config" && { echo "WARN: $sym should be off"; missing=1; }
    else
        grep -qx "$sym=$val" "$KOUT/.config" || { echo "WARN: $sym=$val not applied ($(grep "^$sym=" "$KOUT/.config" || echo unset))"; missing=1; }
    fi
done < /src/kernel/ginkgo.config
[ $missing = 0 ] && echo ">> config fragment fully applied"

make O="$KOUT" ARCH=arm64 LOCALVERSION= -j"$JOBS" Image.gz modules qcom/sm6125-xiaomi-ginkgo.dtb

KREL=$(cat "$KOUT/include/config/kernel.release")
rm -rf "$KOUT/modinst"
make O="$KOUT" ARCH=arm64 LOCALVERSION= INSTALL_MOD_PATH="$KOUT/modinst" INSTALL_MOD_STRIP=1 modules_install >/dev/null

cp "$KOUT/arch/arm64/boot/Image.gz" "$OUT/Image.gz"
cp "$KOUT/arch/arm64/boot/dts/qcom/sm6125-xiaomi-ginkgo.dtb" "$OUT/ginkgo.dtb"
cp "$KOUT/.config" "$OUT/kernel.config"
tar -C "$KOUT/modinst" -czf "$OUT/modules.tar.gz" lib
echo "$KREL" > "$OUT/kernel.release"
echo ">> kernel $KREL built"
