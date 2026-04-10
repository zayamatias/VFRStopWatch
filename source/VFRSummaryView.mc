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

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        // Title
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 10 / 100, Graphics.FONT_TINY, "FLIGHT SUMMARY",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Start UTC
        var startStr = "--:--Z";
        if (_main.tripStartUtcMoment != null) {
            startStr = fmtUtc(_main.tripStartUtcMoment as Time.Moment);
        } else if ((_main as VFRStopWatchView).tripStartUtcHour >= 0) {
            var sh = (_main as VFRStopWatchView).tripStartUtcHour;
            var sm = (_main as VFRStopWatchView).tripStartUtcMin;
            var shStr = sh < 10 ? "0" + sh.toString() : sh.toString();
            var smStr = sm < 10 ? "0" + sm.toString() : sm.toString();
            startStr = shStr + ":" + smStr + "Z";
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 25 / 100, Graphics.FONT_TINY, "START",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 36 / 100, Graphics.FONT_SMALL, startStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // End UTC
        var endStr = "--:--Z";
        if (_main.tripEndUtcMoment != null) {
            endStr = fmtUtc(_main.tripEndUtcMoment as Time.Moment);
        } else if ((_main as VFRStopWatchView).tripEndUtcHour >= 0) {
            var eh = (_main as VFRStopWatchView).tripEndUtcHour;
            var em = (_main as VFRStopWatchView).tripEndUtcMin;
            var ehStr = eh < 10 ? "0" + eh.toString() : eh.toString();
            var emStr = em < 10 ? "0" + em.toString() : em.toString();
            endStr = ehStr + ":" + emStr + "Z";
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 52 / 100, Graphics.FONT_TINY, "END",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 63 / 100, Graphics.FONT_SMALL, endStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Distances — NM and km on the bottom two rows
        var nmStr = fmtDist(_main.totalDistanceM, 1852.0, "NM");
        var kmStr = fmtDist(_main.totalDistanceM, 1000.0, "km");
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 78 / 100, Graphics.FONT_TINY, nmStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, h * 90 / 100, Graphics.FONT_TINY, kmStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
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
