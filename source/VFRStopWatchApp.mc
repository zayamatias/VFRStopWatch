import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class VFRStopWatchApp extends Application.AppBase {

    // Hold a reference so we can forward settings changes to the view
    var _view as VFRStopWatchView? = null;

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        _view = new VFRStopWatchView();
        return [ _view, new VFRStopWatchDelegate(_view) ];
    }

    // Called by the system when the user changes a setting in the watch settings menu
    function onSettingsChanged() as Void {
        if (_view != null) {
            (_view as VFRStopWatchView).loadSettings();
            (_view as VFRStopWatchView).restartGps();
            WatchUi.requestUpdate();
        }
    }

}

function getApp() as VFRStopWatchApp {
    return Application.getApp() as VFRStopWatchApp;
}