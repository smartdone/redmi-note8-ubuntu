# reference/ — material used during bring-up (not build inputs)

Only this README is tracked in git. Everything listed here was used to work out
hardware details (DT values, register maps, protocols); the kernel patches
and tools/patchgen/ scripts say which one each value came from.

| Path | What | Origin |
|---|---|---|
| `xlufoi-willow-mainline-v7.0-2026.11.07/` | Known-good mainline image for ginkgo (Huaxing panel): `boot.img`, `dtbo-empty.img` (24 MiB of zeros), `sm6125-xiaomi-ginkgo-huaxing.dtb` + decompiled `.dts`, `SHA256SUMS`. Source of the zeroed dtbo / board-id 0x22 fix and the display/backlight/touch/modem/Wi‑Fi DT layout. Its public source tree does not contain the panel, backlight or touch drivers. | https://github.com/Xlufoi/willow-mainline-kernel/releases/tag/v7.0-2026.11.07 |
| `lineage-sm6125-ft8719_spi_c3j/` | Downstream FocalTech FT8719 SPI touch driver (GPL), whole directory incl. `include/firmware/fw_huaxing_v0*.i`. Protocol reference for `kernel/patches/0003-*`. | LineageOS `android_kernel_xiaomi_sm6125` @ `8aaa002bfb7ba1cac2c02dbb42ae0259ef2e47ba` (`lineage-24.0`), `drivers/input/touchscreen/ft8719_spi_c3j` |
| `datasheets/KTD3136-04c.pdf` | Kinetic KTD3136 datasheet (Android's name for the backlight; the chip turned out to be an LM3697) | https://www.kinet-ic.com/uploads/KTD3136-04c.pdf |
| `datasheets/lm3697.pdf` | TI LM3697 datasheet (SNOSCS2D): feedback enables 0x19, boost/OVP 0x1A, full-scale current, exponential mapping formula | https://www.ti.com/lit/ds/symlink/lm3697.pdf |
| `mia3-postmarketos/` | Xiaomi Mi A3 (also SM6125) postmarketOS patches: WCN3990 Wi‑Fi node, MPSS for Wi‑Fi, pd-mapper; `ath10k-bdenc.py` (board-2.bin encoder), `extract-firmware.sh` | https://github.com/philipplinux/mia3-postmarketos |
| `downstream-ginkgo-max98937/max98937.{c,h}` | Vendor driver of the speaker amp (Android calls it max98927L; it is a MAX98937, rev 0x43 at 0x0600). Register map, init tables and the unmute sequence for `kernel/patches/0027-*` | https://github.com/tejas101k/kernel_xiaomi_ginkgo branch `fifteen`, `techpack/audio/asoc/codecs/max98937/` |
| `stock-dt/stock-boot-trinket.dts` | Decompiled DTB of the stock (LineageOS 22.2) `boot.img` of this phone | `backup/boot.img` |
| `stock-dt/stock-dtbo-overlay.dts` | Decompiled stock dtbo overlay (panels, touch `touchpad` on `qupv3_se2_spi`, icnss, …) | `backup/dtbo.img` |

Upstream discussions referenced in the log (not downloaded):

- `[PATCH RFC 00/10] arm64: qcom: sm6125-ginkgo: display, backlight, and touch support` (2026-09, Tianma NT36672A + KTD3136 variant)
- `[PATCH 0/2] ath10k: WCN3990 firmware workarounds for WLAN.HL.3.2` (2026-03, quiet mode crash) — https://ratatoskr.run/linux-wireless/2026/03/15793732/t
