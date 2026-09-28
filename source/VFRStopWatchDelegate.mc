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

    // UP button (fallback path, e.g. a touch swipe that never produced key
    // events): same action as a short UP press.
    function onPreviousPage() as Boolean {
        _view.shortUpAction();
        return true;
    }

    // UP / DOWN buttons: raw key events for long-press detection.
    // Returning true from onKeyPressed prevents BehaviorDelegate from also
    // firing onNextPage/onPreviousPage, giving us full control over short vs
    // long press: short UP = previous page, hold UP = sub-timer,
    // short DOWN = next page, hold DOWN = settings (or reset when stopped).
    function onKeyPressed(keyEvent as WatchUi.KeyEvent) as Boolean {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_DOWN) {
            _view.onDownPressed();
            return true; // consume — prevents system music-control fallback
        }
        if (key == WatchUi.KEY_UP) {
            _view.onUpPressed();
            return true;
        }
        return false;
    }

    function onKeyReleased(keyEvent as WatchUi.KeyEvent) as Boolean {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_DOWN) {
            var now = System.getTimer();
            var dur = (_view.downPressAt == 0) ? 0 : (now - _view.downPressAt);
            _view.downPressAt = 0;
            _view.lastDownEventAt = 0;
            if (dur >= _view.DOWN_HOLD_MS) {
                _view.onDownLongPress();
            } else {
                _view.shortDownAction();
            }
            return true;
        }
        if (key == WatchUi.KEY_UP) {
            var nowU = System.getTimer();
            var durU = (_view.upPressAt == 0) ? 0 : (nowU - _view.upPressAt);
            _view.upPressAt = 0;
            _view.lastUpEventAt = 0;
            if (durU >= _view.UP_HOLD_MS) {
                _view.onUpLongPress();
            } else {
                _view.shortUpAction();
            }
            return true;
        }
        return false;
    }

    function onMenu() as Boolean {
        WatchUi.pushView(new Rez.Menus.MainMenu(), new VFRStopWatchMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

}