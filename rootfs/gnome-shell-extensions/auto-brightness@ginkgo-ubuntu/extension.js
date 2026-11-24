// Quick settings toggle for automatic screen brightness.
//
// gsd-power adjusts the backlight from the ambient light sensor (via
// iio-sensor-proxy) while org.gnome.settings-daemon.plugins.power
// ambient-enabled is true; GNOME only offers that switch deep inside
// Settings > Power. This puts it next to Wi-Fi/Bluetooth in the system menu.
// The toggle is hidden while iio-sensor-proxy reports no light sensor.

import Gio from 'gi://Gio';
import GObject from 'gi://GObject';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {QuickToggle, SystemIndicator} from 'resource:///org/gnome/shell/ui/quickSettings.js';

const POWER_SCHEMA = 'org.gnome.settings-daemon.plugins.power';

const SensorProxyIface = `
<node>
  <interface name="net.hadess.SensorProxy">
    <property name="HasAmbientLight" type="b" access="read"/>
  </interface>
</node>`;
const SensorProxy = Gio.DBusProxy.makeProxyWrapper(SensorProxyIface);

const AutoBrightnessToggle = GObject.registerClass(
class AutoBrightnessToggle extends QuickToggle {
    _init() {
        super._init({
            title: 'Auto Brightness',
            iconName: 'display-brightness-symbolic',
            toggleMode: true,
            visible: false,
        });

        this._settings = new Gio.Settings({schema_id: POWER_SCHEMA});
        this._settings.bind('ambient-enabled', this, 'checked',
            Gio.SettingsBindFlags.DEFAULT);

        this._proxy = null;
        this._cancellable = new Gio.Cancellable();
        new SensorProxy(Gio.DBus.system, 'net.hadess.SensorProxy',
            '/net/hadess/SensorProxy', (proxy, error) => {
                if (error) {
                    if (!error.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                        console.warn(`auto-brightness: no sensor proxy: ${error.message}`);
                    return;
                }
                this._proxy = proxy;
                this._propsId = proxy.connect('g-properties-changed',
                    () => this._sync());
                this._ownerId = proxy.connect('notify::g-name-owner',
                    () => this._sync());
                this._sync();
            }, this._cancellable);

        this.connect('destroy', () => {
            this._cancellable.cancel();
            if (this._proxy) {
                this._proxy.disconnect(this._propsId);
                this._proxy.disconnect(this._ownerId);
                this._proxy = null;
            }
            Gio.Settings.unbind(this, 'checked');
            this._settings = null;
        });
    }

    _sync() {
        // Without an owner the cached property is stale: keep the last state
        // while iio-sensor-proxy restarts (it is D-Bus activated on demand).
        if (this._proxy?.g_name_owner)
            this.visible = this._proxy.HasAmbientLight === true;
    }
});

const AutoBrightnessIndicator = GObject.registerClass(
class AutoBrightnessIndicator extends SystemIndicator {
    _init() {
        super._init();
        this.quickSettingsItems.push(new AutoBrightnessToggle());
    }

    destroy() {
        this.quickSettingsItems.forEach(item => item.destroy());
        super.destroy();
    }
});

export default class AutoBrightnessExtension extends Extension {
    enable() {
        this._indicator = new AutoBrightnessIndicator();
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
