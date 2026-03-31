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
            var view = WatchUi.getCurrentView() as VFRStopWatchView;
            if (view != null) {
                view.startStop();
            }
        } else if (item == :item_2) {
            // Reset
            var view = WatchUi.getCurrentView() as VFRStopWatchView;
            if (view != null) {
                view.reset();
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