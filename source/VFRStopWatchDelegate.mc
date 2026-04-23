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

    // DOWN button: raw key events for long-press detection.
    // Returning true from onKeyPressed prevents BehaviorDelegate from also
    // firing onNextPage, giving us full control over short vs long press.
    function onKeyPressed(keyEvent as WatchUi.KeyEvent) as Boolean {
        if (keyEvent.getKey() == WatchUi.KEY_DOWN) {
            _view.onDownPressed();
            return true; // consume — prevents system music-control fallback
        }
        return false;
    }

    function onKeyReleased(keyEvent as WatchUi.KeyEvent) as Boolean {
        if (keyEvent.getKey() == WatchUi.KEY_DOWN) {
            var now = System.getTimer();
            var dur = (_view.downPressAt == 0) ? 0 : (now - _view.downPressAt);
            System.println("DOWN released: dur=" + dur.toString());
            _view.downPressAt = 0;
            _view.lastDownEventAt = 0;
            if (dur >= _view.DOWN_HOLD_MS) {
                _view.openSettingsMenu();
            } else {
                _view.shortDownAction();
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