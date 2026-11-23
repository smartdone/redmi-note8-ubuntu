// SPDX-License-Identifier: GPL-2.0-only
/*
 * Huaxing FT8719 1080x2340 video mode DSI panel (Xiaomi Redmi Note 8, ginkgo).
 *
 * Generated with linux-mdss-dsi-panel-driver-generator from the stock
 * `qcom,mdss_dsi_ft8719_huaxing_video` node of the ginkgo dtbo, then adapted:
 * the backlight is the external LM3697 (`backlight` phandle), not DCS.
 * Copyright (c) 2013, The Linux Foundation. All rights reserved. (vendor DT)
 */

#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/regulator/consumer.h>

#include <video/mipi_display.h>

#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>
#include <drm/drm_probe_helper.h>

static const char * const ft8719_huaxing_supplies[] = {
	"vddio",	/* 1.8 V I/O */
	"vddpos",	/* PMI632 LCDB +5.5 V */
	"vddneg",	/* PMI632 LCDB -5.5 V */
};

struct ft8719_huaxing {
	struct drm_panel panel;
	struct mipi_dsi_device *dsi;
	struct regulator_bulk_data supplies[ARRAY_SIZE(ft8719_huaxing_supplies)];
	struct gpio_desc *reset_gpio;
};

static inline struct ft8719_huaxing *to_ft8719_huaxing(struct drm_panel *panel)
{
	return container_of_const(panel, struct ft8719_huaxing, panel);
}

static void ft8719_huaxing_reset(struct ft8719_huaxing *ctx)
{
	/* stock qcom,mdss-dsi-reset-sequence = <1 10>, <0 10>, <1 10> */
	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	usleep_range(10000, 11000);
	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	usleep_range(10000, 11000);
	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	usleep_range(10000, 11000);
}

static int ft8719_huaxing_on(struct ft8719_huaxing *ctx)
{
	struct mipi_dsi_multi_context dsi_ctx = { .dsi = ctx->dsi };

	ctx->dsi->mode_flags |= MIPI_DSI_MODE_LPM;

	/* unlock the FocalTech command set (FF 87 19 01 / 80: FF 87 19) */
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x00, 0x00);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0x87, 0x19, 0x01);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x00, 0x80);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0x87, 0x19);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x00, 0x80);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xca,
				     0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,
				     0x80, 0x80, 0x80, 0x80, 0x80);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x00, 0x90);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xca,
				     0xfe, 0xff, 0x66, 0xf6, 0xff, 0x66, 0xfb,
				     0xff, 0x32);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x00, 0xb5);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xca, 0x06);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x00, 0xb2);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xca, 0x0c);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_EXIT_SLEEP_MODE, 0x00);
	mipi_dsi_msleep(&dsi_ctx, 120);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_SET_DISPLAY_ON, 0x00);
	mipi_dsi_msleep(&dsi_ctx, 20);
	mipi_dsi_dcs_set_display_brightness_multi(&dsi_ctx, 0x00b8);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_WRITE_CONTROL_DISPLAY,
				     0x24);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_WRITE_POWER_SAVE, 0x00);

	return dsi_ctx.accum_err;
}

static int ft8719_huaxing_off(struct ft8719_huaxing *ctx)
{
	struct mipi_dsi_multi_context dsi_ctx = { .dsi = ctx->dsi };

	ctx->dsi->mode_flags &= ~MIPI_DSI_MODE_LPM;

	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_WRITE_CONTROL_DISPLAY,
				     0x24);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_SET_DISPLAY_OFF, 0x00);
	mipi_dsi_msleep(&dsi_ctx, 20);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_ENTER_SLEEP_MODE, 0x00);
	mipi_dsi_msleep(&dsi_ctx, 120);
	/* deep standby */
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x00, 0x00);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xf7, 0x5a, 0xa5, 0x95, 0x27);

	return dsi_ctx.accum_err;
}

static int ft8719_huaxing_prepare(struct drm_panel *panel)
{
	struct ft8719_huaxing *ctx = to_ft8719_huaxing(panel);
	struct device *dev = &ctx->dsi->dev;
	int ret;

	ret = regulator_bulk_enable(ARRAY_SIZE(ctx->supplies), ctx->supplies);
	if (ret) {
		dev_err(dev, "Failed to enable regulators: %d\n", ret);
		return ret;
	}

	ft8719_huaxing_reset(ctx);

	ret = ft8719_huaxing_on(ctx);
	if (ret < 0) {
		dev_err(dev, "Failed to initialize panel: %d\n", ret);
		gpiod_set_value_cansleep(ctx->reset_gpio, 1);
		regulator_bulk_disable(ARRAY_SIZE(ctx->supplies), ctx->supplies);
		return ret;
	}

	return 0;
}

static int ft8719_huaxing_unprepare(struct drm_panel *panel)
{
	struct ft8719_huaxing *ctx = to_ft8719_huaxing(panel);
	struct device *dev = &ctx->dsi->dev;
	int ret;

	ret = ft8719_huaxing_off(ctx);
	if (ret < 0)
		dev_err(dev, "Failed to un-initialize panel: %d\n", ret);

	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	regulator_bulk_disable(ARRAY_SIZE(ctx->supplies), ctx->supplies);

	return 0;
}

static const struct drm_display_mode ft8719_huaxing_mode = {
	.clock = (1080 + 72 + 4 + 80) * (2340 + 112 + 4 + 12) * 60 / 1000,
	.hdisplay = 1080,
	.hsync_start = 1080 + 72,
	.hsync_end = 1080 + 72 + 4,
	.htotal = 1080 + 72 + 4 + 80,
	.vdisplay = 2340,
	.vsync_start = 2340 + 112,
	.vsync_end = 2340 + 112 + 4,
	.vtotal = 2340 + 112 + 4 + 12,
	.width_mm = 67,
	.height_mm = 145,
	.type = DRM_MODE_TYPE_DRIVER,
};

static int ft8719_huaxing_get_modes(struct drm_panel *panel,
				    struct drm_connector *connector)
{
	return drm_connector_helper_get_modes_fixed(connector, &ft8719_huaxing_mode);
}

static const struct drm_panel_funcs ft8719_huaxing_panel_funcs = {
	.prepare = ft8719_huaxing_prepare,
	.unprepare = ft8719_huaxing_unprepare,
	.get_modes = ft8719_huaxing_get_modes,
};

static int ft8719_huaxing_probe(struct mipi_dsi_device *dsi)
{
	struct device *dev = &dsi->dev;
	struct ft8719_huaxing *ctx;
	int i, ret;

	ctx = devm_drm_panel_alloc(dev, struct ft8719_huaxing, panel,
				   &ft8719_huaxing_panel_funcs,
				   DRM_MODE_CONNECTOR_DSI);
	if (IS_ERR(ctx))
		return PTR_ERR(ctx);

	for (i = 0; i < ARRAY_SIZE(ctx->supplies); i++)
		ctx->supplies[i].supply = ft8719_huaxing_supplies[i];
	ret = devm_regulator_bulk_get(dev, ARRAY_SIZE(ctx->supplies), ctx->supplies);
	if (ret)
		return dev_err_probe(dev, ret, "Failed to get regulators\n");

	/* the bootloader leaves the panel on: keep it out of reset */
	ctx->reset_gpio = devm_gpiod_get(dev, "reset", GPIOD_OUT_LOW);
	if (IS_ERR(ctx->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->reset_gpio),
				     "Failed to get reset-gpios\n");

	ctx->dsi = dsi;
	mipi_dsi_set_drvdata(dsi, ctx);

	dsi->lanes = 4;
	dsi->format = MIPI_DSI_FMT_RGB888;
	dsi->mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_CLOCK_NON_CONTINUOUS;

	ctx->panel.prepare_prev_first = true;

	ret = drm_panel_of_backlight(&ctx->panel);
	if (ret)
		return dev_err_probe(dev, ret, "Failed to get backlight\n");

	ret = devm_drm_panel_add(dev, &ctx->panel);
	if (ret)
		return ret;

	return devm_mipi_dsi_attach(dev, dsi);
}

static const struct of_device_id ft8719_huaxing_of_match[] = {
	{ .compatible = "huaxing,ginkgo-ft8719" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, ft8719_huaxing_of_match);

static struct mipi_dsi_driver ft8719_huaxing_driver = {
	.probe = ft8719_huaxing_probe,
	.driver = {
		.name = "panel-huaxing-ft8719",
		.of_match_table = ft8719_huaxing_of_match,
	},
};
module_mipi_dsi_driver(ft8719_huaxing_driver);

MODULE_DESCRIPTION("DRM driver for the Huaxing FT8719 video mode DSI panel");
MODULE_LICENSE("GPL");
