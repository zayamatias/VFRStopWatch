import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Position;

//---------------------------------------------------------------------------
// GPS sub-menu: choose one of 4 GPS modes.
// Item identifiers are the mode integers 0-3.
//---------------------------------------------------------------------------
class VFRGpsMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _view as VFRStopWatchView;

    function initialize(view as VFRStopWatchView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    // identifier is the mode Number (0=GPS, 1=GPS+GLONASS, 2=All, 3=Aviation)
    function onSelect(item as WatchUi.MenuItem) as Void {
        var mode = item.getId() as Number;
        Application.Properties.setValue("GpsMode", mode);
        _view.gpsMode = mode;   // set directly — don't rely on Properties round-trip
        _view.restartGps();
        WatchUi.popView(WatchUi.SLIDE_RIGHT); // pop GPS sub-menu
        WatchUi.popView(WatchUi.SLIDE_RIGHT); // pop Settings menu → back to main
    }
}

//---------------------------------------------------------------------------
// Number-picker view: displays a title + large current value.
// UP increments, DOWN decrements, SELECT saves & pops, BACK cancels.
//---------------------------------------------------------------------------
class VFRNumberPickerView extends WatchUi.View {
    private var _title    as String;
    private var _value    as Number;
    private var _min      as Number;
    private var _max      as Number;
    private var _step     as Number;
    private var _propKey  as String;
    private var _mainView as VFRStopWatchView;

    function initialize(title   as String,
                        value   as Number,
                        min     as Number,
                        max     as Number,
                        step    as Number,
                        propKey as String,
                        mainView as VFRStopWatchView) {
        View.initialize();
        _title    = title;
        _value    = value;
        _min      = min;
        _max      = max;
        _step     = step;
        _propKey  = propKey;
        _mainView = mainView;
    }

    function increment() as Void {
        _value += _step;
        if (_value > _max) { _value = _max; }
        WatchUi.requestUpdate();
    }

    function decrement() as Void {
        _value -= _step;
        if (_value < _min) { _value = _min; }
        WatchUi.requestUpdate();
    }

    // Persist the current value and update the main view's runtime variables directly.
    // We set vars directly instead of going through loadSettings() because Properties.getValue
    // may not immediately reflect a just-completed setValue on some devices.
    function save() as Void {
        Application.Properties.setValue(_propKey, _value);
        VFRSettings.applySavedNumber(_mainView, _propKey, _value);
    }

    function onUpdate(dc as Dc) as Void {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // Title
        dc.drawText(cx, h / 5,
                    Graphics.FONT_MEDIUM, _title,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Value (large number)
        dc.drawText(cx, h / 2,
                    Graphics.FONT_NUMBER_HOT, _value.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Hint
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(cx, h * 4 / 5,
                    Graphics.FONT_TINY, "UP/DN  SELECT=save",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

//---------------------------------------------------------------------------
// Delegate for the number-picker view.
//---------------------------------------------------------------------------
class VFRNumberPickerDelegate extends WatchUi.BehaviorDelegate {
    private var _picker as VFRNumberPickerView;

    function initialize(picker as VFRNumberPickerView) {
        BehaviorDelegate.initialize();
        _picker = picker;
    }

    function onPreviousPage() as Boolean {   // UP button → increment
        _picker.increment();
        return true;
    }

    function onNextPage() as Boolean {       // DOWN button → decrement
        _picker.decrement();
        return true;
    }

    function onSelect() as Boolean {         // SELECT / OK → save & return to main
        _picker.save();
        WatchUi.popView(WatchUi.SLIDE_RIGHT); // pop number picker
        WatchUi.popView(WatchUi.SLIDE_RIGHT); // pop Settings menu → back to main
        return true;
    }

    function onBack() as Boolean {           // BACK → cancel without saving
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

//---------------------------------------------------------------------------
// Top-level Settings menu delegate.
// Shows GPS Mode, Timer Interval, and Takeoff Speed with current values,
// then pushes the appropriate sub-menu or picker on selection.
//---------------------------------------------------------------------------
class VFRSettingsMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _view as VFRStopWatchView;

    function initialize(view as VFRStopWatchView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;

        if (id.equals("setting_gps")) {
            // Build GPS sub-menu based on device capabilities; mark current selection
            var cur = VFRSettings.readClampedNumber("GpsMode", 3, 0, 3);

            var gpsMenu = new WatchUi.Menu2({:title => "GPS Mode"});

            // Always offer basic GPS (id=0)
            gpsMenu.addItem(new WatchUi.MenuItem("GPS", cur == 0 ? "*" : null, 0, null));

            // GPS+GLONASS (id=1) if device exposes GLONASS
            if (Position has :CONSTELLATION_GLONASS) {
                gpsMenu.addItem(new WatchUi.MenuItem("GPS+GLONASS", cur == 1 ? "*" : null, 1, null));
            }

            // All-systems configuration (id=2) when configuration constants are supported
            if ((Position has :hasConfigurationSupport) &&
                ((Position has :CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1_L5 &&
                  Position.hasConfigurationSupport(Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1_L5)) ||
                 (Position has :CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1 &&
                  Position.hasConfigurationSupport(Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1)))) {
                gpsMenu.addItem(new WatchUi.MenuItem("All Systems", cur == 2 ? "*" : null, 2, null));
            }

            // Aviation mode (id=3) if device supports it
            if (Position has :POSITIONING_MODE_AVIATION) {
                gpsMenu.addItem(new WatchUi.MenuItem("Aviation", cur == 3 ? "*" : null, 3, null));
            }

            WatchUi.pushView(gpsMenu, new VFRGpsMenuDelegate(_view), WatchUi.SLIDE_LEFT);

        } else if (id.equals("setting_timer")) {
            var curMin = VFRSettings.readClampedNumber("TimerInterval", 5, 0, 30);
            var picker = new VFRNumberPickerView("Timer (min)", curMin, 0, 30, 1, "TimerInterval", _view);
            WatchUi.pushView(picker, new VFRNumberPickerDelegate(picker), WatchUi.SLIDE_LEFT);

        } else if (id.equals("setting_takeoff")) {
            var curKts = VFRSettings.readClampedNumber("TakeoffSpeed", 30, 0, 100);
            var picker = new VFRNumberPickerView("Takeoff (kts)", curKts, 0, 100, 5, "TakeoffSpeed", _view);
            WatchUi.pushView(picker, new VFRNumberPickerDelegate(picker), WatchUi.SLIDE_LEFT);
        } else if (id.equals("setting_transition")) {
            var curTrans = VFRSettings.readClampedNumber("TransitionAltitudeFt", 6000, 0, 20000);
            var picker = new VFRNumberPickerView("Transition Alt (ft)", curTrans, 0, 20000, 100, "TransitionAltitudeFt", _view);
            WatchUi.pushView(picker, new VFRNumberPickerDelegate(picker), WatchUi.SLIDE_LEFT);
        } else if (id.equals("setting_hr")) {
            var curHr = VFRSettings.readClampedNumber("HrThreshold", 130, 0, 220);
            var picker = new VFRNumberPickerView("HR Alert (bpm)", curHr, 0, 220, 5, "HrThreshold", _view);
            WatchUi.pushView(picker, new VFRNumberPickerDelegate(picker), WatchUi.SLIDE_LEFT);
        } else if (id.equals("setting_fuel")) {
            var curFuel = VFRSettings.readClampedNumber("FuelCheckInterval", 30, 0, 120);
            var picker = new VFRNumberPickerView("Fuel Check (min)", curFuel, 0, 120, 5, "FuelCheckInterval", _view);
            WatchUi.pushView(picker, new VFRNumberPickerDelegate(picker), WatchUi.SLIDE_LEFT);
        } else if (id.equals("setting_companion")) {
            // Toggle companion app usage immediately
            var rawComp = Application.Properties.getValue("UseCompanionApp");
            var cur = (rawComp != null) ? (rawComp as Number) : 0;
            var newv = (cur == 1) ? 0 : 1;
            Application.Properties.setValue("UseCompanionApp", newv);
            // Update runtime view flag directly
            try { _view.useCompanionApp = (newv == 1); } catch (e) { }
            // Notify app so it can start/stop comms
            try { getApp().onSettingsChanged(); } catch (e2) { }
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }
}
