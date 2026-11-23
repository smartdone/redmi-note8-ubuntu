# tools/patchgen — scripts that produced some of kernel/patches/

The patches in `kernel/patches/` are the source of truth; these scripts are kept
to show how the larger edits were generated (each edits a pristine kernel tree;
`git diff` of the touched files gives the patch). Patches written by hand
(0001, 0003, 0004, 0007, 0008, 0009) have no script.

| Script | Patch |
|---|---|
| `0002-lm3697-feedback-fscurrent-boost.py`, then `0002-lm3697-linear-mapping.py` | `0002-leds-lm3697-*` |
| `0005-sm6125-mpss-wifi-nodes.py` (the `qcom,msa-fixed-perm` line it adds was removed again) | `0005-arm64-dts-qcom-sm6125-*` |
| `0006-ginkgo-enable-modem-wifi.py` | `0006-arm64-dts-qcom-ginkgo-*` (applied on top of 0001+0004) |
| `0010-ath10k-wcn3990-defer-vdev-start.py <tree>` | `0010-wifi-ath10k-*` |
