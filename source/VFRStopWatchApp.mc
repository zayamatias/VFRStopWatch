import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class VFRStopWatchApp extends Application.AppBase {

    // Hold a reference so we can forward settings changes to the view
    var _view  as VFRStopWatchView? = null;
    // Phone communications manager
    var _comms as VFRPhoneComms?    = null;

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
        AppBase.onStart(state);
        if (_view == null) {
            _view = new VFRStopWatchView();
        }
        // Initialise phone comms (sends handshake to phone)
        _comms = new VFRPhoneComms();
        if (state != null && state["viewState"] != null) {
            try {
                (_view as VFRStopWatchView).loadState(state["viewState"] as Dictionary);
            } catch (ex) {
                System.println("loadState failed: " + ex.getErrorMessage());
            }
        }
        // If we have an on-disk backup, load it as a fallback
        try {
            var b = Application.Properties.getValue("vfr_backup");
            if (b != null) {
                // older string-backed backups still possible; ignore here
            }
            // Load per-key Properties backup if present
            try { (_view as VFRStopWatchView).loadBackupProperties(); }
            catch (ex4) { System.println("loadBackupProperties failed: " + ex4.getErrorMessage()); }
        } catch (ex3) {
            System.println("backup load check failed: " + ex3.getErrorMessage());
        }
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
        AppBase.onStop(state);
        if (state == null) { state = new Dictionary(); }
        if (_view != null) {
            try {
                state["viewState"] = (_view as VFRStopWatchView).saveState();
            } catch (ex) {
                System.println("saveState failed: " + ex.getErrorMessage());
            }
        }
        // Also persist an on-disk backup for extra resilience
        try {
            if (_view != null) {
                try { (_view as VFRStopWatchView).saveBackupProperties(); } catch (ex5) { System.println("saveBackupProperties failed: " + ex5.getErrorMessage()); }
            }
        } catch (ex4) {
            System.println("backup save failed: " + ex4.getErrorMessage());
        }
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        if (_view == null) { _view = new VFRStopWatchView(); }
        return [ _view, new VFRStopWatchDelegate(_view) ];
    }

    function getComms() as VFRPhoneComms? {
        return _comms;
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