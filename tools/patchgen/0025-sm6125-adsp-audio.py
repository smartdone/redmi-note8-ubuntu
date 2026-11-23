#!/usr/bin/env python3
# Generates kernel/patches/0025 (applied after 0005/0023): SM6125 audio DSP.
# ADSP remoteproc (PAS id 1, "lpass" glink edge) with the APR audio services
# (q6core/q6afe/q6asm/q6adm), its smp2p, and the primary MI2S pins.
# Values from the stock trinket DT (reference/stock-dt: qcom,lpass@ab00000,
# qcom,smp2p-adsp, glink "lpass", msm-audio-ion iommus SID 0x41) and the same
# as the known-good reference DTB (reference/xlufoi-willow-mainline-*).
# Layout of the services follows sm6115.dtsi.
# Usage: 0025-sm6125-adsp-audio.py <kernel tree>
import sys
p = f"{sys.argv[1]}/arch/arm64/boot/dts/qcom/sm6125.dtsi"
s = open(p).read()

def sub(old, new):
    global s
    assert s.count(old) == 1, old
    s = s.replace(old, new)

sub("#include <dt-bindings/power/qcom-rpmpd.h>\n",
    "#include <dt-bindings/power/qcom-rpmpd.h>\n"
    "#include <dt-bindings/soc/qcom,apr.h>\n"
    "#include <dt-bindings/sound/qcom,q6asm.h>\n")

sub("\tsmp2p-mpss {\n", """\tsmp2p-adsp {
\t\tcompatible = "qcom,smp2p";
\t\tqcom,smem = <443>, <429>;
\t\tinterrupts = <GIC_SPI 393 IRQ_TYPE_EDGE_RISING>;
\t\tmboxes = <&apcs_glb 10>;
\t\tqcom,local-pid = <0>;
\t\tqcom,remote-pid = <2>;

\t\tadsp_smp2p_out: master-kernel {
\t\t\tqcom,entry-name = "master-kernel";
\t\t\t#qcom,smem-state-cells = <1>;
\t\t};

\t\tadsp_smp2p_in: slave-kernel {
\t\t\tqcom,entry-name = "slave-kernel";
\t\t\tinterrupt-controller;
\t\t\t#interrupt-cells = <2>;
\t\t};
\t};

\tsmp2p-mpss {
""")

sub("\t\t\tqup_i2c1_default: qup-i2c1-default-state {\n", """\t\t\tpri_mi2s_active: pri-mi2s-active-state {
\t\t\t\tsck-pins {
\t\t\t\t\tpins = "gpio113";
\t\t\t\t\tfunction = "pri_mi2s";
\t\t\t\t\tdrive-strength = <8>;
\t\t\t\t\tbias-disable;
\t\t\t\t};

\t\t\t\tws-pins {
\t\t\t\t\tpins = "gpio114";
\t\t\t\t\tfunction = "pri_mi2s_ws";
\t\t\t\t\tdrive-strength = <8>;
\t\t\t\t\tbias-disable;
\t\t\t\t};

\t\t\t\tdata-pins {
\t\t\t\t\tpins = "gpio115", "gpio116";
\t\t\t\t\tfunction = "pri_mi2s";
\t\t\t\t\tdrive-strength = <8>;
\t\t\t\t\tbias-disable;
\t\t\t\t};
\t\t\t};

\t\t\tqup_i2c1_default: qup-i2c1-default-state {
""")

sub("\t\tremoteproc_mpss: remoteproc@6080000 {\n", """\t\tremoteproc_adsp: remoteproc@ab00000 {
\t\t\tcompatible = "qcom,sm6115-adsp-pas";
\t\t\treg = <0x0 0x0ab00000 0x0 0x100>;

\t\t\tinterrupts-extended = <&intc GIC_SPI 396 IRQ_TYPE_EDGE_RISING>,
\t\t\t\t\t      <&adsp_smp2p_in 0 IRQ_TYPE_EDGE_RISING>,
\t\t\t\t\t      <&adsp_smp2p_in 1 IRQ_TYPE_EDGE_RISING>,
\t\t\t\t\t      <&adsp_smp2p_in 2 IRQ_TYPE_EDGE_RISING>,
\t\t\t\t\t      <&adsp_smp2p_in 3 IRQ_TYPE_EDGE_RISING>;
\t\t\tinterrupt-names = "wdog", "fatal", "ready",
\t\t\t\t\t  "handover", "stop-ack";

\t\t\tclocks = <&rpmcc RPM_SMD_XO_CLK_SRC>;
\t\t\tclock-names = "xo";

\t\t\tmemory-region = <&adsp_pil_mem>;

\t\t\tqcom,smem-states = <&adsp_smp2p_out 0>;
\t\t\tqcom,smem-state-names = "stop";

\t\t\tstatus = "disabled";

\t\t\tglink-edge {
\t\t\t\tinterrupts = <GIC_SPI 391 IRQ_TYPE_EDGE_RISING>;
\t\t\t\tlabel = "lpass";
\t\t\t\tqcom,remote-pid = <2>;
\t\t\t\tmboxes = <&apcs_glb 8>;

\t\t\t\tapr {
\t\t\t\t\tcompatible = "qcom,apr-v2";
\t\t\t\t\tqcom,glink-channels = "apr_audio_svc";
\t\t\t\t\tqcom,domain = <APR_DOMAIN_ADSP>;
\t\t\t\t\t#address-cells = <1>;
\t\t\t\t\t#size-cells = <0>;

\t\t\t\t\tservice@3 {
\t\t\t\t\t\treg = <APR_SVC_ADSP_CORE>;
\t\t\t\t\t\tcompatible = "qcom,q6core";
\t\t\t\t\t\tqcom,protection-domain = "avs/audio",
\t\t\t\t\t\t\t\t\t "msm/adsp/audio_pd";
\t\t\t\t\t};

\t\t\t\t\tq6afe: service@4 {
\t\t\t\t\t\tcompatible = "qcom,q6afe";
\t\t\t\t\t\treg = <APR_SVC_AFE>;
\t\t\t\t\t\tqcom,protection-domain = "avs/audio",
\t\t\t\t\t\t\t\t\t "msm/adsp/audio_pd";

\t\t\t\t\t\tq6afedai: dais {
\t\t\t\t\t\t\tcompatible = "qcom,q6afe-dais";
\t\t\t\t\t\t\t#address-cells = <1>;
\t\t\t\t\t\t\t#size-cells = <0>;
\t\t\t\t\t\t\t#sound-dai-cells = <1>;
\t\t\t\t\t\t};

\t\t\t\t\t\tq6afecc: clock-controller {
\t\t\t\t\t\t\tcompatible = "qcom,q6afe-clocks";
\t\t\t\t\t\t\t#clock-cells = <2>;
\t\t\t\t\t\t};
\t\t\t\t\t};

\t\t\t\t\tq6asm: service@7 {
\t\t\t\t\t\tcompatible = "qcom,q6asm";
\t\t\t\t\t\treg = <APR_SVC_ASM>;
\t\t\t\t\t\tqcom,protection-domain = "avs/audio",
\t\t\t\t\t\t\t\t\t "msm/adsp/audio_pd";

\t\t\t\t\t\tq6asmdai: dais {
\t\t\t\t\t\t\tcompatible = "qcom,q6asm-dais";
\t\t\t\t\t\t\t#address-cells = <1>;
\t\t\t\t\t\t\t#size-cells = <0>;
\t\t\t\t\t\t\t#sound-dai-cells = <1>;
\t\t\t\t\t\t\tiommus = <&apps_smmu 0x41 0x0>;

\t\t\t\t\t\t\tdai@0 {
\t\t\t\t\t\t\t\treg = <MSM_FRONTEND_DAI_MULTIMEDIA1>;
\t\t\t\t\t\t\t};

\t\t\t\t\t\t\tdai@1 {
\t\t\t\t\t\t\t\treg = <MSM_FRONTEND_DAI_MULTIMEDIA2>;
\t\t\t\t\t\t\t};

\t\t\t\t\t\t\tdai@2 {
\t\t\t\t\t\t\t\treg = <MSM_FRONTEND_DAI_MULTIMEDIA3>;
\t\t\t\t\t\t\t};
\t\t\t\t\t\t};
\t\t\t\t\t};

\t\t\t\t\tq6adm: service@8 {
\t\t\t\t\t\tcompatible = "qcom,q6adm";
\t\t\t\t\t\treg = <APR_SVC_ADM>;
\t\t\t\t\t\tqcom,protection-domain = "avs/audio",
\t\t\t\t\t\t\t\t\t "msm/adsp/audio_pd";

\t\t\t\t\t\tq6routing: routing {
\t\t\t\t\t\t\tcompatible = "qcom,q6adm-routing";
\t\t\t\t\t\t\t#sound-dai-cells = <0>;
\t\t\t\t\t\t};
\t\t\t\t\t};
\t\t\t\t};
\t\t\t};
\t\t};

\t\tremoteproc_mpss: remoteproc@6080000 {
""")
open(p, "w").write(s)
print("patched")
