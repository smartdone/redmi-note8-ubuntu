#!/usr/bin/env python3
# Generates kernel/patches/0015 (after 0005/0011): Adreno 610 for SM6125.
# Layout from upstream sm6115.dtsi; addresses/clocks/OPPs from the working
# ginkgo DTB (reference/xlufoi-*/sm6125-xiaomi-ginkgo-huaxing.dts) and the
# stock trinket DT. No interconnects: there is no SM6125 interconnect driver.
import sys
p = f"{sys.argv[1]}/arch/arm64/boot/dts/qcom/sm6125.dtsi"
s = open(p).read()

inc_old = "#include <dt-bindings/clock/qcom,rpmcc.h>\n"
assert s.count(inc_old) == 1
s = s.replace(inc_old, inc_old + "#include <dt-bindings/clock/qcom,sm6125-gpucc.h>\n")

anchor = "\t\tmdss: display-subsystem@5e00000 {"
assert s.count(anchor) == 1
nodes = """\t\tgpu: gpu@5900000 {
\t\t\tcompatible = "qcom,adreno-610.0", "qcom,adreno";
\t\t\treg = <0x0 0x05900000 0x0 0x40000>,
\t\t\t      <0x0 0x0599e000 0x0 0x1000>,
\t\t\t      <0x0 0x05961000 0x0 0x800>;
\t\t\treg-names = "kgsl_3d0_reg_memory",
\t\t\t\t    "cx_mem",
\t\t\t\t    "cx_dbgc";

\t\t\tclocks = <&gpucc GPU_CC_GX_GFX3D_CLK>,
\t\t\t\t <&gpucc GPU_CC_AHB_CLK>,
\t\t\t\t <&gcc GCC_BIMC_GPU_AXI_CLK>,
\t\t\t\t <&gcc GCC_GPU_MEMNOC_GFX_CLK>,
\t\t\t\t <&gpucc GPU_CC_CX_GMU_CLK>,
\t\t\t\t <&gpucc GPU_CC_CXO_CLK>;
\t\t\tclock-names = "core",
\t\t\t\t      "iface",
\t\t\t\t      "mem_iface",
\t\t\t\t      "alt_mem_iface",
\t\t\t\t      "gmu",
\t\t\t\t      "xo";

\t\t\tinterrupts = <GIC_SPI 177 IRQ_TYPE_LEVEL_HIGH>;

\t\t\tiommus = <&adreno_smmu 0 1>;
\t\t\toperating-points-v2 = <&gpu_opp_table>;
\t\t\tpower-domains = <&rpmpd SM6125_VDDCX>;
\t\t\tqcom,gmu = <&gmu_wrapper>;

\t\t\t#cooling-cells = <2>;

\t\t\tstatus = "disabled";

\t\t\tzap-shader {
\t\t\t\tmemory-region = <&gpu_mem>;
\t\t\t};

\t\t\tgpu_opp_table: opp-table {
\t\t\t\tcompatible = "operating-points-v2";

\t\t\t\topp-320000000 {
\t\t\t\t\topp-hz = /bits/ 64 <320000000>;
\t\t\t\t\trequired-opps = <&rpmpd_opp_low_svs>;
\t\t\t\t};

\t\t\t\topp-465000000 {
\t\t\t\t\topp-hz = /bits/ 64 <465000000>;
\t\t\t\t\trequired-opps = <&rpmpd_opp_svs>;
\t\t\t\t};

\t\t\t\topp-600000000 {
\t\t\t\t\topp-hz = /bits/ 64 <600000000>;
\t\t\t\t\trequired-opps = <&rpmpd_opp_svs_plus>;
\t\t\t\t};

\t\t\t\topp-745000000 {
\t\t\t\t\topp-hz = /bits/ 64 <745000000>;
\t\t\t\t\trequired-opps = <&rpmpd_opp_nom>;
\t\t\t\t};

\t\t\t\topp-820000000 {
\t\t\t\t\topp-hz = /bits/ 64 <820000000>;
\t\t\t\t\trequired-opps = <&rpmpd_opp_nom_plus>;
\t\t\t\t};

\t\t\t\topp-900000000 {
\t\t\t\t\topp-hz = /bits/ 64 <900000000>;
\t\t\t\t\trequired-opps = <&rpmpd_opp_turbo>;
\t\t\t\t};

\t\t\t\topp-950000000 {
\t\t\t\t\topp-hz = /bits/ 64 <950000000>;
\t\t\t\t\trequired-opps = <&rpmpd_opp_turbo>;
\t\t\t\t};
\t\t\t};
\t\t};

\t\tgmu_wrapper: gmu@596a000 {
\t\t\tcompatible = "qcom,adreno-gmu-wrapper";
\t\t\treg = <0x0 0x0596a000 0x0 0x30000>;
\t\t\treg-names = "gmu";
\t\t\tpower-domains = <&gpucc GPU_CX_GDSC>,
\t\t\t\t\t<&gpucc GPU_GX_GDSC>;
\t\t\tpower-domain-names = "cx", "gx";
\t\t};

\t\tgpucc: clock-controller@5990000 {
\t\t\tcompatible = "qcom,sm6125-gpucc";
\t\t\treg = <0x0 0x05990000 0x0 0x9000>;
\t\t\tclocks = <&rpmcc RPM_SMD_XO_CLK_SRC>,
\t\t\t\t <&gcc GCC_GPU_GPLL0_CLK_SRC>;
\t\t\t#clock-cells = <1>;
\t\t\t#power-domain-cells = <1>;
\t\t};

\t\tadreno_smmu: iommu@59a0000 {
\t\t\tcompatible = "qcom,sm6125-smmu-500", "qcom,adreno-smmu",
\t\t\t\t     "qcom,smmu-500", "arm,mmu-500";
\t\t\treg = <0x0 0x059a0000 0x0 0x10000>;
\t\t\tinterrupts = <GIC_SPI 163 IRQ_TYPE_LEVEL_HIGH>,
\t\t\t\t     <GIC_SPI 167 IRQ_TYPE_LEVEL_HIGH>,
\t\t\t\t     <GIC_SPI 168 IRQ_TYPE_LEVEL_HIGH>,
\t\t\t\t     <GIC_SPI 169 IRQ_TYPE_LEVEL_HIGH>,
\t\t\t\t     <GIC_SPI 170 IRQ_TYPE_LEVEL_HIGH>,
\t\t\t\t     <GIC_SPI 171 IRQ_TYPE_LEVEL_HIGH>,
\t\t\t\t     <GIC_SPI 172 IRQ_TYPE_LEVEL_HIGH>,
\t\t\t\t     <GIC_SPI 173 IRQ_TYPE_LEVEL_HIGH>,
\t\t\t\t     <GIC_SPI 174 IRQ_TYPE_LEVEL_HIGH>;

\t\t\tclocks = <&gcc GCC_GPU_MEMNOC_GFX_CLK>,
\t\t\t\t <&gpucc GPU_CC_HLOS1_VOTE_GPU_SMMU_CLK>,
\t\t\t\t <&gcc GCC_GPU_SNOC_DVM_GFX_CLK>;
\t\t\tclock-names = "mem",
\t\t\t\t      "hlos",
\t\t\t\t      "iface";
\t\t\tpower-domains = <&gpucc GPU_CX_GDSC>;

\t\t\t#global-interrupts = <1>;
\t\t\t#iommu-cells = <2>;
\t\t};

"""
s = s.replace(anchor, nodes + anchor)
open(p, "w").write(s)
print("patched")
