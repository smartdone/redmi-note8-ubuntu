# Ubuntu 24.04 on Redmi Note 8 (ginkgo), mainline Linux

Native Ubuntu (not Ubuntu Touch, no Android/Halium underneath) on the
Xiaomi Redmi Note 8 (`ginkgo`, Snapdragon 665 / SM6125), using the upstream
device tree `sm6125-xiaomi-ginkgo.dts` that is in Linux since 2025.

Status: **bring-up, daily-usable desktop**: GNOME with GPU acceleration,
touch, Wi‑Fi, Bluetooth, battery, suspend, speaker and auto-rotate work;
see the table for what is missing. Tested on a Redmi Note 8 with the Huaxing
FT8719 panel.

## What works

| Part | State | Notes |
|---|---|---|
| Boot | stock bootloader → boot.img → initramfs → Ubuntu | `fastboot boot`, nothing flashed to boot |
| Display | MSM DPU + DSI + Huaxing FT8719 panel driver, GNOME at 2x | top bar kept clear of the notch/corners by the screen-shape extension |
| GPU | Adreno 610, Mesa freedreno (FD610) | zap shader copied from the vendor partition at boot |
| CPU | cpufreq-hw, schedutil | little 0.3–1.8 GHz, big 0.3–2.0 GHz |
| Backlight | LM3697 (Android calls it ktd3136) | `/sys/class/backlight/backlight`, 0–2047 |
| Touch | FocalTech FT8719 over SPI, own driver | firmware fetched by `scripts/fetch-firmware.sh` |
| USB network | CDC-NCM, phone `172.16.42.1` | SSH as `ubuntu`, key only |
| Rescue shell | `telnet 172.16.42.1` from the initramfs | if root not found or `boot-rescue.img` |
| Storage | eMMC, microSD | |
| Buttons, vibrator | in upstream DT | phone-style keys (`ginkgo-keys`): Power = screen off + suspend / wake, hold = power-off dialog, Vol-down + Power = screenshot |
| Wi‑Fi | WCN3990 (ath10k) via the modem DSP | modem firmware copied from the phone's `modem` partition at boot; stable per-network MAC |
| Battery | read-only PMI632 QG/SMB5 monitor, stock ATL profile | charging stays under the PMIC's boot-time settings |
| Bluetooth | WCN39xx (Comanche) over UART, `qcom,wcn3950-bt` | firmware from the bluetooth partition; stable address from the serial number |
| Suspend | s2idle (no PSCI SYSTEM_SUSPEND), CPU/cluster power collapse via PSCI OSI | Power key suspends (only blanks while a computer is on USB); Power wakes; 3 min idle on battery |
| Speaker | ADSP (q6 APR) + MAX98937 amp on primary MI2S, own driver | Android calls the amp max98927L; UCM profile in `rootfs/alsa-ucm2/`, PipeWire sink "Speaker" |
| Sensors, auto-rotate | BMI160 accel, stk3x3x light/proximity, ak0991x compass on the ADSP sensor PD (SSC) | hexagonrpcd + libssc + iio-sensor-proxy (SSC build), see `rootfs/sensors/`; GNOME auto-rotate works |
| Headphones, microphones, cellular, camera | **not yet** | stage 2+ |

## Sources and versions

Third-party sources are not in this repository; `./get-sources.sh` downloads
the exact versions below into `sources/` and checks each against a pinned
sha256 (`./build.sh` does the same automatically, so this step is optional,
e.g. to prepare an offline build):

```sh
./get-sources.sh                       # download + verify everything
./get-sources.sh --list                # print the pinned versions
./get-sources.sh --kernel-tree ../ginkgo-linux   # + patched kernel tree to read or build
```

| Component | Version | Upstream | Our changes |
|---|---|---|---|
| Linux | 7.3.5 (stable tarball) | https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.5.tar.xz | `kernel/patches/` (28 patches: DT for display, GPU, modem/Wi‑Fi, Bluetooth, battery, audio, FastRPC, CPU idle; new drivers for the Huaxing FT8719 panel, FT8719 SPI touch, PMI632 battery monitor, MAX98937 amp; fixes for ath10k, dwc3, geni serial, q6asm), config fragment `kernel/ginkgo.config` |
| Ubuntu | 24.04 LTS (noble), arm64 | ports.ubuntu.com (debootstrap + apt at build time) | `scripts/build-rootfs.sh`, `rootfs/` |
| AOSP mkbootimg | commit `d2bb0af5ba6d` | https://android.googlesource.com/platform/system/tools/mkbootimg | — |
| libssc | 0.4.4 | https://codeberg.org/DylanVanAssche/libssc | — |
| hexagonrpc (hexagonrpcd) | 0.5.0 | https://github.com/linux-msm/hexagonrpc | — |
| iio-sensor-proxy | 3.9, `-Dssc-support=enabled` | https://gitlab.freedesktop.org/hadess/iio-sensor-proxy | `rootfs/sensors/iio-sensor-proxy-3.9-claim-during-startup.patch` |
| meson (build tool for the three above) | 1.7.2 | https://github.com/mesonbuild/meson | — |
| FT8719 touch firmware | v0x09 (Huaxing) | LineageOS `android_kernel_xiaomi_sm6125` @ `f5bcc3d7` (converted from the GPL C array) | — |
| ath10k `firmware-5.bin` (WCN3990) | linux-firmware @ `b142c2e0` | https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git | — |
| Adreno `a630_sqe.fw` | linux-firmware @ `75f16899` | same | — |

File names, checksums and details: [`sources/README.md`](sources/README.md).
Not downloadable and not needed at build time: the phone's own signed
firmware (modem, Wi‑Fi board data, ADSP, GPU zap shader, Bluetooth) and
sensor configuration. They are copied from the stock Android partitions on
first boot by `ginkgo-firmware.service`, so keep those partitions intact.

## Build (macOS with Docker, Apple Silicon builds natively)

```sh
./build.sh kernel   # ~1 h first time: kernel 7.3.5 + ginkgo dtb + modules
./build.sh rootfs   # Ubuntu 24.04 + GNOME image (DESKTOP=0 for console only)
./build.sh boot     # initramfs + out/boot.img, out/boot-rescue.img
```

Kernel source and the rootfs tree live in the docker volume `ginkgo-work`
(case-sensitive filesystem). Results go to `out/`.
The phone login key is copied from `~/.ssh/id_ed25519.pub` to `config/authorized_keys`.

## Install

Requirements: unlocked bootloader, phone in fastboot (Power + Vol-down).

1. **Test boot without flashing anything** (rescue initramfs, Android untouched
   except for step 2):

   ```sh
   fastboot boot out/boot-rescue.img
   # on the Mac: the phone shows up as a USB network interface
   telnet 172.16.42.1
   ```

2. The stock bootloader applies the Android `dtbo` overlay to every DT it
   boots, which breaks the mainline DT. On ginkgo, `fastboot erase dtbo` gives
   "The system has been destroyed"; overwrite the whole partition with zeros
   instead: `fastboot flash dtbo out/dtbo-zero.img`. Android will not boot
   until you flash `backup/dtbo.img` again.

3. Root filesystem, pick one:
   - **userdata** (erases all Android data):
     `fastboot flash userdata out/rootfs.simg`
   - **microSD**: write the raw image to the card
     (`simg2img out/rootfs.simg rootfs.img`, then `dd` to the card).

4. Boot Ubuntu: `fastboot boot out/boot.img`, then `ssh ubuntu@172.16.42.1`.
   Once it works reliably, `fastboot flash boot out/boot.img` makes it permanent
   (recovery and Android need their own boot.img again afterwards).

## Layout

```
build.sh                 host entry point (runs everything in Docker)
get-sources.sh           download + verify all pinned sources (optional: patched kernel tree)
docker/Dockerfile        build environment (Ubuntu 24.04 arm64)
kernel/VERSION           pinned kernel tag
kernel/ginkgo.config     config fragment on top of arm64 defconfig
kernel/patches/          our kernel patches (applied in order)
initramfs/init           busybox init: USB net, telnet rescue, switch_root
scripts/                 build-kernel.sh, build-rootfs.sh, build-boot.sh,
                         fetch-sources.sh, fetch-firmware.sh
sources/                 all build inputs, local copies (kernel tarball, mkbootimg,
                         rootfs base, firmware, debs); see sources/README.md
reference/               material used during bring-up (reference images,
                         downstream drivers, datasheets); see reference/README.md
firmware/phone/          this phone's modem/Wi-Fi firmware (local only)
rootfs/                  files installed into the rootfs: display-panels/ (notch and
                         corner data), gnome-shell-extensions/screen-shape@ginkgo-ubuntu,
                         ginkgo-keys/ (power key + screenshot user service),
                         alsa-ucm2/ (sound card use case profile),
                         sensors/ (hexagonrpcd unit, udev rule, sensor stack build)
tools/                   phone helpers: pssh (SSH), psh (rescue telnet),
                         fastboot-boot, reboot-into, deploy-modules;
                         phone/ (debug helpers run on the phone: GPIO v2, amp regs)
tools/patchgen/          generators and sources for kernel/patches/ (DT edits,
                         new drivers), so patches can be regenerated
```

Nothing is kept outside this directory except the docker image `ginkgo-build`
and the docker volume `ginkgo-work` (kernel tree + objects, rootfs tree). Both
are caches rebuilt from this directory: the kernel tree must live on a
case-sensitive file system, which the default macOS volume is not.

Typical loop after changing a kernel patch:

```sh
./build.sh kernel && ./build.sh boot
tools/deploy-modules            # matching modules into the running phone
tools/reboot-into out/boot.img  # fastboot boot + wait for SSH
tools/pssh 'dmesg | tail'
```

## Roadmap

1. Boot + USB SSH (this stage)
2. Touchscreen (panel vendor varies: check `/proc/cmdline` of Android for `dsi_` panel name)
3. Battery / charger (PMI632 fuel gauge)
4. Wi‑Fi (WCN3990, needs remoteprocs + firmware from the vendor partition)
5. Real panel driver (DSI) + Adreno 610 GPU
6. Audio, sensors, modem
