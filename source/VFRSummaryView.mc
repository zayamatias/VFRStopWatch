import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

class VFRSummaryView extends WatchUi.View {
    private var _main as VFRStopWatchView;
    private var _bigFont as Graphics.VectorFont? = null;

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

    function onUpdate(dc as Dc) as Void {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var minWh = (w < h) ? w : h;

        _main.drawBezelBackground(dc);

        // Black inner circle
        var sepR = ((minWh.toFloat() / 2.0) - 27.0).toNumber();
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

        var altStr = "---FT";
        if (_main.maxAltitudeM != null && (_main.maxAltitudeM as Float) > 0.0) {
            var altFt = ((_main.maxAltitudeM as Float) * 3.28084).toNumber();
            altStr = altFt.toString() + "FT";
        }

        var gsStr = "--KT";
        try {
            if ((_main as VFRStopWatchView).gsSamples > 0) {
                var avg = (_main as VFRStopWatchView).gsSumKt / (_main as VFRStopWatchView).gsSamples.toFloat();
                gsStr = Math.round(avg).toNumber().toString() + "KT";
            }
        } catch (ex) { }

        // --- Layout constants ---
        // Each row: label right-justified at cx-6 (blue), value left-justified at cx+6 (white)
        // This pair is symmetric about cx → visually centered on screen
        var lblX  = cx - 6;
        var valX  = cx + 6;
        var jrvc  = Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER;
        var jlvc  = Graphics.TEXT_JUSTIFY_LEFT  | Graphics.TEXT_JUSTIFY_VCENTER;
        var lFont = Graphics.FONT_SMALL;   // blue labels
        var vFont = Graphics.FONT_MEDIUM;  // white values

        // 3 rows above divider (OBT / IBT / DIST.), pitch = 28px
        var pitch = 28;
        var divY  = cy + 12;
        var row3Y = divY - 14;           // DIST.
        var row2Y = row3Y - pitch;       // IBT
        var row1Y = row2Y - pitch;       // OBT

        // 2 rows below divider (M.ALT / A.GS), pitch = 30px
        var row4Y = divY + 22;           // M.ALT
        var row5Y = row4Y + 30;          // A.GS

        dc.setColor(Graphics.COLOR_BLUE,  Graphics.COLOR_TRANSPARENT);
        dc.drawText(lblX, row1Y, lFont, "OBT", jrvc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(valX, row1Y, vFont, startStr, jlvc);

        dc.setColor(Graphics.COLOR_BLUE,  Graphics.COLOR_TRANSPARENT);
        dc.drawText(lblX, row2Y, lFont, "IBT", jrvc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(valX, row2Y, vFont, endStr, jlvc);

        dc.setColor(Graphics.COLOR_BLUE,  Graphics.COLOR_TRANSPARENT);
        dc.drawText(lblX, row3Y, lFont, "DIST.", jrvc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(valX, row3Y, vFont, distStr, jlvc);

        // Divider
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(cx - sepR + 8, divY, cx + sepR - 8, divY);
        dc.setPenWidth(1);

        dc.setColor(Graphics.COLOR_BLUE,  Graphics.COLOR_TRANSPARENT);
        dc.drawText(lblX, row4Y, lFont, "M.ALT", jrvc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(valX, row4Y, vFont, altStr, jlvc);

        dc.setColor(Graphics.COLOR_BLUE,  Graphics.COLOR_TRANSPARENT);
        dc.drawText(lblX, row5Y, lFont, "A.GS", jrvc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(valX, row5Y, vFont, gsStr, jlvc);
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
