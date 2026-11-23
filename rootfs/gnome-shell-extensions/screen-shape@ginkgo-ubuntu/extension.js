// SPDX-License-Identifier: GPL-2.0-or-later
//
// Keep GNOME Shell's top bar clear of the display notch and the rounded
// corners. The panel shape is looked up by the device-tree compatible
// strings of this machine in gmobile-style display-panel JSON files
// ({"x-res", "y-res", "border-radius", "cutouts": [{"path": SVG path}]}):
// the same data Phosh uses, so supported phones work without code changes.

import GLib from 'gi://GLib';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const DATA_DIRS = [
    '/etc/display-panels',
    '/usr/share/display-panels',
    '/usr/share/gmobile/display-panels',
];

function readText(path) {
    try {
        const [ok, bytes] = GLib.file_get_contents(path);
        return ok ? new TextDecoder().decode(bytes) : null;
    } catch {
        return null;
    }
}

function loadPanelInfo() {
    const compat = readText('/proc/device-tree/compatible');
    if (!compat)
        return null;
    for (const name of compat.split('\0').filter(s => s)) {
        for (const dir of DATA_DIRS) {
            const text = readText(`${dir}/${name}.json`);
            if (text) {
                try {
                    return JSON.parse(text);
                } catch (e) {
                    console.warn(`screen-shape: bad ${dir}/${name}.json: ${e}`);
                }
            }
        }
    }
    return null;
}

// Bounding box of all points in an SVG path (absolute M/L/C coordinates).
function pathBounds(path) {
    const pts = [...path.matchAll(/(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)/g)]
        .map(m => [parseFloat(m[1]), parseFloat(m[2])]);
    if (!pts.length)
        return null;
    const xs = pts.map(p => p[0]), ys = pts.map(p => p[1]);
    return {x1: Math.min(...xs), x2: Math.max(...xs), y1: Math.min(...ys), y2: Math.max(...ys)};
}

export default class ScreenShapeExtension extends Extension {
    enable() {
        this._info = loadPanelInfo();
        if (!this._info) {
            console.log('screen-shape: no display-panel data for this device');
            return;
        }
        this._monitorsId = Main.layoutManager.connect('monitors-changed',
            () => this._apply());
        // the UI scale can change without a monitor change
        this._themeContext = St.ThemeContext.get_for_stage(global.stage);
        this._scaleId = this._themeContext.connect('notify::scale-factor',
            () => this._apply());
        this._apply();
    }

    disable() {
        if (this._monitorsId)
            Main.layoutManager.disconnect(this._monitorsId);
        this._monitorsId = 0;
        if (this._scaleId)
            this._themeContext.disconnect(this._scaleId);
        this._scaleId = 0;
        this._restore();
        this._info = null;
    }

    _apply() {
        this._restore();

        const monitor = Main.layoutManager.primaryMonitor;
        if (!monitor || !this._info['x-res'])
            return;
        const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor;
        // panel data is in native pixels of the unrotated (portrait) panel;
        // the monitor can be rotated (auto-rotate), so scale by the short side
        const k = Math.min(monitor.width, monitor.height) / this._info['x-res'];
        const radius = (this._info['border-radius'] ?? 0) * k;
        // the notch is on the short top edge: in landscape it is beside the
        // bar, not in it (upside-down portrait is not told apart)
        const portrait = monitor.height >= monitor.width;

        const panel = Main.panel;
        let panelH = panel.get_preferred_height(-1)[1];

        let style = '';

        // Notch: make the bar at least as tall as the cutout, move the
        // centered clock out of it.
        let notch = null;
        for (const c of portrait ? this._info.cutouts ?? [] : []) {
            const b = c.path ? pathBounds(c.path) : null;
            if (b && b.y1 <= 1)
                notch = {x1: b.x1 * k, x2: b.x2 * k, y2: b.y2 * k};
        }
        if (notch && panelH < notch.y2) {
            style += `min-height: ${Math.ceil(notch.y2 / scale)}px;`;
            panelH = notch.y2;
        }

        // Rounded corners: horizontal inset of the arc at the top of the
        // content band of the bar (icons/text are vertically centered).
        if (radius > 0) {
            const contentTop = Math.max(0, panelH / 2 - 10 * scale);
            let inset = 0;
            if (contentTop < radius)
                inset = radius - Math.sqrt(radius ** 2 - (radius - contentTop) ** 2);
            inset += 2 * scale;
            const pad = Math.ceil(inset / scale);
            style += `padding-left: ${pad}px; padding-right: ${pad}px;`;
        }

        if (style) {
            this._oldStyle = panel.get_style();
            panel.set_style(style);
        }

        const dateMenu = panel.statusArea.dateMenu?.container;
        const center = monitor.width / 2;
        if (notch && dateMenu && notch.x1 < center && notch.x2 > center &&
            dateMenu.get_parent() === panel._centerBox) {
            this._clockIndex = panel._centerBox.get_children().indexOf(dateMenu);
            panel._centerBox.remove_child(dateMenu);
            panel._leftBox.insert_child_at_index(dateMenu,
                Math.min(1, panel._leftBox.get_n_children()));
            this._movedClock = dateMenu;
        }

        console.log(`screen-shape: ${this._info.name ?? 'panel'}: ${style || 'no style'}` +
            `${this._movedClock ? ', clock moved out of the notch' : ''}`);
    }

    _restore() {
        const panel = Main.panel;
        if (this._oldStyle !== undefined) {
            panel.set_style(this._oldStyle);
            this._oldStyle = undefined;
        }
        if (this._movedClock) {
            this._movedClock.get_parent()?.remove_child(this._movedClock);
            panel._centerBox.insert_child_at_index(this._movedClock,
                Math.max(0, this._clockIndex ?? 0));
            this._movedClock = null;
        }
    }
}
