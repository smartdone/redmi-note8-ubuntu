# sources/ — every build input, kept locally

Only this README is tracked in git; the files are large or third-party.
`./get-sources.sh` (and `./build.sh`) run `scripts/fetch-sources.sh` and
`scripts/fetch-firmware.sh`, which verify what is here and download anything
missing. With this directory filled, the only network use
left is apt inside `build-rootfs.sh` (Ubuntu packages) and the Docker base
image `ubuntu:24.04`.

| File | What | Origin | sha256 |
|---|---|---|---|
| `linux-7.3.5.tar.xz` | Kernel source. Unpacked into the docker volume `ginkgo-work` (case-sensitive) by `build.sh`; identical to git tag `v7.3.5` (checked with `diff -r`). Our changes are `kernel/patches/*.patch`. | https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.5.tar.xz | `8f293f83d54f0b7b9be56863ebc5e4ea79d73e530b4ae55c572be97ef39f0990` |
| `linux.sha256` | checksum line for the tarball (pinned in `fetch-sources.sh`, same as kernel.org's) | https://cdn.kernel.org/pub/linux/kernel/v7.x/sha256sums.asc | |
| `mkbootimg-d2bb0af.tar.gz` | AOSP `mkbootimg`/`unpack_bootimg`, commit `d2bb0af5ba6d3198a3e99529c97eda1be0b5a093` (2025-03-02). Installed by `docker/Dockerfile`. | https://android.googlesource.com/platform/system/tools/mkbootimg | `4a627d3fa6c262ac832824fe63472be83052e7a9b02cc19787f0861f789ab8fb` |
| `rootfs-base-noble.tar` | debootstrap `--variant=minbase` base of Ubuntu 24.04 arm64 (systemd, udev, dbus, apt, ca-certificates, gnupg). Created by `build-rootfs.sh` when missing. | ports.ubuntu.com | `e4223e2bf5dc43f1affb637cdcfbd5fb441bbafa05e59cd43cda8a86660d0b8b` |
| `firmware/focaltech/ft8719_huaxing.bin` | FT8719 touch firmware v0x09 (Huaxing panel), converted from the C array in Xiaomi's GPL kernel by `scripts/fetch-firmware.sh` | LineageOS `android_kernel_xiaomi_sm6125` @ `f5bcc3d7`, `drivers/input/touchscreen/ft8719_spi_c3j/include/firmware/fw_huaxing_v09.i` | `7406fbcd395a3ef8dcab098377938bc3ad83096db1979798d49902926b995dfc` |
| `firmware/ath10k/WCN3990/hw1.0/firmware-5.bin` | ath10k feature container for WCN3990 | linux-firmware @ `b142c2e0229bc89b44ac527f4f3c3def063bcbc6` | `fef6539e0127579536bc977be57a90d018b83f2931fedc3a8870fbe38d6c4127` |
| `libssc-v0.4.4.tar.gz` | libssc + `ssccli`: Qualcomm Sensor Core (SSC) over QMI/QRTR. Built in the rootfs by `rootfs/sensors/build-sensors.sh` | https://codeberg.org/DylanVanAssche/libssc (tag v0.4.4) | `716d6bd6b34d2d753060c6b54c9a87e34fae75b724c763bf9ef487efa3621587` |
| `hexagonrpc-v0.5.0.tar.gz` | `hexagonrpcd`: FastRPC file server for the ADSP sensor PD | https://github.com/linux-msm/hexagonrpc (tag v0.5.0) | `2173985932ab68d8ac593f9954357123bdbbbe9ba5f1b17a098d9cbcec22c5d5` |
| `iio-sensor-proxy-3.9.tar.gz` | iio-sensor-proxy with `ssc-support` (noble ships 3.5 without), patched with `rootfs/sensors/iio-sensor-proxy-3.9-claim-during-startup.patch` | https://gitlab.freedesktop.org/hadess/iio-sensor-proxy (tag 3.9) | `af5edd307dcfa52dc3a242d13b7cc756e90a71640caf332efbad960e21649ae4` |
| `meson-1.7.2.tar.gz` | meson run from the tarball for the builds above (noble has 1.3.2; libssc needs newer) | https://github.com/mesonbuild/meson/releases/tag/1.7.2 | `4d40d63aa748a9c139cc41ab9bffe43edd113c5639d78bde81544ca955aea890` |
| `debs/libqrtr1_1.0-2ubuntu3_arm64.deb` | QRTR library | Ubuntu noble universe | `951ec1a2b0ba8f00f786b9cf205c748d677a0532a9dba1ed0e10da019fedc637` |
| `debs/qrtr-tools_1.0-2ubuntu3_arm64.deb` | `qrtr-lookup`, `qrtr-ns` | Ubuntu noble universe | `6a754262863ca6a805144d1dce4f1b829bc3d7a7e0e9683ffa3b6b060faa8629` |
| `debs/rmtfs_1.0-3_arm64.deb` | modem EFS server (modemst1/2, fsg) | Ubuntu noble universe | `7d7dc987985482e9a97f817031b218406dc3c5cd6f3379dbf7390a977e332a7d` |
| `debs/tqftpserv_1.0-5_arm64.deb` | TFTP-over-QRTR server for the modem | Ubuntu noble universe | `71f7bf0a95c0dfe79f4eb2c1f41b758bb763031061e78185003f20ba93525d5e` |

Not here on purpose:

- **Modem / WLAN firmware** (`modem.mdt`, `wlanmdsp.mbn`, `bdwlan.*`): signed for this
  phone, not redistributable. A copy pulled from the phone is in `../firmware/phone/`
  (also untracked); on the phone `ginkgo-modem-firmware.service` copies it from the
  `modem` partition at boot.
- **Sensor data** (`/vendor/etc/sensors`, the persist registry, the `dsp` partition):
  device-specific; copies are in `../firmware/phone/sensors-*` and `dsp-image/`,
  and `ginkgo-firmware.service` copies them from the partitions when missing.
- **Build outputs** go to `../out/`, the kernel tree and object files to the docker
  volume `ginkgo-work` (a cache: `docker volume rm ginkgo-work` and rebuild).
