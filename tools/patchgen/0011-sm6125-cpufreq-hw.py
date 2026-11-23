#!/usr/bin/env python3
# Generates kernel/patches/0011 (applied after 0005): SM6125 cpufreq-hw.
# Without it the big cluster stays at 300 MHz and the little one at 1.3 GHz.
# Usage: 0011-sm6125-cpufreq-hw.py <kernel tree>
import re, sys
p = f"{sys.argv[1]}/arch/arm64/boot/dts/qcom/sm6125.dtsi"
s = open(p).read()

def add_after(pattern, extra, count):
    global s
    n = len(re.findall(re.escape(pattern), s))
    assert n == count, (pattern, n)
    s = s.replace(pattern, pattern + extra)

add_after("\t\t\tcapacity-dmips-mhz = <1024>;\n",
          "\t\t\tqcom,freq-domain = <&cpufreq_hw 0>;\n\t\t\t#cooling-cells = <2>;\n", 4)
add_after("\t\t\tcapacity-dmips-mhz = <1638>;\n",
          "\t\t\tqcom,freq-domain = <&cpufreq_hw 1>;\n\t\t\t#cooling-cells = <2>;\n", 4)

old = "\t\tintc: interrupt-controller@f200000 {"
assert s.count(old) == 1
s = s.replace(old, """\t\tcpufreq_hw: cpufreq@f521000 {
\t\t\tcompatible = "qcom,sm6125-cpufreq-hw", "qcom,cpufreq-hw";
\t\t\treg = <0x0 0x0f521000 0x0 0x1000>,
\t\t\t      <0x0 0x0f523000 0x0 0x1000>;
\t\t\treg-names = "freq-domain0", "freq-domain1";

\t\t\tclocks = <&rpmcc RPM_SMD_XO_CLK_SRC>, <&gcc GPLL0_OUT_EARLY>;
\t\t\tclock-names = "xo", "alternate";

\t\t\t#freq-domain-cells = <1>;
\t\t\t#clock-cells = <1>;
\t\t};

""" + old)
open(p, "w").write(s)
print("patched")
