#!/usr/bin/env python3
# Generates kernel/patches/0023 (applied after 0011): SM6125 CPU idle states.
# Without them the CPUs only ever WFI (no cpuidle states, also not in s2idle),
# so neither the cores nor the clusters power collapse.
#
# Values: the stock trinket "qcom,lpm-levels" (reference/stock-dt) give the
# same latencies as upstream sm6115.dtsi (bengal, same Kryo 260 clusters), so
# that layout is reused: per-CPU power collapse (psci-cpu-mode 3) and per-
# cluster GDHS (L2 mode 2) and power collapse (L2 mode 4), hierarchical PSCI
# OSI domains (firmware reports "OSI mode supported").
# Cluster parameters: in OSI mode the kernel does not OR the cluster parameter
# into the CPU one, it *replaces* it (cpuidle-psci __psci_enter_domain_idle_state),
# so the cluster value must carry the CPU mode in its low nibble, composed like
# downstream lpm-levels does: is_reset << 30 | affinity level << 24 |
# L2 mode << 4 | CPU mode, CPU mode 3 (stock "pc", psci-cpu-mode 3):
#   GDHS (L2 mode 2, no reset)  0x40000023
#   PC   (L2 mode 4, reset)     0x41000043
# The sm6115 values (0x40000022 / 0x40000042 / 0x41000044) carry CPU mode 2
# or 4 and the firmware refused them: thousands of rejected entries per
# second per CPU and higher idle current than plain WFI.
# Usage: 0023-sm6125-cpu-idle-states.py <kernel tree>
import re, sys
p = f"{sys.argv[1]}/arch/arm64/boot/dts/qcom/sm6125.dtsi"
s = open(p).read()

# power-domains for every CPU node
n = 0
def add_pd(m):
    global n
    n += 1
    return (m.group(0) + f"\t\t\tpower-domains = <&cpu_pd{m.group(1)}>;\n"
            "\t\t\tpower-domain-names = \"psci\";\n")
s = re.sub(r'\t\tcpu(\d): cpu@\w+ \{\n(?:\t\t\t.*\n)*?\t\t\tenable-method = "psci";\n',
           add_pd, s)
assert n == 8, n

idle = """\t\tidle-states {
\t\t\tentry-method = "psci";

\t\t\tlittle_cpu_sleep_0: cpu-sleep-0-0 {
\t\t\t\tcompatible = "arm,idle-state";
\t\t\t\tidle-state-name = "silver-rail-power-collapse";
\t\t\t\tarm,psci-suspend-param = <0x40000003>;
\t\t\t\tentry-latency-us = <290>;
\t\t\t\texit-latency-us = <376>;
\t\t\t\tmin-residency-us = <1182>;
\t\t\t\tlocal-timer-stop;
\t\t\t};

\t\t\tbig_cpu_sleep_0: cpu-sleep-1-0 {
\t\t\t\tcompatible = "arm,idle-state";
\t\t\t\tidle-state-name = "gold-rail-power-collapse";
\t\t\t\tarm,psci-suspend-param = <0x40000003>;
\t\t\t\tentry-latency-us = <297>;
\t\t\t\texit-latency-us = <324>;
\t\t\t\tmin-residency-us = <1110>;
\t\t\t\tlocal-timer-stop;
\t\t\t};
\t\t};

\t\tdomain-idle-states {
\t\t\tcluster_0_sleep_0: cluster-sleep-0-0 {
\t\t\t\t/* GDHS */
\t\t\t\tcompatible = "domain-idle-state";
\t\t\t\tarm,psci-suspend-param = <0x40000023>;
\t\t\t\tentry-latency-us = <360>;
\t\t\t\texit-latency-us = <421>;
\t\t\t\tmin-residency-us = <782>;
\t\t\t};

\t\t\tcluster_0_sleep_1: cluster-sleep-0-1 {
\t\t\t\t/* Power Collapse */
\t\t\t\tcompatible = "domain-idle-state";
\t\t\t\tarm,psci-suspend-param = <0x41000043>;
\t\t\t\tentry-latency-us = <800>;
\t\t\t\texit-latency-us = <2118>;
\t\t\t\tmin-residency-us = <7376>;
\t\t\t};

\t\t\tcluster_1_sleep_0: cluster-sleep-1-0 {
\t\t\t\t/* GDHS */
\t\t\t\tcompatible = "domain-idle-state";
\t\t\t\tarm,psci-suspend-param = <0x40000023>;
\t\t\t\tentry-latency-us = <314>;
\t\t\t\texit-latency-us = <345>;
\t\t\t\tmin-residency-us = <660>;
\t\t\t};

\t\t\tcluster_1_sleep_1: cluster-sleep-1-1 {
\t\t\t\t/* Power Collapse */
\t\t\t\tcompatible = "domain-idle-state";
\t\t\t\tarm,psci-suspend-param = <0x41000043>;
\t\t\t\tentry-latency-us = <640>;
\t\t\t\texit-latency-us = <1654>;
\t\t\t\tmin-residency-us = <8094>;
\t\t\t};
\t\t};

"""
old = "\t\tcpu-map {\n"
assert s.count(old) == 1
s = s.replace(old, idle + old)

old = """\tpsci {
\t\tcompatible = "arm,psci-1.0";
\t\tmethod = "smc";
\t};
"""
assert s.count(old) == 1
pds = ""
for cpu in range(8):
    cl, st = (0, "little") if cpu < 4 else (1, "big")
    pds += f"""
\t\tcpu_pd{cpu}: power-domain-cpu{cpu} {{
\t\t\t#power-domain-cells = <0>;
\t\t\tpower-domains = <&cluster_{cl}_pd>;
\t\t\tdomain-idle-states = <&{st}_cpu_sleep_0>;
\t\t}};
"""
for cl in range(2):
    pds += f"""
\t\tcluster_{cl}_pd: power-domain-cpu-cluster{cl} {{
\t\t\t#power-domain-cells = <0>;
\t\t\tdomain-idle-states = <&cluster_{cl}_sleep_0>, <&cluster_{cl}_sleep_1>;
\t\t}};
"""
s = s.replace(old, old[:-4] + pds + "\t};\n")
open(p, "w").write(s)
print("patched")
