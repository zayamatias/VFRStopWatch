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
        }
    }

}