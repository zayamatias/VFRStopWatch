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
    var bezelFontScale as Number;
    var bezelContrast as Number;
    var altitudeSource as Number;  // 0=Baro, 1=GPS
    var circuitEnabled as Boolean;
    var manualFieldElevationFt as Number; // 0 = auto
    var runwayLengthM as Number;
    var altAlertFt as Number;            // 0 = off
    var autoBacklight as Number;         // 0=off, 1=always, 2=night-only
    var nightStartHour as Number;        // backlight window start (0-23)
    var nightEndHour as Number;          // backlight window end (0-23)
    var displayMode as Number;           // 0=bezel ring, 1=paged big values
    var pageCycleSec as Number;          // paged face: seconds per page, 0 = manual only

    function initialize() {
        gpsMode = 3;
        timerIntervalMin = 5;
        takeoffSpeedKts = 30;
        transitionAltitudeFt = 6000;
        hrThreshold = 130;
        fuelCheckIntervalMin = 30;
        useCompanionApp = false;
        bezelFontScale = 100;
        bezelContrast = 100;
        altitudeSource = 0;
        circuitEnabled = false;
        manualFieldElevationFt = 0;
        runwayLengthM = 2405;
        altAlertFt = 0;
        autoBacklight = 0;
        nightStartHour = 20;
        nightEndHour = 7;
        displayMode = 1;
        pageCycleSec = 0;
    }
}

class VFRSettings {

    // Application.Properties.setValue() is ASYNCHRONOUS, and loadSettings()
    // re-reads the properties every time the face re-appears (onShow), so a
    // value written by the settings menu can be read back stale and silently
    // revert the face. Remember the last requested value for this session.
    static var displayModeOverride as Number? = null;

    // Face layout. The settings.xml "DisplayMode" property is what Garmin
    // Connect shows, but a value stored by an install that predates the paged
    // face is 0 (the OLD default), which would hide the new face for ever and
    // make the update look like it changed nothing (it did: the watch kept
    // drawing the ring). So the effective layout comes from this separate key:
    // absent = never chosen = use the paged face, and that is remembered.
    // Because absence means "pages", a lost/slow asynchronous write can never
    // pin the wrong face. The DisplayMode property is still written alongside so
    // the Connect-visible setting matches.
    static var faceLayoutKey as String = "vfr_faceLayout";

    static function effectiveDisplayMode() as Number {
        if (VFRSettings.displayModeOverride != null) {
            return VFRSettings.displayModeOverride as Number;
        }
        try {
            var raw = Application.Properties.getValue(VFRSettings.faceLayoutKey);
            if (raw != null) { return VFRSettings.clampNumber(raw as Number, 0, 1); }
            // First launch after the face rework (or a lost write): paged face.
            Application.Properties.setValue(VFRSettings.faceLayoutKey, 1);
        } catch (ex) { }
        return 1;
    }

    // Store a face layout chosen in the on-device settings menu and apply it
    // immediately (no re-read, so the toggle cannot appear to do nothing).
    static function setDisplayMode(view as VFRStopWatchView, mode as Number) as Void {
        var m = VFRSettings.clampNumber(mode, 0, 1);
        VFRSettings.displayModeOverride = m;
        view.displayMode = m;
        view.pageIdx = 0;
        try { Application.Properties.setValue(VFRSettings.faceLayoutKey, m); } catch (ex) { }
        try { Application.Properties.setValue("DisplayMode", m); } catch (ex) { }
    }

    static function read() as VFRSettingsSnapshot {
        var s = new VFRSettingsSnapshot();
        s.gpsMode = VFRSettings.readClampedNumber("GpsMode", 3, 0, 3);
        s.timerIntervalMin = VFRSettings.readClampedNumber("TimerInterval", 5, 0, 30);
        s.takeoffSpeedKts = VFRSettings.readClampedNumber("TakeoffSpeed", 30, 0, 100);
        s.transitionAltitudeFt = VFRSettings.readClampedNumber("TransitionAltitudeFt", 6000, 0, 20000);
        s.hrThreshold = VFRSettings.readClampedNumber("HrThreshold", 130, 0, 220);
        s.fuelCheckIntervalMin = VFRSettings.readClampedNumber("FuelCheckInterval", 30, 0, 120);
        s.useCompanionApp = VFRSettings.readClampedNumber("UseCompanionApp", 0, 0, 1) == 1;
        s.bezelFontScale = VFRSettings.readClampedNumber("BezelFontScale", 100, 70, 130);
        s.bezelContrast = VFRSettings.readClampedNumber("BezelContrast", 100, 50, 100);
        s.altitudeSource = VFRSettings.readClampedNumber("AltitudeSource", 0, 0, 1);
        s.circuitEnabled = VFRSettings.readClampedNumber("CircuitPractice", 0, 0, 1) == 1;
        s.manualFieldElevationFt = VFRSettings.readClampedNumber("FieldElevationFt", 0, 0, 20000);
        s.runwayLengthM = VFRSettings.readClampedNumber("RunwayLengthM", 2405, 0, 10000);
        s.altAlertFt = VFRSettings.readClampedNumber("AltitudeAlertFt", 0, 0, 30000);
        s.autoBacklight = VFRSettings.readClampedNumber("AutoBacklight", 0, 0, 2);
        s.nightStartHour = VFRSettings.readClampedNumber("NightStartHour", 20, 0, 23);
        s.nightEndHour = VFRSettings.readClampedNumber("NightEndHour", 7, 0, 23);
        s.displayMode = VFRSettings.effectiveDisplayMode();
        s.pageCycleSec = VFRSettings.readClampedNumber("PageCycleSec", 0, 0, 60);
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
        view.bezelFontScale = settings.bezelFontScale;
        view.bezelContrast = settings.bezelContrast;
        view.altitudeSource = settings.altitudeSource;
        view.circuitEnabled = settings.circuitEnabled;
        view.manualFieldElevationFt = settings.manualFieldElevationFt;
        view.runwayLengthM = settings.runwayLengthM;
        view.altAlertFt = settings.altAlertFt;
        view.autoBacklight = settings.autoBacklight;
        view.nightStartHour = settings.nightStartHour;
        view.nightEndHour = settings.nightEndHour;
        view.displayMode = settings.displayMode;
        view.pageCycleSec = settings.pageCycleSec;
        if (settings.manualFieldElevationFt > 0) {
            view.fieldElevationFt = settings.manualFieldElevationFt;
        }
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
        } else if (propKey.equals("BezelFontScale")) {
            view.bezelFontScale = VFRSettings.clampNumber(value, 70, 130);
            view.invalidateBezelRendering();
        } else if (propKey.equals("BezelContrast")) {
            view.bezelContrast = VFRSettings.clampNumber(value, 50, 100);
        } else if (propKey.equals("DisplayMode")) {
            view.displayMode = VFRSettings.clampNumber(value, 0, 1);
        } else if (propKey.equals("PageCycleSec")) {
            view.pageCycleSec = VFRSettings.clampNumber(value, 0, 60);
        } else if (propKey.equals("AltitudeSource")) {
            view.altitudeSource = VFRSettings.clampNumber(value, 0, 1);
        } else if (propKey.equals("CircuitPractice")) {
            view.circuitEnabled = VFRSettings.clampNumber(value, 0, 1) == 1;
        } else if (propKey.equals("FieldElevationFt")) {
            view.manualFieldElevationFt = VFRSettings.clampNumber(value, 0, 20000);
            view.fieldElevationFt = view.manualFieldElevationFt;
        } else if (propKey.equals("RunwayLengthM")) {
            view.runwayLengthM = VFRSettings.clampNumber(value, 0, 10000);
        } else if (propKey.equals("AltitudeAlertFt")) {
            view.altAlertFt = VFRSettings.clampNumber(value, 0, 30000);
        } else if (propKey.equals("NightStartHour")) {
            view.nightStartHour = VFRSettings.clampNumber(value, 0, 23);
        } else if (propKey.equals("NightEndHour")) {
            view.nightEndHour = VFRSettings.clampNumber(value, 0, 23);
        }
    }

    static function gpsModeLabel(mode as Number) as String {
        if (mode == 0) { return "GPS"; }
        if (mode == 1) { return "GPS+GLONASS"; }
        if (mode == 2) { return "All Systems"; }
        return "Aviation";
    }
}
