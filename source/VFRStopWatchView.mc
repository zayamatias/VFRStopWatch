import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Lang;
import Toybox.Attention;
import Toybox.Activity;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;

class VFRStopWatchView extends WatchUi.View {

    // --- Stopwatch state ---
    var running     as Boolean = false;
    var startTime   as Number  = 0;    // System.getTimer() value at (re)start
    var elapsed     as Number  = 0;    // accumulated ms

    // --- GPS distance accumulation ---
    var lastUpdateTimer  as Number = 0;   // System.getTimer() at last onUpdate
    var totalDistanceM   as Float  = 0.0; // meters accumulated since reset
    // --- GPS outage recovery for the distance accumulation ---
    // Distance is integrated from ground speed each second, so anything flown
    // while the fix is missing is lost. `fixLatDeg/fixLonDeg` cache the latest
    // accepted fix and `accumRef*` the fix at the last accumulated sample: when
    // accumulation resumes after an outage, the straight-line distance between
    // the two is added back (see _bridgeDistanceGap).
    var fixLatDeg        as Float   = 0.0;
    var fixLonDeg        as Float   = 0.0;
    var fixValid         as Boolean = false;
    var accumRefLat      as Float   = 0.0;
    var accumRefLon      as Float   = 0.0;
    var accumRefValid    as Boolean = false;
    var lastAccumAtMs    as Number  = 0;  // 0 = nothing accumulated yet
    // Only bridge real outages — normal 1 Hz operation is already covered by the
    // speed integration, so bridging then would double count.
    var GAP_BRIDGE_MIN_MS    as Number = 3000;
    // Reject a "gap" implying an impossible speed (GPS glitch rather than
    // real movement): 200 m/s ≈ 390 kt.
    var MAX_BRIDGE_SPEED_MPS as Float  = 200.0;
    // --- Trip statistics ---
    var maxAltitudeM     as Float  = 0.0; // maximum altitude seen during trip (meters)
    var maxGsKt          as Float  = 0.0; // maximum ground speed (knots)
    // For average GS calculation: cumulative sum (kt) and sample count
    var gsSumKt          as Float  = 0.0;
    var gsSamples        as Number = 0;

    // Trip start/end timestamps
    var tripStartLocal     as Object?       = null; // result of System.getClockTime()
    var tripStartUtcMoment as Time.Moment?  = null; // result of Time.now()
    var tripEndUtcMoment   as Time.Moment?  = null; // captured when activity is stopped
    // Also store simple hour/min snapshots for persistence/display without Moment
    var tripStartUtcHour   as Number = -1;
    var tripStartUtcMin    as Number = -1;
    var tripEndUtcHour     as Number = -1;
    var tripEndUtcMin      as Number = -1;

    // --- 5-minute checkpoint state ---
    var nextVibrateAt    as Number = 300000; // elapsed ms when next alert fires
    var kmAtCheckpoint   as Float  = 0.0;   // km snapshot shown below timer
    var nmAtCheckpoint   as Float  = 0.0;   // nautical miles snapshot shown above timer
    var checkpointHit    as Boolean = false; // true once first checkpoint passed
    var checkpointActive as Boolean = false; // true when 5-min interval scheduling is active

    // --- Lap state ---
    var lapMode          as Boolean = false;
    var lapElapsed       as Number  = 0;
    var lapKm            as Float   = 0.0;
    var lapNm            as Float   = 0.0;

    // --- Sub-timer state (UP button) ---
    // subTimerState: 0=off, 1=running (blue), 2=stopped (frozen blue)
    var subTimerState    as Number  = 0;
    var subTimerStart    as Number  = 0;  // System.getTimer() when sub started
    var subTimerElapsed  as Number  = 0;  // accumulated ms

    // --- Heart rate monitoring ---
    var lastHr         as Number  = 0;     // last known bpm (0 = unknown)
    var hrAlertActive  as Boolean = false;  // true when HR > threshold
    var hrFlashOn      as Boolean = false;  // alternates each frame for screen flash
    var hrNextVibrate  as Number  = 0;     // System.getTimer() gate for repeat vibration
    var HR_THRESHOLD   as Number  = 130;   // bpm — alert fires above this
    // --- Fuel check (every 30 minutes) ---
    var FUEL_CHECK_INTERVAL_MS as Number = 1800000; // 30 minutes in ms
    var nextFuelCheckAt as Number = 1800000; // elapsed ms when next fuel check fires
    var fuelFlashUntil as Number = 0; // System.getTimer() until which to flash

    // --- Auto-start (settings-driven) ---
    // Armed at start/reset; disarmed as soon as the stopwatch begins running.
    var autoStartEnabled as Boolean = true;
    var AUTO_START_SPEED_MS as Float = 15.4333; // default 30 kts in m/s; updated by loadSettings()
    // --- Off-block (taxi) start ---
    // The clock now starts when the aircraft begins to roll, not at take-off, so
    // OBT is the off-block time. The taxi threshold sits above walking pace (a
    // pilot walking to the aircraft reaches ~1.6-2.7 kt, normal taxi is
    // 5-15 kt) and must be held for TAXI_START_HOLD_MS so a speed spike can't
    // start the clock.
    var TAXI_START_SPEED_MS as Float  = 2.5722; // 5 kt
    var TAXI_START_HOLD_MS  as Number = 5000;   // sustained speed required (ms)
    var taxiStartSince      as Number = 0;      // 0 = not currently above the taxi threshold
    // Set once ground speed has reached the take-off threshold: only then is the
    // zero-speed auto-stop armed, so stopping during taxi (or pausing before
    // take-off) cannot end the flight.
    var hasTakenOff as Boolean = false;

    // --- Settings-derived runtime values ---
    // gpsMode:          0=GPS  1=GPS+GLONASS  2=All  3=Aviation
    // timerIntervalMs:  checkpoint interval in ms (0 = disabled)
    // (AUTO_START_SPEED_MS is also settings-driven; 0 kts => -1 to disable)
    var gpsMode         as Number = 3;
    var timerIntervalMs as Number = 300000; // default 5 min
    // Transition altitude (feet) and flag for Flight Level display
    var transitionAltitudeFt as Number = 6000; // default
    var transitionActive as Boolean = false;
    var transitionExitOffsetFt as Number = 500; // hysteresis: exit when below (transitionAltitudeFt - offset)
    // (altitude comes from sensors — Sensor.getInfo().altitude preferred)

    // --- GPS fix quality (Position.QUALITY_* values 0-4) ---
    // 0=not available, 1=last known, 2=poor/acquiring, 3=usable, 4=good
    var gpsQuality as Number = 0;
    // Last time (System.getTimer()) we received a Position.onPosition callback
    var lastPositionMillis as Number = 0;
    // --- Altitude tendency detection ---
    var lastAltitudeMeters as Float = 0.0;      // last altitude sample in meters
    var lastAltitudeMillis as Number = 0;       // System.getTimer() at last altitude
    var VERT_SPEED_THRESHOLD_MPS as Float = 1.0; // 1 m/s vertical speed threshold (~200 ft/min)
    var tendency as Number = 0;                 // -1 = down, 0 = none, 1 = up
    var tendencyUntil as Number = 0;            // System.getTimer() until which arrow is shown
    var tendencyVibrateCooldownMs as Number = 5000; // minimum ms between tendency vibrations
    var lastTendencyVibrateAt as Number = 0;
    var vertSpeedFpm as Float = 0.0;            // raw instantaneous vertical speed (FPM, for tendency)
    var VERT_SPEED_SMOOTH_ALPHA as Float = 0.15; // EMA smoothing factor (0.15 = heavy smoothing)
    var vertSpeedSmoothFpm as Float = 0.0;       // EMA-smoothed vertical speed FPM (for display)
    var MIN_VS_DT_MS as Number = 500;            // minimum ms between altitude samples for VS calc
    var lastAltSource as Number = -1;            // -1=none, 0=baro, 1=gps (keeps VS on one datum)
    var lastTrackDeg as Float = -1.0;            // last GPS track (deg) for turn-rate / bank estimate
    var lastTrackMillis as Number = 0;           // System.getTimer() of the last track sample
    var turnRateDegS as Float = 0.0;             // EMA-smoothed turn rate (deg/s)
    // Sanity limits for the bank estimate: a GPS track jump is not a turn.
    var MAX_TURN_RATE_DEG_S as Float = 15.0;     // clamp the rate fed into the model
    var MAX_BANK_DEG        as Float = 60.0;     // clamp the reported bank
    var liveBankDeg as Float = 0.0;              // estimated bank angle (deg, coordinated-turn model)
    // --- Altitude source (0=Baro, 1=GPS) ---
    var altitudeSource as Number = 0;
    var gpsAltitudeM as Float = 0.0;            // cached GPS altitude from Position.Info
    var gpsAltitudeMillis as Number = 0;        // System.getTimer() at last GPS altitude
    // Periodic backup gate (ms)
    var lastBackupMillis as Number = 0;
    var BACKUP_INTERVAL_MS as Number = 30000; // 30s

    // --- Resume prompt + auto-stop on zero speed ---
    var needsResumePrompt  as Boolean = false;
    var zeroSpeedStartMs   as Number  = 0;
    var AUTO_STOP_DELAY_MS as Number  = 3000; // auto-stop after 3s at speed=0

    // --- GPS activity recording ---
    // One session per start/stop cycle; saved as a FIT activity on stop.
    var _session as ActivityRecording.Session? = null;

    // --- FIT developer fields (flight summary shown on the Garmin Connect report) ---
    // Field ids MUST match the <fitField id="…"> entries in resources/fit/fit.xml
    // or the values are written to the FIT file but never displayed.
    var FIT_FIELD_OBT      as Number = 0;
    var FIT_FIELD_IBT      as Number = 1;
    var FIT_FIELD_BLOCK_S  as Number = 2;
    var FIT_FIELD_LANDINGS as Number = 3;
    var FIT_FIELD_DIST_NM  as Number = 4;
    var FIT_FIELD_MAX_ALT  as Number = 5;
    var FIT_FIELD_AVG_GS   as Number = 6;
    var FIT_FIELD_MAX_G    as Number = 7;
    var FIT_FIELD_MAX_BANK as Number = 8;
    var FIT_FIELD_G        as Number = 9;
    var FIT_FIELD_BANK     as Number = 10;
    var FIT_FIELD_PITCH    as Number = 11;
    var FIT_FIELD_MAX_PITCH as Number = 12;
    var _fitObt      as FitContributor.Field? = null;
    var _fitIbt      as FitContributor.Field? = null;
    var _fitBlockS   as FitContributor.Field? = null;
    var _fitLandings as FitContributor.Field? = null;
    var _fitDistNm   as FitContributor.Field? = null;
    var _fitMaxAltFt as FitContributor.Field? = null;
    var _fitAvgGsKt  as FitContributor.Field? = null;
    var _fitMaxG     as FitContributor.Field? = null;
    var _fitMaxBank  as FitContributor.Field? = null;
    var _fitMaxPitch as FitContributor.Field? = null;
    var _fitG        as FitContributor.Field? = null;
    var _fitBank     as FitContributor.Field? = null;
    var _fitPitch    as FitContributor.Field? = null;

    // --- Accelerometer (G-force) capture ---
    // Magnitude is orientation independent, so sqrt(x2+y2+z2)/1000 is the
    // resultant load factor. Wrist-mounted, so treat it as indicative.
    var gForceG          as Float   = 1.0;  // smoothed current load factor (G)
    var maxG             as Float   = 0.0;  // peak 1 s-averaged load factor (G)
    var maxBankDeg       as Float   = 0.0;  // peak |bank| estimate (deg)
    var maxPitchDeg      as Float   = 0.0;  // peak |flight-path angle| (deg)
    var _sensorOn        as Boolean = false;
    var _sensorDataSeen  as Boolean = false;  // true once the batch listener delivered data
    var G_EMA_ALPHA      as Float   = 0.35;
    // Minimum gap between counted touch-downs (debounce against a noisy AGL
    // trace or the same event being seen by both onUpdate and onPosition)
    var lastLandingAt    as Number  = 0;
    var MIN_LANDING_GAP_MS as Number = 20000;

    // --- Display layout (settings-driven) ---
    // 0 = bezel ring with small radial fields, 1 = "pages": the chrono plus one
    // large value per page, cycled with UP (previous) and DOWN (next). Built for
    // legibility: the ring's radial text is capped by its arc length (~16-27 px
    // glyphs), whereas a page value gets ~26% of the screen height in the
    // boldest available face.
    var displayMode as Number = 1;
    var pageIdx as Number = 0;
    var pageCycleSec as Number = 0;      // paged face: seconds per page, 0 = manual only
    var lastPageCycleAt as Number = 0;   // System.getTimer() of the last page change
    var bigValFonts as Array = [];   // candidate value fonts, largest first
    var bigLblFont as Graphics.VectorFont? = null;
    var bigSubFont as Graphics.VectorFont? = null;
    var bigTimerFont as Graphics.VectorFont? = null;
    var bigFontsInitialized as Boolean = false;

    // --- Vector fonts (optional rounded font resource) ---
    var roundedFontLarge as Graphics.VectorFont? = null;
    var roundedFontSmall as Graphics.VectorFont? = null;
    var bezelLblFont     as Graphics.VectorFont? = null; // small label font for bezel items
    var bezelLblFace     as String? = null;
    var bezelLblFaceSize as Number = 0;
    var bezelFontsInitialized as Boolean = false;
    var bezelFontScale as Number = 100;
    var bezelContrast as Number = 100;
    // Whether companion app features are enabled (settings-driven)
    var useCompanionApp as Boolean = false;

    // --- Down-button hold detection ---
    var downPressAt as Number = 0; // System.getTimer() when DOWN pressed
    var DOWN_HOLD_MS as Number = 800; // ms to consider a long press
    var lastDownEventAt as Number = 0; // debounce last physical press
    // --- Up-button hold detection (pages mode: previous page, hold = sub-timer)
    var upPressAt as Number = 0;  // System.getTimer() when UP pressed
    var UP_HOLD_MS as Number = 800;
    var lastUpEventAt as Number = 0; // debounce last physical UP press
    var quickInfoShown as Boolean = false;
    var quickInfoLastNavAt as Number = 0; // ms timestamp of last quick-info navigation action
    var dimMode as Boolean = false;       // true when idle (clock showing) → dim chrome
    var lastIdleRefresh as Number = 0;    // System.getTimer() of last throttled redraw
    // Auto-backlight (settings-driven): keeps the display lit while flying so it
    // can be read in a dark cockpit without pressing a key.
    var autoBacklight as Number = 0;   // 0=off, 1=always, 2=night-only
    var nightStartHour as Number = 20; // backlight window start hour (0-23)
    var nightEndHour as Number = 7;    // backlight window end hour (0-23; < start = crosses midnight)
    var lastBacklightAt as Number = 0;        // System.getTimer() of last backlight request
    var BACKLIGHT_REPEAT_MS as Number = 20000; // re-light cadence while running

    // --- Circuit practice & landing counter ---
    var circuitEnabled as Boolean = false;
    var fieldElevationFt as Number = 0;       // effective field elevation (ft MSL); 0 = not captured
    var manualFieldElevationFt as Number = 0; // user override (0 = auto)
    var runwayLengthM as Number = 2405;
    var circuitPhase as Number = 0;           // 0=none, 1=upwind, 2=crosswind, 3=downwind, 4=base, 5=final
    var circuitLegStartMs as Number = 0;
    var circuitLevelVibrated as Boolean = false;
    var landings as Number = 0;
    var airborne as Boolean = false;
    var lastAglFt as Float = 0.0;
    var PATTERN_AGL_FT as Number = 1000;
    var TURN_CROSSWIND_AGL_FT as Number = 700;
    var CROSSWIND_SEC as Number = 35;
    var BASE_SEC as Number = 20;
    var DOWNWIND_EXTRA_M as Number = 300;

    // --- Altitude alert ---
    var altAlertFt as Number = 0;         // target MSL altitude (ft); 0 = off
    var altAlertApproaching as Boolean = false;
    var altAlertCrossed as Boolean = false;
    var lastAltForAlert as Float = 0.0;

    function initialize() {
        View.initialize();
    }

    // No XML layout — everything drawn manually
    function onLayout(dc as Dc) as Void {
    }



    // Read the three user-configurable properties and update runtime variables.
    // Safe to call at any time; GPS restart is handled separately by restartGps().
    function loadSettings() as Void {
        try {
        var settings = VFRSettings.read();
        VFRSettings.applySnapshot(self, settings);
        if (gpsMode == 3) {
            // Mode 3: Aviation
            Position.enableLocationEvents(
                { :acquisitionType => Position.LOCATION_CONTINUOUS,
                  :mode           => Position.POSITIONING_MODE_AVIATION },
                method(:onPosition)
            );
        } else if (gpsMode == 2) {
            // Mode 2: best multi-constellation available on device
            if ((Position has :CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1_L5) &&
                (Position has :hasConfigurationSupport) &&
                Position.hasConfigurationSupport(Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1_L5)) {
                Position.enableLocationEvents(
                    { :acquisitionType => Position.LOCATION_CONTINUOUS,
                      :configuration  => Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1_L5 },
                    method(:onPosition)
                );
            } else if ((Position has :CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1) &&
                       (Position has :hasConfigurationSupport) &&
                       Position.hasConfigurationSupport(Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1)) {
                Position.enableLocationEvents(
                    { :acquisitionType => Position.LOCATION_CONTINUOUS,
                      :configuration  => Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1 },
                    method(:onPosition)
                );
            } else if (Position has :CONSTELLATION_GLONASS) {
                Position.enableLocationEvents(
                    { :acquisitionType => Position.LOCATION_CONTINUOUS,
                      :constellations => [ Position.CONSTELLATION_GPS,
                                          Position.CONSTELLATION_GLONASS ] },
                    method(:onPosition)
                );
            } else {
                Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
            }
        } else if (gpsMode == 1 && (Position has :CONSTELLATION_GLONASS)) {
            // Mode 1: GPS + GLONASS
            Position.enableLocationEvents(
                { :acquisitionType => Position.LOCATION_CONTINUOUS,
                  :constellations => [ Position.CONSTELLATION_GPS,
                                       Position.CONSTELLATION_GLONASS ] },
                method(:onPosition)
            );
        } else {
            // Mode 0 (GPS only) or fallback when requested mode unsupported
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        }
        } catch (ex) { /* ignore settings parse errors */ }
    }

    function onShow() as Void {
        lastUpdateTimer = System.getTimer();
        loadSettings();
        restartGps();
        // With Auto Backlight on, light the display as soon as the face appears
        // (respecting the night-only window).
        if (autoBacklight != 0 && isBacklightWindow()) {
            lastBacklightAt = System.getTimer();
            lightUpBacklight();
        }
        if (needsResumePrompt) {
            needsResumePrompt = false;
            WatchUi.pushView(new VFRResumeView(self), new VFRResumeDelegate(self), WatchUi.SLIDE_UP);
        }
        WatchUi.requestUpdate();
    }

    // Request the display backlight at the system level. The backlight switches
    // itself off after the device's configured timeout, so this never holds it on
    // indefinitely (which could trip BacklightOnTooLongException on some devices).
    function lightUpBacklight() as Void {
        if (!(Attention has :backlight)) { return; }
        try { Attention.backlight(true); } catch (ex) { }
    }

    // True when auto-backlight should act right now. "Always" mode is always
    // true; "Night-only" mode checks the configured clock window (handles a
    // window that crosses midnight, e.g. 20:00–07:00).
    function isBacklightWindow() as Boolean {
        if (autoBacklight == 2) {
            var h = 0;
            try {
                var clk = System.getClockTime();
                if (clk != null) { h = clk.hour; }
            } catch (e) { h = 0; }
            if (nightStartHour < nightEndHour) {
                return (h >= nightStartHour) && (h < nightEndHour);
            }
            // Crosses midnight: active late (>= start) or early (< end).
            return (h >= nightStartHour) || (h < nightEndHour);
        }
        return true; // off handled by callers; mode 1 = always
    }

    // Restart GPS subscriptions according to current settings.
    // Minimal stub: loadSettings already enables events; callers expect this method to exist.
    function restartGps() as Void {
        try { /* noop for now - loadSettings handles subscription */ } catch (ex) { }
    }

    // GPS position callback — updates fix quality used for timer colour
    function onPosition(info as Position.Info) as Void {
        // Update cached quality and timestamp so we can detect stale fixes
        if (info != null) {
            if (info.accuracy != null) { gpsQuality = info.accuracy; }
            // Cache the latest accepted fix so a GPS outage can be repaired with
            // the straight-line distance to the fix that ends it.
            if (gpsQuality >= 3 && info.position != null) {
                try {
                    var degs = info.position.toDegrees();
                    if (degs != null && degs.size() >= 2) {
                        fixLatDeg = (degs[0] as Double).toFloat();
                        fixLonDeg = (degs[1] as Double).toFloat();
                        fixValid  = true;
                    }
                } catch (pe) { }
            }
            // Capture altitude when available and compute vertical speed
            {
                try {
                    var now = System.getTimer();
                    var sInfo = Sensor.getInfo();
                    // Use ONE altitude source (per the user's setting) for max-altitude
                    // and vertical speed. Barometric (QNH) and GPS altitudes sit on
                    // different datums, so mixing samples between them produces bogus
                    // vertical-speed spikes.
                    var useSource = (altitudeSource == 1) ? 1 : 0;
                    var alt = null;
                    if (useSource == 1) {
                        if (info.altitude != null) { alt = (info.altitude as Float); }
                    } else {
                        if (sInfo != null && sInfo.altitude != null) {
                            alt = (sInfo.altitude as Float);
                        } else if (info.altitude != null) {
                            // Device without a baro altimeter: fall back to GPS altitude
                            useSource = 1;
                            alt = (info.altitude as Float);
                        }
                    }
                    if (alt != null) {
                        if (running && (alt as Float) > maxAltitudeM) {
                            maxAltitudeM = (alt as Float);
                        }
                        // Take-off / touch-down detection and the bank & pitch
                        // graphs also run from here (not only onUpdate): position
                        // callbacks keep firing while a sub-view (quick info,
                        // trip, map, settings) covers the main view, so a
                        // landing can no longer be missed just because the
                        // screen was hidden at touch-down.
                        var aglFtPos = ((alt as Float) * 3.28084) - fieldElevationFt.toFloat();
                        var gsKtPos  = -1.0; // -1 = speed unknown
                        try {
                            if (info.speed != null) { gsKtPos = (info.speed as Float) * 1.94384; }
                        } catch (se) { }
                        lastAglFt = aglFtPos;
                        _updateAirborneState(aglFtPos, gsKtPos, now);
                        _updateAttitude(gsKtPos);
                        // GPS altitude is noisier → require longer spacing between samples
                        var minVsDt = (useSource == 1) ? 1000 : MIN_VS_DT_MS;
                        if (lastAltitudeMillis != 0 && lastAltSource == useSource) {
                            var dtMs = now - lastAltitudeMillis;
                            if (dtMs >= minVsDt) {
                                var vspd = (alt - lastAltitudeMeters) / (dtMs.toFloat() / 1000.0); // m/s
                                vertSpeedFpm = vspd * 196.85; // FPM
                                if (vertSpeedSmoothFpm == 0.0) {
                                    vertSpeedSmoothFpm = vertSpeedFpm;
                                } else {
                                    vertSpeedSmoothFpm = VERT_SPEED_SMOOTH_ALPHA * vertSpeedFpm
                                                       + (1.0 - VERT_SPEED_SMOOTH_ALPHA) * vertSpeedSmoothFpm;
                                }
                                var newTendency = 0;
                                if (vspd >= VERT_SPEED_THRESHOLD_MPS) { newTendency = 1; }
                                else if (vspd <= -VERT_SPEED_THRESHOLD_MPS) { newTendency = -1; }
                                if (newTendency != 0) {
                                    tendency = newTendency;
                                    tendencyUntil = now + 5000; // show arrow for 5s
                                    if ((now - lastTendencyVibrateAt) >= tendencyVibrateCooldownMs) {
                                        if (tendency > 0) { doTendencyVibrateUp(); }
                                        else { doTendencyVibrateDown(); }
                                        lastTendencyVibrateAt = now;
                                    }
                                }
                            }
                        }
                        lastAltitudeMeters = alt;
                        lastAltitudeMillis = now;
                        lastAltSource = useSource;
                        try {
                            var la = getApp();
                            var teleAltM = (altitudeSource == 1 && gpsAltitudeM != 0.0) ? gpsAltitudeM : alt;
                            la.liveAltFt = Math.round(teleAltM * 3.28084).toNumber();
                            la.liveVsFpm = (Math.round(vertSpeedSmoothFpm / 10.0).toNumber()) * 10;
                            la.liveGpsQuality = gpsQuality;
                        } catch (le) {}
                    }
                    // --- Turn rate from GPS track changes (for the bank estimate) ---
                    if (info.heading != null) {
                        var trackDeg = ((info.heading as Float) * (180.0 / Math.PI)).toFloat();
                        var trackNow = System.getTimer();
                        if (lastTrackDeg >= 0.0 && lastTrackMillis != 0) {
                            var dtS = (trackNow - lastTrackMillis).toFloat() / 1000.0;
                            if (dtS >= 0.5 && dtS <= 5.0) {
                                var dTrk = trackDeg - lastTrackDeg;
                                while (dTrk > 180.0) { dTrk -= 360.0; }
                                while (dTrk < -180.0) { dTrk += 360.0; }
                                var instRate = dTrk / dtS;
                                if (turnRateDegS == 0.0) { turnRateDegS = instRate; }
                                else { turnRateDegS = (0.3 * instRate) + (0.7 * turnRateDegS); }
                            }
                        }
                        lastTrackDeg = trackDeg;
                        lastTrackMillis = trackNow;
                    }
                    // Always cache GPS altitude separately (for GPS altitude source mode)
                    if (info.altitude != null) {
                        gpsAltitudeM = (info.altitude as Float);
                        gpsAltitudeMillis = now;
                    }
                    // Flight-level transition re-evaluated from the latest altitude.
                    // Runs off the baro sensor so it does not depend on GPS fix quality.
                    updateTransitionActive();
                } catch (ex) { }
            }
        }
        lastPositionMillis = System.getTimer();
        WatchUi.requestUpdate();
    }

    // Flight Level transition: active once the DISPLAYED altitude crosses the
    // configured transition altitude (with hysteresis). We decide from the same
    // altitude shown below transition — QNH-indicated baro altitude in baro mode,
    // GPS altitude in GPS mode — NOT pressure altitude, so the switch matches the
    // altimeter a pilot reads. (The FL value itself and the QNH=1013 display are
    // handled separately in drawBezelBackground.) Re-run every frame from the
    // sensor, so it works even without a GPS fix.
    function updateTransitionActive() as Void {
        var decideFt = -1.0;
        try {
            if (altitudeSource == 1) {
                if (gpsAltitudeM != 0.0) {
                    decideFt = gpsAltitudeM * 3.28084;
                } else {
                    var b = VFRAvionicsData.readAltitudeFeet();
                    if (b != null) { decideFt = (b as Number).toFloat(); }
                }
            } else {
                var a = VFRAvionicsData.readAltitudeFeet();
                if (a != null) { decideFt = (a as Number).toFloat(); }
            }
        } catch (ex) { decideFt = -1.0; }
        if (decideFt < 0.0) { return; }
        if (!transitionActive && decideFt >= transitionAltitudeFt) {
            transitionActive = true;
        } else if (transitionActive && decideFt <= (transitionAltitudeFt - transitionExitOffsetFt)) {
            transitionActive = false;
        }
    }

    function startStop() as Void {
        if (!running) {
            // First press: start the main stopwatch (no 5-min alerts yet)
            running = true;
            autoStartEnabled = false; // disarm auto-start once running
            hasTakenOff = false;      // re-armed when the take-off speed is reached
            taxiStartSince = 0;
            checkpointActive = false;
            // Capture field elevation on start (unless manually set)
            if (manualFieldElevationFt > 0) {
                fieldElevationFt = manualFieldElevationFt;
            } else if (fieldElevationFt == 0) {
                try {
                    var altStart = VFRAvionicsData.readAltitudeFeet();
                    if (altStart != null) { fieldElevationFt = (altStart as Number); }
                } catch (fe) { }
            }
            circuitPhase = 0;
            circuitLevelVibrated = false;
            airborne = false;
            altAlertApproaching = false;
            altAlertCrossed = false;
            lastAltForAlert = 0.0;
            startTime = System.getTimer() - elapsed;
            try { var la = getApp(); la.liveRunning = true; la.liveStartTime = startTime; } catch (le) {}
            // record trip start wall-clock times
            tripStartLocal = System.getClockTime();
            tripStartUtcMoment = Time.now();
            try {
                var info = Gregorian.utcInfo((tripStartUtcMoment as Time.Moment), Time.FORMAT_SHORT);
                tripStartUtcHour = info.hour;
                tripStartUtcMin = info.min;
            } catch (ex) { }
            // Start the fuel check counter relative to current elapsed
            nextFuelCheckAt = elapsed + FUEL_CHECK_INTERVAL_MS;
            lastUpdateTimer = System.getTimer();
            // Begin a new GPS recording session
            if (ActivityRecording has :createSession) {
                _session = ActivityRecording.createSession({
                    :name => "VFR Flight",
                    :sport => ActivityRecording.SPORT_GENERIC,
                    :subSport => ActivityRecording.SUB_SPORT_GENERIC
                });
                _session.start();
                // Developer fields are attached once the session is recording
                // (same ordering as Garmin's own MO2Display sample).
                var sess = _session;
                if (sess != null && (sess has :createField)) {
                    _createFitFields(sess as ActivityRecording.Session);
                }
                _startSensorCapture();
            }
            // Notify phone of flight start (OBT is already known here)
            var commsStart = getApp().getComms();
            if (commsStart != null && tripStartUtcMoment != null) {
                try {
                    commsStart.sendFlightStart((tripStartUtcMoment as Time.Moment).value().toNumber(),
                                               buildFlightReport(false));
                } catch (ex) {}
            }
            doStartVibrate();
            WatchUi.requestUpdate();
        } else if (running && !checkpointActive && timerIntervalMs > 0) {
            // Second press while running and interval enabled: start checkpoint alerts
            checkpointActive = true;
            // schedule next alert from now using the settings-driven interval
            var now = System.getTimer();
            var curElapsed = elapsedSince(now, startTime);
            nextVibrateAt = curElapsed + timerIntervalMs;
            checkpointHit = false;
            WatchUi.requestUpdate();
        } else {
            // Third press (running and checkpointActive): stop the stopwatch
            autoStop();
        }
    }

    function reset() as Void {
        // Discard any active recording session without saving
        if (_session != null) {
            if (_session.isRecording()) {
                _session.stop();
            }
            _session.discard();
            _session = null;
            _clearFitFields();
        }
        _stopSensorCapture();
        maxG = 0.0;        gForceG = 1.0;
        maxBankDeg = 0.0;
        maxPitchDeg = 0.0;
        running = false;
        elapsed = 0;
        try { var la = getApp(); la.liveRunning = false; la.liveBaseElapsed = 0; la.liveStartTime = 0; } catch (le) {}
        autoStartEnabled = true; // re-arm auto-start after reset
        hasTakenOff = false;     // next flight must reach take-off speed again
        taxiStartSince = 0;
        // Drop the stored fixes so a new flight cannot bridge across flights
        fixValid = false;
        accumRefValid = false;
        lastAccumAtMs = 0;
        totalDistanceM = 0.0;
        maxAltitudeM = 0.0;
        maxGsKt = 0.0;
        gsSumKt = 0.0;
        gsSamples = 0;
        kmAtCheckpoint = 0.0;
        nmAtCheckpoint = 0.0;
        checkpointHit = false;
        nextVibrateAt = timerIntervalMs > 0 ? timerIntervalMs : 300000; // respect user setting
        checkpointActive = false;
        nextFuelCheckAt = FUEL_CHECK_INTERVAL_MS;
        fuelFlashUntil = 0;
        lapMode = false;
        lapElapsed = 0;
        lapKm = 0.0;
        lapNm = 0.0;
        subTimerState = 0;
        subTimerStart = 0;
        subTimerElapsed = 0;
        startTime = System.getTimer();
        tripStartLocal = null;
        tripStartUtcMoment = null;
        tripEndUtcMoment = null;
        tripStartUtcHour = -1;
        tripStartUtcMin  = -1;
        tripEndUtcHour   = -1;
        tripEndUtcMin    = -1;
        zeroSpeedStartMs = 0;
        lastUpdateTimer = System.getTimer();
        landings = 0;
        airborne = false;
        circuitPhase = 0;
        circuitLevelVibrated = false;
        fieldElevationFt = 0;
        lastAglFt = 0.0;
        altAlertApproaching = false;
        altAlertCrossed = false;
        lastAltForAlert = 0.0;
        clearBackupProperties();
        doResetVibrate();
        WatchUi.requestUpdate();
    }

    function subTimer() as Void {
        var now = System.getTimer();
        if (subTimerState == 0) {
            // Start sub-timer
            subTimerStart = now;
            subTimerElapsed = 0;
            subTimerState = 1;
        } else if (subTimerState == 1) {
            // Stop (freeze) sub-timer
            subTimerElapsed = elapsedSince(now, subTimerStart);
            subTimerState = 2;
        } else {
            // Return to main view
            subTimerState = 0;
        }
        WatchUi.requestUpdate();
    }

    // Wrap-safe elapsed since a System.getTimer() reference. System.getTimer()
    // is a signed 32-bit millisecond counter that wraps after ~24.8 days of
    // continuous uptime. Interpreting both values as unsigned 32-bit and
    // subtracting in 64-bit keeps the timer correct across a single wrap
    // (a flight is always far shorter than one full wrap period).
    function elapsedSince(now as Number, start as Number) as Number {
        var unow = now.toDouble();
        if (unow < 0.0) { unow = unow + 4294967296.0; }
        var ustart = start.toDouble();
        if (ustart < 0.0) { ustart = ustart + 4294967296.0; }
        var d = unow - ustart;
        if (d < 0.0) { d = 0.0; }
        return d.toNumber();
    }

    function onUpdate(dc as Dc) as Void {
        var now = System.getTimer();
        dc.setAntiAlias(true);
        // Keep the Flight Level / QNH transition fresh from the baro sensor every
        // frame — independent of GPS callbacks and throttled redraws.
        updateTransitionActive();
        // Drive phone comms retry logic
        var comms = getApp().getComms();
        if (comms != null) {
            comms.tick(now);
            // Consume a pending trip clear
            if (comms.pendingTripClear) {
                comms.pendingTripClear = false;
                getApp().getTrip().clear();
            }
            // Consume a pending trip load
            if (comms.pendingTrip != null) {
                getApp().getTrip().loadFromMessage(comms.pendingTrip as Dictionary);
                comms.pendingTrip = null;
            }
        }
        // Single Activity.Info fetch — shared by GPS accumulation, HR and auto-start
        var actInfo = Activity.getActivityInfo();

        if (running) {
            elapsed = elapsedSince(now, startTime);

            // Auto backlight: periodically re-light while flying so the pilot can
            // read the face in a dark cockpit without pressing a button.
            if (autoBacklight != 0 && isBacklightWindow()
                && (now - lastBacklightAt) >= BACKLIGHT_REPEAT_MS) {
                lastBacklightAt = now;
                lightUpBacklight();
            }

            // Accumulate GPS ground speed into distance. Only with a usable fix:
            // a gap (no speed, no fix) is repaired by _bridgeDistanceGap() as
            // soon as the fix is back, so the metres flown meanwhile are not lost.
            var deltaMs = elapsedSince(now, lastUpdateTimer);
            if (deltaMs > 0 && deltaMs < 2000 && actInfo != null && gpsQuality >= 3) {
                var spd = actInfo.currentSpeed;
                if (spd != null) {
                    // currentSpeed is m/s; deltaMs is ms
                    var addM = (spd as Float) * (deltaMs.toFloat() / 1000.0);
                    totalDistanceM += addM;
                    // Add back the distance covered during any GPS outage and
                    // remember this fix as the new reference point.
                    _bridgeDistanceGap(now);
                    // Track max ground speed (knots)
                    try {
                        var gsKt = ((spd as Float) * 1.94384).toFloat();
                                    if (running && gsKt > maxGsKt) { maxGsKt = gsKt; }
                            // accumulate for average GS
                            if (running) {
                                gsSumKt = (gsSumKt as Float) + (gsKt as Float);
                                gsSamples = (gsSamples as Number) + 1;
                            }
                    } catch (ex) { }
                }
            }
            lastUpdateTimer = now;

            // Timer checkpoint: vibrate + snapshot km (only when activated)
            if (checkpointActive && timerIntervalMs > 0 && elapsed >= nextVibrateAt) {
                kmAtCheckpoint = totalDistanceM / 1000.0;
                nmAtCheckpoint = totalDistanceM / 1852.0;
                checkpointHit = true;
                nextVibrateAt += timerIntervalMs;
                doFiveMinAlert();
            }
            // 30-minute fuel check: flash stopwatch colours and vibrate
            if (FUEL_CHECK_INTERVAL_MS > 0 && elapsed >= nextFuelCheckAt) {
                fuelFlashUntil = now + 5000; // flash for 5 seconds
                doFuelAlert();
                nextFuelCheckAt += FUEL_CHECK_INTERVAL_MS;
            }

            // Auto-stop if speed is truly zero for AUTO_STOP_DELAY_MS.
            // Only count while GPS fix is good (quality >= 3) and speed is
            // explicitly non-null — a null speed means GPS is lost, not grounded.
            // ALSO gated on hasTakenOff: the flight now starts during taxi, so a
            // stop on the apron (before the take-off threshold is ever reached)
            // must not end the flight — that is the pilot's manual job.
            if (actInfo != null && gpsQuality >= 3 && hasTakenOff) {
                var aspd = actInfo.currentSpeed;
                if (aspd != null && (aspd as Float) < 0.5) {
                    // Confirmed zero speed with a good GPS fix
                    if (zeroSpeedStartMs == 0) { zeroSpeedStartMs = now; }
                    else if (elapsedSince(now, zeroSpeedStartMs) >= AUTO_STOP_DELAY_MS) {
                        zeroSpeedStartMs = 0;
                        autoStop();
                    }
                } else {
                    // Speed > 0, null (no fix), or GPS quality dropped — reset counter
                    zeroSpeedStartMs = 0;
                }
            } else {
                // GPS not good enough to make a call — reset counter to avoid false trigger
                zeroSpeedStartMs = 0;
            }

            // --- Circuit practice & landing counter ---
            if (running) {
                // G-force fallback when the batch listener is silent (also the
                // 1 Hz graph heartbeat for the accelerometer channel).
                _captureGForceFallback();
                var gsKtNow = -1.0; // -1 = speed unknown
                if (actInfo != null && actInfo.currentSpeed != null) {
                    gsKtNow = (actInfo.currentSpeed as Float) * 1.94384;
                }
                var aglNow = 0.0;
                var altMslNow = VFRAvionicsData.readAltitudeFeet();
                var haveAlt = (altMslNow != null);
                if (haveAlt) {
                    aglNow = (altMslNow as Number).toFloat() - fieldElevationFt.toFloat();
                    lastAglFt = aglNow;
                    checkAltitudeAlert((altMslNow as Number).toFloat());
                }

                // Estimated bank angle from smoothed turn rate (coordinated-turn model)
                // → computed in onPosition() along with the bank/pitch graphs.

                // Airborne / landing + circuit only when altitude is valid, so a
                // momentary sensor dropout can't be misread as "on the ground".
                if (haveAlt) {
                    _updateAirborneState(aglNow, gsKtNow, now);

                    // Circuit phase machine
                    if (circuitEnabled && airborne && circuitPhase > 0) {
                        var legMs = now - circuitLegStartMs;
                        if (circuitPhase == 1) {
                            if (aglNow >= TURN_CROSSWIND_AGL_FT) {
                                circuitPhase = 2; circuitLegStartMs = now; doTurnVibrate();
                            }
                        } else if (circuitPhase == 2) {
                            if (legMs >= CROSSWIND_SEC * 1000) {
                                circuitPhase = 3; circuitLegStartMs = now; circuitLevelVibrated = false; doTurnVibrate();
                            }
                        } else if (circuitPhase == 3) {
                            if (!circuitLevelVibrated && aglNow >= (PATTERN_AGL_FT - 50)) {
                                circuitLevelVibrated = true; doLevelVibrate();
                            }
                            if (legMs >= computeDownwindMs(gsKtNow)) {
                                circuitPhase = 4; circuitLegStartMs = now; doTurnVibrate();
                            }
                        } else if (circuitPhase == 4) {
                            if (legMs >= BASE_SEC * 1000) {
                                circuitPhase = 5; circuitLegStartMs = now; doTurnVibrate();
                            }
                        }
                    }
                }
            }
        }

        // Periodic on-disk backup: save a compact state to Application settings
        if ((now - lastBackupMillis) >= BACKUP_INTERVAL_MS) {
            try {
                saveBackupProperties();
                lastBackupMillis = now;
            } catch (ex) {
            }
        }

        // --- Heart rate monitoring + GPS quality sync (reuses actInfo, no extra allocation) ---
        if (actInfo != null) {
            var hrVal = actInfo.currentHeartRate;
            if (hrVal != null && hrVal > 0) {
                lastHr = hrVal;
            }
            // Keep gpsQuality current between Position callback firings
            var locAcc = actInfo.currentLocationAccuracy;
            if (locAcc != null) {
                gpsQuality = locAcc;
                // mark as recently updated so we don't immediately go stale
                lastPositionMillis = System.getTimer();
            }
        }

        // If we haven't received a position update recently, consider the fix lost
        // and force quality to 0 so the UI shows the no-fix state (red).
        // Use a short timeout (5s) to avoid false positives during brief gaps.
        if (elapsedSince(now, lastPositionMillis) > 5000) {
            if (gpsQuality != 0) {
                gpsQuality = 0;
            }
        }

        // --- Auto-start on taxi: begin the clock as soon as the aircraft starts
        // rolling, so OBT is the off-block time. Requires a recent good fix and
        // the taxi speed held for TAXI_START_HOLD_MS, which keeps the pilot
        // walking to the aircraft (well under the taxi threshold) from starting
        // the flight. ---
        if (autoStartEnabled && !running && AUTO_START_SPEED_MS > 0.0 && actInfo != null
            && gpsQuality >= 3 && (elapsedSince(now, lastPositionMillis) <= 5000)) {
            var spd = actInfo.currentSpeed;
            if (spd != null && (spd as Float) >= TAXI_START_SPEED_MS) {
                if (taxiStartSince == 0) {
                    taxiStartSince = now;
                } else if (elapsedSince(now, taxiStartSince) >= TAXI_START_HOLD_MS) {
                    taxiStartSince = 0;
                    startStop();
                }
            } else {
                // Slowed down / no usable speed → restart the hold window
                taxiStartSince = 0;
            }
        } else {
            taxiStartSince = 0;
        }
        // Reaching the take-off speed marks the flight as genuinely airborne and
        // arms the zero-speed auto-stop for the rest of the flight.
        if (running && !hasTakenOff && actInfo != null && actInfo.currentSpeed != null
                && (actInfo.currentSpeed as Float) >= takeoffArmSpeedMs()) {
            hasTakenOff = true;
        }
        if (HR_THRESHOLD > 0 && lastHr > 0 && lastHr > HR_THRESHOLD) {
            hrFlashOn = (((now / 500).toNumber() % 2) == 0); // time-based 1 Hz blink
            if (!hrAlertActive) {
                hrAlertActive = true;
                hrNextVibrate = 0; // fire immediately on first detection
            }
            if (now >= hrNextVibrate) {
                doHrAlert();
                hrNextVibrate = now + 30000; // repeat every 30 s while elevated
            }
        } else {
            hrAlertActive = false;
            hrFlashOn = false;
        }

        // --- Update flight plan navigation (bearing/distance/ETE) ---
        var trip = getApp().getTrip();
        if (trip.active && actInfo != null) {
            try {
                var pos = Position.getInfo();
                if (pos != null && pos.accuracy != null && (pos.accuracy as Number) >= 3
                        && pos.position != null) {
                    var degs = pos.position.toDegrees();
                    if (degs != null && degs.size() >= 2) {
                        var gsKt = 0.0;
                        if (actInfo.currentSpeed != null) {
                            gsKt = ((actInfo.currentSpeed as Float) * 1.94384).toFloat();
                        }
                        trip.updateFromPosition(
                            (degs[0] as Double).toFloat(),
                            (degs[1] as Double).toFloat(),
                            gsKt);
                    }
                }
            } catch (ex) {}
        }

        // --- Compute sub-timer elapsed if running ---
        var subMs = subTimerElapsed;
        if (subTimerState == 1) {
            subMs = elapsedSince(now, subTimerStart);
        }

        // --- Decide whether to display clock or timer ---
        var displayClock = (!running && elapsed == 0 && subTimerState == 0);
        dimMode = displayClock;

        // --- Pick which values to display ---
        // Sub-timer takes priority over lap mode for the number display
        var displayMs  = 0;
        var timerColor = Graphics.COLOR_WHITE;
        if (subTimerState != 0) {
            displayMs  = subMs < 0 ? 0 : subMs;
            timerColor = Graphics.COLOR_BLUE;
        } else if (lapMode) {
            displayMs  = lapElapsed;
            timerColor = Graphics.COLOR_GREEN;
        } else {
            displayMs  = elapsed < 0 ? 0 : elapsed;
            // GPS fix indicator on the timer colour: red=no fix, flashing orange=acquiring, green=captured
            if (gpsQuality >= 3) {
                timerColor = Graphics.COLOR_GREEN;
            } else if (gpsQuality == 2) {
                // Blink between orange and black (text disappears against black bg)
                var blinkPhase = ((now / 500).toNumber() % 2).toNumber();
                timerColor = (blinkPhase == 0) ? Graphics.COLOR_ORANGE : Graphics.COLOR_BLACK;
            } else {
                timerColor = Graphics.COLOR_RED;
            }
        }
        // Fuel flash active while within the flash window
        var fuelFlashActive = fuelFlashUntil > now;
        if (fuelFlashActive) {
            var phase = ((now / 400).toNumber() % 2).toNumber();
            if (phase == 0) {
                timerColor = Graphics.COLOR_YELLOW;
            } else {
                timerColor = Graphics.COLOR_ORANGE;
            }
        }

        var totalSec = displayMs / 1000;
        var hours    = totalSec / 3600;
        var minutes  = (totalSec % 3600) / 60;
        var seconds  = totalSec % 60;
        var mStr = minutes < 10 ? "0" + minutes.toString() : minutes.toString();
        var sStr = seconds < 10 ? "0" + seconds.toString() : seconds.toString();

        // Optional auto page rotation (off unless PageCycleSec > 0)
        updatePageCycle(now);

        // --- Draw (face layout) ---
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var minWh = (w < h) ? w : h;
        var R2 = (minWh / 2).toFloat();

        if (displayMode == 1) {
            // Paged layout: the chrono plus one large value per page. UP cycles
            // backwards, DOWN forwards (hold UP for the sub-timer).
            drawPagesView(dc, displayTimerString(displayClock, hours, mStr, sStr), timerColor);
        } else {
        drawBezelBackground(dc);

        // --- FPL indicator (shown when a flight plan is loaded) ---
        var tripFpl = getApp().getTrip();
        if (tripFpl.active) {
            var wpLbl = "FPL " + (tripFpl.activeIdx + 1).toString() + "/" + tripFpl.count.toString();
            dc.setColor(0x00FFFF, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - (R2 * 0.48).toNumber(), Graphics.FONT_XTINY, wpLbl,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // --- Centre: timer / clock (colour reflects GPS/run state) ---
        var chronoFont = (roundedFontLarge != null) ? roundedFontLarge : Graphics.FONT_NUMBER_HOT;
        var centerStr = displayTimerString(displayClock, hours, mStr, sStr);
        dc.setColor(timerColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, chronoFont, centerStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // V/S below the timer (when recent altitude data is available)
        if (lastAltitudeMillis != 0 && (now - lastAltitudeMillis) < 10000) {
            var fpmRounded = (Math.round(vertSpeedSmoothFpm / 10.0) * 10.0).toNumber();
            var vsSign = fpmRounded >= 0 ? "+" : "";
            var vsStr = "V/S " + vsSign + fpmRounded.toString();
            var vsFont = (roundedFontSmall != null) ? roundedFontSmall : Graphics.FONT_SMALL;
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + (R2 * 0.28).toNumber(), vsFont, vsStr,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // --- Circuit practice status (cyan line above the timer) ---
        // While airborne in a circuit: current leg + AGL + bank. Before the
        // pattern begins (armed but still on the ground / climbing out) show a
        // plain "CIRCUIT" cue so the pilot can confirm the helper is active.
        if (circuitEnabled && running) {
            var circStr = "";
            if (circuitPhase > 0) {
                circStr = circuitPhaseName() + " " + Math.round(lastAglFt).toNumber().toString() + "FT";
                var bankAbs = liveBankDeg < 0.0 ? -liveBankDeg : liveBankDeg;
                if (bankAbs >= 5.0) {
                    circStr = circStr + " B" + Math.round(liveBankDeg).toNumber().toString() + "\u00B0";
                }
            } else {
                circStr = "CIRCUIT";
            }
            dc.setColor(0x00FFFF, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - (R2 * 0.30).toNumber(), Graphics.FONT_XTINY, circStr,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // --- Distance flown (NM, persistent while running or frozen on lap/checkpoint) ---
        if (running || lapMode || checkpointHit) {
            var nmVal = lapMode ? lapNm : (checkpointHit ? nmAtCheckpoint : (totalDistanceM / 1852.0));
            var nmInt = nmVal.toNumber();
            var nmDec = ((nmVal - nmInt.toFloat()) * 10.0).toNumber();
            if (nmDec < 0) { nmDec = 0; }
            var nmStr = nmInt.toString() + "." + nmDec.toString() + " NM";
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + (R2 * 0.50).toNumber(), Graphics.FONT_TINY, nmStr,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        }   // end of ring layout

        // Refresh policy: fast while anything is live/flashing, otherwise throttle.
        var fast = running || subTimerState == 1 || hrAlertActive || fuelFlashActive
                 || (tendency != 0 && tendencyUntil > now);
        var slow = false;
        if (!fast) {
            if ((autoStartEnabled && AUTO_START_SPEED_MS > 0.0) || gpsQuality < 3) {
                // Armed waiting for takeoff or still acquiring GPS → poll at 1 Hz
                slow = (now - lastIdleRefresh) >= 1000;
            } else if (displayClock) {
                // Idle clock → refresh every 5 s (clock text changes per minute;
                // GPS colour updates come via position callbacks)
                slow = (now - lastIdleRefresh) >= 5000;
            }
        }
        if (fast || slow) {
            lastIdleRefresh = now;
            WatchUi.requestUpdate();
        }
    }

    // Draw the static bezel background: clear, annulus labels, separator ring,
    // group separators, and phone indicator arc.
    // Pure drawing — no state mutation and no WatchUi.requestUpdate().
    function drawBezelBackground(dc as Dc) as Void {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var now = System.getTimer();

        // Background: flash red when HR alert active, otherwise black
        if (hrAlertActive && hrFlashOn) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_RED);
        } else {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        }
        dc.clear();

        var minWh = (w < h) ? w : h;

        // Initialize vector fonts once.  Bezel text chooses its own small face
        // instead of inheriting whichever face happened to fit the chrono.
        if (!bezelFontsInitialized) {
            var chronoSize   = (minWh * 0.24).toNumber();
            var fontScale = bezelFontScale.toFloat() / 100.0;
            var bezelSize    = (minWh.toFloat() * 0.062 * fontScale).toNumber();
            var bezelLblSize = (minWh.toFloat() * 0.082 * fontScale).toNumber();
            var faces = ["OpenSans", "OpenSansRegular", "Nunito", "NunitoRegular", "RobotoCondensed", "Roboto", "RobotoBlack", "RobotoRegular", "Swiss721Bold", "TomorrowBold"];
            for (var fi = 0; fi < faces.size() && roundedFontLarge == null; fi++) {
                try {
                    var f = Graphics.getVectorFont({:face => faces[fi], :size => chronoSize});
                            if (f != null) {
                                roundedFontLarge = f;
                                roundedFontSmall = Graphics.getVectorFont({:face => faces[fi], :size => bezelSize});
                            }
                } catch (ex) { }
            }

            var bezelFaces = ["OpenSans", "OpenSansRegular", "Nunito", "NunitoRegular", "RobotoCondensed", "RobotoRegular", "Roboto", "Swiss721Bold", "TomorrowBold", "RobotoBlack"];
            for (var bfi = 0; bfi < bezelFaces.size() && bezelLblFont == null; bfi++) {
                try {
                    var bf = Graphics.getVectorFont({:face => bezelFaces[bfi], :size => bezelLblSize});
                    if (bf != null) {
                        bezelLblFont = bf;
                        bezelLblFace = bezelFaces[bfi];
                        bezelLblFaceSize = bezelLblSize;
                    }
                } catch (exf) { }
            }
            if (roundedFontSmall == null && bezelLblFace != null) {
                try { roundedFontSmall = Graphics.getVectorFont({:face => bezelLblFace, :size => bezelSize}); } catch (exs) { }
            }
            bezelFontsInitialized = true;
        }

        // --- Bezel data strings ---

        // Heading: use GPS-derived `course` (degrees) when available
        var hdgStr = "--";
        var gsStr = "--";
        try {
            var hdg = VFRHeading.getHeadingDeg();
            if (hdg >= 0) {
                var hdgInt = Math.round(hdg).toNumber();
                if (hdgInt < 10)       { hdgStr = "00" + hdgInt.toString(); }
                else if (hdgInt < 100) { hdgStr = "0"  + hdgInt.toString(); }
                else                   { hdgStr = hdgInt.toString(); }
            }
        } catch (ex) { }

        // Ground speed (knots) — use Math.round to avoid truncation error
        // (e.g. 30 kt = 15.43 m/s → 29.99 kt rounds to 30, not truncates to 29)
        try {
            var actInfoLocal = Activity.getActivityInfo();
            if (actInfoLocal != null && actInfoLocal.currentSpeed != null) {
                gsStr = Math.round((actInfoLocal.currentSpeed as Float) * 1.94384).toNumber().toString();
            }
        } catch (ex) { }

        // QNH + Altitude
        var altStr    = "-----";
        var altLbl    = (altitudeSource == 1) ? "GALT" : "ALT";
        var qnhInfo = VFRAvionicsData.readQnhInfo();

        // Altitude: barometric or GPS per user setting
        try {
            if (altitudeSource == 1) {
                // GPS altitude mode — use cached GPS altitude from Position.Info
                var gpsAgeMs = now - gpsAltitudeMillis;
                if (gpsAltitudeM != 0.0 && gpsAgeMs < 30000) {
                    var gpsAltFt = Math.round(gpsAltitudeM * 3.28084).toNumber();
                    if (transitionActive) {
                        var fl = Math.round(gpsAltFt.toFloat() / 100.0).toNumber();
                        altStr = "FL" + fl.toString();
                    } else {
                        altStr = gpsAltFt.toString();
                    }
                }
            } else {
                // Barometric altitude mode (default)
                if (transitionActive) {
                    // Above transition: Flight Level from pressure altitude (1013.25 hPa reference),
                    // NOT from QNH altitude — the two differ whenever local QNH ≠ 1013.
                    var paFtObj = VFRAvionicsData.readPressureAltitudeFeet();
                    if (paFtObj != null) {
                        var fl = Math.round((paFtObj as Number).toFloat() / 100.0).toNumber();
                        altStr = "FL" + fl.toString();
                    }
                } else {
                    // Below transition: QNH altitude from barometric sensor
                    var altFtObj = VFRAvionicsData.readAltitudeFeet();
                    if (altFtObj != null) {
                        altStr = (altFtObj as Number).toString();
                    }
                }
            }
        } catch (ae) { System.println("Altitude error: " + ae.getErrorMessage()); }

        // Append tendency indicator to the alt string
        if (running && tendency != 0 && now < tendencyUntil) {
            altStr = altStr + (tendency > 0 ? "+" : "-");
        }

        // --- Face chrome ---
        var R = (minWh / 2).toFloat();
        var ringR = (R - 6.0).toNumber();
        var guideColor = bezelGuideColor();

        // Anti-aliased reference ring
        dc.setColor(guideColor, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawCircle(cx, cy, ringR);

        // Inner circle to form the data ring (annulus) with the outer ring
        var ringInner = (R * 0.79).toNumber();
        dc.setColor(guideColor, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawCircle(cx, cy, ringInner);
        dc.setPenWidth(1);

        // Cardinal tick marks at 12/3/6/9 o'clock
        dc.setColor(guideColor, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        var tickAngles = [90.0, 0.0, 270.0, 180.0];
        for (var ti = 0; ti < tickAngles.size(); ti++) {
            var aDeg = (tickAngles[ti] as Float).toFloat();
            var aRad = aDeg * (Math.PI / 180.0);
            var sx = (cx.toFloat() + (ringR - 1.0) * Math.cos(aRad)).toNumber();
            var sy = (cy.toFloat() - (ringR - 1.0) * Math.sin(aRad)).toNumber();
            var ex = (cx.toFloat() + (ringR - 8.0) * Math.cos(aRad)).toNumber();
            var ey = (cy.toFloat() - (ringR - 8.0) * Math.sin(aRad)).toNumber();
            dc.drawLine(sx, sy, ex, ey);
        }
        dc.setPenWidth(1);

        // --- Bezel fields: HDG / GS on top, ALT below ---
        // QNH was dropped by request (set from ATIS, not read in flight), which
        // also frees the SE quadrant.
        // Angles are degrees CCW from 3 o'clock (0=right, 90=top).
        // CLOCKWISE extends glyphs outward from the given radius, while
        // COUNTER_CLOCKWISE extends them inward — compensate so both halves
        // share the same visual ring, hugging the outer reference ring.
        // Use the ACTUAL scaled bezel label size for the radius compensation so
        // the top (clockwise) fields don't overlap the ring when Bezel Font >100%.
        var textH    = (bezelLblFaceSize > 0) ? bezelLblFaceSize : (minWh * 0.082).toNumber();
        var rOuter   = (R - 8.0).toNumber();
        var rClock   = rOuter - textH + 5;
        var rCounter = rOuter;
        var neutralColor = bezelLabelColor();
        var altColor     = transitionActive ? 0x00FFFF : neutralColor;   // cyan in FL regime
        drawRadialField(dc, cx, cy, 135.0, "HDG " + hdgStr,       rClock,   Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE,         neutralColor);
        drawRadialField(dc, cx, cy, 45.0,  "GS " + gsStr,         rClock,   Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE,         neutralColor);
        drawRadialField(dc, cx, cy, 225.0, altLbl + " " + altStr, rCounter, Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE, altColor);

        // --- Phone connection dot (just inside the ring at 6 o'clock) ---
        if (useCompanionApp) {
            var cInd = getApp().getComms();
            var dotCol = Graphics.COLOR_YELLOW;
            var showDot = true;
            if (cInd != null) {
                if (cInd.connected) {
                    dotCol = Graphics.COLOR_GREEN;
                } else if (cInd.connecting) {
                    var lastShake = 0;
                    try { lastShake = (cInd.lastHandshakeAt as Number); } catch (e) { lastShake = 0; }
                    if (lastShake > 0 && (now - lastShake) < 30000) {
                        showDot = (((now / 500).toNumber() % 2) == 0);
                        dotCol = Graphics.COLOR_YELLOW;
                    } else {
                        dotCol = Graphics.COLOR_RED;
                    }
                } else {
                    dotCol = Graphics.COLOR_RED;
                }
            }
            if (showDot) {
                dc.setColor(dotCol, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx, cy + (R - 14.0).toNumber(), 4);
            }
        }
    }

    function saveState() as Dictionary {
        // NOTE: seed with a LITERAL. In this project's typing mode
        // `new Dictionary()` builds a SYMBOL-keyed dictionary, so writing a
        // String key into it throws "ExpectedTypeException: Expected Symbol,
        // given String" — and the caller swallows that exception, silently
        // losing the state. A literal creates a String-keyed dictionary.
        var d = { "running" => running };
        d["running"] = running;
        d["startTime"] = startTime;
        // When running, 'elapsed' field is 0; compute live elapsed for persistence
        d["elapsed"] = running ? elapsedSince(System.getTimer(), startTime) : elapsed;
        d["totalDistanceM"] = totalDistanceM;
        d["checkpointActive"] = checkpointActive;
        d["nextVibrateAt"] = nextVibrateAt;
        d["kmAtCheckpoint"] = kmAtCheckpoint;
        d["nmAtCheckpoint"] = nmAtCheckpoint;
        d["lapMode"] = lapMode;
        d["lapElapsed"] = lapElapsed;
        d["lapKm"] = lapKm;
        d["lapNm"] = lapNm;
        d["subTimerState"] = subTimerState;
        d["subTimerStart"] = subTimerStart;
        // Persist a live sub-timer elapsed so a kill mid-sub-timer freezes at
        // the correct value instead of 0.
        d["subTimerElapsed"] = (subTimerState == 1) ? elapsedSince(System.getTimer(), subTimerStart) : subTimerElapsed;
        // Save trip start/end times as epoch numbers if available
        // Save simple hour/min snapshots for display on restore
        if (tripStartUtcHour >= 0) { d["tripStartUtcHour"] = tripStartUtcHour; }
        if (tripStartUtcMin  >= 0) { d["tripStartUtcMin"]  = tripStartUtcMin; }
        if (tripEndUtcHour   >= 0) { d["tripEndUtcHour"]   = tripEndUtcHour; }
        if (tripEndUtcMin    >= 0) { d["tripEndUtcMin"]    = tripEndUtcMin; }
        return d;
    }

    // ── Bezel labels ────────────────────────────────────────────────────────
    // Each bezel label is drawn with Dc.drawRadialText(), which arcs the whole
    // string around the ring (the native Garmin approach). The `angle` passed
    // in is degrees counter-clockwise from 3 o'clock (0° = right, 90° = top),
    // matching angleHDG/GS/ALT/QNH in drawBezelBackground().
    function invalidateBezelRendering() as Void {
        roundedFontLarge = null;
        roundedFontSmall = null;
        bezelLblFont = null;
        bezelLblFace = null;
        bezelLblFaceSize = 0;
        bezelFontsInitialized = false;
    }

    // Draw a bezel field as a single line of text oriented along the ring
    // (label and value combined, e.g. "HDG 330"), rendered with the native
    // drawRadialText API. `angle` is degrees counter-clockwise from 3 o'clock.
    function drawRadialField(dc as Dc, cx as Number, cy as Number, angle as Float,
            text as String, radius as Number, direction as Graphics.RadialTextDirection,
            valueColor as Number) as Void {
        if (bezelLblFont != null) {
            dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
            dc.drawRadialText(cx, cy, bezelLblFont as Graphics.VectorFont, text,
                Graphics.TEXT_JUSTIFY_CENTER, angle.toFloat(), radius.toFloat(), direction);
        }
    }

    function bezelLabelColor() as Number {
        // Field text is always full white for clear readability; the idle dim
        // only softens the decorative guide ring below, never the data text.
        return Graphics.COLOR_WHITE;
    }

    function bezelGuideColor() as Number {
        if (dimMode) { return Graphics.COLOR_DK_GRAY; }
        if (bezelContrast >= 75) { return Graphics.COLOR_LT_GRAY; }
        return Graphics.COLOR_DK_GRAY;
    }

    function loadState(d as Dictionary) as Void {
        if (d == null) { return; }
        if (d["running"] != null) { running = d["running"] as Boolean; }
        if (d["startTime"] != null) { startTime = d["startTime"] as Number; }
        if (d["elapsed"] != null) { elapsed = d["elapsed"] as Number; }
        if (d["totalDistanceM"] != null) { totalDistanceM = d["totalDistanceM"] as Float; }
        if (d["checkpointActive"] != null) { checkpointActive = d["checkpointActive"] as Boolean; }
        if (d["nextVibrateAt"] != null) { nextVibrateAt = d["nextVibrateAt"] as Number; }
        if (d["kmAtCheckpoint"] != null) { kmAtCheckpoint = d["kmAtCheckpoint"] as Float; }
        if (d["nmAtCheckpoint"] != null) { nmAtCheckpoint = d["nmAtCheckpoint"] as Float; }
        if (d["lapMode"] != null) { lapMode = d["lapMode"] as Boolean; }
        if (d["lapElapsed"] != null) { lapElapsed = d["lapElapsed"] as Number; }
        if (d["lapKm"] != null) { lapKm = d["lapKm"] as Float; }
        if (d["lapNm"] != null) { lapNm = d["lapNm"] as Float; }
        if (d["subTimerState"] != null) { subTimerState = d["subTimerState"] as Number; }
        if (d["subTimerStart"] != null) { subTimerStart = d["subTimerStart"] as Number; }
        if (d["subTimerElapsed"] != null) { subTimerElapsed = d["subTimerElapsed"] as Number; }
        if (d["tripStartUtcHour"] != null) { tripStartUtcHour = d["tripStartUtcHour"] as Number; }
        if (d["tripStartUtcMin"]  != null) { tripStartUtcMin  = d["tripStartUtcMin"]  as Number; }
        if (d["tripEndUtcHour"]   != null) { tripEndUtcHour   = d["tripEndUtcHour"]   as Number; }
        if (d["tripEndUtcMin"]    != null) { tripEndUtcMin    = d["tripEndUtcMin"]    as Number; }
        // Ensure UI updates to reflect restored state
        WatchUi.requestUpdate();
    }

    // Stop the activity from any running state; push summary screen
    function autoStop() as Void {
        if (!running) { return; }
        running = false;
        // The clock can be stopped by hand or by the zero-speed timer; make sure
        // the last touch-down is in the logbook either way.
        _countLandingIfGroundborne();
        doStopVibrate();
        elapsed = elapsedSince(System.getTimer(), startTime);
        try { var la = getApp(); la.liveRunning = false; la.liveBaseElapsed = elapsed; } catch (le) {}
        tripEndUtcMoment = Time.now();
        try {
            var einfo = Gregorian.utcInfo((tripEndUtcMoment as Time.Moment), Time.FORMAT_SHORT);
            tripEndUtcHour = einfo.hour;
            tripEndUtcMin = einfo.min;
        } catch (ex) { }
        checkpointActive = false;
        zeroSpeedStartMs = 0;
        if (_session != null) {
            // Session developer fields are written once, at the end of the
            // recording — so the summary has to be set before stop().
            _writeFitSummary();
            if (_session.isRecording()) { _session.stop(); }
            _session.save();
            _session = null;
            _clearFitFields();
        }
        _stopSensorCapture();
        saveBackupProperties(); // persist so summary survives a kill
        // Notify phone of flight stop, with the flight report attached
        var commsStop = getApp().getComms();
        if (commsStop != null && tripEndUtcMoment != null) {
            try {
                commsStop.sendFlightStop((tripEndUtcMoment as Time.Moment).value().toNumber(),
                                         buildFlightReport(true));
            } catch (ex) {}
        }
        WatchUi.pushView(new VFRSummaryView(self), new VFRSummaryDelegate(self), WatchUi.SLIDE_UP);
    }

    // Speed that marks "we have taken off": the configured take-off speed, or
    // 30 kt when auto-start has been disabled by setting it to 0.
    function takeoffArmSpeedMs() as Float {
        return (AUTO_START_SPEED_MS > 0.0) ? AUTO_START_SPEED_MS : 15.4333;
    }

    // ── Distance gap repair ──────────────────────────────────────────────

    // Called after every accumulated sample. If accumulation was interrupted
    // (GPS outage, stale fix, app busy elsewhere) the distance flown meanwhile
    // is missing, so add the great-circle distance from the fix at the last
    // accumulated sample to the current one. Normal 1 Hz operation is skipped
    // (the speed integration already covers it) and so is any "gap" implying an
    // impossible speed, which is a GPS glitch rather than movement.
    function _bridgeDistanceGap(now as Number) as Void {
        var gapMs = (lastAccumAtMs != 0) ? elapsedSince(now, lastAccumAtMs) : 0;
        if (gapMs >= GAP_BRIDGE_MIN_MS && fixValid && accumRefValid) {
            var dM = _distanceM(accumRefLat, accumRefLon, fixLatDeg, fixLonDeg);
            var gapS = gapMs.toFloat() / 1000.0;
            var impliedMps = (gapS > 0.0) ? (dM / gapS) : 0.0;
            if (impliedMps <= MAX_BRIDGE_SPEED_MPS) {
                totalDistanceM += dM;
                try {
                    System.println("VFR: GPS gap " + (gapMs / 1000).toString() + "s bridged, +"
                        + dM.toNumber().toString() + " m");
                } catch (le) { }
            }
        }
        // The current fix becomes the reference for the next gap
        if (fixValid) {
            accumRefLat   = fixLatDeg;
            accumRefLon   = fixLonDeg;
            accumRefValid = true;
        }
        lastAccumAtMs = now;
    }

    // Great-circle distance in metres between two decimal-degree positions.
    function _distanceM(lat1 as Float, lon1 as Float, lat2 as Float, lon2 as Float) as Float {
        var d2r = Math.PI / 180.0;
        var rlat1 = lat1 * d2r;
        var rlat2 = lat2 * d2r;
        var dLat  = (lat2 - lat1) * d2r;
        var dLon  = (lon2 - lon1) * d2r;
        var sinDLat = Math.sin(dLat / 2.0);
        var sinDLon = Math.sin(dLon / 2.0);
        var a = (sinDLat * sinDLat)
              + (Math.cos(rlat1) * Math.cos(rlat2) * sinDLon * sinDLon);
        var c = 2.0 * Math.atan2(Math.sqrt(a), Math.sqrt(1.0 - a));
        return (6371000.0 * c).toFloat();
    }

    // ── Flight report ───────────────────────────────────────────────────────
    // The same figures shown on the TRIP SUMMARY screen are also written into
    // the saved activity (FIT developer fields → Garmin Connect) and sent to
    // the phone companion app with the flight_event stop message.

    // UTC epoch seconds for a Moment, or -1 when unavailable.
    function momentEpochSec(m as Time.Moment?) as Number {
        if (m == null) { return -1; }
        try { return (m as Time.Moment).value().toNumber(); } catch (ex) { return -1; }
    }

    // "HHMMZ" for a stored UTC hour/min snapshot, "--" when unknown.
    function hhmmZ(h as Number, mn as Number) as String {
        if (h < 0 || mn < 0) { return "--"; }
        return ((h < 10) ? "0" : "") + h.toString()
             + ((mn < 10) ? "0" : "") + mn.toString() + "Z";
    }

    // Average ground speed over the flight (kt); 0 when no samples were taken.
    function avgGsKtValue() as Float {
        if (gsSamples <= 0) { return 0.0; }
        return (gsSumKt / gsSamples.toFloat()).toFloat();
    }

    // Flight report as a phone-message payload. `withEnd` adds the arrival /
    // landing figures, which only exist once the flight has been stopped.
    function buildFlightReport(withEnd as Boolean) as Dictionary {
        var obt = momentEpochSec(tripStartUtcMoment);
        // Seeded with a LITERAL on purpose: `new Dictionary()` is Symbol-keyed in
        // this typing mode and a String-key write throws, which silently killed
        // this whole report (the call sites wrap it in try/catch). "obt" is
        // therefore always present; -1 means the time was unavailable.
        var d = { "obt" => obt };
        if (obt >= 0) { d["obt"] = obt; }
        if (tripStartUtcHour >= 0) { d["obt_text"] = hhmmZ(tripStartUtcHour, tripStartUtcMin); }
        if (!withEnd) { return d; }

        var ibt = momentEpochSec(tripEndUtcMoment);
        if (ibt >= 0) { d["ibt"] = ibt; }
        if (tripEndUtcHour >= 0) { d["ibt_text"] = hhmmZ(tripEndUtcHour, tripEndUtcMin); }
        d["block_time_s"] = (elapsed / 1000).toNumber();
        d["landings"]     = landings;
        d["distance_nm"]  = (totalDistanceM / 1852.0).toFloat();
        d["max_alt_ft"]   = (maxAltitudeM * 3.28084).toFloat();
        d["avg_gs_kt"]    = avgGsKtValue();
        d["max_gs_kt"]    = maxGsKt;
        try {
            var trip = getApp().getTrip();
            if (trip != null && trip.active && trip.tripName.length() > 0) {
                d["trip_name"] = trip.tripName;
            }
        } catch (tex) {}
        if (maxG > 0.0)     { d["max_g"] = maxG; }
        d["max_bank_deg"] = maxBankDeg;
        if (maxPitchDeg > 0.0) { d["max_pitch_deg"] = maxPitchDeg; }
        if (gForceG > 0.0)  { d["g_force"] = gForceG; }

        // Final density altitude (needs indicated altitude and OAT)
        try {
            var dens = densityAltFt();
            if (dens != null) { d["density_alt_ft"] = dens as Number; }
        } catch (dex) { }

        // Latest weather observation, when the companion app has one
        try {
            var wr = VFRWeather.read(getApp().getComms());
            if (wr != null) {
                try { if (wr.windDir >= 0) { d["wind_dir_deg"] = wr.windDir; } } catch (e) { }
                try { if (wr.windSpd >= 0) { d["wind_spd_kt"] = wr.windSpd; } } catch (e) { }
                try { if (wr.temp != -999) { d["oat_c"] = wr.temp; } } catch (e) { }
                try { if (wr.dew != -999) { d["dew_c"] = wr.dew; } } catch (e) { }
                try { if (wr.cloudCover >= 0) { d["clouds_pct"] = wr.cloudCover; } } catch (e) { }
                try {
                    if (wr.cloudAlt >= 0) {
                        d["cloud_base_ft"] = (wr.cloudAlt.toFloat() * 3.28084).toNumber();
                    }
                } catch (e) { }
            }
        } catch (wex) { }
        return d;
    }

    // ── Take-off / touch-down state machine ─────────────────────────────────

    // Runs from onUpdate() AND onPosition() so the landing counter keeps
    // working while a sub-view covers the main view.
    // gsKt < 0 means "speed unknown" (GPS lost) — deliberately NOT the same as
    // 0 kt, otherwise a dropout at altitude would look like a touch-down.
    function _updateAirborneState(aglFt as Float, gsKt as Float, now as Number) as Void {
        if (!running) { return; }
        if (!airborne) {
            // Airborne once clearly clear of the ground
            if (aglFt > 300.0) {
                airborne = true;
                if (circuitEnabled) { circuitPhase = 1; circuitLegStartMs = now; circuitLevelVibrated = false; }
            }
            return;
        }
        // Touch-down, either:
        //  * close to the ground and no longer flying, or
        //  * down at taxi speed — no aircraft is still airborne at 15 kt GS.
        // The second test matters because AGL is only as good as the field
        // elevation captured at start: if the QNH drifts during the flight the
        // whole AGL trace is offset and "agl < 50" can never become true, which
        // silently loses every landing.
        var gsKnown = (gsKt >= 0.0);
        var lowAndSlow = (aglFt < 50.0) && (!gsKnown || gsKt < 40.0);
        var atTaxiSpeed = gsKnown && (gsKt < 15.0);
        if (lowAndSlow || atTaxiSpeed) {
            // Wrap-safe debounce: System.getTimer() is a signed 32-bit counter,
            // so a raw `now - lastLandingAt` goes negative after ~24.8 days of
            // uptime and blocks every landing for the rest of the session.
            if (lastLandingAt != 0 && elapsedSince(now, lastLandingAt) < MIN_LANDING_GAP_MS) { return; }
            _registerLanding(now);
        }
    }

    // Count one touch-down and reset the pattern state.
    private function _registerLanding(now as Number) as Void {
        airborne = false;
        lastLandingAt = now;
        landings = (landings as Number) + 1;
        circuitPhase = 0;
        doLandingVibrate();
    }

    // Safety net for the END of a flight: if the recording is being stopped
    // while the aircraft is on the ground (taxi speed) but the touch-down test
    // never fired — wrong field elevation, QNH drift, sensor dropout, or the
    // pilot stopping the clock by hand — count that final landing before the
    // summary and the saved activity are built.
    private function _countLandingIfGroundborne() as Void {
        if (!airborne) { return; }
        var gsKt = -1.0;
        try {
            var ai = Activity.getActivityInfo();
            if (ai != null && ai.currentSpeed != null) {
                gsKt = (ai.currentSpeed as Float) * 1.94384;
            }
        } catch (ex) { }
        // Unknown speed falls back to the AGL reading
        if (gsKt < 0.0) {
            if (lastAglFt < 50.0) { _registerLanding(System.getTimer()); }
            return;
        }
        if (gsKt < 40.0) { _registerLanding(System.getTimer()); }
    }

    // ── Bank / pitch capture ────────────────────────────────────────────────

    // bank  = coordinated-turn estimate atan(omega * v / g), from the smoothed
    //         GPS turn rate and ground speed (signed: negative = left turn).
    // pitch = flight-path angle atan2(VS, GS), i.e. the climb/descent angle —
    //         NOT the attitude shown on an artificial horizon.
    // Both feed the per-second FIT graphs; maxBankDeg is summarised at stop.
    function _updateAttitude(gsKt as Float) as Void {
        var bankDeg = 0.0;
        // A GPS track jump (or a turn during taxi) can produce an absurd turn
        // rate, and the coordinated-turn formula turns that into an impossible
        // bank (a real flight logged -71°). Clamp the input to a plausible rate
        // (a standard-rate turn is 3°/s, a steep 60° turn ≈ 10°/s), require real
        // flying speed and a usable fix, and clamp the result.
        var rate = turnRateDegS;
        if (rate > MAX_TURN_RATE_DEG_S) { rate = MAX_TURN_RATE_DEG_S; }
        if (rate < -MAX_TURN_RATE_DEG_S) { rate = -MAX_TURN_RATE_DEG_S; }
        if (gsKt > 40.0 && gpsQuality >= 3 && rate != 0.0) {
            var omega = rate * (Math.PI / 180.0);
            var vMps  = gsKt * 0.514444;
            bankDeg = Math.atan(omega * vMps / 9.81) * (180.0 / Math.PI);
            if (bankDeg >  MAX_BANK_DEG) { bankDeg =  MAX_BANK_DEG; }
            if (bankDeg < -MAX_BANK_DEG) { bankDeg = -MAX_BANK_DEG; }
        }
        liveBankDeg = bankDeg;
        var absBank = (bankDeg < 0.0) ? -bankDeg : bankDeg;
        if (absBank > maxBankDeg) { maxBankDeg = absBank; }

        var pitchDeg = 0.0;
        if (gsKt > 30.0) {
            pitchDeg = Math.atan2(vertSpeedSmoothFpm, gsKt * 101.269) * (180.0 / Math.PI);
        }
        // Track the peak magnitude of the flight-path angle (nose-up OR
        // nose-down), same idea as maxBankDeg, so the flight summary can report
        // it and it does not have to be read back out of the per-second graph.
        var absPitch = (pitchDeg < 0.0) ? -pitchDeg : pitchDeg;
        if (absPitch > maxPitchDeg) { maxPitchDeg = absPitch; }
        try {
            if (_fitBank  != null) { (_fitBank  as FitContributor.Field).setData(bankDeg); }
            if (_fitPitch != null) { (_fitPitch as FitContributor.Field).setData(pitchDeg); }
        } catch (ex) { }
    }

    // ── Accelerometer (G-force) ─────────────────────────────────────────────

    // Register the 1 Hz accelerometer batch while a flight is being recorded.
    // The callback keeps firing when the main view is hidden, so the graph has
    // no holes while the pilot is on another screen.
    function _startSensorCapture() as Void {
        if (_sensorOn) { return; }
        if (!(Sensor has :registerSensorDataListener)) { return; }
        try {
            Sensor.registerSensorDataListener(method(:onSensorData), {
                :period        => 1,
                :accelerometer => { :enabled => true, :sampleRate => 25, :includePower => true }
            });
            _sensorOn = true;
            _sensorDataSeen = false;
            try { System.println("VFR: accelerometer capture started"); } catch (e) { }
        } catch (ex) {
            _sensorOn = false;
            try { System.println("VFR: accelerometer start failed: " + ex.getErrorMessage()); } catch (e) { }
        }
    }

    function _stopSensorCapture() as Void {
        if (!_sensorOn) { return; }
        try {
            if (Sensor has :unregisterSensorDataListener) { Sensor.unregisterSensorDataListener(); }
        } catch (ex) { }
        _sensorOn = false;
    }

    // One batch per second (≈25 samples). The magnitude is orientation
    // independent, so the mean resultant acceleration is the load factor in G.
    // CAVEAT: this is the wrist IMU — it measures the aircraft's specific force
    // plus any wrist movement, so read the graph as indicative.
    function onSensorData(data as Sensor.SensorData) as Void {
        try {
            if (data == null || !(data has :accelerometerData)) { return; }
            var ad = data.accelerometerData;
            if (ad == null) { return; }
            _sensorDataSeen = true;
            var g = _averageGForce(ad as Sensor.AccelerometerData);
            _applyGForce(g);
        } catch (ex) { }
    }

    // Fallback for when the batch listener is unavailable or silent (it also
    // covers devices that reject the :includePower option): read the vector
    // accelerometer straight from Sensor.Info once per second.
    function _captureGForceFallback() as Void {
        if (_sensorDataSeen) { return; }
        try {
            var si = Sensor.getInfo();
            if (si == null || si.accel == null) { return; }
            var a = si.accel as Array;
            if (a.size() < 3) { return; }
            var ax = (a[0] as Number).toFloat();
            var ay = (a[1] as Number).toFloat();
            var az = (a[2] as Number).toFloat();
            _applyGForce((Math.sqrt((ax * ax) + (ay * ay) + (az * az)) / 1000.0));
        } catch (ex) { }
    }

    // Smooth, remember the peak and push the value to the FIT graph.
    private function _applyGForce(g as Float) as Void {
        if (g <= 0.0) { return; }
        gForceG = (G_EMA_ALPHA * g) + ((1.0 - G_EMA_ALPHA) * gForceG);
        if (g > maxG) { maxG = g; }
        try {
            if (_fitG != null) { (_fitG as FitContributor.Field).setData(gForceG); }
        } catch (ex) { }
    }

    // Mean resultant acceleration of the batch, in G (sensor reports milli-g).
    // Prefers the vector power channel; falls back to sqrt(x²+y²+z²).
    private function _averageGForce(ad as Sensor.AccelerometerData) as Float {
        try {
            var pw = ad.power;
            if (pw != null && pw.size() > 0) {
                var p = pw as Array;
                var sum = 0.0;
                for (var i = 0; i < p.size(); i++) { sum += (p[i] as Number).toFloat(); }
                return (sum / p.size().toFloat()) / 1000.0;
            }
            var xs = ad.x as Array;
            var ys = ad.y as Array;
            var zs = ad.z as Array;
            var n  = xs.size();
            if (n == 0) { return 0.0; }
            var acc = 0.0;
            for (var i = 0; i < n; i++) {
                var ax = (xs[i] as Number).toFloat();
                var ay = (ys[i] as Number).toFloat();
                var az = (zs[i] as Number).toFloat();
                acc += Math.sqrt((ax * ax) + (ay * ay) + (az * az));
            }
            return (acc / n.toFloat()) / 1000.0;
        } catch (ex) { return 0.0; }
    }

    // ── FIT developer fields (Garmin Connect activity report) ───────────────

    // Create the custom summary fields on a recording session. Field ids must
    // match the <fitField id="…"> entries in resources/fit/fit.xml.
    private function _createFitFields(session as ActivityRecording.Session) as Void {
        _clearFitFields();
        try {
            _fitObt = session.createField("obt", FIT_FIELD_OBT,
                FitContributor.DATA_TYPE_STRING,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :count => 8 });
            _fitIbt = session.createField("ibt", FIT_FIELD_IBT,
                FitContributor.DATA_TYPE_STRING,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :count => 8 });
            _fitBlockS = session.createField("block_time_s", FIT_FIELD_BLOCK_S,
                FitContributor.DATA_TYPE_UINT32,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s" });
            _fitLandings = session.createField("landings", FIT_FIELD_LANDINGS,
                FitContributor.DATA_TYPE_UINT16,
                { :mesgType => FitContributor.MESG_TYPE_SESSION });
            _fitDistNm = session.createField("distance_nm", FIT_FIELD_DIST_NM,
                FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "nm" });
            _fitMaxAltFt = session.createField("max_alt_ft", FIT_FIELD_MAX_ALT,
                FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "ft" });
            _fitAvgGsKt = session.createField("avg_gs_kt", FIT_FIELD_AVG_GS,
                FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "kt" });
            _fitMaxG = session.createField("max_g", FIT_FIELD_MAX_G,
                FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "G" });
            _fitMaxBank = session.createField("max_bank_deg", FIT_FIELD_MAX_BANK,
                FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "deg" });
            // Per-second graphs (MESG_TYPE_RECORD). These are what produce the
            // charts on the Garmin Connect activity page; setData() must be
            // called about once per second while recording.
            _fitG = session.createField("g_force", FIT_FIELD_G,
                FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "G" });
            _fitBank = session.createField("bank_deg", FIT_FIELD_BANK,
                FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "deg" });
            _fitPitch = session.createField("pitch_deg", FIT_FIELD_PITCH,
                FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "deg" });

            // Peak |flight-path angle| for the flight (session summary)
            if (session has :createField) {
                _fitMaxPitch = session.createField("max_pitch_deg", FIT_FIELD_MAX_PITCH,
                    FitContributor.DATA_TYPE_FLOAT,
                    { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "deg" });
            }
        } catch (ex) {
            try { System.println("VFR: FIT field setup failed: " + ex.getErrorMessage()); } catch (e) { }
            _clearFitFields();
        }
    }

    // Push the trip summary into the session's developer fields. Must be called
    // while recording — session data is written out once, at the end.
    private function _writeFitSummary() as Void {
        try {
            if (_fitObt != null && tripStartUtcHour >= 0) {
                (_fitObt as FitContributor.Field).setData(hhmmZ(tripStartUtcHour, tripStartUtcMin));
            }
            if (_fitIbt != null && tripEndUtcHour >= 0) {
                (_fitIbt as FitContributor.Field).setData(hhmmZ(tripEndUtcHour, tripEndUtcMin));
            }
            if (_fitBlockS != null) {
                (_fitBlockS as FitContributor.Field).setData((elapsed / 1000).toNumber());
            }
            if (_fitLandings != null) {
                (_fitLandings as FitContributor.Field).setData(landings);
            }
            if (_fitDistNm != null) {
                (_fitDistNm as FitContributor.Field).setData((totalDistanceM / 1852.0).toFloat());
            }
            if (_fitMaxAltFt != null) {
                (_fitMaxAltFt as FitContributor.Field).setData((maxAltitudeM * 3.28084).toFloat());
            }
            if (_fitAvgGsKt != null) {
                (_fitAvgGsKt as FitContributor.Field).setData(avgGsKtValue());
            }
            // Only claim a peak G when the accelerometer actually produced data
            if (_fitMaxG != null && maxG > 0.0) {
                (_fitMaxG as FitContributor.Field).setData(maxG);
            }
            if (_fitMaxBank != null) {
                (_fitMaxBank as FitContributor.Field).setData(maxBankDeg);
            }
            if (_fitMaxPitch != null && maxPitchDeg > 0.0) {
                (_fitMaxPitch as FitContributor.Field).setData(maxPitchDeg);
            }
        } catch (ex) {
            try { System.println("VFR: FIT summary write failed: " + ex.getErrorMessage()); } catch (e) { }
        }
    }

    private function _clearFitFields() as Void {
        _fitObt      = null;
        _fitIbt      = null;
        _fitBlockS   = null;
        _fitLandings = null;
        _fitDistNm   = null;
        _fitMaxAltFt = null;
        _fitAvgGsKt  = null;
        _fitMaxG     = null;
        _fitMaxBank  = null;
        _fitG        = null;
        _fitBank     = null;
        _fitPitch    = null;
    }

    // Clear the on-disk backup (call on reset so no stale resume prompt appears)
    function clearBackupProperties() as Void {
        try {
            Application.Properties.setValue("vfr_backup_hasBackup", false);
        } catch (ex) {
            
        }
    }

    // Save/Load backup to Application.Properties as individual keys
    function saveBackupProperties() as Void {
        try {
            // When running, the 'elapsed' field is 0; compute live elapsed instead
            var liveElapsed = running ? elapsedSince(System.getTimer(), startTime) : elapsed;
            Application.Properties.setValue("vfr_backup_hasBackup", true);
            Application.Properties.setValue("vfr_backup_running", running);
            Application.Properties.setValue("vfr_backup_startTime", startTime);
            Application.Properties.setValue("vfr_backup_elapsed", liveElapsed);
            Application.Properties.setValue("vfr_backup_totalDistanceM", totalDistanceM);
            Application.Properties.setValue("vfr_backup_checkpointActive", checkpointActive);
            Application.Properties.setValue("vfr_backup_nextVibrateAt", nextVibrateAt);
            Application.Properties.setValue("vfr_backup_kmAtCheckpoint", kmAtCheckpoint);
            Application.Properties.setValue("vfr_backup_nmAtCheckpoint", nmAtCheckpoint);
            Application.Properties.setValue("vfr_backup_maxAltitudeM", maxAltitudeM);
            Application.Properties.setValue("vfr_backup_maxGsKt", maxGsKt);
            Application.Properties.setValue("vfr_backup_gsSumKt", gsSumKt);
            Application.Properties.setValue("vfr_backup_gsSamples", gsSamples);
            // The landing counter and the attitude/G peaks must survive an app
            // restart: otherwise a mid-flight kill silently resets the logbook
            // count (and the aircraft state), under-reporting landings.
            Application.Properties.setValue("vfr_backup_landings", landings);
            Application.Properties.setValue("vfr_backup_airborne", airborne);
            Application.Properties.setValue("vfr_backup_hasTakenOff", hasTakenOff);
            Application.Properties.setValue("vfr_backup_maxG", maxG);
            Application.Properties.setValue("vfr_backup_maxBankDeg", maxBankDeg);
            Application.Properties.setValue("vfr_backup_maxPitchDeg", maxPitchDeg);
            Application.Properties.setValue("vfr_backup_lapMode", lapMode);
            Application.Properties.setValue("vfr_backup_lapElapsed", lapElapsed);
            Application.Properties.setValue("vfr_backup_lapKm", lapKm);
            Application.Properties.setValue("vfr_backup_lapNm", lapNm);
            Application.Properties.setValue("vfr_backup_subTimerState", subTimerState);
            Application.Properties.setValue("vfr_backup_subTimerStart", subTimerStart);
            var liveSubElapsed = (subTimerState == 1) ? elapsedSince(System.getTimer(), subTimerStart) : subTimerElapsed;
            Application.Properties.setValue("vfr_backup_subTimerElapsed", liveSubElapsed);
            Application.Properties.setValue("vfr_backup_tripStartUtcHour", tripStartUtcHour);
            Application.Properties.setValue("vfr_backup_tripStartUtcMin", tripStartUtcMin);
            Application.Properties.setValue("vfr_backup_tripEndUtcHour", tripEndUtcHour);
            Application.Properties.setValue("vfr_backup_tripEndUtcMin", tripEndUtcMin);
        } catch (ex) {
            
        }
    }

    function loadBackupProperties() as Void {
        // Only restore if a valid backup was previously saved
        try {
            var hasBackup = Application.Properties.getValue("vfr_backup_hasBackup");
            if (hasBackup == null || !(hasBackup as Boolean)) { return; }
        } catch (ex) { return; }
        try {
            var v = Application.Properties.getValue("vfr_backup_running"); if (v != null) { running = v as Boolean; }
            v = Application.Properties.getValue("vfr_backup_startTime"); if (v != null) { startTime = v as Number; }
            v = Application.Properties.getValue("vfr_backup_elapsed"); if (v != null) { elapsed = v as Number; }
            v = Application.Properties.getValue("vfr_backup_totalDistanceM"); if (v != null) { totalDistanceM = v as Float; }
            v = Application.Properties.getValue("vfr_backup_checkpointActive"); if (v != null) { checkpointActive = v as Boolean; }
            v = Application.Properties.getValue("vfr_backup_nextVibrateAt"); if (v != null) { nextVibrateAt = v as Number; }
            v = Application.Properties.getValue("vfr_backup_kmAtCheckpoint"); if (v != null) { kmAtCheckpoint = v as Float; }
            v = Application.Properties.getValue("vfr_backup_nmAtCheckpoint"); if (v != null) { nmAtCheckpoint = v as Float; }
            v = Application.Properties.getValue("vfr_backup_maxAltitudeM"); if (v != null) { maxAltitudeM = v as Float; }
            v = Application.Properties.getValue("vfr_backup_maxGsKt"); if (v != null) { maxGsKt = v as Float; }
            v = Application.Properties.getValue("vfr_backup_gsSumKt"); if (v != null) { gsSumKt = v as Float; }
            v = Application.Properties.getValue("vfr_backup_gsSamples"); if (v != null) { gsSamples = v as Number; }
            v = Application.Properties.getValue("vfr_backup_landings"); if (v != null) { landings = v as Number; }
            v = Application.Properties.getValue("vfr_backup_airborne"); if (v != null) { airborne = v as Boolean; }
            v = Application.Properties.getValue("vfr_backup_hasTakenOff"); if (v != null) { hasTakenOff = v as Boolean; }
            v = Application.Properties.getValue("vfr_backup_maxG"); if (v != null) { maxG = v as Float; }
            v = Application.Properties.getValue("vfr_backup_maxBankDeg"); if (v != null) { maxBankDeg = v as Float; }
            v = Application.Properties.getValue("vfr_backup_maxPitchDeg"); if (v != null) { maxPitchDeg = v as Float; }
            v = Application.Properties.getValue("vfr_backup_lapMode"); if (v != null) { lapMode = v as Boolean; }
            v = Application.Properties.getValue("vfr_backup_lapElapsed"); if (v != null) { lapElapsed = v as Number; }
            v = Application.Properties.getValue("vfr_backup_lapKm"); if (v != null) { lapKm = v as Float; }
            v = Application.Properties.getValue("vfr_backup_lapNm"); if (v != null) { lapNm = v as Float; }
            v = Application.Properties.getValue("vfr_backup_subTimerState"); if (v != null) { subTimerState = v as Number; }
            v = Application.Properties.getValue("vfr_backup_subTimerStart"); if (v != null) { subTimerStart = v as Number; }
            v = Application.Properties.getValue("vfr_backup_subTimerElapsed"); if (v != null) { subTimerElapsed = v as Number; }
            // If sub-timer was running when the app was killed, freeze it so we
            // don't compute `now - staleStartTime` from a previous boot session.
            if (subTimerState == 1) { subTimerState = 2; }
            v = Application.Properties.getValue("vfr_backup_tripStartUtcHour"); if (v != null) { tripStartUtcHour = v as Number; }
            v = Application.Properties.getValue("vfr_backup_tripStartUtcMin"); if (v != null) { tripStartUtcMin = v as Number; }
            v = Application.Properties.getValue("vfr_backup_tripEndUtcHour"); if (v != null) { tripEndUtcHour = v as Number; }
            v = Application.Properties.getValue("vfr_backup_tripEndUtcMin"); if (v != null) { tripEndUtcMin = v as Number; }
        } catch (ex) {
            
        }
        // Timer cannot continue across a kill; pause and let user resume manually
        running = false;
        if (elapsed > 0) { needsResumePrompt = true; }
        WatchUi.requestUpdate();
    }

    // Timer / clock string shown in the middle of the face: the local time when
    // idle, otherwise the elapsed time (H:MM:SS past an hour, else MM:SS).
    function displayTimerString(displayClock as Boolean, hours as Number, mStr as String, sStr as String) as String {
        if (displayClock) {
            var hour = 0; var min = 0;
            try {
                var clk = System.getClockTime();
                if (clk != null) {
                    try { hour = clk.hour; } catch (e) { hour = 0; }
                    try { min  = clk.min;  } catch (e) { min = 0; }
                }
            } catch (e2) {
                try {
                    var nowMoment = Time.now();
                    var info = Gregorian.utcInfo((nowMoment as Time.Moment), Time.FORMAT_SHORT);
                    hour = info.hour;
                    min  = info.min;
                } catch (e3) { hour = 0; min = 0; }
            }
            var hh = (hour < 10) ? ("0" + hour.toString()) : hour.toString();
            var mm = (min  < 10) ? ("0" + min.toString())  : min.toString();
            return hh + ":" + mm;
        }
        if (hours >= 1) { return hours.toString() + ":" + mStr + ":" + sStr; }
        return mStr + ":" + sStr;
    }

    // ── Paged face ──────────────────────────────────────────────────────────
    // One value at a time, cycled with UP (previous) / DOWN (next). Page 0 is
    // the chrono, then distance, altitude, heading, ... — the same data the ring
    // shows, but each value gets ~a quarter of the screen height in the boldest
    // available face. The ring cannot do that: its radial glyphs are capped by
    // the quadrant's arc length (16-27 px whatever Bezel Font is set to).

    var PAGE_CHRONO as Number = 0;
    var PAGE_DIST   as Number = 1;
    var PAGE_ALT    as Number = 2;
    var PAGE_HDG    as Number = 3;
    var PAGE_GS     as Number = 4;
    var PAGE_VS     as Number = 5;
    var PAGE_ZULU   as Number = 6;
    var PAGE_WIND   as Number = 7;
    var PAGE_TEMP   as Number = 8;
    var PAGE_CLOUDS as Number = 9;
    var PAGE_QNH    as Number = 10;
    var PAGE_DENS   as Number = 11;
    var PAGE_FPL    as Number = 12;
    var PAGE_STATS  as Number = 13;
    var PAGE_COUNT  as Number = 14;
    // Set while computing the density-altitude page, for its "approx" note
    var densAltApprox as Boolean = false;

    // Label (with unit) for page `idx`.
    function pageLabel(idx as Number) as String {
        if (idx == PAGE_DIST)  { return "DIST nm"; }
        if (idx == PAGE_ALT)   { return "ALT ft"; }
        if (idx == PAGE_HDG)   { return "HDG"; }
        if (idx == PAGE_GS)    { return "GS kt"; }
        if (idx == PAGE_VS)    { return "V/S fpm"; }
        if (idx == PAGE_ZULU)  { return "ZULU"; }
        if (idx == PAGE_WIND)  { return "WIND"; }
        if (idx == PAGE_TEMP)  { return "OAT/DP"; }
        if (idx == PAGE_CLOUDS) { return "CLOUDS"; }
        if (idx == PAGE_QNH)   { return "QNH hPa"; }
        if (idx == PAGE_DENS)  { return "DENS ALT"; }
        if (idx == PAGE_FPL)   { return "FLIGHT PLAN"; }
        if (idx == PAGE_STATS) { return "LANDINGS"; }
        return "CHRONO";
    }

    // One decimal place, e.g. 12.4
    function fmtOneDec(v as Float) as String {
        var i = v.toNumber();
        var d = ((v - i.toFloat()) * 10.0).toNumber();
        if (d < 0) { d = 0; }
        return i.toString() + "." + d.toString();
    }

    // Zero-padded to `digits` places.
    function fmtPadded(v as Number, digits as Number) as String {
        var s = v.toString();
        while (s.length() < digits) { s = "0" + s; }
        return s;
    }

    // Density altitude in feet, or null when indicated altitude or OAT is
    // missing. Pressure altitude (indicated, adjusted by QNH when known) plus
    // 120 ft per °C above ISA. Sets densAltApprox when no QNH was available.
    function densityAltFt() as Number? {
        densAltApprox = false;
        try {
            var indicated = VFRAvionicsData.readAltitudeFeet();
            if (indicated == null) { return null; }
            var oat = -999;
            try {
                var wr = VFRWeather.read(getApp().getComms());
                if (wr != null && wr.temp != -999) { oat = wr.temp; }
            } catch (we) { }
            if (oat == -999) { return null; }

            var pressureAltFt = (indicated as Number).toFloat();
            densAltApprox = true;
            try {
                var qnhInfo = VFRAvionicsData.readQnhInfo();
                if (qnhInfo != null && (qnhInfo as VFRQnhInfo).isQnh) {
                    pressureAltFt = (indicated as Number).toFloat()
                                  + ((1013.0 - (qnhInfo as VFRQnhInfo).hPa) * 27.0);
                    densAltApprox = false;
                }
            } catch (qe) { }

            var thousands = (pressureAltFt / 1000.0).toFloat();
            var isa = (15.0 - (2.0 * thousands)).toFloat();
            var dens = (pressureAltFt + (120.0 * (oat.toFloat() - isa))).toFloat();
            return Math.round(dens).toNumber();
        } catch (ex) { return null; }
    }

    // Same value as the DENS ALT page: a string, "----" when unavailable.
    function densityAltStr() as String {
        var ft = densityAltFt();
        return (ft != null) ? (ft as Number).toString() : "----";
    }

    // Formatted value for page `idx` (page 0 is the timer, supplied by the caller).
    function pageValue(idx as Number) as String {
        if (idx == PAGE_DIST) { return fmtOneDec((totalDistanceM / 1852.0).toFloat()); }

        if (idx == PAGE_ALT) {
            try {
                var alt = VFRAvionicsData.readAltitudeFeet();
                if (alt == null) { return "----"; }
                var altFt = (alt as Number);
                if (transitionActive) {
                    return "FL" + Math.round(altFt.toFloat() / 100.0).toNumber().toString();
                }
                return altFt.toString();
            } catch (ex) { return "----"; }
        }

        if (idx == PAGE_HDG) {
            try {
                var hdg = VFRHeading.getHeadingDeg();
                if (hdg < 0.0) { return "---"; }
                return fmtPadded(Math.round(hdg).toNumber() % 360, 3);
            } catch (ex) { return "---"; }
        }

        if (idx == PAGE_GS) {
            try {
                var ai = Activity.getActivityInfo();
                if (ai != null && ai.currentSpeed != null) {
                    return Math.round((ai.currentSpeed as Float) * 1.94384).toNumber().toString();
                }
            } catch (ex) { }
            return "---";
        }

        if (idx == PAGE_VS) {
            if (lastAltitudeMillis == 0) { return "----"; }
            var fpm = (Math.round(vertSpeedSmoothFpm / 10.0) * 10.0).toNumber();
            return (fpm >= 0 ? "+" : "") + fpm.toString();
        }

        if (idx == PAGE_ZULU) {
            // Zulu time; the page label already says ZULU, so no "Z" suffix.
            try {
                var info = Gregorian.utcInfo(Time.now() as Time.Moment, Time.FORMAT_SHORT);
                return fmtPadded(info.hour, 2) + ":" + fmtPadded(info.min, 2);
            } catch (ex) { return "--:--"; }
        }

        if (idx == PAGE_WIND || idx == PAGE_TEMP) {
            var wDir = -1; var wSpd = -1; var tmp = -999; var dew = -999;
            try {
                var wr = VFRWeather.read(getApp().getComms());
                if (wr != null) {
                    try { wDir = wr.windDir; } catch (e) { }
                    try { wSpd = wr.windSpd; } catch (e) { }
                    try { tmp  = wr.temp;    } catch (e) { }
                    try { dew  = wr.dew;     } catch (e) { }
                }
            } catch (we) { }
            if (idx == PAGE_WIND) {
                if (wDir < 0 && wSpd < 0) { return "--/--"; }
                var dStr = (wDir < 0) ? "--" : fmtPadded(wDir, 3);
                var sStr = (wSpd < 0) ? "--" : wSpd.toString();
                return dStr + "/" + sStr;
            }
            if (tmp == -999 && dew == -999) { return "--/--"; }
            var tStr = (tmp == -999) ? "--" : Math.round(tmp.toFloat()).toNumber().toString();
            var d2Str = (dew == -999) ? "--" : Math.round(dew.toFloat()).toNumber().toString();
            return tStr + "/" + d2Str;
        }

        if (idx == PAGE_CLOUDS) {
            try {
                var cw = VFRWeather.read(getApp().getComms());
                if (cw != null && cw.cloudCover >= 0) { return cw.cloudCover.toString() + "%"; }
            } catch (ce) { }
            return "---%";
        }

        if (idx == PAGE_QNH) {
            try {
                return VFRAvionicsData.formatQnh(VFRAvionicsData.readQnhInfo());
            } catch (qe) { return "----"; }
        }

        if (idx == PAGE_DENS) { return densityAltStr(); }
        if (idx == PAGE_FPL) {
            try {
                var trip = getApp().getTrip();
                if (trip.active && trip.bearingDeg >= 0) {
                    return fmtPadded(trip.bearingDeg, 3) + "\u00B0";
                }
            } catch (ex) { }
            return "---";
        }

        if (idx == PAGE_STATS) { return (landings as Number).toString(); }

        return "";   // chrono: value comes from the caller
    }

    // Small second line under the value; "" when there is nothing useful to add.
    function pageSub(idx as Number) as String {
        if (idx == PAGE_CHRONO) {
            if (subTimerState != 0) {
                var ms = (subTimerState == 1) ? elapsedSince(System.getTimer(), subTimerStart) : subTimerElapsed;
                var sec = ms / 1000;
                return "SUB " + fmtPadded(sec / 60, 2) + ":" + fmtPadded(sec % 60, 2);
            }
            return "";
        }
        if (idx == PAGE_DIST) {
            // No lap line: the lap snapshot feature is not used in flight.
            return "";
        }
        if (idx == PAGE_ALT) {
            if (fieldElevationFt > 0) {
                // Clamp: a negative AGL only means the field elevation / QNH is
                // off, and "AGL -1259" is worse than useless in flight.
                var agl = Math.round(getAglFt()).toNumber();
                if (agl < 0) { agl = 0; }
                return "AGL " + agl.toString();
            }
            return "";
        }
        if (idx == PAGE_GS) {
            if (maxGsKt > 0.0) { return "MAX " + Math.round(maxGsKt).toNumber().toString(); }
            return "";
        }
        if (idx == PAGE_VS) {
            if (altAlertFt > 0) { return "TGT " + altAlertFt.toString(); }
            return "";
        }
        if (idx == PAGE_ZULU) {
            try {
                var clk = System.getClockTime();
                if (clk != null) {
                    return "LOCAL " + fmtPadded(clk.hour, 2) + ":" + fmtPadded(clk.min, 2);
                }
            } catch (e) { }
            return "";
        }
        if (idx == PAGE_CLOUDS) {
            // Cloud base comes from the weather provider in metres.
            try {
                var cw = VFRWeather.read(getApp().getComms());
                if (cw != null && cw.cloudAlt >= 0) {
                    var ft = ((cw.cloudAlt.toFloat() * 3.28084)).toNumber();
                    return "BASE " + ft.toString() + " ft";
                }
            } catch (ce) { }
            return "";
        }
        if (idx == PAGE_QNH) {
            try {
                var qi = VFRAvionicsData.readQnhInfo();
                if (qi == null) { return ""; }
                return (qi as VFRQnhInfo).isQnh ? "weather" : "barometer";
            } catch (qe) { return ""; }
        }
        if (idx == PAGE_DENS) { return densAltApprox ? "~ no QNH set" : ""; }
        if (idx == PAGE_FPL) {
            try {
                var trip = getApp().getTrip();
                if (trip.active) {
                    var s = "";
                    if (trip.distanceNm >= 0.0) { s = fmtOneDec(trip.distanceNm) + " nm"; }
                    if (trip.eteSec >= 0) {
                        s = (s.length() > 0 ? s + "  " : "") + (trip.eteSec / 60).toString() + " min";
                    }
                    return s;
                }
            } catch (ex) { }
            return "no plan";
        }
        if (idx == PAGE_STATS) {
            var s2 = "";
            if (maxG > 0.0) { s2 = "G " + fmtOneDec(maxG); }
            if (maxBankDeg > 0.0) {
                s2 = (s2.length() > 0 ? s2 + "  " : "") + "BANK " + Math.round(maxBankDeg).toNumber().toString();
            }
            return s2;
        }
        return "";
    }

    // Usable width of the round screen at a vertical offset from the centre
    // (`frac` is a fraction of minWh). Half-width is sqrt(R^2 - dy^2), so text
    // that is drawn lower needs to be narrower to avoid being clipped.
    function chordWidthAt(minWh as Number, frac as Float) as Number {
        var r = minWh.toFloat() / 2.0;
        var dy = minWh.toFloat() * frac;
        if (dy < 0.0) { dy = -dy; }
        if (dy >= r) { return 0; }
        return (2.0 * Math.sqrt((r * r) - (dy * dy))).toNumber();
    }

    // Largest candidate value font whose rendered width fits `maxW`, or null if
    // even the smallest does not. Measuring beats guessing an em-width: the
    // difference between a 4-character and a 7-character value is then used to
    // make the type as large as the screen allows, page by page.
    function pickValFont(dc as Dc, text as String, maxW as Number) as Graphics.VectorFont? {
        for (var i = 0; i < bigValFonts.size(); i++) {
            var f = bigValFonts[i] as Graphics.VectorFont;
            try {
                var dim = dc.getTextDimensions(text, f);
                if (dim != null && (dim[0] as Number) <= maxW) { return f; }
            } catch (ex) { }
        }
        return null;
    }

    // Draw the paged face. `timerStr` is only used by page 0 (the chrono) and
    // `timerColor` carries the usual GPS/fuel/HR colour coding.
    function drawPagesView(dc as Dc, timerStr as String, timerColor as Number) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var minWh = (w < h) ? w : h;
        var jc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Background (flashes red on an HR alert, same as the ring layout)
        if (hrAlertActive && hrFlashOn) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_RED);
        } else {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        }
        dc.clear();

        // Fonts, created once. Condensed faces first: they carry the same text
        // in ~15% less width, so the type can be TALLER without the round screen
        // clipping the sides. Bold faces next, then the plain ones.
        if (!bigFontsInitialized) {
            var faces    = ["RobotoCondensed", "RobotoCondensed-Bold", "RobotoBlack",
                            "Swiss721Bold", "TomorrowBold", "RobotoBold", "Roboto", "OpenSans"];
            // Candidate value sizes (fraction of minWh), largest first. The
            // draw code measures the actual string and picks the biggest one
            // that fits the usable chord at that line's height.
            var valSizes = [0.32, 0.28, 0.24, 0.20];
            var timerSize = (minWh.toFloat() * 0.19).toNumber();
            var lblSize   = (minWh.toFloat() * 0.08).toNumber();
            var subSize   = (minWh.toFloat() * 0.065).toNumber();
            for (var bi = 0; bi < faces.size() && bigValFonts.size() == 0; bi++) {
                try {
                    var probeSize = (minWh.toFloat() * valSizes[0]).toNumber();
                    var probe = Graphics.getVectorFont({:face => faces[bi], :size => probeSize});
                    if (probe != null) {
                        bigValFonts.add(probe);
                        for (var si = 1; si < valSizes.size(); si++) {
                            var fs = (minWh.toFloat() * valSizes[si]).toNumber();
                            var f  = Graphics.getVectorFont({:face => faces[bi], :size => fs});
                            if (f != null) { bigValFonts.add(f); }
                        }
                        bigTimerFont = Graphics.getVectorFont({:face => faces[bi], :size => timerSize});
                        bigLblFont   = Graphics.getVectorFont({:face => faces[bi], :size => lblSize});
                        bigSubFont   = Graphics.getVectorFont({:face => faces[bi], :size => subSize});
                    }
                } catch (exf) { }
            }
            bigFontsInitialized = true;
        }
        var lblFont    = (bigLblFont   != null) ? bigLblFont   : Graphics.FONT_TINY;
        var subFont    = (bigSubFont   != null) ? bigSubFont   : Graphics.FONT_XTINY;
        var chronoFont = (bigTimerFont != null) ? bigTimerFont :
                         ((roundedFontLarge != null) ? roundedFontLarge : Graphics.FONT_NUMBER_HOT);

        // Timer / clock: on every page except the chrono it sits in the upper
        // slot as a small reference line (the chrono page replaces it with the
        // hero value, centred). Any page-value failure degrades to a placeholder
        // instead of crashing the whole face (seen on the first weather page).
        var vs = "----";
        try { vs = pageValue(pageIdx); } catch (ex) { vs = "----"; }
        var labelY  = (pageIdx == PAGE_CHRONO) ? -0.30 : -0.075;
        var valueY  = (pageIdx == PAGE_CHRONO) ?  0.00 :  0.16;
        if (pageIdx != PAGE_CHRONO) {
            dc.setColor(timerColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - (minWh.toFloat() * 0.245).toNumber(), chronoFont, timerStr, jc);

            // Separator
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(3);
            dc.drawLine(cx - (minWh.toFloat() * 0.32).toNumber(), cy - (minWh.toFloat() * 0.135).toNumber(),
                        cx + (minWh.toFloat() * 0.32).toNumber(), cy - (minWh.toFloat() * 0.135).toNumber());
            dc.setPenWidth(1);
        }

        // Label above the value
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (minWh.toFloat() * labelY).toNumber(), lblFont, pageLabel(pageIdx), jc);

        // The value: the largest prepared font whose rendered width still fits
        // the circle at this line's height. Using the measured width (instead of
        // assuming ~0.55em per glyph) is what lets the type grow on the shorter
        // pages without ever being clipped on the longer ones.
        var valueStr  = (pageIdx == PAGE_CHRONO) ? timerStr : vs;
        var valueCol  = (pageIdx == PAGE_CHRONO) ? timerColor : Graphics.COLOR_WHITE;
        if (pageIdx != PAGE_CHRONO && valueStr.length() > 0
            && valueStr.substring(0, 1).equals("-")) {
            valueCol = Graphics.COLOR_DK_GRAY;   // placeholder (---): grey it out
        }
        var maxW = chordWidthAt(minWh, valueY) - 12;
        if (maxW < 40) { maxW = 40; }
        var vf = pickValFont(dc, valueStr, maxW);
        dc.setColor(valueCol, Graphics.COLOR_TRANSPARENT);
        if (vf != null) {
            dc.drawText(cx, cy + (minWh.toFloat() * valueY).toNumber(), vf, valueStr, jc);
        } else {
            dc.drawText(cx, cy + (minWh.toFloat() * valueY).toNumber(), chronoFont, valueStr, jc);
        }

        // Optional sub-line (lap / AGL / max GS / local time / trip ETE / stats)
        var sub = "";
        try { sub = pageSub(pageIdx); } catch (ex) { sub = ""; }
        if (sub.length() > 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + (minWh.toFloat() * 0.41).toNumber(), subFont, sub, jc);
        }

        // Page indicator (bottom centre) plus the phone status dot to its left
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 8, cy + (minWh.toFloat() * 0.472).toNumber(), subFont,
                    (pageIdx + 1).toString() + "/" + PAGE_COUNT.toString(), jc);
        if (useCompanionApp) {
            var cInd = getApp().getComms();
            var dotCol = Graphics.COLOR_RED;
            if (cInd != null) {
                if (cInd.connected) { dotCol = Graphics.COLOR_GREEN; }
                else if (cInd.connecting) {
                    dotCol = (((System.getTimer() / 500).toNumber() % 2) == 0) ? Graphics.COLOR_YELLOW : Graphics.COLOR_BLACK;
                }
            }
            dc.setColor(dotCol, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx - 26, (cy + (minWh.toFloat() * 0.472).toNumber()).toNumber(), 4);
        }
    }

    // Open the on-device settings menu (called from DOWN shortcut and main menu).
    function openSettingsMenu() as Void {
        var settings = VFRSettings.read();
        var gpsLabel = VFRSettings.gpsModeLabel(settings.gpsMode);
        var menu = new WatchUi.Menu2({:title => "Settings"});
        menu.addItem(new WatchUi.MenuItem("GPS Mode",      gpsLabel,                        "setting_gps",     null));
        menu.addItem(new WatchUi.MenuItem("Timer",         settings.timerIntervalMin.toString() + " min", "setting_timer",   null));
        menu.addItem(new WatchUi.MenuItem("Takeoff Speed", settings.takeoffSpeedKts.toString() + " kts",      "setting_takeoff", null));
        menu.addItem(new WatchUi.MenuItem("Transition Altitude", settings.transitionAltitudeFt.toString() + " ft", "setting_transition", null));
        menu.addItem(new WatchUi.MenuItem("HR Alert", settings.hrThreshold.toString() + " bpm", "setting_hr", null));
        menu.addItem(new WatchUi.MenuItem("Fuel Check", settings.fuelCheckIntervalMin.toString() + " min", "setting_fuel", null));
        menu.addItem(new WatchUi.MenuItem("Altitude Source",  settings.altitudeSource == 1 ? "GPS" : "Baro", "setting_altitude_source", null));
        menu.addItem(new WatchUi.MenuItem("Use Companion App", settings.useCompanionApp ? "On" : "Off", "setting_companion", null));
        menu.addItem(new WatchUi.MenuItem("Circuit Practice", settings.circuitEnabled ? "On" : "Off", "setting_circuit", null));
        menu.addItem(new WatchUi.MenuItem("Field Elevation", settings.manualFieldElevationFt == 0 ? "Auto" : settings.manualFieldElevationFt.toString() + " ft", "setting_field_elev", null));
        menu.addItem(new WatchUi.MenuItem("Runway Length", settings.runwayLengthM.toString() + " m", "setting_runway", null));
        menu.addItem(new WatchUi.MenuItem("Altitude Alert", settings.altAlertFt == 0 ? "Off" : settings.altAlertFt.toString() + " ft", "setting_alt_alert", null));
        menu.addItem(new WatchUi.MenuItem("Auto Backlight", settings.autoBacklight == 2 ? "Night" : (settings.autoBacklight == 1 ? "Always" : "Off"), "setting_auto_backlight", null));
        if (settings.autoBacklight == 2) {
            menu.addItem(new WatchUi.MenuItem("Night Start", settings.nightStartHour.toString() + ":00", "setting_night_start", null));
            menu.addItem(new WatchUi.MenuItem("Night End", settings.nightEndHour.toString() + ":00", "setting_night_end", null));
        }
        menu.addItem(new WatchUi.MenuItem("Bezel Font", settings.bezelFontScale.toString() + "%", "setting_bezel_font", null));
        menu.addItem(new WatchUi.MenuItem("Bezel Contrast", settings.bezelContrast.toString() + "%", "setting_bezel_contrast", null));
        menu.addItem(new WatchUi.MenuItem("Display", settings.displayMode == 1 ? "Pages (big)" : "Bezel ring", "setting_display", null));
        menu.addItem(new WatchUi.MenuItem("Auto Page Cycle", settings.pageCycleSec == 0 ? "Off" : settings.pageCycleSec.toString() + " s", "setting_page_cycle", null));
        WatchUi.pushView(menu, new VFRSettingsMenuDelegate(self), WatchUi.SLIDE_UP);
    }

    // DOWN button behavior:
    //   The hold timer is armed on press; the action is decided on release so a
    //   short tap can never destroy a flight. Long press (hold):
    //     idle (no elapsed)  → settings
    //     stopped (elapsed)  → RESET (hold is the confirmation)
    //     running            → settings
    function onDownPressed() as Void {
        var now = System.getTimer();
        // debounce spurious repeated press events (200 ms)
        if (lastDownEventAt != 0 && (now - lastDownEventAt) < 200) { return; }
        lastDownEventAt = now;
        if (downPressAt == 0) {
            downPressAt = now;
        }
    }

    function onDownLongPress() as Void {
        if (!running && elapsed == 0) {
            openSettingsMenu();
        } else if (!running) {
            reset();
        } else {
            openSettingsMenu();
        }
    }

    // Short-press action for DOWN.
    //   pages mode → next page
    //   ring mode  → quick-info chain (heading/GS, wind, temp, dens alt, map)
    function shortDownAction() as Void {
        // In "pages" mode a short DOWN press cycles to the next value, so the
        // quick-info screens would be redundant — every one of their values is
        // a page now (the map is in the MENU instead).
        if (displayMode == 1) {
            pageNext();
            return;
        }
        if (quickInfoShown) { return; }
        quickInfoShown = true;
        // Show heading/GS summary first, then allow navigating to wind/temp
        quickInfoLastNavAt = System.getTimer();
        WatchUi.pushView(new VFRQuickInfoHdgGsView(self), new VFRQuickInfoHdgGsDelegate(self), WatchUi.SLIDE_UP);
    }

    // --- Paged face navigation ---
    // Pages change ONLY when the user presses UP/DOWN, unless the optional
    // "Auto Page Cycle" setting (pageCycleSec > 0) is enabled, which advances
    // one page every N seconds while the clock is running. A manual press
    // always restarts that timer, so it never steals the page you just chose.
    function pageNext() as Void {
        pageIdx = (pageIdx + 1) % PAGE_COUNT;
        lastPageCycleAt = System.getTimer();
        WatchUi.requestUpdate();
    }

    function pagePrev() as Void {
        pageIdx = (pageIdx + PAGE_COUNT - 1) % PAGE_COUNT;
        lastPageCycleAt = System.getTimer();
        WatchUi.requestUpdate();
    }

    // Called from onUpdate: rotate the paged face on a timer when configured.
    function updatePageCycle(now as Number) as Void {
        if (displayMode != 1 || pageCycleSec <= 0) { return; }
        // Only while a flight/timer is running: an idle face should sit still on
        // whatever page was left showing.
        if (!running && subTimerState == 0) { return; }
        if (lastPageCycleAt == 0) { lastPageCycleAt = now; return; }
        var intervalMs = pageCycleSec * 1000;
        if (elapsedSince(now, lastPageCycleAt) >= intervalMs) {
            lastPageCycleAt = now;
            pageIdx = (pageIdx + 1) % PAGE_COUNT;
        }
    }

    // UP press/release, mirroring the DOWN pattern: the action is decided on
    // release so a short tap pages backwards and a hold opens the sub-timer.
    function onUpPressed() as Void {
        var now = System.getTimer();
        // debounce spurious repeated press events (200 ms)
        if (lastUpEventAt != 0 && (now - lastUpEventAt) < 200) { return; }
        lastUpEventAt = now;
        if (upPressAt == 0) {
            upPressAt = now;
        }
    }

    // Long-press UP → sub-timer (relocated here in pages mode because a short
    // UP now means "previous page"; the ring face keeps short UP = sub-timer).
    function onUpLongPress() as Void {
        subTimer();
    }

    function shortUpAction() as Void {
        if (displayMode == 1) {
            pagePrev();
            return;
        }
        subTimer();
    }

    // 5 short vibration pulses (100% duty, 200 ms each)
    function doFiveMinAlert() as Void {
        if (!(Attention has :vibrate)) { return; }
        try {
            var pattern = [
                new Attention.VibeProfile(100, 200),
                new Attention.VibeProfile(1,   100),
                new Attention.VibeProfile(100, 200),
                new Attention.VibeProfile(1,   100),
                new Attention.VibeProfile(100, 200),
                new Attention.VibeProfile(1,   100),
                new Attention.VibeProfile(100, 200),
                new Attention.VibeProfile(1,   100),
                new Attention.VibeProfile(100, 200)
            ];
            Attention.vibrate(pattern);
        } catch (ex instanceof Lang.Exception) {
        }
    }

    // 3 short pulses for HR alert (duty=1 for silent gaps to avoid fr55 crash)
    function doHrAlert() as Void {
        if (!(Attention has :vibrate)) { return; }
        try {
            var pattern = [
                new Attention.VibeProfile(100, 150),
                new Attention.VibeProfile(1,   100),
                new Attention.VibeProfile(100, 150),
                new Attention.VibeProfile(1,   100),
                new Attention.VibeProfile(100, 150)
            ];
            Attention.vibrate(pattern);
        } catch (ex instanceof Lang.Exception) {
        }
    }

    // Fuel alert: single short pulse to indicate 30-minute fuel check
    function doFuelAlert() as Void {
        if (!(Attention has :vibrate)) { return; }
        try {
            var pattern = [ new Attention.VibeProfile(100, 400) ];
            Attention.vibrate(pattern);
        } catch (ex instanceof Lang.Exception) {
        }
    }

    // Tendency vibrate for climb: two short quick pulses
    function doTendencyVibrateUp() as Void {
        if (!(Attention has :vibrate)) { return; }
        try {
            var pattern = [
                new Attention.VibeProfile(100, 150),
                new Attention.VibeProfile(1,   80),
                new Attention.VibeProfile(100, 150)
            ];
            Attention.vibrate(pattern);
        } catch (ex instanceof Lang.Exception) {
        }
    }

    // Tendency vibrate for descent: three short pulses
    function doTendencyVibrateDown() as Void {
        if (!(Attention has :vibrate)) { return; }
        try {
            var pattern = [
                new Attention.VibeProfile(100, 120),
                new Attention.VibeProfile(1,   80),
                new Attention.VibeProfile(100, 120),
                new Attention.VibeProfile(1,   80),
                new Attention.VibeProfile(100, 120)
            ];
            Attention.vibrate(pattern);
        } catch (ex instanceof Lang.Exception) {
        }
    }

    // Start: two quick pulses
    function doStartVibrate() as Void {
        if (!(Attention has :vibrate)) { return; }
        try {
            var pattern = [
                new Attention.VibeProfile(100, 120),
                new Attention.VibeProfile(1,   60),
                new Attention.VibeProfile(100, 120)
            ];
            Attention.vibrate(pattern);
        } catch (ex instanceof Lang.Exception) {
        }
    }

    // Stop: one long pulse
    function doStopVibrate() as Void {
        if (!(Attention has :vibrate)) { return; }
        try {
            var pattern = [ new Attention.VibeProfile(100, 300) ];
            Attention.vibrate(pattern);
        } catch (ex instanceof Lang.Exception) {
        }
    }

    // Reset: three quick pulses
    function doResetVibrate() as Void {
        if (!(Attention has :vibrate)) { return; }
        try {
            var pattern = [
                new Attention.VibeProfile(100, 100),
                new Attention.VibeProfile(1,   60),
                new Attention.VibeProfile(100, 100),
                new Attention.VibeProfile(1,   60),
                new Attention.VibeProfile(100, 100)
            ];
            Attention.vibrate(pattern);
        } catch (ex instanceof Lang.Exception) {
        }
    }

    // Turn point in the circuit: two medium pulses
    function doTurnVibrate() as Void {
        if (!(Attention has :vibrate)) { return; }
        try {
            var pattern = [
                new Attention.VibeProfile(100, 200),
                new Attention.VibeProfile(1,   100),
                new Attention.VibeProfile(100, 200)
            ];
            Attention.vibrate(pattern);
        } catch (ex instanceof Lang.Exception) {
        }
    }

    // Level-off reached: one medium pulse
    function doLevelVibrate() as Void {
        if (!(Attention has :vibrate)) { return; }
        try {
            var pattern = [ new Attention.VibeProfile(100, 250) ];
            Attention.vibrate(pattern);
        } catch (ex instanceof Lang.Exception) {
        }
    }

    // Touchdown: two long pulses
    function doLandingVibrate() as Void {
        if (!(Attention has :vibrate)) { return; }
        try {
            var pattern = [
                new Attention.VibeProfile(100, 400),
                new Attention.VibeProfile(1,   120),
                new Attention.VibeProfile(100, 400)
            ];
            Attention.vibrate(pattern);
        } catch (ex instanceof Lang.Exception) {
        }
    }

    // Approaching the altitude target: two pulses
    function doApproachVibrate() as Void {
        if (!(Attention has :vibrate)) { return; }
        try {
            var pattern = [
                new Attention.VibeProfile(100, 150),
                new Attention.VibeProfile(1,   80),
                new Attention.VibeProfile(100, 150)
            ];
            Attention.vibrate(pattern);
        } catch (ex instanceof Lang.Exception) {
        }
    }

    // Reached the altitude target: three medium pulses
    function doAltAlertVibrate() as Void {
        if (!(Attention has :vibrate)) { return; }
        try {
            var pattern = [
                new Attention.VibeProfile(100, 180),
                new Attention.VibeProfile(1,   100),
                new Attention.VibeProfile(100, 180),
                new Attention.VibeProfile(1,   100),
                new Attention.VibeProfile(100, 180)
            ];
            Attention.vibrate(pattern);
        } catch (ex instanceof Lang.Exception) {
        }
    }

    // Monitor the MSL altitude against the configured alert target.
    // Re-arms with hysteresis so repeated level-off / cross events alert again,
    // instead of firing only once for the whole flight.
    function checkAltitudeAlert(altFt as Float) as Void {
        if (altAlertFt <= 0) { return; }
        var target = altAlertFt.toFloat();
        var lead = 200.0;
        if (lastAltForAlert == 0.0) { lastAltForAlert = altFt; return; }
        var prev = lastAltForAlert;
        lastAltForAlert = altFt;

        // Once well clear of the target (more than `lead` away), reset both
        // one-shot flags so a later approach/cross alerts again.
        var dist = altFt - target;
        var adist = dist < 0.0 ? -dist : dist;
        if (adist > lead) {
            altAlertApproaching = false;
            altAlertCrossed = false;
        }

        if (!altAlertCrossed) {
            var crossed = (prev < target && altFt >= target) || (prev > target && altFt <= target);
            if (crossed) {
                altAlertCrossed = true;
                altAlertApproaching = false;
                doAltAlertVibrate();
                return;
            }
        }
        if (!altAlertApproaching && prev < (target - lead) && altFt >= (target - lead)) {
            altAlertApproaching = true;
            doApproachVibrate();
        }
    }

    // Estimated height above field elevation (feet).
    function getAglFt() as Float {
        var alt = VFRAvionicsData.readAltitudeFeet();
        if (alt == null) { return 0.0; }
        return (alt as Number).toFloat() - fieldElevationFt.toFloat();
    }

    function circuitPhaseName() as String {
        if (circuitPhase == 1) { return "UPWIND"; }
        if (circuitPhase == 2) { return "XWIND"; }
        if (circuitPhase == 3) { return "DWIND"; }
        if (circuitPhase == 4) { return "BASE"; }
        if (circuitPhase == 5) { return "FINAL"; }
        return "";
    }

    // Downwind duration derived from runway length + margin, divided by groundspeed.
    function computeDownwindMs(gsKt as Float) as Number {
        var gsMps = gsKt.toFloat() * 0.514444;
        if (gsMps < 5.0) { return 60000; }
        var sec = (runwayLengthM.toFloat() + DOWNWIND_EXTRA_M.toFloat()) / gsMps;
        if (sec < 20.0) { sec = 20.0; }
        if (sec > 120.0) { sec = 120.0; }
        return (sec * 1000.0).toNumber();
    }

    function onHide() as Void {
        // Keep GPS live while a flight is in progress: pushing a subview
        // (quick info, map, trip, settings) hides the main view, and disabling
        // location events here would freeze altitude/V-S updates and drive the
        // timer colour back to red mid-flight.
        if (running) { return; }
        if (Position has :enableLocationEvents) {
            Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
        }
    }

}

// Quick info view: four evenly spaced large lines showing key flight info.
class VFRQuickInfoView extends WatchUi.View {
    private var _main    as VFRStopWatchView;
    private var _bigFont as Graphics.VectorFont? = null;
    private var _lastRefresh as Number = 0;
    function initialize(main as VFRStopWatchView) {
        View.initialize();
        _main = main;
    }

    function onShow() as Void {
        WatchUi.requestUpdate();
    }

    function onLayout(dc as Dc) as Void { }

    function onUpdate(dc as Dc) as Void {
        var now = System.getTimer();
        try { var c = getApp().getComms(); if (c != null) { c.tick(now); } } catch (ce) {}
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var jc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // --- Draw the full main view as background (annulus, separators, phone arc) ---
        _main.drawBezelBackground(dc);

        // --- Black-fill the inner circle (covers the main chrono) ---
        // Mirrors main view geometry: sepRadius = R - 25  (R = 130 for 260px screen)
        var minWh = (w < h) ? w : h;
        var sepR  = ((minWh.toFloat() / 2.0) - 27.0).toNumber();
        try { } catch (e) {}
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillCircle(cx, cy, sepR);

        // --- Lazy-init medium vector font for large display values ---
        if (_bigFont == null) {
            var sz    = (minWh * 0.18).toNumber(); // reduced size for wind/temp
            var faces = ["RobotoCondensed", "Roboto", "RobotoBlack", "Swiss721Bold", "TomorrowBold"];
            for (var fi = 0; fi < faces.size() && _bigFont == null; fi++) {
                try { _bigFont = Graphics.getVectorFont({:face => faces[fi], :size => sz}); } catch (e) {}
            }
        }
        var bigFont = (_bigFont != null) ? _bigFont : Graphics.FONT_NUMBER_HOT;

        // --- Pull weather data via VFRWeather helper ---
        var wDir = -1;
        var wSpd = -1; // knots
        var tmp  = -999;
        var dew  = -999;

        try {
            var wr = VFRWeather.read(getApp().getComms());
            try { tmp  = wr.temp; } catch (e) {}
            try { wDir = wr.windDir; } catch (e) {}
            try { wSpd = wr.windSpd; } catch (e) {}
            try { dew  = wr.dew; } catch (e) {}
        } catch (we) { }

        // Format: "DDD/SS" (direction zero-padded to 3 digits)
        var windStr = "--/--";
        // Show partial wind info when available: DDD/SS, --/SS, or DDD/--
        if (wDir >= 0 || wSpd >= 0) {
            var dStr = "--";
            if (wDir >= 0) {
                dStr = (wDir < 10)  ? "00" + wDir.toString()
                     : (wDir < 100) ? "0"  + wDir.toString()
                     :                      wDir.toString();
            }
            var sStr = "--";
            if (wSpd >= 0) { sStr = wSpd.toString(); }
            windStr = dStr + "/" + sStr;
        }

        // Format: "T/D" (temperature/dewpoint, sign included in number)
        var tempStr = "--/--";
        // Show partial temperature/dew when available. Use -- for missing values.
        if (tmp != -999 || dew != -999) {
            var tStr = (tmp != -999) ? (Math.round(tmp).toNumber().toString()) : "--";
            var dStr = (dew != -999) ? (Math.round(dew).toNumber().toString()) : "--";
            tempStr = tStr + "/" + dStr;
        }

        // --- Blue horizontal divider line across inner circle ---
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(cx - sepR, cy, cx + sepR, cy);
        dc.setPenWidth(1);

        // --- Top half: WIND label + direction/speed ---
        // "WIND" label (small, blue, near top of inner circle)
        dc.drawText(cx, cy - 85, Graphics.FONT_SMALL, "WIND", jc);
        // Wind value: DDD/SS  (large, white)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 44, bigFont, windStr, jc);

        // --- Bottom half: TEMP/DP label + temp/dewpoint ---
        // "TEMP/DP" label (small, blue)
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 22, Graphics.FONT_SMALL, "TEMP/DP", jc);
        // Temp/dewpoint value (large, white)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 70, bigFont, tempStr, jc);

        var comms = getApp().getComms();

        // Throttle to 1 Hz: an unconditional requestUpdate() here redraws at full
        // frame rate for as long as the quick-info view is open, draining battery.
        if ((now - _lastRefresh) >= 1000) { _lastRefresh = now; WatchUi.requestUpdate(); }
    }
}

// Heading / GS quick-info (shown before wind/temp)
class VFRQuickInfoHdgGsView extends WatchUi.View {
    private var _main as VFRStopWatchView;
    private var _bigFont as Graphics.VectorFont? = null;
    private var _lastRefresh as Number = 0;
    function initialize(main as VFRStopWatchView) {
        View.initialize();
        _main = main;
    }
    function onShow() as Void { WatchUi.requestUpdate(); }
    function onLayout(dc as Dc) as Void { }
    function onUpdate(dc as Dc) as Void {
        var now = System.getTimer();
        try { var c = getApp().getComms(); if (c != null) { c.tick(now); } } catch (ce) {}
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var jc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Draw bezel background so it matches other quick-info screens
        _main.drawBezelBackground(dc);

        // Black inner circle
        var minWh = (w < h) ? w : h;
        var sepR  = ((minWh.toFloat() / 2.0) - 27.0).toNumber();
        try { } catch (e) {}
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillCircle(cx, cy, sepR);

        // --- Blue horizontal divider line across inner circle ---
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(cx - sepR, cy, cx + sepR, cy);
        dc.setPenWidth(1);

        // Big font
        if (_bigFont == null) {
            var sz = (minWh * 0.20).toNumber();
            var faces = ["RobotoCondensed", "Roboto", "RobotoBlack", "Swiss721Bold", "TomorrowBold"];
            for (var fi = 0; fi < faces.size() && _bigFont == null; fi++) {
                try { _bigFont = Graphics.getVectorFont({:face => faces[fi], :size => sz}); } catch (e) {}
            }
        }
        var bigFont = (_bigFont != null) ? _bigFont : Graphics.FONT_NUMBER_HOT;

        // Get heading and GS from system APIs (prefer GPS course)
        var hdgStr = "--";
        var gsStr = "--";
        try {
            var hdg = VFRHeading.getHeadingDeg();
            if (hdg >= 0) {
                var hdgInt = Math.round(hdg).toNumber();
                if (hdgInt < 10)       { hdgStr = "00" + hdgInt.toString(); }
                else if (hdgInt < 100) { hdgStr = "0"  + hdgInt.toString(); }
                else                   { hdgStr = hdgInt.toString(); }
            }
            } catch (ex) {
            }
        try {
            var actInfoLocal = Activity.getActivityInfo();
            if (actInfoLocal != null && actInfoLocal.currentSpeed != null) {
                gsStr = Math.round((actInfoLocal.currentSpeed as Float) * 1.94384).toNumber().toString();
            }
            } catch (ex) {
            }
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 60, Graphics.FONT_SMALL, "HDG", jc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 20, bigFont, hdgStr, jc);

        // Draw GS value above its label (label below digits), nudged down 5px
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 25, bigFont, gsStr + " kt", jc);
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 65, Graphics.FONT_SMALL, "GS", jc);

        // Throttle to 1 Hz to avoid a continuous redraw loop.
        if ((now - _lastRefresh) >= 1000) { _lastRefresh = now; WatchUi.requestUpdate(); }
    }
}

class VFRQuickInfoHdgGsDelegate extends WatchUi.BehaviorDelegate {
    private var _main as VFRStopWatchView;
    function initialize(main as VFRStopWatchView) {
        BehaviorDelegate.initialize();
        _main = main;
    }
    function onBack() as Boolean {
        try { _main.quickInfoShown = false; } catch (ex) {}
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
    // DOWN (next page) → push wind/temp quick-info
    function onNextPage() as Boolean {
        try {
            _main.quickInfoLastNavAt = System.getTimer();
            WatchUi.pushView(new VFRQuickInfoView(_main), new VFRQuickInfoDelegate(_main), WatchUi.SLIDE_UP);
        } catch (ex) { }
        return true;
    }
}

class VFRQuickInfoDelegate extends WatchUi.BehaviorDelegate {
    private var _main as VFRStopWatchView;
    function initialize(main as VFRStopWatchView) {
        BehaviorDelegate.initialize();
        _main = main;
    }
    function onBack() as Boolean {
        // Mark quick-info as closed so subsequent short-presses can re-open it
        try { _main.quickInfoShown = false; } catch (ex) { }
        WatchUi.popView(WatchUi.SLIDE_DOWN); // pop quick info
        return true;
    }
    function onSelect() as Boolean {
        try { _main.quickInfoShown = false; } catch (ex) { }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
    // Second short DOWN press → push map view (if device has map support)
    function onKeyPressed(keyEvent as WatchUi.KeyEvent) as Boolean {
        if (keyEvent.getKey() == WatchUi.KEY_DOWN) { return true; }
        return false;
    }
    function onKeyReleased(keyEvent as WatchUi.KeyEvent) as Boolean {
        if (keyEvent.getKey() == WatchUi.KEY_DOWN) {
            // Avoid reacting to the same DOWN press/release used to navigate
            // between quick-info pages: require a small delay after navigation.
            var now = System.getTimer();
            if ((now - _main.quickInfoLastNavAt) < 300) {
                return true;
            }
            if (WatchUi has :MapView) {
                try {
                    var mapView = new VFRMapView(_main);
                    WatchUi.pushView(mapView, new VFRMapDelegate(_main, mapView), WatchUi.SLIDE_IMMEDIATE);
                } catch (ex) {
                }
            }
            return true;
        }
        return false;
    }
    // Also intercept onNextPage so BehaviorDelegate doesn't swallow the DOWN press
    function onNextPage() as Boolean {
        // First try to push the second weather quick-info screen
        try {
            _main.quickInfoLastNavAt = System.getTimer();
            WatchUi.pushView(new VFRQuickInfoWeather2View(_main), new VFRQuickInfoWeather2Delegate(_main), WatchUi.SLIDE_UP);
            return true;
        } catch (ex) { }

        // Fallback: if maps are available, push the map view
        if (WatchUi has :MapView) {
            try {
                var mapView = new VFRMapView(_main);
                WatchUi.pushView(mapView, new VFRMapDelegate(_main, mapView), WatchUi.SLIDE_IMMEDIATE);
            } catch (ex) {
            }
        }
        return true;
    }
}
