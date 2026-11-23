// SPDX-License-Identifier: GPL-2.0-only
/*
 * FocalTech FT8719 in-cell touchscreen over SPI (host-download firmware).
 *
 * Protocol taken from the FocalTech/Xiaomi GPL driver for the Redmi Note 8
 * (drivers/input/touchscreen/ft8719_spi_c3j in the vendor kernel):
 *
 *  - every exchange starts with polling a status packet (0x05) until the
 *    controller is idle,
 *  - a command packet (0xC0, ctrl|len, cmd...) selects the register,
 *  - a data packet (0x3F, data...) moves the payload; reads carry a
 *    CRC-16/KERMIT trailer.
 *
 * The controller has no flash: after reset the ROM boot loader waits for the
 * application to be written into program RAM, checked (ECC) and started.
 */

#include <linux/delay.h>
#include <linux/firmware.h>
#include <linux/gpio/consumer.h>
#include <linux/input.h>
#include <linux/input/mt.h>
#include <linux/input/touchscreen.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/regulator/consumer.h>
#include <linux/spi/spi.h>
#include <linux/workqueue.h>

#include <drm/drm_panel.h>

#define FT8719_STATUS_PKG		0x05
#define FT8719_COMMAND_PKG		0xc0
#define FT8719_DATA_PKG			0x3f
#define FT8719_CTRL_WRITE		0x00
#define FT8719_CTRL_READ		0xa0	/* read + data CRC */

#define FT8719_BUSY_TIMEOUT		100
#define FT8719_BUSY_DELAY_US		150
#define FT8719_CS_HIGH_DELAY_US		150
#define FT8719_FIRST_BYTE_DELAY_US	30
#define FT8719_MAX_CMD_LEN		16

/* boot loader / ROM commands */
#define FT8719_CMD_START1		0x55
#define FT8719_CMD_START2		0xaa
#define FT8719_CMD_READ_ID		0x90
#define FT8719_ROM_WRITE		0xae
#define FT8719_ROM_START_APP		0x08
#define FT8719_ROM_ECC			0xcc
#define FT8719_ROM_ECC_FINISH		0xce
#define FT8719_ROM_ECC_READ		0xcd

/* application registers */
#define FT8719_REG_CHIP_ID		0xa3
#define FT8719_REG_FW_VER		0xa6

#define FT8719_CHIP_ID_H		0x87
#define FT8719_CHIP_ID_L		0x19

#define FT8719_APP_INFO_OFF		0x100
#define FT8719_FW_MIN_LEN		0x120
#define FT8719_FW_MAX_LEN		(64 * 1024)
#define FT8719_PKT_FAST			(64 * 1024)
#define FT8719_PKT_SLOW			(4 * 1024 - 4)
#define FT8719_ECC_COEF			((1 << 15) + (1 << 10) + (1 << 3))

/* touch report: header(2) + 10 points * 6 bytes + gesture area */
#define FT8719_MAX_POINTS		10
#define FT8719_POINT_LEN		6
#define FT8719_REPORT_LEN		(FT8719_MAX_POINTS * FT8719_POINT_LEN + 3 + 6 * 4 + 4)

#define FT8719_DEFAULT_FW		"focaltech/ft8719_huaxing.bin"

struct ft8719 {
	struct spi_device *spi;
	struct input_dev *input;
	struct gpio_desc *reset_gpio;
	struct regulator *vddio;
	struct touchscreen_properties prop;
	struct mutex bus_lock;
	/* in-cell: the panel reset wipes the firmware, follow its power state */
	struct drm_panel_follower follower;
	struct work_struct resume_work;
	const char *fw_name;
	bool fw_running;
	u8 *buf;			/* DMA safe, FT8719_REPORT_LEN + 8 */
};

static int ft8719_xfer(struct ft8719 *ts, u8 *tx, u8 *rx, u32 len)
{
	struct spi_transfer xfer[2] = {
		{
			.tx_buf = tx,
			.rx_buf = rx,
			.len = 1,
			.delay = {
				.value = FT8719_FIRST_BYTE_DELAY_US,
				.unit = SPI_DELAY_UNIT_USECS,
			},
		}, {
			.tx_buf = tx + 1,
			.rx_buf = rx ? rx + 1 : NULL,
			.len = len - 1,
		},
	};
	int ret;

	ret = spi_sync_transfer(ts->spi, xfer, len > 1 ? 2 : 1);
	udelay(FT8719_CS_HIGH_DELAY_US);
	return ret;
}

static u16 ft8719_crc(const u8 *data, u32 len)
{
	u16 crc = 0xffff;
	u32 i;
	int j;

	for (i = 0; i < len; i++) {
		crc ^= data[i];
		for (j = 0; j < 8; j++)
			crc = (crc & 1) ? (crc >> 1) ^ 0x8408 : crc >> 1;
	}
	return crc;
}

static int ft8719_wait_idle(struct ft8719 *ts)
{
	u8 *b = ts->buf;
	int i, ret;

	for (i = 0; i < FT8719_BUSY_TIMEOUT; i++) {
		udelay(FT8719_BUSY_DELAY_US);
		b[0] = FT8719_STATUS_PKG;
		b[1] = 0xff;
		ret = ft8719_xfer(ts, b, b, 2);
		if (ret)
			continue;
		if (ts->fw_running ? (b[1] & 0x81) == 0x01 : (b[1] & 0x81) == 0x00)
			return 0;
	}
	dev_dbg(&ts->spi->dev, "bus busy, status 0x%02x (running %d)\n",
		b[1], ts->fw_running);
	return -EIO;
}

static int ft8719_cmd(struct ft8719 *ts, u8 ctrl, const u8 *cmd, u32 cmdlen,
		      u32 datalen)
{
	u8 *b = ts->buf;
	u32 n = 0, i;

	if (cmdlen + 2 > FT8719_MAX_CMD_LEN - 4)
		return -EINVAL;

	b[n++] = FT8719_COMMAND_PKG;
	b[n++] = 0;	/* ctrl | len, filled below */
	for (i = 0; i < cmdlen; i++)
		b[n++] = cmd[i];
	if (ts->fw_running && datalen) {
		b[n++] = (datalen >> 8) & 0xff;
		b[n++] = datalen & 0xff;
	}
	b[1] = ctrl | ((n - 2) & 0x0f);
	return ft8719_xfer(ts, b, NULL, n);
}

/* Write @cmd and optional @data. Caller holds bus_lock. */
static int ft8719_write_locked(struct ft8719 *ts, const u8 *cmd, u32 cmdlen,
			       const u8 *data, u32 datalen)
{
	u8 *tx;
	int ret;

	ret = ft8719_wait_idle(ts);
	if (ret)
		return ret;
	ret = ft8719_cmd(ts, FT8719_CTRL_WRITE, cmd, cmdlen, datalen);
	if (ret || !datalen)
		return ret;

	ret = ft8719_wait_idle(ts);
	if (ret)
		return ret;

	tx = kmalloc(datalen + 1, GFP_KERNEL);
	if (!tx)
		return -ENOMEM;
	tx[0] = FT8719_DATA_PKG;
	memcpy(tx + 1, data, datalen);
	ret = ft8719_xfer(ts, tx, NULL, datalen + 1);
	kfree(tx);
	return ret;
}

static int ft8719_write(struct ft8719 *ts, const u8 *cmd, u32 cmdlen,
			const u8 *data, u32 datalen)
{
	int ret;

	mutex_lock(&ts->bus_lock);
	ret = ft8719_write_locked(ts, cmd, cmdlen, data, datalen);
	mutex_unlock(&ts->bus_lock);
	return ret;
}

/* Read @len bytes into @out. With @cmd == NULL only the data phase runs. */
static int ft8719_read(struct ft8719 *ts, const u8 *cmd, u32 cmdlen,
		       u8 *out, u32 len)
{
	u8 *b = ts->buf;
	u16 crc;
	int ret;

	if (len + 3 > FT8719_REPORT_LEN + 8)
		return -EINVAL;

	mutex_lock(&ts->bus_lock);
	if (cmd) {
		ret = ft8719_wait_idle(ts);
		if (ret)
			goto out;
		ret = ft8719_cmd(ts, FT8719_CTRL_READ, cmd, cmdlen, len);
		if (ret)
			goto out;
		ret = ft8719_wait_idle(ts);
		if (ret)
			goto out;
	}

	memset(b, 0xff, len + 3);
	b[0] = FT8719_DATA_PKG;
	ret = ft8719_xfer(ts, b, b, len + 3);
	if (ret)
		goto out;

	memcpy(out, b + 1, len);
	crc = ft8719_crc(b + 1, len);
	if (crc != (b[len + 1] | (b[len + 2] << 8)))
		ret = -EBADMSG;
out:
	mutex_unlock(&ts->bus_lock);
	return ret;
}

static int ft8719_read_reg(struct ft8719 *ts, u8 reg, u8 *val)
{
	return ft8719_read(ts, &reg, 1, val, 1);
}

static void ft8719_reset(struct ft8719 *ts)
{
	gpiod_set_value_cansleep(ts->reset_gpio, 1);
	msleep(5);
	gpiod_set_value_cansleep(ts->reset_gpio, 0);
}

static int ft8719_enter_boot(struct ft8719 *ts)
{
	u8 cmd, id[2];
	int i, j, ret;

	ts->fw_running = false;
	for (i = 0; i < 10; i++) {
		ft8719_reset(ts);
		mdelay(8);
		for (j = 0; j < 3; j++) {
			cmd = FT8719_CMD_START1;
			ret = ft8719_write(ts, &cmd, 1, NULL, 0);
			if (ret)
				continue;
			mdelay(8);
			cmd = FT8719_CMD_READ_ID;
			ret = ft8719_read(ts, &cmd, 1, id, 2);
			if (!ret && id[0] == FT8719_CHIP_ID_H &&
			    id[1] == FT8719_CHIP_ID_L)
				return 0;
			dev_dbg(&ts->spi->dev, "boot id %02x%02x (%d)\n",
				id[0], id[1], ret);
		}
	}
	return -ENODEV;
}

static bool ft8719_fast_download(struct ft8719 *ts)
{
	static const u8 f2[] = { 0xf2, 0x00, 0x78, 0x0a, 0x00, 0x02 };
	u8 reg = 0xdb, v, v2[2];

	if (ft8719_read(ts, &reg, 1, &v, 1))
		return false;
	if (ft8719_read(ts, f2, sizeof(f2), v2, 2))
		return false;
	return v >= 0x18 && v2[0] == 0x55;
}

static u16 ft8719_ecc_host(const u8 *data, u32 len)
{
	u16 ecc = 0;
	u32 i;
	int j;

	for (i = 0; i < len; i += 2) {
		ecc ^= (data[i] << 8) | data[i + 1];
		for (j = 0; j < 16; j++)
			ecc = (ecc & 1) ? (ecc >> 1) ^ FT8719_ECC_COEF : ecc >> 1;
	}
	return ecc;
}

static int ft8719_ecc_tp(struct ft8719 *ts, u32 len, u16 *ecc)
{
	u8 cmd[7] = { FT8719_ROM_ECC, 0, 0, 0,
		      (len >> 16) & 0xff, (len >> 8) & 0xff, len & 0xff };
	u8 v[2];
	int i, ret;

	ret = ft8719_write(ts, cmd, sizeof(cmd), NULL, 0);
	if (ret)
		return ret;
	mdelay(3);

	cmd[0] = FT8719_ROM_ECC_FINISH;
	for (i = 0; i < 100; i++) {
		ret = ft8719_read(ts, cmd, 1, v, 1);
		if (ret)
			return ret;
		if (!v[0])
			break;
		mdelay(1);
	}
	if (i == 100)
		return -ETIMEDOUT;

	cmd[0] = FT8719_ROM_ECC_READ;
	ret = ft8719_read(ts, cmd, 1, v, 2);
	if (ret)
		return ret;
	*ecc = (v[0] << 8) | v[1];
	return 0;
}

static int ft8719_download(struct ft8719 *ts, const struct firmware *fw)
{
	struct device *dev = &ts->spi->dev;
	u32 len, off, pkt, n;
	u16 ecc_host, ecc_tp;
	u8 cmd[6];
	int ret;

	if (fw->size < FT8719_APP_INFO_OFF + 4)
		return -EINVAL;
	len = (fw->data[FT8719_APP_INFO_OFF] << 8) | fw->data[FT8719_APP_INFO_OFF + 1];
	n = (fw->data[FT8719_APP_INFO_OFF + 2] << 8) | fw->data[FT8719_APP_INFO_OFF + 3];
	if (len + n != 0xffff || len < FT8719_FW_MIN_LEN ||
	    len > FT8719_FW_MAX_LEN || len > fw->size) {
		dev_err(dev, "bad firmware image (len %u/%u)\n", len, n);
		return -EINVAL;
	}

	ret = ft8719_enter_boot(ts);
	if (ret) {
		dev_err(dev, "cannot enter boot loader\n");
		return ret;
	}

	pkt = ft8719_fast_download(ts) ? FT8719_PKT_FAST : FT8719_PKT_SLOW;
	for (off = 0; off < len; off += n) {
		n = min(pkt, len - off);
		cmd[0] = FT8719_ROM_WRITE;
		cmd[1] = (off >> 16) & 0xff;
		cmd[2] = (off >> 8) & 0xff;
		cmd[3] = off & 0xff;
		cmd[4] = (n >> 8) & 0xff;
		cmd[5] = n & 0xff;
		ret = ft8719_write(ts, cmd, sizeof(cmd), fw->data + off, n);
		if (ret) {
			dev_err(dev, "program RAM write at %u failed: %d\n", off, ret);
			return ret;
		}
		if (pkt == FT8719_PKT_SLOW)
			mdelay(3);
	}

	ecc_host = ft8719_ecc_host(fw->data, len);
	ret = ft8719_ecc_tp(ts, len, &ecc_tp);
	if (ret || ecc_host != ecc_tp) {
		dev_err(dev, "ECC mismatch (host %04x, tp %04x, %d)\n",
			ecc_host, ecc_tp, ret);
		return ret ?: -EIO;
	}

	cmd[0] = FT8719_ROM_START_APP;
	ret = ft8719_write(ts, cmd, 1, NULL, 0);
	if (ret)
		return ret;
	ts->fw_running = true;
	return 0;
}

static int ft8719_start(struct ft8719 *ts)
{
	struct device *dev = &ts->spi->dev;
	const struct firmware *fw;
	u8 id = 0, ver = 0;
	int ret, i;

	ret = request_firmware(&fw, ts->fw_name, dev);
	if (ret) {
		dev_err(dev, "cannot load firmware %s: %d\n", ts->fw_name, ret);
		return ret;
	}

	for (i = 0; i < 3; i++) {
		ret = ft8719_download(ts, fw);
		if (!ret)
			break;
	}
	release_firmware(fw);
	if (ret)
		return ret;

	for (i = 0; i < 10; i++) {
		msleep(50);
		if (!ft8719_read_reg(ts, FT8719_REG_CHIP_ID, &id) &&
		    id == FT8719_CHIP_ID_H)
			break;
	}
	if (id != FT8719_CHIP_ID_H) {
		dev_err(dev, "firmware did not start (id 0x%02x)\n", id);
		return -EIO;
	}
	ft8719_read_reg(ts, FT8719_REG_FW_VER, &ver);
	dev_info(dev, "firmware %s running, version 0x%02x\n", ts->fw_name, ver);
	return 0;
}

static irqreturn_t ft8719_irq(int irq, void *dev_id)
{
	struct ft8719 *ts = dev_id;
	u8 buf[FT8719_REPORT_LEN];
	int i, ret, id, flag, base;
	unsigned int x, y;

	if (!ts->fw_running)
		return IRQ_HANDLED;

	ret = ft8719_read(ts, NULL, 0, buf, sizeof(buf) - 1);
	dev_dbg(&ts->spi->dev, "report %d: %*ph\n", ret, 16, buf);
	if (ret || (buf[0] & 0xf0) != 0x90)
		return IRQ_HANDLED;

	/*
	 * buf[] here is the downstream point buffer shifted by one:
	 * buf[1] = point count, then 6 bytes per point starting at buf[2].
	 */
	for (i = 0; i < FT8719_MAX_POINTS; i++) {
		base = i * FT8719_POINT_LEN + 2;
		id = buf[base + 2] >> 4;
		if (id >= FT8719_MAX_POINTS)
			break;
		flag = buf[base] >> 6;
		x = ((buf[base] & 0x0f) << 8) | buf[base + 1];
		y = ((buf[base + 2] & 0x0f) << 8) | buf[base + 3];

		input_mt_slot(ts->input, id);
		/* 0 = down, 2 = contact, 1 = up */
		if (flag == 1) {
			input_mt_report_slot_inactive(ts->input);
			continue;
		}
		input_mt_report_slot_state(ts->input, MT_TOOL_FINGER, true);
		touchscreen_report_pos(ts->input, &ts->prop, x, y, true);
		input_report_abs(ts->input, ABS_MT_PRESSURE, buf[base + 4] ?: 0x3f);
		input_report_abs(ts->input, ABS_MT_TOUCH_MAJOR, buf[base + 5] >> 4);
	}
	/* point count 0 means every finger was lifted */
	if ((buf[1] & 0x0f) == 0) {
		for (i = 0; i < FT8719_MAX_POINTS; i++) {
			input_mt_slot(ts->input, i);
			input_mt_report_slot_inactive(ts->input);
		}
	}
	input_mt_sync_frame(ts->input);
	input_sync(ts->input);
	return IRQ_HANDLED;
}

static void ft8719_resume_work(struct work_struct *work)
{
	struct ft8719 *ts = container_of(work, struct ft8719, resume_work);

	if (ft8719_start(ts))
		return;
	enable_irq(ts->spi->irq);
}

static int ft8719_panel_prepared(struct drm_panel_follower *follower)
{
	struct ft8719 *ts = container_of(follower, struct ft8719, follower);

	/* firmware download takes ~100 ms, do not hold up the panel */
	schedule_work(&ts->resume_work);
	return 0;
}

static int ft8719_panel_unpreparing(struct drm_panel_follower *follower)
{
	struct ft8719 *ts = container_of(follower, struct ft8719, follower);
	int i;

	cancel_work_sync(&ts->resume_work);
	if (ts->fw_running)
		disable_irq(ts->spi->irq);
	ts->fw_running = false;

	for (i = 0; i < FT8719_MAX_POINTS; i++) {
		input_mt_slot(ts->input, i);
		input_mt_report_slot_inactive(ts->input);
	}
	input_mt_sync_frame(ts->input);
	input_sync(ts->input);
	return 0;
}

static const struct drm_panel_follower_funcs ft8719_follower_funcs = {
	.panel_prepared = ft8719_panel_prepared,
	.panel_unpreparing = ft8719_panel_unpreparing,
};

static int ft8719_probe(struct spi_device *spi)
{
	struct device *dev = &spi->dev;
	struct ft8719 *ts;
	int ret;

	ts = devm_kzalloc(dev, sizeof(*ts), GFP_KERNEL);
	if (!ts)
		return -ENOMEM;
	ts->buf = devm_kzalloc(dev, FT8719_REPORT_LEN + 8, GFP_KERNEL | GFP_DMA);
	if (!ts->buf)
		return -ENOMEM;
	ts->spi = spi;
	mutex_init(&ts->bus_lock);
	spi_set_drvdata(spi, ts);

	ts->fw_name = FT8719_DEFAULT_FW;
	device_property_read_string(dev, "firmware-name", &ts->fw_name);

	/* SPI mode 1, chip select active low (verified on hardware) */
	spi->mode = SPI_MODE_1 | (spi->mode & SPI_CS_HIGH);
	spi->bits_per_word = 8;
	if (!spi->max_speed_hz || spi->max_speed_hz > 10000000)
		spi->max_speed_hz = 10000000;
	ret = spi_setup(spi);
	if (ret)
		return ret;

	ts->reset_gpio = devm_gpiod_get(dev, "reset", GPIOD_OUT_LOW);
	if (IS_ERR(ts->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(ts->reset_gpio), "reset gpio\n");

	ts->vddio = devm_regulator_get(dev, "vddio");
	if (IS_ERR(ts->vddio))
		return dev_err_probe(dev, PTR_ERR(ts->vddio), "vddio supply\n");
	ret = regulator_enable(ts->vddio);
	if (ret)
		return ret;

	ts->input = devm_input_allocate_device(dev);
	if (!ts->input) {
		ret = -ENOMEM;
		goto err_regulator;
	}
	ts->input->name = "FocalTech FT8719 Touchscreen";
	ts->input->id.bustype = BUS_SPI;
	input_set_abs_params(ts->input, ABS_MT_POSITION_X, 0, 1079, 0, 0);
	input_set_abs_params(ts->input, ABS_MT_POSITION_Y, 0, 2339, 0, 0);
	input_set_abs_params(ts->input, ABS_MT_PRESSURE, 0, 255, 0, 0);
	input_set_abs_params(ts->input, ABS_MT_TOUCH_MAJOR, 0, 15, 0, 0);
	touchscreen_parse_properties(ts->input, true, &ts->prop);
	ret = input_mt_init_slots(ts->input, FT8719_MAX_POINTS,
				  INPUT_MT_DIRECT | INPUT_MT_DROP_UNUSED);
	if (ret)
		goto err_regulator;
	ret = input_register_device(ts->input);
	if (ret)
		goto err_regulator;

	ret = devm_request_threaded_irq(dev, spi->irq, NULL, ft8719_irq,
					IRQF_ONESHOT | IRQF_NO_AUTOEN, "ft8719", ts);
	if (ret)
		goto err_regulator;

	INIT_WORK(&ts->resume_work, ft8719_resume_work);
	if (drm_is_panel_follower(dev)) {
		/* firmware is loaded whenever the panel has been powered up */
		ts->follower.funcs = &ft8719_follower_funcs;
		ret = devm_drm_panel_add_follower(dev, &ts->follower);
		if (ret)
			goto err_regulator;
		return 0;
	}

	ret = ft8719_start(ts);
	if (ret)
		goto err_regulator;
	enable_irq(spi->irq);
	return 0;

err_regulator:
	regulator_disable(ts->vddio);
	return ret;
}

static void ft8719_remove(struct spi_device *spi)
{
	struct ft8719 *ts = spi_get_drvdata(spi);

	cancel_work_sync(&ts->resume_work);
	disable_irq(spi->irq);
	gpiod_set_value_cansleep(ts->reset_gpio, 1);
	regulator_disable(ts->vddio);
}

static const struct of_device_id ft8719_of_match[] = {
	{ .compatible = "focaltech,ft8719-spi" },
	{ }
};
MODULE_DEVICE_TABLE(of, ft8719_of_match);

static const struct spi_device_id ft8719_spi_ids[] = {
	{ "ft8719-spi" },
	{ }
};
MODULE_DEVICE_TABLE(spi, ft8719_spi_ids);

static struct spi_driver ft8719_driver = {
	.driver = {
		.name = "focaltech-ft8719-spi",
		.of_match_table = ft8719_of_match,
	},
	.id_table = ft8719_spi_ids,
	.probe = ft8719_probe,
	.remove = ft8719_remove,
};
module_spi_driver(ft8719_driver);

MODULE_DESCRIPTION("FocalTech FT8719 SPI touchscreen");
MODULE_LICENSE("GPL");
MODULE_FIRMWARE(FT8719_DEFAULT_FW);
