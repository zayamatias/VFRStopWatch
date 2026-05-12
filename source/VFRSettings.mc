import Toybox.Application;
import Toybox.Lang;

class VFRSettingsSnapshot {
    var gpsMode as Number;
    var timerIntervalMin as Number;
    var takeoffSpeedKts as Number;
    var transitionAltitudeFt as Number;
    var hrThreshold as Number;
    var fuelCheckIntervalMin as Number;
    var useCompanionApp as Boolean;

    function initialize() {
        gpsMode = 3;
        timerIntervalMin = 5;
        takeoffSpeedKts = 30;
        transitionAltitudeFt = 6000;
        hrThreshold = 130;
        fuelCheckIntervalMin = 30;
        useCompanionApp = false;
    }
}

class VFRSettings {
    static function read() as VFRSettingsSnapshot {
        var s = new VFRSettingsSnapshot();
        s.gpsMode = VFRSettings.readClampedNumber("GpsMode", 3, 0, 3);
        s.timerIntervalMin = VFRSettings.readClampedNumber("TimerInterval", 5, 0, 30);
        s.takeoffSpeedKts = VFRSettings.readClampedNumber("TakeoffSpeed", 30, 0, 100);
        s.transitionAltitudeFt = VFRSettings.readClampedNumber("TransitionAltitudeFt", 6000, 0, 20000);
        s.hrThreshold = VFRSettings.readClampedNumber("HrThreshold", 130, 0, 220);
        s.fuelCheckIntervalMin = VFRSettings.readClampedNumber("FuelCheckInterval", 30, 0, 120);
        s.useCompanionApp = VFRSettings.readClampedNumber("UseCompanionApp", 0, 0, 1) == 1;
        return s;
    }

    static function readClampedNumber(key as String, defaultValue as Number, minValue as Number, maxValue as Number) as Number {
        var value = defaultValue;
        try {
            var raw = Application.Properties.getValue(key);
            if (raw != null) { value = raw as Number; }
        } catch (ex) { value = defaultValue; }
        return VFRSettings.clampNumber(value, minValue, maxValue);
    }

    static function clampNumber(value as Number, minValue as Number, maxValue as Number) as Number {
        if (value < minValue) { return minValue; }
        if (value > maxValue) { return maxValue; }
        return value;
    }

    static function takeoffSpeedToMetersPerSecond(speedKts as Number) as Float {
        if (speedKts <= 0) { return -1.0; }
        return speedKts.toFloat() * 0.514444f;
    }

    static function applySnapshot(view as VFRStopWatchView, settings as VFRSettingsSnapshot) as Void {
        view.gpsMode = settings.gpsMode;
        view.timerIntervalMs = settings.timerIntervalMin * 60000;
        view.AUTO_START_SPEED_MS = VFRSettings.takeoffSpeedToMetersPerSecond(settings.takeoffSpeedKts);
        view.transitionAltitudeFt = settings.transitionAltitudeFt;
        view.HR_THRESHOLD = settings.hrThreshold;
        view.FUEL_CHECK_INTERVAL_MS = settings.fuelCheckIntervalMin * 60000;
        view.useCompanionApp = settings.useCompanionApp;
    }

    static function applySavedNumber(view as VFRStopWatchView, propKey as String, value as Number) as Void {
        if (propKey.equals("TimerInterval")) {
            var minutes = VFRSettings.clampNumber(value, 0, 30);
            view.timerIntervalMs = minutes * 60000;
            if (!view.running && view.timerIntervalMs > 0) { view.nextVibrateAt = view.timerIntervalMs; }
        } else if (propKey.equals("TakeoffSpeed")) {
            view.AUTO_START_SPEED_MS = VFRSettings.takeoffSpeedToMetersPerSecond(VFRSettings.clampNumber(value, 0, 100));
        } else if (propKey.equals("TransitionAltitudeFt")) {
            view.transitionAltitudeFt = VFRSettings.clampNumber(value, 0, 20000);
        } else if (propKey.equals("HrThreshold")) {
            view.HR_THRESHOLD = VFRSettings.clampNumber(value, 0, 220);
        } else if (propKey.equals("FuelCheckInterval")) {
            var fuelMin = VFRSettings.clampNumber(value, 0, 120);
            view.FUEL_CHECK_INTERVAL_MS = fuelMin * 60000;
            if (!view.running) { view.nextFuelCheckAt = view.FUEL_CHECK_INTERVAL_MS; }
        }
    }

    static function gpsModeLabel(mode as Number) as String {
        if (mode == 0) { return "GPS"; }
        if (mode == 1) { return "GPS+GLONASS"; }
        if (mode == 2) { return "All Systems"; }
        return "Aviation";
    }
}
