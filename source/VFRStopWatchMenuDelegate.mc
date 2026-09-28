import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class VFRStopWatchMenuDelegate extends WatchUi.MenuInputDelegate {

    function initialize() {
        MenuInputDelegate.initialize();
    }

    function onMenuItem(item as Symbol) as Void {
        if (item == :item_1) {
            // Start/Stop
            var view = getApp()._view;
            if (view != null) {
                (view as VFRStopWatchView).startStop();
            }
        } else if (item == :item_2) {
            // Reset
            var view = getApp()._view;
            if (view != null) {
                (view as VFRStopWatchView).reset();
            }
        } else if (item == :item_3) {
            // Delegate to the view's helper to avoid code duplication
            var mainView = getApp()._view;
            if (mainView != null) {
                (mainView as VFRStopWatchView).openSettingsMenu();
            }
        } else if (item == :item_4) {
            // Open the flight plan / trip navigation view
            WatchUi.pushView(new VFRTripView(), new VFRTripDelegate(), WatchUi.SLIDE_LEFT);
        } else if (item == :item_5) {
            // Map. On the "pages" face DOWN cycles values instead of opening the
            // quick-info chain, so the map lives here to stay reachable.
            var view5 = getApp()._view;
            if (view5 != null && (WatchUi has :MapView)) {
                try {
                    var mapView = new VFRMapView(view5 as VFRStopWatchView);
                    WatchUi.pushView(mapView, new VFRMapDelegate(view5 as VFRStopWatchView, mapView), WatchUi.SLIDE_IMMEDIATE);
                } catch (ex) {
                }
            }
        } else if (item == :item_6) {
            // Full weather detail (cloud cover, cloud base, trend). The common
            // numbers (wind, temp/dew, clouds, density altitude) are pages on
            // the main face; this screen keeps the whole set one tap away.
            var view6 = getApp()._view;
            if (view6 != null) {
                try {
                    WatchUi.pushView(new VFRQuickInfoWeather2View(view6 as VFRStopWatchView),
                                     new VFRQuickInfoWeather2Delegate(view6 as VFRStopWatchView),
                                     WatchUi.SLIDE_UP);
                } catch (ex) {
                }
            }
        }
    }

}