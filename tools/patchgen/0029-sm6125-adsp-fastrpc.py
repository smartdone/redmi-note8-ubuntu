#!/usr/bin/env python3
# Generates kernel/patches/0029 (applied after 0025): FastRPC on the SM6125
# ADSP. Needed by hexagonrpcd, which serves the sensor configuration and
# registry files to the ADSP sensor PD (the SSC / QMI service 400 only
# reports sensors once it has them).
# Stock trinket DT (reference/stock-dt): one ADSP context bank "adsprpc-smd"
# with iommus SIDs 0x43 and 0x44, shared-cb = <5> -> qcom,nsessions = <5>.
# Layout as in sm6115.dtsi.
# Usage: 0029-sm6125-adsp-fastrpc.py <kernel tree>
import sys
p = f"{sys.argv[1]}/arch/arm64/boot/dts/qcom/sm6125.dtsi"
s = open(p).read()

anchor = """\t\t\t\t\t\tq6routing: routing {
\t\t\t\t\t\t\tcompatible = "qcom,q6adm-routing";
\t\t\t\t\t\t\t#sound-dai-cells = <0>;
\t\t\t\t\t\t};
\t\t\t\t\t};
\t\t\t\t};
"""
assert s.count(anchor) == 1
s = s.replace(anchor, anchor + """
\t\t\t\tfastrpc {
\t\t\t\t\tcompatible = "qcom,fastrpc";
\t\t\t\t\tqcom,glink-channels = "fastrpcglink-apps-dsp";
\t\t\t\t\tlabel = "adsp";
\t\t\t\t\tqcom,non-secure-domain;
\t\t\t\t\t#address-cells = <1>;
\t\t\t\t\t#size-cells = <0>;

\t\t\t\t\tcompute-cb@3 {
\t\t\t\t\t\tcompatible = "qcom,fastrpc-compute-cb";
\t\t\t\t\t\treg = <3>;
\t\t\t\t\t\tiommus = <&apps_smmu 0x43 0x0>,
\t\t\t\t\t\t\t <&apps_smmu 0x44 0x0>;
\t\t\t\t\t\tqcom,nsessions = <5>;
\t\t\t\t\t};
\t\t\t\t};
""")
open(p, "w").write(s)
print("patched")
