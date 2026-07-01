import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class VFRStopWatchApp extends Application.AppBase {

    // Hold a reference so we can forward settings changes to the view
    var _view  as VFRStopWatchView? = null;
    // Phone communications manager
    var _comms as VFRPhoneComms?    = null;
    // Active flight plan (always allocated; active flag is false when no plan loaded)
    var _trip  as VFRTrip           = new VFRTrip();

    // Live sensor/timer state — updated by VFRStopWatchView callbacks so that
    // any active view (TripView, SummaryView, etc.) can read fresh data for
    // the BLE telemetry push that runs inside comms.tick().
    var liveRunning     as Boolean = false;
    var liveStartTime   as Number  = 0;    // System.getTimer() reference; elapsed = now - liveStartTime when running
    var liveBaseElapsed as Number  = 0;    // ms elapsed when last stopped
    var liveAltFt       as Number  = -1;   // altitude in feet (-1 = no data)
    var liveVsFpm       as Number  = 0;    // vertical speed FPM (rounded to 10)
    var liveGpsQuality  as Number  = 0;    // GPS accuracy 0-4

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
        AppBase.onStart(state);
        if (_view == null) {
            _view = new VFRStopWatchView();
        }
        // Initialise phone comms only if enabled in properties
        try {
            var rawComp = Application.Properties.getValue("UseCompanionApp");
            var want = (rawComp != null) ? (rawComp as Number) : 0;
            if (want == 1) { _comms = new VFRPhoneComms(); }
            else { _comms = null; }
        } catch (e) { _comms = null; }
        if (state != null && state["viewState"] != null) {
            try {
                (_view as VFRStopWatchView).loadState(state["viewState"] as Dictionary);
            } catch (ex) {
            }
        }
        // If we have an on-disk backup, load it as a fallback
        // Load per-key Properties backup if present
        try { (_view as VFRStopWatchView).loadBackupProperties(); } catch (ex4) { }
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
        AppBase.onStop(state);
        if (state == null) { state = new Dictionary(); }
        if (_view != null) {
            try {
                state["viewState"] = (_view as VFRStopWatchView).saveState();
            } catch (ex) {
            }
        }
        // Also persist an on-disk backup for extra resilience
        try {
            if (_view != null) {
                try { (_view as VFRStopWatchView).saveBackupProperties(); } catch (ex5) { }
            }
        } catch (ex4) {
        }
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        // Start on the main stopwatch view by default. Remove the debug
        // startup screen to avoid confusing users when no payload is present.
        if (_view == null) {
            _view = new VFRStopWatchView();
        }
        var main = _view as VFRStopWatchView;
        return [ main, new VFRStopWatchDelegate(main) ];
    }

    function getComms() as VFRPhoneComms? {
        return _comms;
    }

    function getTrip() as VFRTrip {
        return _trip;
    }

    // Called by the system when the user changes a setting in the watch settings menu
    function onSettingsChanged() as Void {
        // Start/stop comms based on the UseCompanionApp property value
        try {
            var rawComp = Application.Properties.getValue("UseCompanionApp");
            var want = (rawComp != null) ? (rawComp as Number) : 0;
            if (want == 1) {
                if (_comms == null) { _comms = new VFRPhoneComms(); }
            } else {
                // disable companion features
                _comms = null;
            }
        } catch (e) { _comms = null; }

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