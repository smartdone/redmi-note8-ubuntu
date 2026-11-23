import sys
p = sys.argv[1]; s = open(p).read()
def sub(old, new):
    global s
    assert s.count(old) == 1, old
    s = s.replace(old, new)
sub("#define LM3697_FEEDBACK_EN\t\t0x19\n",
    "#define LM3697_FEEDBACK_EN\t\t0x19\n")
sub("#define LM3697_BOOST_OVP_SHIFT\t1\n",
    "#define LM3697_BOOST_OVP_SHIFT\t1\n#define LM3697_MAP_LINEAR\tBIT(0)\n")
sub("\tint boost_cfg;\n", "\tint boost_cfg;\n\tbool linear_map;\n")
sub("""	if (priv->boost_cfg >= 0) {""",
"""	/* Both banks share the mapping; exponential is the chip default. */
	if (priv->linear_map) {
		ret = regmap_update_bits(priv->regmap, LM3697_CTRL_A_B_BRT_CFG,
					 LM3697_MAP_LINEAR, LM3697_MAP_LINEAR);
		if (ret)
			dev_err(dev, "Cannot set linear mapping\\n");
	}

	if (priv->boost_cfg >= 0) {""")
sub("""	priv->boost_cfg = -1;
""", """	priv->boost_cfg = -1;
	priv->linear_map = device_property_read_bool(dev, "ti,linear-mapping-mode");
""")
open(p, "w").write(s); print("patched")
