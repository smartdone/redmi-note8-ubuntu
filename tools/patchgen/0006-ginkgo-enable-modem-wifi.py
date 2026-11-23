import sys
p = sys.argv[1]; s = open(p).read()
old = "#include <dt-bindings/leds/common.h>\n"
assert s.count(old) == 1
s = s.replace(old, "#include <dt-bindings/firmware/qcom,scm.h>\n" + old)
s += """
/ {
	reserved-memory {
		rmtfs_mem: memory@89b01000 {
			compatible = "qcom,rmtfs-mem";
			reg = <0x0 0x89b01000 0x0 0x200000>;
			no-map;

			qcom,client-id = <1>;
			qcom,vmid = <QCOM_SCM_VMID_MSS_MSA>, <QCOM_SCM_VMID_NAV>;
		};
	};
};


/* The modem (MPSS) hosts the WCN3990 Wi-Fi firmware on SM6125. */
&remoteproc_mpss {
	firmware-name = "qcom/sm6125/xiaomi/ginkgo/modem.mdt";
	status = "okay";
};

/* WCN3990 digital core (vdd-0.8-cx-mx): stock icnss uses 640 mV. */
&vreg_l8a {
	regulator-min-microvolt = <640000>;
	regulator-max-microvolt = <640000>;
};

&wifi {
	vdd-0.8-cx-mx-supply = <&vreg_l8a>;
	vdd-1.8-xo-supply = <&vreg_l16a>;
	vdd-1.3-rfa-supply = <&vreg_l17a>;
	vdd-3.3-ch0-supply = <&vreg_l23a>;
	vdd-3.3-ch1-supply = <&vreg_l23a>;
	qcom,calibration-variant = "Xiaomi_ginkgo";
	status = "okay";
};
"""
open(p, "w").write(s); print("patched ginkgo dts")
