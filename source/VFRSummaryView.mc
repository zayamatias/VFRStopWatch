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

    function fmtTimeMs(ms as Number) as String {
        var totalSec = (ms / 1000).toNumber();
        var hours = (totalSec / 3600).toNumber();
        var mins = ((totalSec % 3600) / 60).toNumber();
        var secs = (totalSec % 60).toNumber();
        var hStr = hours.toString();
        var mStr = mins < 10 ? "0" + mins.toString() : mins.toString();
        var sStr = secs < 10 ? "0" + secs.toString() : secs.toString();
        return hStr + ":" + mStr + ":" + sStr;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        // Start Local Time
        var ltStr = "--:--";
        if (_main.tripStartLocal != null) {
            var ct = _main.tripStartLocal as System.ClockTime;
            var lh = ct.hour;
            var lm = ct.min;
            var lhStr = lh < 10 ? "0" + lh.toString() : lh.toString();
            var lmStr = lm < 10 ? "0" + lm.toString() : lm.toString();
            ltStr = "LT " + lhStr + ":" + lmStr;
        }

        // Start UTC
        var utcStr = "UTC --:--";
        if (_main.tripStartUtcMoment != null) {
            var info = Gregorian.utcInfo((_main.tripStartUtcMoment as Time.Moment), Time.FORMAT_SHORT);
            var uh = info.hour;
            var um = info.min;
            var uhStr = uh < 10 ? "0" + uh.toString() : uh.toString();
            var umStr = um < 10 ? "0" + um.toString() : um.toString();
            utcStr = "UTC " + uhStr + ":" + umStr;
        }

        // Total time
        var totalMs = _main.elapsed;
        var totalStr = fmtTimeMs(totalMs);

        // Distances
        var km = (_main.totalDistanceM / 1000.0).toNumber();
        var nm = (_main.totalDistanceM / 1852.0).toNumber();
        var kmInt = km.toNumber();
        var kmDecFloat = km - kmInt.toFloat();
        var kmDec = (kmDecFloat * 10.0).toNumber();
        if (kmDec < 0) { kmDec = 0; }
        var kmStr = kmInt.toString() + "." + kmDec.toString() + " km";
        var nmInt = nm.toNumber();
        var nmDecFloat = nm - nmInt.toFloat();
        var nmDec = (nmDecFloat * 10.0).toNumber();
        if (nmDec < 0) { nmDec = 0; }
        var nmStr = nmInt.toString() + "." + nmDec.toString() + " NM";

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 12 / 100, Graphics.FONT_SMALL, ltStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 28 / 100, Graphics.FONT_SMALL, utcStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 46 / 100, Graphics.FONT_MEDIUM, totalStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 64 / 100, Graphics.FONT_SMALL, nmStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 80 / 100, Graphics.FONT_SMALL, kmStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        WatchUi.requestUpdate();
    }
}

class VFRSummaryDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onSelect() as Boolean {
        // also close on select
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
