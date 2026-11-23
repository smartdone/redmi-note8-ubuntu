#!/bin/bash
# Build an Ubuntu 24.04 (noble) arm64 root filesystem image for ginkgo.
# Runs inside the (arm64, privileged) ginkgo-build container, so no qemu is needed.
#   DESKTOP=1 (default) installs GNOME, DESKTOP=0 a console-only system.
set -euo pipefail

SUITE=noble
MIRROR=http://ports.ubuntu.com/ubuntu-ports
OUT=/src/out
ROOT=/work/rootfs
BASE_CACHE=/src/sources/rootfs-base-$SUITE.tar
DESKTOP=${DESKTOP:-1}
IMG_SIZE=$([ "$DESKTOP" = 1 ] && echo 7G || echo 3G)

[ -f "$OUT/modules.tar.gz" ] || { echo "run ./build.sh kernel first"; exit 1; }
[ -s /src/config/authorized_keys ] || { echo "missing config/authorized_keys"; exit 1; }

cleanup() {
    for m in dev/pts dev proc sys run; do umount -l "$ROOT/$m" 2>/dev/null || true; done
}
trap cleanup EXIT

# ---- base system (cached) --------------------------------------------------
rm -rf "$ROOT" && mkdir -p "$ROOT"
if [ -f "$BASE_CACHE" ]; then
    echo ">> using cached debootstrap base"
    tar -C "$ROOT" -xpf "$BASE_CACHE"
else
    debootstrap --arch=arm64 --variant=minbase \
        --include=systemd,systemd-sysv,udev,dbus,apt,ca-certificates,gnupg \
        "$SUITE" "$ROOT" "$MIRROR"
    tar -C "$ROOT" -cpf "$BASE_CACHE" .
fi

mount --bind /dev "$ROOT/dev"
mount --bind /dev/pts "$ROOT/dev/pts"
mount -t proc proc "$ROOT/proc"
mount -t sysfs sysfs "$ROOT/sys"
mount -t tmpfs tmpfs "$ROOT/run"

cat > "$ROOT/etc/apt/sources.list.d/ubuntu.sources" <<EOF
Types: deb
URIs: $MIRROR
Suites: $SUITE $SUITE-updates $SUITE-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
rm -f "$ROOT/etc/apt/sources.list"
echo "nameserver 1.1.1.1" > "$ROOT/etc/resolv.conf"

# Never start services inside the chroot.
printf '#!/bin/sh\nexit 101\n' > "$ROOT/usr/sbin/policy-rc.d"
chmod +x "$ROOT/usr/sbin/policy-rc.d"

PKGS="ubuntu-minimal openssh-server sudo nano less vim-tiny bash-completion \
    iproute2 iputils-ping network-manager wpasupplicant wireless-regdb \
    systemd-resolved systemd-timesyncd systemd-zram-generator \
    kmod e2fsprogs parted usbutils pciutils htop locales tzdata \
    evtest i2c-tools device-tree-compiler iw \
    rmtfs tqftpserv qrtr-tools bluez alsa-utils alsa-ucm-conf"
if [ "$DESKTOP" = 1 ]; then
    PKGS="$PKGS gdm3 gnome-shell gnome-session ubuntu-session gnome-terminal \
        nautilus gnome-control-center gnome-text-editor gnome-system-monitor \
        yaru-theme-gtk yaru-theme-icon yaru-theme-gnome-shell yaru-theme-sound \
        fonts-noto-core fonts-noto-cjk fonts-noto-color-emoji \
        xdg-user-dirs-gtk gsettings-desktop-schemas dconf-cli \
        mesa-utils pipewire wireplumber gnome-screenshot libnotify-bin eog \
        gnome-menus"
    # Firefox from Mozilla's APT repository (native arm64 deb); Ubuntu's own
    # firefox package is a snap wrapper and snapd needs AppArmor. Repository
    # files and the signing key are in rootfs/firefox/.
    install -D -m 0644 /src/rootfs/firefox/packages.mozilla.org.asc \
        "$ROOT/etc/apt/keyrings/packages.mozilla.org.asc"
    install -m 0644 /src/rootfs/firefox/mozilla.sources "$ROOT/etc/apt/sources.list.d/mozilla.sources"
    install -D -m 0644 /src/rootfs/firefox/mozilla.pref "$ROOT/etc/apt/preferences.d/mozilla"
    PKGS="$PKGS firefox"
fi

chroot "$ROOT" /bin/bash -euo pipefail <<EOF
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
apt-get update
apt-get -y upgrade
apt-get install -y --no-install-recommends $PKGS
apt-get clean
EOF

# ---- kernel modules --------------------------------------------------------
KREL=$(cat "$OUT/kernel.release")
rm -rf "$ROOT/usr/lib/modules"
tar -C "$ROOT/usr" -xzf "$OUT/modules.tar.gz"
# Device firmware that is not in linux-firmware (see fetch-firmware.sh).
bash /src/scripts/fetch-firmware.sh
mkdir -p "$ROOT/usr/lib/firmware"
cp -r /src/sources/firmware/. "$ROOT/usr/lib/firmware/"
# This phone's signed firmware, if it was pulled into firmware/phone/ (local
# only, not redistributable). Without it, ginkgo-firmware.service copies it
# from the modem/vendor partitions at first boot.
if [ -f /src/firmware/phone/modem-image/modem.mdt ]; then
    install -d "$ROOT/usr/lib/firmware/qcom/sm6125/xiaomi/ginkgo" "$ROOT/usr/lib/firmware/ath10k/WCN3990/hw1.0"
    cp -r /src/firmware/phone/modem-image/. "$ROOT/usr/lib/firmware/qcom/sm6125/xiaomi/ginkgo/"
    cp /src/firmware/phone/modem-image/bdwlan.bin "$ROOT/usr/lib/firmware/ath10k/WCN3990/hw1.0/board.bin"
fi
if [ -d /src/firmware/phone/bluetooth-image ]; then
    install -d "$ROOT/usr/lib/firmware/qca"
    cp /src/firmware/phone/bluetooth-image/* "$ROOT/usr/lib/firmware/qca/"
fi
if [ -f /src/firmware/phone/vendor-firmware/a610_zap.mdt ]; then
    install -d "$ROOT/usr/lib/firmware/qcom/sm6125/xiaomi/ginkgo"
    cp /src/firmware/phone/vendor-firmware/a610_zap.* "$ROOT/usr/lib/firmware/qcom/sm6125/xiaomi/ginkgo/"
fi
chroot "$ROOT" depmod -a "$KREL"

# ---- system configuration --------------------------------------------------
echo ginkgo > "$ROOT/etc/hostname"
cat > "$ROOT/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 ginkgo
::1 localhost ip6-localhost ip6-loopback
EOF

cat > "$ROOT/etc/fstab" <<EOF
LABEL=ginkgo-root / ext4 defaults,noatime,x-systemd.growfs 0 1
EOF

sed -i 's/^# *\(en_US.UTF-8\)/\1/; s/^# *\(zh_CN.UTF-8\)/\1/' "$ROOT/etc/locale.gen"
chroot "$ROOT" locale-gen
echo 'LANG=en_US.UTF-8' > "$ROOT/etc/default/locale"
ln -sf /usr/share/zoneinfo/Asia/Shanghai "$ROOT/etc/localtime"

# zram swap, half of RAM, zstd
cat > "$ROOT/etc/systemd/zram-generator.conf" <<EOF
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF

# USB network: phone 172.16.42.1, DHCP gives the host 172.16.42.2.
# systemd-networkd owns usb0, NetworkManager handles everything else (Wi-Fi later).
mkdir -p "$ROOT/etc/systemd/network" "$ROOT/etc/NetworkManager/conf.d"
cat > "$ROOT/etc/systemd/network/50-usb0.network" <<EOF
[Match]
Name=usb0

[Network]
Address=172.16.42.1/24
DHCPServer=yes
ConfigureWithoutCarrier=yes

[DHCPServer]
PoolOffset=2
PoolSize=1
# Only give the host an address. With a router/DNS option the host (macOS
# orders new USB network services above Wi-Fi) routes all its traffic here.
EmitRouter=no
EmitDNS=no
EOF
cat > "$ROOT/etc/NetworkManager/conf.d/10-unmanage-usb0.conf" <<EOF
[keyfile]
unmanaged-devices=interface-name:usb0
EOF
chroot "$ROOT" systemctl enable systemd-networkd systemd-resolved ssh
ln -sf /run/systemd/resolve/stub-resolv.conf "$ROOT/etc/resolv.conf"

# User "ubuntu": SSH key login only, no password, passwordless sudo.
chroot "$ROOT" useradd -m -s /bin/bash -G sudo,video,audio,input,render,plugdev,netdev ubuntu 2>/dev/null \
    || chroot "$ROOT" useradd -m -s /bin/bash -G sudo,video,audio,input ubuntu
chroot "$ROOT" passwd -l ubuntu
chroot "$ROOT" passwd -l root
echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > "$ROOT/etc/sudoers.d/90-ubuntu"
chmod 0440 "$ROOT/etc/sudoers.d/90-ubuntu"
install -d -m 700 -o 1000 -g 1000 "$ROOT/home/ubuntu/.ssh"
install -m 600 -o 1000 -g 1000 /src/config/authorized_keys "$ROOT/home/ubuntu/.ssh/authorized_keys"
cat > "$ROOT/etc/ssh/sshd_config.d/10-ginkgo.conf" <<EOF
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
# Host keys are generated on the phone at first boot, not baked into the image.
rm -f "$ROOT"/etc/ssh/ssh_host_*
mkdir -p "$ROOT/etc/systemd/system/ssh.service.d"
# Drop-in ExecStartPre lines are appended after the stock "sshd -t", which fails
# without host keys, so reset the list and generate the keys first.
cat > "$ROOT/etc/systemd/system/ssh.service.d/keygen.conf" <<EOF
[Service]
ExecStartPre=
ExecStartPre=/usr/bin/ssh-keygen -A
ExecStartPre=/usr/sbin/sshd -t
EOF
# Ubuntu 24.04 uses socket activation for ssh; use the plain service instead.
chroot "$ROOT" systemctl disable ssh.socket 2>/dev/null || true

# Signed firmware (modem/Wi-Fi on the modem DSP, GPU zap shader) cannot be
# redistributed, so copy it from the phone's own `modem` and `vendor`
# partitions at boot (only when it changed) and start the modem remoteproc.
# rmtfs gives the modem its EFS (modemst1/2, fsg), tqftpserv serves it files.
cat > "$ROOT/usr/local/sbin/ginkgo-firmware" <<'EOF'
#!/bin/sh
# Install signed firmware from the stock `modem` and `vendor` partitions (read-only).
set -eu
FW=/usr/lib/firmware/qcom/sm6125/xiaomi/ginkgo
ATH=/usr/lib/firmware/ath10k/WCN3990/hw1.0
mnt=$(mktemp -d)
trap 'umount "$mnt" 2>/dev/null; rmdir "$mnt"' EXIT
mkdir -p "$FW"
mount -o ro /dev/disk/by-partlabel/modem "$mnt"
if ! cmp -s "$mnt/image/modem.mdt" "$FW/modem.mdt"; then
    cp "$mnt"/image/modem.* "$mnt"/image/modem*.jsn "$mnt"/image/wlanmdsp.mbn \
       "$mnt"/image/bdwlan.* "$FW/"
    echo "modem firmware installed"
fi
# audio DSP (ADSP), started by the kernel once the file is there
if ! cmp -s "$mnt/image/adsp.mdt" "$FW/adsp.mdt"; then
    cp "$mnt"/image/adsp.* "$mnt"/image/adsp*.jsn "$FW/"
    echo "adsp firmware installed"
fi
umount "$mnt"
# Adreno 610 zap shader
mount -o ro /dev/disk/by-partlabel/vendor "$mnt"
if ! cmp -s "$mnt/firmware/a610_zap.mdt" "$FW/a610_zap.mdt"; then
    cp "$mnt"/firmware/a610_zap.mdt "$mnt"/firmware/a610_zap.b0* "$FW/"
    echo "GPU zap shader installed"
fi
umount "$mnt"
# Bluetooth (WCN39xx Comanche): cmbtfw*/cmnv* (+ apbtfw*/apnv*) for btqca
mount -o ro /dev/disk/by-partlabel/bluetooth "$mnt"
mkdir -p /usr/lib/firmware/qca
for f in "$mnt"/image/*; do
    cmp -s "$f" "/usr/lib/firmware/qca/$(basename "$f")" || { cp "$f" /usr/lib/firmware/qca/; echo "installed qca/$(basename "$f")"; }
done
# Sensors (ADSP sensor PD, served by hexagonrpcd): vendor configs, the
# persist registry and the dsp partition. Copied once: the DSP may update
# the registry afterwards.
QC=/usr/share/qcom/sm6125/Xiaomi/ginkgo
if [ ! -d "$QC/sensors/registry" ]; then
    mkdir -p "$QC/sensors"
    mount -o ro /dev/disk/by-partlabel/vendor "$mnt"
    cp -r "$mnt/etc/sensors/config" "$QC/sensors/config"
    cp "$mnt/etc/sensors/sns_reg_config" "$QC/sensors/sns_reg.conf"
    umount "$mnt"
    mount -o ro /dev/disk/by-partlabel/persist "$mnt"
    cp -r "$mnt/sensors/registry/registry" "$QC/sensors/registry"
    umount "$mnt"
    mount -o ro /dev/disk/by-partlabel/dsp "$mnt"
    mkdir -p "$QC/dsp" && cp -r "$mnt"/adsp "$mnt"/cdsp "$QC/dsp/"
    umount "$mnt"
    chown -R fastrpc:fastrpc "$QC/sensors/registry"
    echo "sensor configuration installed"
fi
# The WLAN OTP reports board id 0xff: its board data is bdwlan.bin.
mkdir -p "$ATH"
cmp -s "$FW/bdwlan.bin" "$ATH/board.bin" || cp "$FW/bdwlan.bin" "$ATH/board.bin"
# The remoteprocs tried to boot before the firmware existed: start them now.
for r in /sys/class/remoteproc/remoteproc*; do
    case "$(cat "$r/name")" in modem|adsp) ;; *) continue ;; esac
    [ "$(cat "$r/state")" = offline ] && echo start > "$r/state" || true
done
EOF
chmod 0755 "$ROOT/usr/local/sbin/ginkgo-firmware"
cat > "$ROOT/etc/systemd/system/ginkgo-firmware.service" <<EOF
[Unit]
Description=Install signed modem/Wi-Fi/GPU/Bluetooth firmware from the stock partitions
After=local-fs.target systemd-modules-load.service
Before=rmtfs.service tqftpserv.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ginkgo-firmware

[Install]
WantedBy=multi-user.target
EOF
chroot "$ROOT" systemctl enable ginkgo-firmware rmtfs tqftpserv

# ---- sensors (accelerometer etc. on the ADSP sensor PD, see rootfs/sensors/) -
# hexagonrpcd serves the sensor config/registry to the DSP over FastRPC,
# libssc talks to the SSC over QMI, iio-sensor-proxy (SSC build, with a
# startup race fix) feeds GNOME's auto-rotate.
chroot "$ROOT" sh -c 'getent group fastrpc >/dev/null || groupadd -r fastrpc;
    getent passwd fastrpc >/dev/null || useradd -r -g fastrpc -d /nonexistent -s /usr/sbin/nologin fastrpc'
rm -rf "$ROOT/tmp/sensors"; mkdir -p "$ROOT/tmp/sensors"
for t in meson-1.7.2 libssc-v0.4.4 hexagonrpc-v0.5.0 iio-sensor-proxy-3.9; do
    tar -C "$ROOT/tmp/sensors" -xzf "/src/sources/$t.tar.gz"
done
cp /src/rootfs/sensors/iio-sensor-proxy-3.9-claim-during-startup.patch \
   /src/rootfs/sensors/build-sensors.sh "$ROOT/tmp/sensors/"
chroot "$ROOT" /bin/bash /tmp/sensors/build-sensors.sh
rm -rf "$ROOT/tmp/sensors"
install -m 0644 /src/rootfs/sensors/hexagonrpcd-ginkgo-sensorspd.service "$ROOT/etc/systemd/system/"
install -m 0644 /src/rootfs/sensors/79-ginkgo-sensors.rules "$ROOT/etc/udev/rules.d/"
QC="$ROOT/usr/share/qcom/sm6125/Xiaomi/ginkgo"
mkdir -p "$QC"
ln -sfn /sys/devices/soc0 "$QC/socinfo"
# Local copy of this phone's sensor data (not redistributable); otherwise
# ginkgo-firmware.service copies it from the stock partitions at first boot.
if [ -d /src/firmware/phone/sensors-persist/registry/registry ]; then
    mkdir -p "$QC/sensors"
    cp -r /src/firmware/phone/sensors-vendor/config "$QC/sensors/config"
    cp /src/firmware/phone/sensors-vendor/sns_reg_config "$QC/sensors/sns_reg.conf"
    cp -r /src/firmware/phone/sensors-persist/registry/registry "$QC/sensors/registry"
    cp -r /src/firmware/phone/dsp-image "$QC/dsp"
    chroot "$ROOT" chown -R fastrpc:fastrpc /usr/share/qcom/sm6125/Xiaomi/ginkgo/sensors/registry
fi
chroot "$ROOT" systemctl enable hexagonrpcd-ginkgo-sensorspd

# Stable addresses. The WCN39xx has no Bluetooth/Wi-Fi address of its own
# (Android reads them from modem NV over QMI): Bluetooth comes up unconfigured
# and ath10k picks a random MAC on every boot. Give Bluetooth a fixed,
# locally administered address derived from the board serial number, and let
# NetworkManager use a stable per-network Wi-Fi MAC (stable DHCP lease).
cat > "$ROOT/usr/local/sbin/ginkgo-bt-address" <<'EOF'
#!/bin/sh
set -eu
serial=$(sed -n 's/.*androidboot.serialno=\([^ ]*\).*/\1/p' /proc/cmdline)
[ -n "$serial" ] || serial=$(cat /etc/machine-id)
h=$(printf 'ginkgo-bt-%s' "$serial" | sha256sum | cut -c1-10)
addr=$(printf '02:%s:%s:%s:%s:%s' $(echo "$h" | sed 's/../& /g'))
for i in $(seq 1 20); do [ -e /sys/class/bluetooth/hci0 ] && break; sleep 1; done
# only an unconfigured (RAW) controller takes a new public address
hciconfig hci0 2>/dev/null | grep -q RAW || exit 0
# btmgmt (bt_shell) hangs on EOF stdin; give it a pipe that stays open
sleep 5 | timeout 10 btmgmt --timeout 3 --index 0 public-addr "$addr"
EOF
chmod 0755 "$ROOT/usr/local/sbin/ginkgo-bt-address"
cat > "$ROOT/etc/systemd/system/ginkgo-bt-address.service" <<EOF
[Unit]
Description=Set a stable Bluetooth address (WCN39xx has none)
After=bluetooth.service
Wants=bluetooth.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ginkgo-bt-address

[Install]
WantedBy=multi-user.target
EOF
chroot "$ROOT" systemctl enable ginkgo-bt-address
cat > "$ROOT/etc/NetworkManager/conf.d/20-ginkgo-wifi-mac.conf" <<EOF
[connection-wifi]
match-device=interface-name:wlan0
wifi.cloned-mac-address=stable
EOF

# led-backlight registers powered off and waits for a DRM panel driver to turn
# it on. With simpledrm there is none, so power it on when it appears.
cat > "$ROOT/etc/udev/rules.d/60-ginkgo-backlight.rules" <<EOF
ACTION=="add", SUBSYSTEM=="backlight", KERNEL=="backlight", ATTR{bl_power}="0"
EOF

# Machine id is generated at first boot.
: > "$ROOT/etc/machine-id"

if [ "$DESKTOP" = 1 ]; then
    # No working touchscreen yet: log in automatically so the desktop is visible.
    mkdir -p "$ROOT/etc/gdm3"
    cat > "$ROOT/etc/gdm3/custom.conf" <<EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=ubuntu
# Automatic login only happens once per GDM start; after "Log Out" the
# greeter would ask for a password the ubuntu account does not have.
TimedLoginEnable=true
TimedLogin=ubuntu
TimedLoginDelay=1
WaylandEnable=true
EOF
    # Phone-friendly defaults: scaling, on-screen keyboard, screen off after
    # 2 min idle, suspend (s2idle) 3 min idle on battery; never on AC so a USB
    # development session stays up.
    mkdir -p "$ROOT/etc/dconf/db/local.d" "$ROOT/etc/dconf/profile"
    printf 'user-db:user\nsystem-db:local\n' > "$ROOT/etc/dconf/profile/user"
    cat > "$ROOT/etc/dconf/db/local.d/00-ginkgo" <<EOF
[org/gnome/desktop/interface]
# 2x: 540 logical px wide; at 3x (360 px) the quick settings menu does not fit
scaling-factor=uint32 2
show-battery-percentage=true
text-scaling-factor=1.0

[org/gnome/shell]
enabled-extensions=['screen-shape@ginkgo-ubuntu']

[org/gnome/desktop/a11y/applications]
screen-keyboard-enabled=true

[org/gnome/desktop/session]
idle-delay=uint32 120

[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='suspend'
sleep-inactive-battery-timeout=180
# the power key is handled by ginkgo-keys (screen off + suspend, screenshot)
power-button-action='nothing'

[org/gnome/desktop/screensaver]
# the ubuntu account has no password (SSH keys only): a lock screen could
# never be unlocked. Ubuntu's own lock-on-suspend key is separate from
# lock-enabled and locks on every suspend.
lock-enabled=false
ubuntu-lock-on-suspend=false
EOF
    # Keep the top bar clear of the notch and rounded corners (see
    # rootfs/gnome-shell-extensions/; panel shape in rootfs/display-panels/).
    install -d "$ROOT/usr/share/gnome-shell/extensions" "$ROOT/usr/share/display-panels"
    cp -r /src/rootfs/gnome-shell-extensions/. "$ROOT/usr/share/gnome-shell/extensions/"
    cp /src/rootfs/display-panels/*.json "$ROOT/usr/share/display-panels/"
    # ALSA UCM for the sound card (DSP routing to the speaker amp), see
    # rootfs/alsa-ucm2/; PipeWire/WirePlumber pick it up.
    cp -r /src/rootfs/alsa-ucm2/. "$ROOT/usr/share/alsa/ucm2/"
    # Phone keys: power = screen off + suspend / wake, hold = power-off dialog,
    # volume down + power = screenshot (rootfs/ginkgo-keys/).
    install -m 0755 /src/rootfs/ginkgo-keys/ginkgo-keys "$ROOT/usr/local/bin/ginkgo-keys"
    install -m 0644 /src/rootfs/ginkgo-keys/ginkgo-keys.service "$ROOT/usr/lib/systemd/user/ginkgo-keys.service"
    install -D -m 0644 /src/rootfs/ginkgo-keys/logind-power-key.conf "$ROOT/etc/systemd/logind.conf.d/10-ginkgo-power-key.conf"
    chroot "$ROOT" systemctl --global enable ginkgo-keys.service
    chroot "$ROOT" dconf update
    chroot "$ROOT" systemctl set-default graphical.target
else
    chroot "$ROOT" systemctl set-default multi-user.target
fi

rm -f "$ROOT/usr/sbin/policy-rc.d"
cleanup
trap - EXIT

# ---- image -----------------------------------------------------------------
IMG=/work/rootfs.img
rm -f "$IMG"
truncate -s "$IMG_SIZE" "$IMG"
mkfs.ext4 -q -L ginkgo-root -d "$ROOT" "$IMG"
e2fsck -fy "$IMG" >/dev/null || true
img2simg "$IMG" "$OUT/rootfs.simg"
ls -lh "$OUT/rootfs.simg"
echo ">> rootfs built (sparse image: out/rootfs.simg, raw image in docker volume: $IMG)"
