#!/usr/bin/env python3
# Generates kernel/patches/0018: ginkgo battery (simple-battery from the stock
# ATL profile) + PMI632 read-only battery monitor + battery thermistor channel.
# Usage: 0018-ginkgo-battery.py <kernel tree> <ocv table snippet from battery-ocv-table.py>
import sys
p = f"{sys.argv[1]}/arch/arm64/boot/dts/qcom/sm6125-xiaomi-ginkgo.dts"
table = open(sys.argv[2]).read().strip().replace("\n", "\n\t\t")
s = open(p).read()
s += f"""
/*
 * Battery: 4000 mAh, 4.4 V. OCV table: stock profile
 * 4124117_LC_M516_ATL_4000mAH_PMI632 (batt-id 68k), 25 degC column; the
 * Coslight (100k) cell is within ~20 mV. Charging is left to the PMIC as set
 * up by the boot firmware; the monitor below only reads registers.
 */
/ {{
	battery: battery {{
		compatible = "simple-battery";
		device-chemistry = "lithium-ion-polymer";
		charge-full-design-microamp-hours = <4000000>;
		voltage-min-design-microvolt = <3400000>;
		voltage-max-design-microvolt = <4400000>;
		ocv-capacity-celsius = <25>;
		{table}
	}};
}};

&pmi632_adc {{
	channel@4a {{
		reg = <ADC5_BAT_THERM_100K_PU>;
		qcom,hw-settle-time = <200>;
		qcom,pre-scaling = <1 1>;
		qcom,ratiometric;
		label = "bat_therm";
	}};
}};

&spmi_bus {{
	pmic@2 {{
		battery-monitor@4800 {{
			compatible = "qcom,pmi632-battery-monitor";
			/* QG block, SMB5 charger block */
			reg = <0x4800>, <0x1000>;
			monitored-battery = <&battery>;
			io-channels = <&pmi632_adc ADC5_BAT_THERM_100K_PU>;
			io-channel-names = "batt-therm";
		}};
	}};
}};
"""
open(p, "w").write(s)
print("patched")
