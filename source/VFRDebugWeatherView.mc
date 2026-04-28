import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Lang;

// Debug view: shows raw phone weather payload on startup.
// Stays visible until the user presses BACK. Up/Down scroll, page up/down jump.
// All input is handled by VFRDebugWeatherDelegate (BehaviorDelegate).
class VFRDebugWeatherView extends WatchUi.View {
    // Exposed to delegate for scroll control
    var scroll  as Number = 0;
    var maxLines as Number = 8;

    private var _lines as Array = [];

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        scroll = 0;
        _rebuildLines();
        WatchUi.requestUpdate();
    }

    function onHide() as Void {}
    function onLayout(dc as Dc) as Void {}

    function onUpdate(dc as Dc) as Void {
        var w   = dc.getWidth();
        var h   = dc.getHeight();
        var cx  = w / 2;
        var jc  = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var now = System.getTimer();

        // Fill background black
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // ── Header ──────────────────────────────────────────────────────────
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 22, Graphics.FONT_MEDIUM, "RAW WEATHER (phone)", jc);

        // Divider line under header
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(4, 38, w - 4, 38);

        // --- Connection debug (phone/app/comms) ---
        var comms = null;
        try { comms = getApp().getComms(); } catch (e) { comms = null; }
        // Drive comms state machine even while the debug view is shown
        try { if (comms != null) { comms.tick(now); } } catch (et) {}
        var connLabel = "(no comms)";
        var hsAgeStr = "";
        var flightId = "";
        try {
            if (comms != null) {
                if (comms.connected == true) { connLabel = "CONNECTED"; }
                else if (comms.connecting == true) { connLabel = "CONNECTING"; }
                else { connLabel = "PHONE UNREACHABLE"; }
                try { if (comms.messagesRegistered == true) { connLabel = connLabel + " (msg cb ok)"; } else { connLabel = connLabel + " (no msg cb)"; } } catch (e4) {}
                try {
                    if (comms.lastHandshakeAt != null && (comms.lastHandshakeAt as Number) > 0) {
                        var ageMs = System.getTimer() - (comms.lastHandshakeAt as Number);
                        hsAgeStr = " hs:" + ((ageMs / 1000).toNumber()).toString() + "s";
                    }
                } catch (e2) {}
                try { if (comms.flightId != null) { flightId = " id:" + (comms.flightId as String); } } catch (e3) {}
            }
        } catch (e) {}
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 46, Graphics.FONT_XTINY, connLabel + hsAgeStr + flightId, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Show last saved raw payload from Application.Properties (VFRLogger fallback)
        var lastSaved = null;
        try { lastSaved = Application.Properties.getValue("VFR_lastRawPayload"); } catch (e) { lastSaved = null; }
        if (lastSaved != null) {
            var savedStr = (lastSaved as String);
            // draw on a single line below the connection info (trimmed)
            if (savedStr.length() > 80) { savedStr = savedStr.substring(0, 80) + "..."; }
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(6, 60, Graphics.FONT_XTINY, savedStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // ── Refresh lines from comms every frame so new data shows live ────
        _rebuildLines();

        // ── Content area ────────────────────────────────────────────────────
        var lineH    = 18;
        var startY   = 46;
        var visLines = ((h - startY - 4) / lineH).toNumber();
        if (visLines < 1) { visLines = 1; }
        maxLines = visLines;

        // Clamp scroll
        var lastScroll = (_lines.size() - visLines);
        if (lastScroll < 0) { lastScroll = 0; }
        if (scroll < 0) { scroll = 0; }
        if (scroll > lastScroll) { scroll = lastScroll; }

        if (_lines.size() == 0) {
            // Bold "NO PAYLOAD" notice
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h / 2, Graphics.FONT_LARGE, "NO PAYLOAD", jc);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h / 2 + 28, Graphics.FONT_SMALL, "Waiting for phone...", jc);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            for (var i = 0; i < visLines; i++) {
                var idx = scroll + i;
                if (idx >= _lines.size()) { break; }
                dc.drawText(4, startY + (i * lineH), Graphics.FONT_SMALL,
                    (_lines[idx] as String),
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            }

            // Scrollbar on right edge
            if (_lines.size() > visLines) {
                var sbX     = w - 5;
                var sbTop   = startY;
                var sbBot   = h - 4;
                var sbH     = sbBot - sbTop;
                var tH      = (sbH * visLines / _lines.size()).toNumber();
                if (tH < 6) { tH = 6; }
                var tY      = sbTop + ((sbH - tH) * scroll / lastScroll).toNumber();
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(3);
                dc.drawLine(sbX, sbTop, sbX, sbBot);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(sbX, tY, sbX, tY + tH);
                dc.setPenWidth(1);
            }

            // Page indicator (e.g. "3/12")
            var totalPages = ((_lines.size() + visLines - 1) / visLines).toNumber();
            var curPage    = (scroll / visLines).toNumber() + 1;
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h - 10, Graphics.FONT_XTINY,
                curPage.toString() + "/" + totalPages.toString(), jc);
        }
    }

    // Rebuild wrapped lines from current comms payload
    function _rebuildLines() as Void {
        var raw = "(no payload)";
        try {
            var comms = getApp().getComms();
            if (comms != null && comms.lastRawWeather != null
                    && (comms.lastRawWeather as String).length() > 0) {
                raw = comms.lastRawWeather as String;
            }
        } catch (e) {
            raw = "(error reading comms)";
        }

        // Wrap at 30 chars per line (safe for FONT_SMALL on 260px wide display)
        var out  = [] as Array<String>;
        var cur  = raw;
        var wrap = 30;
        while (cur.length() > 0) {
            var take = (cur.length() < wrap) ? cur.length() : wrap;
            out.add(cur.substring(0, take) as String);
            cur = cur.substring(take, cur.length()) as String;
        }
        _lines = out;
    }
}

// ── Delegate — all input here ────────────────────────────────────────────────
class VFRDebugWeatherDelegate extends WatchUi.BehaviorDelegate {
    private var _view as VFRDebugWeatherView;

    function initialize(v as VFRDebugWeatherView) {
        BehaviorDelegate.initialize();
        _view = v;
    }

    // BACK → open main view
    function onBack() as Boolean {
        try {
            // Remove debug view from the stack then push main so BACK from
            // main will exit the app (expected behaviour).
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            var main = new VFRStopWatchView();
            WatchUi.pushView(main, new VFRStopWatchDelegate(main), WatchUi.SLIDE_LEFT);
        } catch (e) {}
        return true;
    }

    // SELECT → also open main view
    function onSelect() as Boolean {
        try {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            var main = new VFRStopWatchView();
            WatchUi.pushView(main, new VFRStopWatchDelegate(main), WatchUi.SLIDE_LEFT);
        } catch (e) {}
        return true;
    }

    // UP button → scroll one line up
    function onPreviousPage() as Boolean {
        _view.scroll = _view.scroll - 1;
        if (_view.scroll < 0) { _view.scroll = 0; }
        WatchUi.requestUpdate();
        return true;
    }

    // DOWN button → scroll one line down
    function onNextPage() as Boolean {
        _view.scroll = _view.scroll + 1;
        WatchUi.requestUpdate();
        return true;
    }
}
