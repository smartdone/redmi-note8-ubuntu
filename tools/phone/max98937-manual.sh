#!/bin/sh
# max98937-manual.sh [REGS]: program the ginkgo MAX98937 by hand over I2C
# (bus 0, 0x3a) the way the downstream driver does for 16-bit/48 kHz I2S
# slave playback, then enable it. For bring-up tests while a stream runs.
set -eu
REGS=${1:-/tmp/max98937-regs.txt}
w() { i2ctransfer -f -y 0 w3@0x3a $(printf '0x%02x 0x%02x 0x%02x' $(( $1 >> 8 )) $(( $1 & 0xff )) $2); }
r() { i2ctransfer -f -y 0 w2@0x3a $(printf '0x%02x 0x%02x' $(( $1 >> 8 )) $(( $1 & 0xff ))) r1; }
w 0x0500 0                                  # global disable while configuring
grep -v '^#' "$REGS" | while read a v; do w $a $v; done
w 0x0024 0x00                               # PCM master mode: slave
w 0x0023 0x40                               # I2S, NB, 16-bit channels
w 0x0025 0x02                               # BSEL: 32 BCLK per frame
w 0x0026 0x08                               # DIG_IF_SR 48 kHz
w 0x0027 0x88                               # SPK_SR / IVADC_SR 48 kHz
w 0x0039 0x01                               # AMP enable
w 0x0500 0x01                               # global enable
w 0x0600 0x54; w 0x0600 0x4d; w 0x030d 0x40  # downstream unmute magic
sleep 0.3
echo "rev=$(r 0x0600) global=$(r 0x0500) amp=$(r 0x0039) int1=$(r 0x0001) int2=$(r 0x0002) int3=$(r 0x0003)"
