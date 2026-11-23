#!/usr/bin/env python3
# Generates kernel/patches/0026 (applied after 0025): ginkgo loudspeaker.
# MAX98937 (Android: max98927L) on QUP SE1 I2C (0x3a, reset TLMM 27 active low, stock dtbo
# fragment@38) on primary MI2S (q6afe PRIMARY_MI2S_RX, SD0: stock
# dai_mi2s0 qcom,msm-mi2s-rx-lines = <1>), ADSP firmware from the modem
# partition (installed by ginkgo-firmware.service). Card through the sm8250
# machine driver, as the reference DTB (reference/xlufoi-*) does.
# Usage: 0026-ginkgo-speaker.py <kernel tree>
import sys
p = f"{sys.argv[1]}/arch/arm64/boot/dts/qcom/sm6125-xiaomi-ginkgo.dts"
s = open(p).read()

def sub(old, new):
    global s
    assert s.count(old) == 1, old
    s = s.replace(old, new)

sub("#include <dt-bindings/leds/common.h>\n",
    "#include <dt-bindings/leds/common.h>\n"
    "#include <dt-bindings/sound/qcom,q6afe.h>\n"
    "#include <dt-bindings/sound/qcom,q6asm.h>\n")

# the amp sits on the same bus as the backlight controller
sub("""			color = <LED_COLOR_ID_WHITE>;
		};
	};
};
""", """			color = <LED_COLOR_ID_WHITE>;
		};
	};

	/*
	 * Loudspeaker amplifier. Android's DT says maxim,max98927L, but the
	 * part is a MAX98937 (revision register 0x0600 reads 0x43), which has
	 * a different register map.
	 */
	speaker_amp: audio-codec@3a {
		compatible = "maxim,max98937";
		reg = <0x3a>;
		reset-gpios = <&tlmm 27 GPIO_ACTIVE_LOW>;
		#sound-dai-cells = <0>;
	};
};
""")

s += """
&remoteproc_adsp {
	firmware-name = "qcom/sm6125/xiaomi/ginkgo/adsp.mdt";
	status = "okay";
};

&q6afedai {
	dai@16 {
		reg = <PRIMARY_MI2S_RX>;
		qcom,sd-lines = <0>;
	};
};

/ {
	sound {
		compatible = "qcom,sm8250-sndcard";
		model = "Xiaomi Redmi Note 8";
		pinctrl-0 = <&pri_mi2s_active>;
		pinctrl-names = "default";

		mm1-dai-link {
			link-name = "MultiMedia1";

			cpu {
				sound-dai = <&q6asmdai MSM_FRONTEND_DAI_MULTIMEDIA1>;
			};
		};

		mm2-dai-link {
			link-name = "MultiMedia2";

			cpu {
				sound-dai = <&q6asmdai MSM_FRONTEND_DAI_MULTIMEDIA2>;
			};
		};

		mm3-dai-link {
			link-name = "MultiMedia3";

			cpu {
				sound-dai = <&q6asmdai MSM_FRONTEND_DAI_MULTIMEDIA3>;
			};
		};

		speaker-dai-link {
			link-name = "Speaker Playback";

			cpu {
				sound-dai = <&q6afedai PRIMARY_MI2S_RX>;
			};

			platform {
				sound-dai = <&q6routing>;
			};

			codec {
				sound-dai = <&speaker_amp>;
			};
		};
	};
};
"""
open(p, "w").write(s)
print("patched")
