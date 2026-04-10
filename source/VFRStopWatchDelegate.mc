import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class VFRStopWatchDelegate extends WatchUi.BehaviorDelegate {

    var _view as VFRStopWatchView;

    function initialize(view as VFRStopWatchView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // START / SELECT button → start or stop the stopwatch
    function onSelect() as Boolean {
        _view.startStop();
        return true;
    }

    // BACK button → exit app (return to watch face)
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    // UP button → sub-timer (start → stop → back to main)
    function onPreviousPage() as Boolean {
        _view.subTimer();
        return true;
    }

    // DOWN button → lap or reset when stopped
    function onNextPage() as Boolean {
        _view.onDownPressed();
        return true;
    }

    function onMenu() as Boolean {
        WatchUi.pushView(new Rez.Menus.MainMenu(), new VFRStopWatchMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

}