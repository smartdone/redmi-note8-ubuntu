// SPDX-License-Identifier: GPL-2.0-only
/*
 * Maxim MAX98937 mono class-D speaker amplifier (I2S slave, playback only).
 *
 * Found on the Xiaomi Redmi Note 8 (ginkgo), where Android's device tree
 * calls it "max98927L". It is not register compatible with the MAX98927:
 * revision ID at 0x0600 (0x43 here), global enable at 0x0500, amplifier
 * enable at 0x0039, PCM setup at 0x0023-0x0027. The initialisation follows
 * the vendor driver (techpack/audio/asoc/codecs/max98937/max98937.c in the
 * ginkgo Android kernel): mono channel map, then the common register table,
 * and on unmute the amplifier/global enables followed by an access sequence
 * on 0x0600 and a write of 0x40 to 0x030d. Speaker protection (DSM on the
 * ADSP, IV feedback) is not supported; the gains stay at the vendor
 * defaults.
 */

#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/regmap.h>
#include <sound/pcm.h>
#include <sound/pcm_params.h>
#include <sound/soc.h>
#include <sound/tlv.h>

#define MAX98937_PCM_MODE_CFG		0x0023
#define  MAX98937_PCM_MODE_BCLKEDGE	BIT(2)
#define  MAX98937_PCM_MODE_FORMAT_MASK	GENMASK(5, 3)
#define  MAX98937_PCM_MODE_FORMAT_I2S	(0 << 3)
#define  MAX98937_PCM_MODE_FORMAT_LEFT	(1 << 3)
#define  MAX98937_PCM_MODE_CHANSZ_MASK	GENMASK(7, 6)
#define  MAX98937_PCM_MODE_CHANSZ_16	(1 << 6)
#define  MAX98937_PCM_MODE_CHANSZ_24	(2 << 6)
#define  MAX98937_PCM_MODE_CHANSZ_32	(3 << 6)
#define MAX98937_PCM_MASTER_MODE	0x0024
#define  MAX98937_PCM_MSTR_MODE_MASK	GENMASK(1, 0)
#define  MAX98937_PCM_MSTR_MODE_SLAVE	0
#define MAX98937_PCM_CLOCK_SETUP	0x0025
#define  MAX98937_PCM_BSEL_MASK		GENMASK(3, 0)
#define MAX98937_PCM_SR_SETUP1		0x0026
#define  MAX98937_DIG_IF_SR_MASK	GENMASK(3, 0)
#define MAX98937_PCM_SR_SETUP2		0x0027
#define  MAX98937_SPK_SR_MASK		GENMASK(7, 4)
#define  MAX98937_IVADC_SR_MASK		GENMASK(3, 0)
#define MAX98937_AMP_VOLUME		0x0036
#define MAX98937_AMP_ENABLES		0x0039
#define MAX98937_SPK_GAIN		0x003b
#define MAX98937_GLOBAL_ENABLE		0x0500
#define MAX98937_SOFTWARE_RESET		0x0501
#define MAX98937_REV_ID			0x0600

struct max98937_priv {
	struct regmap *regmap;
	struct gpio_desc *reset_gpio;
};

/* Mono channel map, then the common table, as the vendor driver writes them */
static const struct reg_sequence max98937_init[] = {
	{ 0x0040, 0x01 }, { 0x001e, 0x01 }, { 0x0018, 0x03 }, { 0x001a, 0x03 },
	{ 0x001c, 0xfc }, { 0x0028, 0x80 }, { 0x0029, 0x01 },

	{ 0x0011, 0x03 }, { 0x0053, 0x00 }, { 0x0055, 0x00 }, { 0x005e, 0x16 },
	{ 0x005f, 0x00 }, { 0x0060, 0x0c }, { 0x0061, 0x0c }, { 0x0062, 0x12 },
	{ 0x0063, 0x00 }, { 0x0064, 0x0c }, { 0x0065, 0x0c }, { 0x0066, 0x0e },
	{ 0x0067, 0x03 }, { 0x0068, 0x18 }, { 0x0069, 0x18 }, { 0x006a, 0x0a },
	{ 0x006b, 0x00 }, { 0x006c, 0x80 }, { 0x006d, 0x00 }, { 0x005a, 0x00 },
	{ 0x005b, 0x00 }, { 0x005c, 0x1f }, { 0x005d, 0x00 }, { 0x0042, 0x07 },
	{ 0x0014, 0x75 }, { 0x0015, 0x8c }, { 0x0017, 0x55 }, { 0x003e, 0xf7 },
	{ 0x0023, 0x40 }, { 0x003a, 0x00 }, { 0x001b, 0x00 }, { 0x0019, 0x00 },
	{ 0x001f, 0x03 }, { 0x001d, 0xff }, { 0x003d, 0x03 }, { 0x0035, 0x00 },
	{ 0x0036, 0x38 }, { 0x0037, 0x0f }, { 0x003b, 0x55 }, { 0x003c, 0xa0 },
	{ 0x003f, 0x1c }, { 0x0041, 0x40 }, { 0x0043, 0x00 }, { 0x0044, 0xff },
	{ 0x0016, 0x08 }, { 0x0073, 0x0f }, { 0x0077, 0x01 }, { 0x0052, 0x02 },
	{ 0x0020, 0x00 }, { 0x0021, 0x00 }, { 0x0022, 0x00 }, { 0x004e, 0x10 },
	{ 0x0079, 0x45 }, { 0x007a, 0x2b }, { 0x007b, 0x04 },
};

static int max98937_set_fmt(struct snd_soc_dai *dai, unsigned int fmt)
{
	struct max98937_priv *priv = snd_soc_component_get_drvdata(dai->component);
	unsigned int mode = 0;

	if ((fmt & SND_SOC_DAIFMT_CLOCK_PROVIDER_MASK) != SND_SOC_DAIFMT_CBC_CFC)
		return -EINVAL;

	switch (fmt & SND_SOC_DAIFMT_INV_MASK) {
	case SND_SOC_DAIFMT_NB_NF:
		break;
	case SND_SOC_DAIFMT_IB_NF:
		mode |= MAX98937_PCM_MODE_BCLKEDGE;
		break;
	default:
		return -EINVAL;
	}

	switch (fmt & SND_SOC_DAIFMT_FORMAT_MASK) {
	case SND_SOC_DAIFMT_I2S:
		mode |= MAX98937_PCM_MODE_FORMAT_I2S;
		break;
	case SND_SOC_DAIFMT_LEFT_J:
		mode |= MAX98937_PCM_MODE_FORMAT_LEFT;
		break;
	default:
		return -EINVAL;
	}

	regmap_update_bits(priv->regmap, MAX98937_PCM_MASTER_MODE,
			   MAX98937_PCM_MSTR_MODE_MASK, MAX98937_PCM_MSTR_MODE_SLAVE);
	regmap_update_bits(priv->regmap, MAX98937_PCM_MODE_CFG,
			   MAX98937_PCM_MODE_BCLKEDGE | MAX98937_PCM_MODE_FORMAT_MASK,
			   mode);
	return 0;
}

static int max98937_hw_params(struct snd_pcm_substream *substream,
			      struct snd_pcm_hw_params *params,
			      struct snd_soc_dai *dai)
{
	struct max98937_priv *priv = snd_soc_component_get_drvdata(dai->component);
	static const unsigned int rates[] = {
		8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000,
	};
	unsigned int chansz, bsel, sr;

	switch (params_physical_width(params)) {
	case 16:
		chansz = MAX98937_PCM_MODE_CHANSZ_16;
		bsel = 2;		/* 32 BCLK per frame */
		break;
	case 32:
		chansz = MAX98937_PCM_MODE_CHANSZ_32;
		bsel = 4;		/* 64 BCLK per frame */
		break;
	default:
		return -EINVAL;
	}

	for (sr = 0; sr < ARRAY_SIZE(rates); sr++)
		if (rates[sr] == params_rate(params))
			break;
	if (sr == ARRAY_SIZE(rates))
		return -EINVAL;

	regmap_update_bits(priv->regmap, MAX98937_PCM_MODE_CFG,
			   MAX98937_PCM_MODE_CHANSZ_MASK, chansz);
	regmap_update_bits(priv->regmap, MAX98937_PCM_CLOCK_SETUP,
			   MAX98937_PCM_BSEL_MASK, bsel);
	regmap_update_bits(priv->regmap, MAX98937_PCM_SR_SETUP1,
			   MAX98937_DIG_IF_SR_MASK, sr);
	regmap_update_bits(priv->regmap, MAX98937_PCM_SR_SETUP2,
			   MAX98937_SPK_SR_MASK | MAX98937_IVADC_SR_MASK,
			   sr << 4 | sr);
	return 0;
}

static int max98937_mute_stream(struct snd_soc_dai *dai, int mute, int stream)
{
	struct max98937_priv *priv = snd_soc_component_get_drvdata(dai->component);

	if (mute) {
		regmap_update_bits(priv->regmap, MAX98937_GLOBAL_ENABLE, 1, 0);
		regmap_update_bits(priv->regmap, MAX98937_AMP_ENABLES, 1, 0);
		return 0;
	}

	regmap_update_bits(priv->regmap, MAX98937_AMP_ENABLES, 1, 1);
	regmap_update_bits(priv->regmap, MAX98937_GLOBAL_ENABLE, 1, 1);
	/* vendor driver: without this the output stays silent */
	regmap_write(priv->regmap, MAX98937_REV_ID, 0x54);
	regmap_write(priv->regmap, MAX98937_REV_ID, 0x4d);
	regmap_write(priv->regmap, 0x030d, 0x40);
	return 0;
}

static const struct snd_soc_dai_ops max98937_dai_ops = {
	.set_fmt = max98937_set_fmt,
	.hw_params = max98937_hw_params,
	.mute_stream = max98937_mute_stream,
	.no_capture_mute = 1,
};

static struct snd_soc_dai_driver max98937_dai = {
	.name = "max98937-aif1",
	.playback = {
		.stream_name = "HiFi Playback",
		.channels_min = 1,
		.channels_max = 2,
		.rates = SNDRV_PCM_RATE_8000_48000,
		.formats = SNDRV_PCM_FMTBIT_S16_LE | SNDRV_PCM_FMTBIT_S24_LE |
			   SNDRV_PCM_FMTBIT_S32_LE,
	},
	.ops = &max98937_dai_ops,
};

static const DECLARE_TLV_DB_SCALE(max98937_spk_tlv, 300, 300, 0);
static const DECLARE_TLV_DB_SCALE(max98937_digital_tlv, -1600, 25, 0);

static const struct snd_kcontrol_new max98937_controls[] = {
	SOC_SINGLE_TLV("Speaker Volume", MAX98937_SPK_GAIN, 0, 6, 0,
		       max98937_spk_tlv),
	SOC_SINGLE_TLV("Digital Volume", MAX98937_AMP_VOLUME, 0, 0x7f, 0,
		       max98937_digital_tlv),
};

static const struct snd_soc_dapm_widget max98937_dapm_widgets[] = {
	SND_SOC_DAPM_AIF_IN("AIF IN", "HiFi Playback", 0, SND_SOC_NOPM, 0, 0),
	SND_SOC_DAPM_OUTPUT("SPK"),
};

static const struct snd_soc_dapm_route max98937_dapm_routes[] = {
	{ "SPK", NULL, "AIF IN" },
};

static const struct snd_soc_component_driver max98937_component = {
	.controls = max98937_controls,
	.num_controls = ARRAY_SIZE(max98937_controls),
	.dapm_widgets = max98937_dapm_widgets,
	.num_dapm_widgets = ARRAY_SIZE(max98937_dapm_widgets),
	.dapm_routes = max98937_dapm_routes,
	.num_dapm_routes = ARRAY_SIZE(max98937_dapm_routes),
	.idle_bias_on = 1,
	.use_pmdown_time = 1,
	.endianness = 1,
};

static const struct regmap_config max98937_regmap_config = {
	.reg_bits = 16,
	.val_bits = 8,
	.max_register = MAX98937_REV_ID,
	.cache_type = REGCACHE_NONE,
};

static int max98937_i2c_probe(struct i2c_client *i2c)
{
	struct device *dev = &i2c->dev;
	struct max98937_priv *priv;
	unsigned int rev;
	int ret;

	priv = devm_kzalloc(dev, sizeof(*priv), GFP_KERNEL);
	if (!priv)
		return -ENOMEM;
	i2c_set_clientdata(i2c, priv);

	priv->regmap = devm_regmap_init_i2c(i2c, &max98937_regmap_config);
	if (IS_ERR(priv->regmap))
		return dev_err_probe(dev, PTR_ERR(priv->regmap), "regmap init failed\n");

	priv->reset_gpio = devm_gpiod_get_optional(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(priv->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(priv->reset_gpio), "no reset GPIO\n");
	if (priv->reset_gpio) {
		usleep_range(1000, 2000);
		gpiod_set_value_cansleep(priv->reset_gpio, 0);
		usleep_range(5000, 6000);
	}

	ret = regmap_read(priv->regmap, MAX98937_REV_ID, &rev);
	if (ret)
		return dev_err_probe(dev, ret, "failed to read revision\n");
	if (!(rev & 0x40))
		return dev_err_probe(dev, -ENODEV, "unexpected revision 0x%02x\n", rev);
	dev_info(dev, "MAX98937 revision 0x%02x\n", rev);

	ret = regmap_multi_reg_write(priv->regmap, max98937_init,
				     ARRAY_SIZE(max98937_init));
	if (ret)
		return dev_err_probe(dev, ret, "register init failed\n");

	return devm_snd_soc_register_component(dev, &max98937_component,
					       &max98937_dai, 1);
}

static void max98937_i2c_remove(struct i2c_client *i2c)
{
	struct max98937_priv *priv = i2c_get_clientdata(i2c);

	regmap_write(priv->regmap, MAX98937_GLOBAL_ENABLE, 0);
	if (priv->reset_gpio)
		gpiod_set_value_cansleep(priv->reset_gpio, 1);
}

static const struct of_device_id max98937_of_match[] = {
	{ .compatible = "maxim,max98937" },
	{ }
};
MODULE_DEVICE_TABLE(of, max98937_of_match);

static const struct i2c_device_id max98937_i2c_id[] = {
	{ "max98937" },
	{ }
};
MODULE_DEVICE_TABLE(i2c, max98937_i2c_id);

static struct i2c_driver max98937_i2c_driver = {
	.driver = {
		.name = "max98937",
		.of_match_table = max98937_of_match,
	},
	.probe = max98937_i2c_probe,
	.remove = max98937_i2c_remove,
	.id_table = max98937_i2c_id,
};
module_i2c_driver(max98937_i2c_driver);

MODULE_DESCRIPTION("ASoC Maxim MAX98937 speaker amplifier driver");
MODULE_LICENSE("GPL");
