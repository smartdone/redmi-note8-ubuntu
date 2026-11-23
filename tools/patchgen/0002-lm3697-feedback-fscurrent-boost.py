import re, sys
p = sys.argv[1]
s = open(p).read()

def sub(old, new):
    global s
    assert s.count(old) == 1, old
    s = s.replace(old, new)

sub("#define LM3697_PWM_CFG\t\t\t0x1c\n",
    "#define LM3697_FEEDBACK_EN\t\t0x19\n"
    "#define LM3697_BOOST_CTRL\t\t0x1a\n"
    "#define LM3697_PWM_CFG\t\t\t0x1c\n")

sub("#define LM3697_MAX_CONTROL_BANKS 2\n",
    "#define LM3697_MAX_CONTROL_BANKS 2\n"
    "\n"
    "#define LM3697_FS_CURR_MIN_UA\t5000\n"
    "#define LM3697_FS_CURR_STEP_UA\t800\n"
    "#define LM3697_FS_CURR_MAX_CODE\t0x1f\n"
    "#define LM3697_BOOST_FREQ_1MHZ\tBIT(0)\n"
    "#define LM3697_BOOST_OVP_SHIFT\t1\n")

sub("\tint bank_cfg;\n\tint num_banks;\n",
    "\tint bank_cfg;\n"
    "\tint feedback_cfg;\n"
    "\tint fs_curr[LM3697_MAX_CONTROL_BANKS];\n"
    "\tint boost_cfg;\n"
    "\tint num_banks;\n")

sub("\t{LM3697_CTRL_B_FS_CURR_CFG, 0x13},\n",
    "\t{LM3697_CTRL_B_FS_CURR_CFG, 0x13},\n"
    "\t{LM3697_FEEDBACK_EN, 0x7},\n"
    "\t{LM3697_BOOST_CTRL, 0x0},\n")

# init: program feedback, full-scale current and boost after OUTPUT_CONFIG
sub("""	ret = regmap_write(priv->regmap, LM3697_OUTPUT_CONFIG, priv->bank_cfg);
	if (ret)
		dev_err(dev, "Cannot write OUTPUT config\\n");
""", """	ret = regmap_write(priv->regmap, LM3697_OUTPUT_CONFIG, priv->bank_cfg);
	if (ret)
		dev_err(dev, "Cannot write OUTPUT config\\n");

	/* Only strings that are wired up should take part in boost regulation. */
	ret = regmap_write(priv->regmap, LM3697_FEEDBACK_EN, priv->feedback_cfg);
	if (ret)
		dev_err(dev, "Cannot write feedback enables\\n");

	for (i = 0; i < LM3697_MAX_CONTROL_BANKS; i++) {
		if (priv->fs_curr[i] < 0)
			continue;
		ret = regmap_write(priv->regmap, LM3697_CTRL_A_FS_CURR_CFG + i,
				   priv->fs_curr[i]);
		if (ret)
			dev_err(dev, "Cannot write full-scale current\\n");
	}

	if (priv->boost_cfg >= 0) {
		ret = regmap_write(priv->regmap, LM3697_BOOST_CTRL, priv->boost_cfg);
		if (ret)
			dev_err(dev, "Cannot write boost control\\n");
	}
""")

# DT parsing: board-level boost settings
sub("""	priv->regulator = devm_regulator_get(dev, "vled");
	if (IS_ERR(priv->regulator))
		priv->regulator = NULL;
""", """	priv->regulator = devm_regulator_get(dev, "vled");
	if (IS_ERR(priv->regulator))
		priv->regulator = NULL;

	priv->fs_curr[LM3697_CONTROL_A] = -1;
	priv->fs_curr[LM3697_CONTROL_B] = -1;
	priv->boost_cfg = -1;
	if (!device_property_read_u32(dev, "ti,ovp-microvolt", &val)) {
		/* 16 V, 24 V, 32 V, 40 V */
		if (val < 16000000 || val > 40000000 || val % 8000000) {
			dev_err(dev, "invalid ti,ovp-microvolt %u\\n", val);
			return -EINVAL;
		}
		priv->boost_cfg = ((val - 16000000) / 8000000) <<
				  LM3697_BOOST_OVP_SHIFT;
	}
	if (!device_property_read_u32(dev, "ti,boost-frequency-hz", &val)) {
		if (val != 500000 && val != 1000000) {
			dev_err(dev, "invalid ti,boost-frequency-hz %u\\n", val);
			return -EINVAL;
		}
		if (priv->boost_cfg < 0)
			priv->boost_cfg = 0;
		if (val == 1000000)
			priv->boost_cfg |= LM3697_BOOST_FREQ_1MHZ;
	}
""")

sub("""	int control_bank;
	size_t i = 0;
	int j;
""", """	int control_bank;
	size_t i = 0;
	u32 val;
	int j;
""")

sub("""		for (j = 0; j < led->num_leds; j++)
			priv->bank_cfg |=
				(led->control_bank << led->hvled_strings[j]);
""", """		for (j = 0; j < led->num_leds; j++) {
			priv->bank_cfg |=
				(led->control_bank << led->hvled_strings[j]);
			priv->feedback_cfg |= BIT(led->hvled_strings[j]);
		}

		if (!fwnode_property_read_u32(child, "led-max-microamp", &val)) {
			if (val < LM3697_FS_CURR_MIN_UA)
				val = LM3697_FS_CURR_MIN_UA;
			priv->fs_curr[control_bank] =
				min((val - LM3697_FS_CURR_MIN_UA) /
				    LM3697_FS_CURR_STEP_UA,
				    (u32)LM3697_FS_CURR_MAX_CODE);
		}
""")
open(p, "w").write(s)
print("patched")
