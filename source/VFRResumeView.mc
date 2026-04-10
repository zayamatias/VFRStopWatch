import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Shown on launch when a previous session backup exists.
// SELECT → keep restored state, return to main view, press START to resume timing.
// BACK / UP → reset everything, fresh start.
class VFRResumeView extends WatchUi.View {
    private var _main as VFRStopWatchView;

    function initialize(mainView as VFRStopWatchView) {
        View.initialize();
        _main = mainView;
    }

    function onLayout(dc as Dc) as Void {}

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        // Title
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 12 / 100, Graphics.FONT_TINY, "FLIGHT IN PROGRESS",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Saved elapsed time
        var totalSec = (_main.elapsed / 1000).toNumber();
        var hrs  = (totalSec / 3600).toNumber();
        var mins = ((totalSec % 3600) / 60).toNumber();
        var secs = (totalSec % 60).toNumber();
        var mStr = mins < 10 ? "0" + mins.toString() : mins.toString();
        var sStr = secs < 10 ? "0" + secs.toString() : secs.toString();
        var tStr = hrs > 0
            ? (hrs.toString() + ":" + mStr + ":" + sStr)
            : (mStr + ":" + sStr);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 38 / 100, Graphics.FONT_MEDIUM, tStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Instructions
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 58 / 100, Graphics.FONT_TINY, "START = Resume",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, h * 70 / 100, Graphics.FONT_TINY, "BACK / UP = New flight",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class VFRResumeDelegate extends WatchUi.BehaviorDelegate {
    private var _main as VFRStopWatchView;

    function initialize(mainView as VFRStopWatchView) {
        BehaviorDelegate.initialize();
        _main = mainView;
    }

    // SELECT → resume: keep restored state, pop back to main view
    function onSelect() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    // BACK / UP → new flight: wipe saved state
    function onBack() as Boolean {
        _main.reset();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onPreviousPage() as Boolean {
        _main.reset();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
