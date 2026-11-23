#!/usr/bin/env python3
# Generates kernel/patches/0020 (after 0005/0011/0015): QUP WRAP1 SE4 UART
# (4c90000) used for the WCN39xx Bluetooth, pins from the working ginkgo DTB.
import sys
p = f"{sys.argv[1]}/arch/arm64/boot/dts/qcom/sm6125.dtsi"
s = open(p).read()
a = "\t\t\tqup_uart4_default: qup-uart4-default-state {"
assert s.count(a) == 1
s = s.replace(a, """\t\t\tqup_uart9_default: qup-uart9-default-state {
\t\t\t\tcts-rx-pins {
\t\t\t\t\tpins = "gpio10", "gpio13";
\t\t\t\t\tfunction = "qup14";
\t\t\t\t\tdrive-strength = <2>;
\t\t\t\t\tbias-disable;
\t\t\t\t};

\t\t\t\trts-pins {
\t\t\t\t\tpins = "gpio11";
\t\t\t\t\tfunction = "qup14";
\t\t\t\t\tdrive-strength = <2>;
\t\t\t\t\tbias-pull-down;
\t\t\t\t};

\t\t\t\ttx-pins {
\t\t\t\t\tpins = "gpio12";
\t\t\t\t\tfunction = "qup14";
\t\t\t\t\tdrive-strength = <2>;
\t\t\t\t\tbias-pull-up;
\t\t\t\t};
\t\t\t};

""" + a)
a = "\t\t\tspi9: spi@4c90000 {"
assert s.count(a) == 1
s = s.replace(a, """\t\t\tuart9: serial@4c90000 {
\t\t\t\tcompatible = "qcom,geni-uart";
\t\t\t\treg = <0x0 0x04c90000 0x0 0x4000>;
\t\t\t\tclocks = <&gcc GCC_QUPV3_WRAP1_S4_CLK>;
\t\t\t\tclock-names = "se";
\t\t\t\tinterrupts = <GIC_SPI 312 IRQ_TYPE_LEVEL_HIGH>;
\t\t\t\tpinctrl-0 = <&qup_uart9_default>;
\t\t\t\tpinctrl-names = "default";
\t\t\t\tstatus = "disabled";
\t\t\t};

""" + a)
open(p, "w").write(s)
print("patched")
