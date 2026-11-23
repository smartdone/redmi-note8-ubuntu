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

// App grid on a phone-sized screen. GNOME 46 picks the icon size from the
// first grid item only, but sizes the cells from the largest item (an app
// folder is bigger than an app icon), and picks rows x columns from a fixed
// list by aspect ratio (8x3, 6x4, 4x6, 3x8) whether they fit or not. On this
// screen the cells then do not fit, the spacing goes negative and icons
// overlap, differently after each rotation. Use a fixed icon size and as many
// rows/columns as really fit; the rest goes to the next page.
const APP_GRID_ICON_SIZE = 64;

function fittingGridMode(width, height) {
    const layout = this.layout_manager;
    const item = layout._getChildrenMaxSize?.() ?? 0;
    if (item <= 0) {
        // no items measured yet: GNOME's own choice
        Object.getPrototypeOf(this)._findBestModeForSize.call(this, width, height);
        return;
    }
    // The grid can be allocated taller than the scroll view that clips it
    // (landscape: the second row was cut off above the dash).
    const view = this.get_parent();
    if (view?.has_allocation())
        height = Math.min(height, view.allocation.get_height());
    const pad = layout.pagePadding;
    const w = width - pad.left - pad.right;
    const h = height - pad.top - pad.bottom;
    const columns = Math.max(1, Math.floor((w + layout.column_spacing) /
        (item + layout.column_spacing)));
    const rows = Math.max(1, Math.floor((h + layout.row_spacing) /
        (item + layout.row_spacing)));
    if (layout.columns_per_page !== columns || layout.rows_per_page !== rows) {
        console.log(`screen-shape: app grid ${columns}x${rows} for ${width}x${height} ` +
            `(item ${item}, padding ${pad.top}/${pad.right}/${pad.bottom}/${pad.left}, ` +
            `spacing ${layout.column_spacing}/${layout.row_spacing})`);
        layout.columns_per_page = columns;
        layout.rows_per_page = rows;
        // GNOME never moves items between pages when the page holds fewer
        // (or more) of them: the extra row stayed on the page, cut off.
        if (!this._ginkgoRepaginateId) {
            this._ginkgoRepaginateId = GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
                this._ginkgoRepaginateId = 0;
                try {
                    repaginate(this);
                } catch (e) {
                    console.warn(`screen-shape: app grid repagination failed: ${e}`);
                }
                return GLib.SOURCE_REMOVE;
            });
        }
    }
    this._currentMode = -1;
}

// Lay all items out again, in their current order, with the current number
// of items per page.
function repaginate(grid) {
    const layout = grid.layout_manager;
    if (!Array.isArray(layout._pages) || typeof layout._addItemToPage !== 'function')
        return;
    const perPage = layout.columns_per_page * layout.rows_per_page;
    const items = layout._pages.flatMap(page => [...page.children]);
    for (const item of items)
        layout._removeItemData(item);
    let visible = 0;
    for (const item of items) {
        let page;
        if (item.visible) {
            page = Math.floor(visible / perPage);
            visible++;
        } else {
            // hidden items stay next to the previous visible one
            page = Math.floor(Math.max(visible - 1, 0) / perPage);
        }
        layout._addItemToPage(item, Math.min(page, layout._pages.length), -1);
    }
    grid.queue_relayout();
}

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
        this._fixAppGrid(true);
    }

    _fixAppGrid(enable) {
        const grid = Main.overview._overview?.controls?._appDisplay?._grid;
        const layout = grid?.layout_manager;
        if (!layout || !('fixed_icon_size' in layout) ||
            typeof grid._findBestModeForSize !== 'function')
            return;
        layout.fixed_icon_size = enable ? APP_GRID_ICON_SIZE : -1;
        if (enable) {
            grid._findBestModeForSize = fittingGridMode;
        } else {
            delete grid._findBestModeForSize;
            if (grid._ginkgoRepaginateId)
                GLib.source_remove(grid._ginkgoRepaginateId);
            grid._ginkgoRepaginateId = 0;
        }
        grid._currentMode = -1;
        // sizes are only re-evaluated when the page size changes
        layout._pageWidth = layout._pageHeight = 0;
        layout._childrenMaxSize = -1;
        grid.queue_relayout();
    }

    disable() {
        if (this._monitorsId)
            Main.layoutManager.disconnect(this._monitorsId);
        this._monitorsId = 0;
        if (this._scaleId)
            this._themeContext.disconnect(this._scaleId);
        this._scaleId = 0;
        this._restore();
        this._fixAppGrid(false);
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
