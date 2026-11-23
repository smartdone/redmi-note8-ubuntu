#!/usr/bin/env python3
# Generates kernel/patches/0013 (on top of 0001/0004/0006): DSI display.
import sys
p = f"{sys.argv[1]}/arch/arm64/boot/dts/qcom/sm6125-xiaomi-ginkgo.dts"
s = open(p).read()
s += """
/* Display: DPU -> DSI0 -> Huaxing FT8719 1080x2340 video mode panel */
&mdss {
	status = "okay";
};

&mdss_dsi0 {
	vdda-supply = <&vreg_l18a>;
	status = "okay";

	panel: panel@0 {
		compatible = "huaxing,ginkgo-ft8719";
		reg = <0>;

		reset-gpios = <&tlmm 90 GPIO_ACTIVE_LOW>;
		vddio-supply = <&vreg_l9a>;
		/* vddpos/vddneg come from the PMI632 LCDB (no mainline driver, left on by the bootloader) */
		backlight = <&backlight>;

		port {
			panel_in: endpoint {
				remote-endpoint = <&mdss_dsi0_out>;
			};
		};
	};
};

&mdss_dsi0_out {
	data-lanes = <0 1 2 3>;
	remote-endpoint = <&panel_in>;
};

&mdss_dsi0_phy {
	vdda-supply = <&vreg_l7a>;
	status = "okay";
};

/* In-cell touch: the panel reset wipes the touch firmware, reload it after power-up */
&spi2 {
	touchscreen@0 {
		panel = <&panel>;
	};
};
"""
open(p, "w").write(s)
print("patched")
