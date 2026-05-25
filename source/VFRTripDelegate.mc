import Toybox.Lang;
import Toybox.WatchUi;

// Input delegate for the trip navigation view.
//   BACK  → return to main stopwatch
//   UP    → previous waypoint
//   DOWN  → next waypoint

class VFRTripDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onPreviousPage() as Boolean {
        var trip = getApp().getTrip();
        if (trip != null) {
            trip.previousWaypoint();
            WatchUi.requestUpdate();
        }
        return true;
    }

    function onNextPage() as Boolean {
        var trip = getApp().getTrip();
        if (trip != null) {
            trip.advanceWaypoint();
            WatchUi.requestUpdate();
        }
        return true;
    }
}
