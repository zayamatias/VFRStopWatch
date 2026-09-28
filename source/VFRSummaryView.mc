import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

class VFRSummaryView extends WatchUi.View {
    private var _main as VFRStopWatchView;

    function initialize(mainView as VFRStopWatchView) {
        View.initialize();
        _main = mainView;
    }

    function onLayout(dc as Dc) as Void {}

    // Format a UTC Moment as "HH:MM UTC"
    private function fmtUtc(moment as Time.Moment) as String {
        var info = Gregorian.utcInfo(moment, Time.FORMAT_SHORT);
        var h = info.hour;
        var m = info.min;
        var hStr = h < 10 ? "0" + h.toString() : h.toString();
        var mStr = m < 10 ? "0" + m.toString() : m.toString();
        return hStr + ":" + mStr + "Z";
    }

    // Format a distance in metres as "XX.X NM" or "XX.X km"
    private function fmtDist(metres as Float, divisor as Float, unit as String) as String {
        var val = metres / divisor;
        var intPart = val.toNumber();
        var decPart = ((val - intPart.toFloat()) * 10.0).toNumber();
        if (decPart < 0) { decPart = 0; }
        return intPart.toString() + "." + decPart.toString() + " " + unit;
    }

    // Draw a centred label/value row: label (blue, right-aligned) and value
    // (white, left-aligned), with the whole pair centred horizontally on cx.
    private function drawStatRow(dc as Dc, cx as Number, y as Number,
            label as String, value as String,
            lChar as Number, vChar as Number, gap as Number) as Void {
        var lw = label.length() * lChar;
        var vw = value.length() * vChar;
        var totalW = lw + gap + vw;
        var labelRightX = cx - (totalW / 2).toNumber() + lw;
        var valueLeftX  = labelRightX + gap;

        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(labelRightX, y, Graphics.FONT_SMALL, label,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(valueLeftX, y, Graphics.FONT_MEDIUM, value,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function onUpdate(dc as Dc) as Void {
        var now = System.getTimer();
        try { var c = getApp().getComms(); if (c != null) { c.tick(now); } } catch (ce) {}
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var minWh = (w < h) ? w : h;

        _main.drawBezelBackground(dc);

        // Black inner circle (leave the separator ring drawn by the bezel visible)
        var sepR = ((minWh.toFloat() / 2.0) - 30.0).toNumber();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillCircle(cx, cy, sepR);

        // --- Build time strings ---
        var startStr = "--:--Z";
        if (_main.tripStartUtcMoment != null) {
            startStr = fmtUtc(_main.tripStartUtcMoment as Time.Moment);
        } else if (_main.tripStartUtcHour >= 0) {
            var sh = _main.tripStartUtcHour;
            var sm = _main.tripStartUtcMin;
            startStr = (sh < 10 ? "0" : "") + sh.toString() + ":" + (sm < 10 ? "0" : "") + sm.toString() + "Z";
        }
        var endStr = "--:--Z";
        if (_main.tripEndUtcMoment != null) {
            endStr = fmtUtc(_main.tripEndUtcMoment as Time.Moment);
        } else if (_main.tripEndUtcHour >= 0) {
            var eh = _main.tripEndUtcHour;
            var em = _main.tripEndUtcMin;
            endStr = (eh < 10 ? "0" : "") + eh.toString() + ":" + (em < 10 ? "0" : "") + em.toString() + "Z";
        }

        // --- Build stat strings ---
        var nmVal = (_main.totalDistanceM as Float) / 1852.0;
        var nmInt = nmVal.toNumber();
        var nmDec = ((nmVal - nmInt.toFloat()) * 10.0).toNumber();
        if (nmDec < 0) { nmDec = 0; }
        var distStr = nmInt.toString() + "." + nmDec.toString() + "NM";

        var altStr = "---";
        if (_main.maxAltitudeM != null && (_main.maxAltitudeM as Float) > 0.0) {
            var altFt = ((_main.maxAltitudeM as Float) * 3.28084).toNumber();
            altStr = altFt.toString();
        }

        var ldgStr = (_main.landings as Number).toString();

        // Block time (H:MM:SS, or MM:SS under an hour)
        var blockMs = (_main.elapsed as Number);
        var blockSec = blockMs / 1000;
        var bh = blockSec / 3600;
        var bm = (blockSec % 3600) / 60;
        var bs = blockSec % 60;
        var timeStr = (bh >= 1)
            ? bh.toString() + ":" + (bm < 10 ? "0" : "") + bm.toString() + ":" + (bs < 10 ? "0" : "") + bs.toString()
            : bm.toString() + ":" + (bs < 10 ? "0" : "") + bs.toString();

        // Peak load factor (only when the accelerometer produced data)
        var gStr = "--G";
        try {
            if ((_main.maxG as Float) > 0.0) {
                var gv = _main.maxG as Float;
                var gi = gv.toNumber();
                var gd = ((gv - gi.toFloat()) * 100.0).toNumber();
                if (gd < 0) { gd = 0; }
                gStr = gi.toString() + "." + (gd < 10 ? "0" : "") + gd.toString() + "G";
            }
        } catch (gex) { }

        // --- Title ---
        var jc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 42, Graphics.FONT_XTINY, "TRIP SUMMARY", jc);

        // --- Layout constants ---
        // Seven rows inside the black inner circle (R ≈ 100 px). Row offsets and
        // label/value lengths were measured (Dc.getTextDimensions against the
        // circle's chord 2·sqrt(R²−dy²)): the widest rows sit near the middle,
        // where the chord is widest, so nothing is clipped by the round bezel.
        // Measured: OBT 147 px, IBT 138, TIME 163, DIST 164, LDG 90, ALT 117,
        // G 105 — chords: 157 @−62, 198 @−14, 187 @+36, 125 @+78.
        // "ALT" shows feet only (the old "M.ALT 4969FT" row was 180 px, wider
        // than the chord at any usable row height).
        var lChar = 10;   // FONT_SMALL label glyph width
        var vChar = 13;   // FONT_MEDIUM value glyph width
        var gap   = 18;   // gutter between label and value

        var rowY0 = cy - 62;   // OBT
        var rowY1 = cy - 38;   // IBT
        var rowY2 = cy - 14;   // TIME
        var divY  = cy - 2;    // divider between the time block and the rest
        var rowY3 = cy + 12;   // DIST
        var rowY4 = cy + 36;   // LDG
        var rowY5 = cy + 58;   // ALT
        var rowY6 = cy + 78;   // G (peak)

        drawStatRow(dc, cx, rowY0, "OBT",   startStr, lChar, vChar, gap);
        drawStatRow(dc, cx, rowY1, "IBT",   endStr,   lChar, vChar, gap);
        drawStatRow(dc, cx, rowY2, "TIME",  timeStr,  lChar, vChar, gap);

        // Divider
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(cx - sepR + 8, divY, cx + sepR - 8, divY);
        dc.setPenWidth(1);

        drawStatRow(dc, cx, rowY3, "DIST",  distStr, lChar, vChar, gap);
        drawStatRow(dc, cx, rowY4, "LDG",   ldgStr,  lChar, vChar, gap);
        drawStatRow(dc, cx, rowY5, "ALT",   altStr,  lChar, vChar, gap);
        drawStatRow(dc, cx, rowY6, "G",     gStr,    lChar, vChar, gap);
    }
}

class VFRSummaryDelegate extends WatchUi.BehaviorDelegate {
    private var _main as VFRStopWatchView;

    function initialize(mainView as VFRStopWatchView) {
        BehaviorDelegate.initialize();
        _main = mainView;
    }

    // Both Back and Select clear the backup and return to main view
    function onBack() as Boolean {
        _main.clearBackupProperties();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onSelect() as Boolean {
        _main.clearBackupProperties();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
