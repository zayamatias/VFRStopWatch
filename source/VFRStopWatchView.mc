import Toybox.ActivityRecording;
import Toybox.Application;
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

    // --- Vector fonts (optional rounded font resource) ---
    var roundedFontLarge as Graphics.VectorFont? = null;
    var roundedFontSmall as Graphics.VectorFont? = null;
    var bezelLblFont     as Graphics.VectorFont? = null; // small label font for bezel items
    var bezelLblFace     as String? = null;
    var bezelLblFaceSize as Number = 0;
    var bezelSlotFont    as Graphics.VectorFont? = null;  // slot-sized font (auto-fit)
    var SHOW_BEZEL_ANGLE_DEBUG as Boolean = false; // debug overlay disabled
    var FORCE_FLAT_BEZEL as Boolean = false; // when true, skip radial text and use flat placement fallback
    var lastDrawTimes as Dictionary = new Dictionary(); // guard per-label draw timestamps
    var bezelFrameId as Number = 0; // incremented each onUpdate to identify a frame
    // Cache loaded phone icon resource to avoid per-frame allocations
    var cachedPhoneIcon as Object? = null;

    // --- Down-button hold detection ---
    var downPressAt as Number = 0; // System.getTimer() when DOWN pressed
    var DOWN_HOLD_MS as Number = 800; // ms to consider a long press
    var lastDownEventAt as Number = 0; // debounce last physical press
    var quickInfoShown as Boolean = false;
    var quickInfoLastNavAt as Number = 0; // ms timestamp of last quick-info navigation action

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
        // GPS mode
        try {
            var rawMode = Application.Properties.getValue("GpsMode");
            gpsMode = (rawMode != null) ? (rawMode as Number) : 3;
        } catch (ex) { gpsMode = 3; }

        // Timer interval (minutes → ms; 0 = disabled)
        var intervalMin = 5;
        try {
            var rawInterval = Application.Properties.getValue("TimerInterval");
            intervalMin = (rawInterval != null) ? (rawInterval as Number) : 5;
        } catch (ex) { intervalMin = 5; }
        if (intervalMin < 0) { intervalMin = 0; }
        if (intervalMin > 30) { intervalMin = 30; }
        timerIntervalMs = intervalMin * 60000;

        // Takeoff speed (knots → m/s; 0 = disable auto-start)
        var speedKts = 30;
        try {
            var rawSpeed = Application.Properties.getValue("TakeoffSpeed");
            speedKts = (rawSpeed != null) ? (rawSpeed as Number) : 30;
        } catch (ex) { speedKts = 30; }
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
        if (needsResumePrompt) {
            needsResumePrompt = false;
            WatchUi.pushView(new VFRResumeView(self), new VFRResumeDelegate(self), WatchUi.SLIDE_UP);
        }
        WatchUi.requestUpdate();
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
            // Capture altitude when available and compute vertical speed
            if (info != null) {
                try {
                    var now = System.getTimer();
                    // Prefer sensor-derived altitude (barometric) when available;
                    // fall back to Position.Info.altitude (GPS) if not.
                    var sInfo = Sensor.getInfo();
                    var alt = null;
                    if (sInfo != null && sInfo.altitude != null) {
                        alt = (sInfo.altitude as Float);
                        System.println("onPosition: using Sensor.altitude (baro) = " + alt.toString());
                    } else if (info.altitude != null) {
                        alt = (info.altitude as Float);
                        System.println("onPosition: using Position.altitude (GPS) = " + alt.toString());
                    }
                    if (alt != null) {
                        // Track max altitude during an active trip
                        if (running && (alt as Float) > maxAltitudeM) {
                            maxAltitudeM = (alt as Float);
                        }
                        if (lastAltitudeMillis != 0) {
                            var dtMs = now - lastAltitudeMillis;
                            if (dtMs > 0) {
                                var vspd = (alt - lastAltitudeMeters) / (dtMs.toFloat() / 1000.0); // m/s
                                var newTendency = 0;
                                if (vspd >= VERT_SPEED_THRESHOLD_MPS) { newTendency = 1; }
                                else if (vspd <= -VERT_SPEED_THRESHOLD_MPS) { newTendency = -1; }
                                if (newTendency != 0) {
                                    tendency = newTendency;
                                    tendencyUntil = now + 5000; // show arrow for 5s
                                    // Vibrate on new detection but throttle repeats
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
                    }
                    // Update transition flag using pressure if available
                    try {
                        var sPressure = null;
                        if (sInfo != null) {
                            if (sInfo.pressure != null) { sPressure = sInfo.pressure as Float; }
                        }
                        if (sPressure != null) {
                            var p = (sPressure as Float).toFloat();
                            var paFt = 145366.45 * (1.0 - Math.pow((p / 1013.25), 0.190284));
                            if (!transitionActive && paFt >= transitionAltitudeFt) {
                                transitionActive = true;
                                System.println("Transition ACTIVE at paFt=" + paFt.toString());
                            } else if (transitionActive && paFt <= (transitionAltitudeFt - transitionExitOffsetFt)) {
                                transitionActive = false;
                                System.println("Transition CLEARED at paFt=" + paFt.toString());
                            }
                        } else {
                            if (lastAltitudeMeters != 0) {
                                var altFtF = lastAltitudeMeters * 3.28084;
                                if (!transitionActive && altFtF >= transitionAltitudeFt) { transitionActive = true; }
                                else if (transitionActive && altFtF <= (transitionAltitudeFt - transitionExitOffsetFt)) { transitionActive = false; }
                            }
                        }
                    } catch (ex) { }
                } catch (ex) { }
            }
        }
        lastPositionMillis = System.getTimer();
        WatchUi.requestUpdate();
    }

    function startStop() as Void {
        if (!running) {
            // First press: start the main stopwatch (no 5-min alerts yet)
            running = true;
            autoStartEnabled = false; // disarm auto-start once running
            checkpointActive = false;
            startTime = System.getTimer() - elapsed;
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
                System.println("ActivityRecording session started");
            }
            // Notify phone of flight start
            var commsStart = getApp().getComms();
            if (commsStart != null && tripStartUtcMoment != null) {
                try { commsStart.sendFlightStart((tripStartUtcMoment as Time.Moment).value().toNumber()); } catch (ex) {}
            }
            WatchUi.requestUpdate();
        } else if (running && !checkpointActive && timerIntervalMs > 0) {
            // Second press while running and interval enabled: start checkpoint alerts
            checkpointActive = true;
            // schedule next alert from now using the settings-driven interval
            var now = System.getTimer();
            var curElapsed = now - startTime;
            nextVibrateAt = curElapsed + timerIntervalMs;
            checkpointHit = false;
            System.println("Interval started; nextVibrateAt=" + nextVibrateAt.toString());
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
            System.println("ActivityRecording session discarded on reset");
        }
        running = false;
        elapsed = 0;
        autoStartEnabled = true; // re-arm auto-start after reset
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
        clearBackupProperties();
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
            subTimerElapsed = now - subTimerStart;
            subTimerState = 2;
        } else {
            // Return to main view
            subTimerState = 0;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var now = System.getTimer();
        // bump frame id so per-label guards can skip duplicates within the same frame
        bezelFrameId = (bezelFrameId as Number) + 1;
        // Drive phone comms retry logic
        var comms = getApp().getComms();
        if (comms != null) { comms.tick(now); }
        // Single Activity.Info fetch — shared by GPS accumulation, HR and auto-start
        var actInfo = Activity.getActivityInfo();

        if (running) {
            elapsed = now - startTime;

            // Accumulate GPS ground speed into distance
            var deltaMs = now - lastUpdateTimer;
            if (deltaMs > 0 && deltaMs < 2000 && actInfo != null) {
                var spd = actInfo.currentSpeed;
                if (spd != null) {
                    // currentSpeed is m/s; deltaMs is ms
                    var addM = (spd as Float) * (deltaMs.toFloat() / 1000.0);
                    totalDistanceM += addM;
                    // Track max ground speed (knots)
                    try {
                        var gsKt = ((spd as Float) * 1.94384).toFloat();
                            if (running && gsKt > maxGsKt) { 
                                maxGsKt = gsKt; 
                            }
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
                System.println("CHECKPOINT HIT: elapsed=" + elapsed + " nextVibrateAt=" + nextVibrateAt);
                kmAtCheckpoint = totalDistanceM / 1000.0;
                nmAtCheckpoint = totalDistanceM / 1852.0;
                checkpointHit = true;
                nextVibrateAt += timerIntervalMs;
                System.println("Calling doFiveMinAlert...");
                doFiveMinAlert();
                System.println("doFiveMinAlert returned OK");
            }
            // 30-minute fuel check: flash stopwatch colours and vibrate
            if (elapsed >= nextFuelCheckAt) {
                fuelFlashUntil = now + 5000; // flash for 5 seconds
                doFuelAlert();
                nextFuelCheckAt += FUEL_CHECK_INTERVAL_MS;
            }

            // Auto-stop if speed is truly zero for AUTO_STOP_DELAY_MS.
            // Only count while GPS fix is good (quality >= 3) and speed is
            // explicitly non-null — a null speed means GPS is lost, not grounded.
            if (actInfo != null && gpsQuality >= 3) {
                var aspd = actInfo.currentSpeed;
                if (aspd != null && (aspd as Float) < 0.5) {
                    // Confirmed zero speed with a good GPS fix
                    if (zeroSpeedStartMs == 0) { zeroSpeedStartMs = now; }
                    else if ((now - zeroSpeedStartMs) >= AUTO_STOP_DELAY_MS) {
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
        }

        // Periodic on-disk backup: save a compact state to Application settings
        if ((now - lastBackupMillis) >= BACKUP_INTERVAL_MS) {
            try {
                saveBackupProperties();
                lastBackupMillis = now;
            } catch (ex) {
                System.println("backup failed: " + ex.getErrorMessage());
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
        if ((now - lastPositionMillis) > 5000) {
            if (gpsQuality != 0) {
                gpsQuality = 0;
            }
        }

        // --- Auto-start: begin stopwatch when ground speed exceeds configured threshold ---
        // Require a recent, good GPS fix to avoid false triggers on devices
        // that may report a non-zero speed without a valid location fix.
        if (autoStartEnabled && !running && AUTO_START_SPEED_MS > 0.0 && actInfo != null
            && gpsQuality >= 3 && ((System.getTimer() - lastPositionMillis) <= 5000)) {
            var spd = actInfo.currentSpeed;
            if (spd != null && (spd as Float) >= AUTO_START_SPEED_MS) {
                System.println("Auto-start triggered: speed=" + (spd as Float).toString() + " m/s");
                startStop();
            }
        }
        if (lastHr > 0 && lastHr > HR_THRESHOLD) {
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

        // --- Compute sub-timer elapsed if running ---
        var subMs = subTimerElapsed;
        if (subTimerState == 1) {
            subMs = now - subTimerStart;
        }

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
            // GPS fix indicator: red=no fix, blinking orange=acquiring, white=fix
            if (gpsQuality >= 3) {
                timerColor = Graphics.COLOR_WHITE;
            } else if (gpsQuality == 2) {
                // Blink between orange and black (text disappears against black bg)
                var blinkPhase = ((now / 500).toNumber() % 2).toNumber();
                timerColor = (blinkPhase == 0) ? Graphics.COLOR_ORANGE : Graphics.COLOR_BLACK;
            } else {
                timerColor = Graphics.COLOR_RED;
            }
        }
        var displayKm  = lapMode ? lapKm  : kmAtCheckpoint;
        var showDist   = lapMode || checkpointHit;

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
        var minutes  = totalSec / 60;
        var seconds  = totalSec % 60;
        var mStr = minutes < 10 ? "0" + minutes.toString() : minutes.toString();
        var sStr = seconds < 10 ? "0" + seconds.toString() : seconds.toString();

        // --- Draw (circular/bezel layout) ---
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var minWh = (w < h) ? w : h;
        var margin = (minWh * 8) / 100;
        var radius = (minWh / 2) - margin;

        drawBezelBackground(dc);

        // --- Centre: large chrono ---
        dc.setColor(timerColor, Graphics.COLOR_TRANSPARENT);
        var chronoFont = (roundedFontLarge != null) ? roundedFontLarge : Graphics.FONT_NUMBER_HOT;
        dc.drawText(cx, cy, chronoFont, mStr + ":" + sStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // --- Distance (small) ---
        if (showDist) {
            var kmInt = displayKm.toNumber();
            var kmDecFloat = displayKm - kmInt.toFloat();
            var kmDec = (kmDecFloat * 10.0).toNumber();
            if (kmDec < 0) { kmDec = 0; }
            var kmStr = kmInt.toString() + "." + kmDec.toString() + " km";
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + radius * 0.9, Graphics.FONT_TINY, kmStr,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        if (running || subTimerState == 1 || hrAlertActive || fuelFlashActive || autoStartEnabled || gpsQuality < 3 || (tendency != 0 && tendencyUntil > now)) {
            WatchUi.requestUpdate();
        }
    }

    function lap() as Void {
        if (lapMode) {
            // Second press: return to live view
            lapMode = false;
        } else {
            // First press: snapshot current values
            lapMode = true;
            lapElapsed = elapsed < 0 ? 0 : elapsed;
            lapKm = totalDistanceM / 1000.0;
            lapNm = totalDistanceM / 1852.0;
        }
        WatchUi.requestUpdate();
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

        // Build clock strings
        var localTime = System.getClockTime();
        var lh = localTime.hour;
        var lm = localTime.min;
        var lhStr = lh < 10 ? "0" + lh.toString() : lh.toString();
        var lmStr = lm < 10 ? "0" + lm.toString() : lm.toString();

        var utcMoment = Time.now();
        var utcInfo = Gregorian.utcInfo(utcMoment, Time.FORMAT_SHORT);
        var uh = utcInfo.hour;
        var um = utcInfo.min;
        var uhStr = uh < 10 ? "0" + uh.toString() : uh.toString();
        var umStr = um < 10 ? "0" + um.toString() : um.toString();

        var minWh = (w < h) ? w : h;
        var margin = (minWh * 8) / 100;
        var radius = (minWh / 2) - margin;

        // Initialize vector fonts
        if (roundedFontLarge == null) {
            var chronoSize   = (minWh * 0.30).toNumber();
            var bezelSize    = (minWh * 0.110).toNumber();
            var bezelLblSize = (minWh * 0.095).toNumber();
            var faces = ["RobotoCondensed", "Roboto", "RobotoBlack", "RobotoRegular", "Swiss721Bold", "TomorrowBold"];
            for (var fi = 0; fi < faces.size() && roundedFontLarge == null; fi++) {
                try {
                    var f = Graphics.getVectorFont({:face => faces[fi], :size => chronoSize});
                            if (f != null) {
                                roundedFontLarge = f;
                                roundedFontSmall = Graphics.getVectorFont({:face => faces[fi], :size => bezelSize});
                                try {
                                    var tmp = Graphics.getVectorFont({:face => faces[fi], :size => bezelLblSize});
                                    if (tmp != null) {
                                        bezelLblFont = tmp;
                                        bezelLblFace = faces[fi];
                                        bezelLblFaceSize = bezelLblSize;
                                    }
                                } catch (exf) { }
                            }
                } catch (ex) { }
            }
        }

        // Prefer a lighter, condensed/regular face for small bezel labels
        try {
            var bezelSizeLocal = (minWh * 0.110).toNumber();
            if (roundedFontSmall == null) {
                var trySmall = Graphics.getVectorFont({:face => "RobotoCondensed", :size => bezelSizeLocal});
                if (trySmall != null) { roundedFontSmall = trySmall; }
            } else {
                try {
                    var altSmall = Graphics.getVectorFont({:face => "RobotoRegular", :size => bezelSizeLocal});
                    if (altSmall != null) { roundedFontSmall = altSmall; }
                } catch (ex2) { }
            }
        } catch (ex3) { }

        // --- Bezel data strings ---
        var drawNow = now;

        // Heading: use GPS-derived `course` (degrees) when available
        var hdgStr = "--";
        try {
            var hdg = VFRHeading.getHeadingDeg();
            if (hdg >= 0) {
                var hdgInt = Math.round(hdg).toNumber();
                if (hdgInt < 10)       { hdgStr = "00" + hdgInt.toString(); }
                else if (hdgInt < 100) { hdgStr = "0"  + hdgInt.toString(); }
                else                   { hdgStr = hdgInt.toString(); }
            }
        } catch (ex) { }

        // Ground speed (knots)
        var gsStr = "--";
        try {
            var actInfoLocal = Activity.getActivityInfo();
            if (actInfoLocal != null && actInfoLocal.currentSpeed != null) {
                gsStr = ((actInfoLocal.currentSpeed as Float) * 1.94384).toNumber().toString();
            }
        } catch (ex) { }

        // QNH + Altitude
        var qnhValStr = "--";
        var altStr    = "-----";
        var altLbl    = "ALT";
        try {
            var sInfoDraw = Sensor.getInfo();
            if (sInfoDraw != null) {
                if (sInfoDraw.pressure != null) {
                    // Truncate fractional part — only show digits before decimal
                    qnhValStr = Math.floor((sInfoDraw.pressure as Float)).toNumber().toString();
                }
                if (sInfoDraw.altitude != null) {
                    var altFt = ((sInfoDraw.altitude as Float) * 3.28084).toNumber();
                    if (transitionActive) {
                        altStr = "FL" + (altFt / 100).toNumber().toString();
                    } else {
                        altStr = altFt.toString();
                    }
                }
            }
        } catch (ex) { }

        // Append tendency indicator to the alt string
        if (running && tendency != 0 && drawNow < tendencyUntil) {
            altStr = altStr + (tendency > 0 ? "+" : "-");
        }

        // --- Radial bezel geometry ---
        var R = (minWh / 2).toFloat();
        var radiusOuter = (R - 2.0).toFloat();
        var sepRadius = (radiusOuter - 25.0).toNumber();
        var radiusInner  = (radiusOuter - 34.0).toFloat();
        var radiusCenter = ((radiusInner + radiusOuter) / 2.0).toFloat();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(cx, cy, sepRadius);

        var slotDeg = 360.0 / 62.0;
        var numSlotsHDG = 9;
        var numSlotsGS  = 11;
        var numSlotsALT = 11;
        var numSlotsUTC = 11;
        var numSlotsQNH = 10;
        var numSlotsLT  = 10;
        var spanHDG = numSlotsHDG * slotDeg;
        var spanGS  = numSlotsGS  * slotDeg;
        var spanALT = numSlotsALT * slotDeg;
        var spanUTC = numSlotsUTC * slotDeg;
        var spanQNH = numSlotsQNH * slotDeg;
        var spanLT  = numSlotsLT  * slotDeg;
        // User-requested bezel angles (degrees):
        //  - HDG centered at 270 + 45 = 315°
        //  - GS centered at 45°
        //  - QNH centered at 135°
        //  - ALT centered at 225°
        var angleHDG = 135.0;
        var angleGS  = 45.0;
        var angleQNH = 315.0;
        var angleALT = 225.0;
        // Keep legacy angle vars for completeness
        var angleLT  = 225.0;
        var angleUTC = 330.0;
        var rHDG = (radiusCenter - 2.0).toNumber();
        var rGS  = (radiusCenter - 6.0).toNumber();
        var rALT = (radiusCenter - 6.0).toNumber();
        var rUTC = (radiusCenter + 7.0).toNumber();
        var rQNH = (radiusCenter + 7.0).toNumber();
        var rLT  = (radiusCenter + 7.0).toNumber();

        var qnhDisplay = qnhValStr;
        // Ensure we never show decimals: operate on the string form only
        // to avoid casting arbitrary Objects to Float (which can crash).
        if (qnhDisplay != null && qnhDisplay != "--" && qnhDisplay != "") {
            var cut = -1;
            for (var i = 0; i < qnhDisplay.length(); i++) {
                var ch = qnhDisplay.substring(i, i + 1);
                // Stop at standard decimal separators or any non-digit
                if (ch == "." || ch == ",") { cut = i; break; }
                // If we encounter a non-digit character, cut there too
                var isDigit = false;
                for (var di = 0; di < 10; di++) {
                    if (ch == di.toString()) { isDigit = true; break; }
                }
                if (!isDigit) { cut = i; break; }
            }
            if (cut >= 0) { qnhDisplay = qnhDisplay.substring(0, cut); }
        }
        if (qnhDisplay == "--" or qnhDisplay == "") {
            qnhDisplay = "----";
        } else {
            while (qnhDisplay.length() < 4) {
                qnhDisplay = "-" + qnhDisplay;
            }
        }

        // Compute a dedicated text radius (visual centroid of the annulus).
        // Start with the mathematical midpoint but allow small per-quadrant
        // nudges; this lets us calibrate to the bezel art without changing
        // slot math or rotation.
        var radiusText = radiusCenter;
        var rTextHDG = radiusText; // NW
        var rTextGS  = radiusText; // NE
        // Nudge bottom quadrants slightly inward to visually centre text
        // within the bezel artwork (non-invasive cosmetic tweak).
        var rTextALT = radiusText + 10.0; // SW (-2px from +12)
        var rTextQNH = radiusText + 10.0; // SE (-2px from +12)

        // Debug overlay: when enabled, draw slot centres and quadrant guide lines
        // to help measure the correct angles/radii in the screenshot tool.
        if (SHOW_BEZEL_ANGLE_DEBUG) {
            try {
                dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
                // small markers at each of the 48 slot CENTRES
                for (var kk = 0; kk < 48; kk++) {
                    var slotTheta = (90.0 - (kk.toFloat() + 0.5) * 7.5) * (Math.PI / 180.0);
                    var mx = (cx.toFloat() + radiusText * Math.cos(slotTheta)).toNumber();
                    var my = (cy.toFloat() - radiusText * Math.sin(slotTheta)).toNumber();
                    dc.fillCircle(mx, my, 2);
                }
                // Crosshair at exact centre
                dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(1);
                dc.drawLine(cx - 2, cy, cx + 2, cy);
                dc.drawLine(cx, cy - 2, cx, cy + 2);

                // Draw radial guide for each configured quadrant anchor
                dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
                var quads = [ [angleHDG, "HDG"], [angleGS, "GS"], [angleALT, "ALT"], [angleQNH, "QNH"] ];
                for (var qi = 0; qi < quads.size(); qi++) {
                    var a = (quads[qi][0] as Number).toFloat();
                    var aRad = a * (Math.PI / 180.0);
                    var ex = (cx.toFloat() + radiusText * Math.cos(aRad)).toNumber();
                    var ey = (cy.toFloat() - radiusText * Math.sin(aRad)).toNumber();
                    dc.drawLine(cx, cy, ex, ey);
                    // label the guide at its tip so you can read the angle visually
                    try { dc.drawText(ex, ey, bezelLblFont, (quads[qi][1] as String), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER); } catch (e) { }
                }
                dc.setPenWidth(1);
            } catch (dbgEx) { }
        }

        // Call drawLabelInQuadrant with per-quadrant radii so the visual
        // text radius can be calibrated independently of the slot math.
        drawLabelInQuadrant(dc, cx, cy, angleHDG, "HDG", hdgStr,     Graphics.COLOR_WHITE, rTextHDG, false);
        drawLabelInQuadrant(dc, cx, cy, angleGS,  "GS",  gsStr + " kt", Graphics.COLOR_WHITE, rTextGS,  false);
        drawLabelInQuadrant(dc, cx, cy, angleALT, altLbl, altStr,    Graphics.COLOR_WHITE, rTextALT, true);
        drawLabelInQuadrant(dc, cx, cy, angleQNH, "QNH", qnhDisplay, Graphics.COLOR_WHITE, rTextQNH, true);

        // Group separators
        try {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            // Four primary separators at 12, 3, 6, 9 o'clock
            var groupAngles = [90.0, 0.0, 270.0, 180.0];
            var innerClamp = ((sepRadius as Number).toFloat() + 1.0).toFloat();
            var outerClamp = (R - 1.0).toFloat();
            for (var gi = 0; gi < groupAngles.size(); gi++) {
                var a = (groupAngles[gi] as Float).toFloat();
                var aRad = a * (Math.PI / 180.0);
                var sx = (cx.toFloat() + innerClamp * Math.cos(aRad)).toNumber();
                var sy = (cy.toFloat() - innerClamp * Math.sin(aRad)).toNumber();
                var ex = (cx.toFloat() + outerClamp * Math.cos(aRad)).toNumber();
                var ey = (cy.toFloat() - outerClamp * Math.sin(aRad)).toNumber();
                dc.drawLine(sx, sy, ex, ey);
            }
            dc.setPenWidth(1);
        } catch (sepEx) { }

        // --- Phone connection indicator arc ---
        var commsIndicator = getApp().getComms();
        try {
            if (cachedPhoneIcon == null) {
                try { cachedPhoneIcon = WatchUi.loadResource(Rez.Drawables.PhoneIcon); } catch (rEx) { cachedPhoneIcon = null; }
            }
            if (cachedPhoneIcon != null) {
                var iconHalf = 12.0;
                var px = (cx.toFloat() - iconHalf).toNumber();
                var py = (cy.toFloat() + radius * 0.52 - iconHalf).toNumber();
                var drawColour = Graphics.COLOR_YELLOW;
                var visible = true;
                if (commsIndicator != null) {
                    if (commsIndicator.connected) {
                        drawColour = Graphics.COLOR_GREEN;
                    } else if (commsIndicator.connecting) {
                        var lastShake = 0;
                        try { lastShake = (commsIndicator.lastHandshakeAt as Number); } catch (e) { lastShake = 0; }
                        var since = (lastShake > 0) ? (now - lastShake) : 0;
                        if (since >= 30000) {
                            drawColour = Graphics.COLOR_RED;
                            visible = true;
                        } else {
                            var blinkPhase = ((now / 500).toNumber() % 2).toNumber();
                            visible = (blinkPhase == 0);
                            drawColour = Graphics.COLOR_YELLOW;
                        }
                    } else {
                        drawColour = Graphics.COLOR_RED;
                    }
                } else {
                    drawColour = Graphics.COLOR_YELLOW;
                }
                if (visible) {
                    var arcStartDeg = 10.0;
                    var arcEndDeg   = 80.0;
                    var arcStepDeg  = 4.0;
                    var arcR = (sepRadius as Number).toFloat();
                    dc.setColor(drawColour, Graphics.COLOR_TRANSPARENT);
                    dc.setPenWidth(3);
                    var prevX = 0.0;
                    var prevY = 0.0;
                    var havePrev = false;
                    for (var a = arcStartDeg; a <= arcEndDeg; a += arcStepDeg) {
                        var aRad = a * (Math.PI / 180.0);
                        var px1 = (cx.toFloat() + arcR * Math.cos(aRad)).toNumber();
                        var py1 = (cy.toFloat() - arcR * Math.sin(aRad)).toNumber();
                        if (havePrev) {
                            dc.drawLine(prevX, prevY, px1, py1);
                        }
                        prevX = px1; prevY = py1; havePrev = true;
                    }
                    var aRadEnd = arcEndDeg * (Math.PI / 180.0);
                    var endX = (cx.toFloat() + arcR * Math.cos(aRadEnd)).toNumber();
                    var endY = (cy.toFloat() - arcR * Math.sin(aRadEnd)).toNumber();
                    if (havePrev) { dc.drawLine(prevX, prevY, endX, endY); }
                    dc.setPenWidth(1);
                }
            }
        } catch (iconEx) { }
    }

    // Helper: draw a metric using a small radial arc to approximate rotation.
    function drawRotatedMetric(dc as Dc, cx as Number, cy as Number, angle as Float,
                                text as String, color as Number, r as Number, arcSpan as Float, reverse as Boolean, flipTangent as Boolean, preferRadial as Boolean, slotDeg as Float, radiusCenter as Float, radiusOuter as Float) as Void {
        // Debug logging removed to avoid per-frame overhead
        // Skip duplicate draws within the same millisecond per-label (prevents double-rendering)
        try {
            var lastFrame = lastDrawTimes[text];
            if (lastFrame != null && (lastFrame as Number) == bezelFrameId) {
                try { System.println("drawRotatedMetric: skipping duplicate for '" + text + "' (frame guard)"); } catch (e) { }
                return;
            }
            lastDrawTimes[text] = bezelFrameId;
        } catch (exSkip) { }
        // Try vector font radial drawing first (main text), then draw a red trailing pipe.
        try {
            if (roundedFontSmall != null && !FORCE_FLAT_BEZEL) {
                // In fixed-grid mode (slotDeg > 0), arcSpan is the total allocated
                // slot span — use it as-is.  In dynamic mode, expand it from text width.
                var estSpan = arcSpan.toFloat();
                // Optionally reverse the text for rendering order when APIs
                // produce inverted glyph sequences for some directions.
                var drawTextStr = text;
                if (reverse) {
                    var rb = "";
                    for (var ri = text.length() - 1; ri >= 0; ri--) {
                        rb += text.substring(ri, ri + 1);
                    }
                    drawTextStr = rb;
                }
                if (slotDeg <= 0.0) {
                    // Dynamic mode: compute span from character pixel width (fallback)
                    try {
                        if (roundedFontSmall != null) {
                            var px = 18.0 * drawTextStr.length();
                            var paddingFactor = 1.25;
                            var rawDeg = (px * 180.0) / (Math.PI * r.toFloat());
                            var minSpan = 8.0;
                            var maxSpan = 120.0;
                            var computed = rawDeg * paddingFactor;
                            if (drawTextStr.length() <= 1) {
                                estSpan = minSpan;
                            } else {
                                if (computed < minSpan) { estSpan = minSpan; }
                                else if (computed > maxSpan) { estSpan = maxSpan; }
                                else { estSpan = computed; }
                            }
                        } else {
                            var nChars = drawTextStr.length();
                            if (nChars > 1) {
                                var perCharPx = 13.0;
                                var perCharDeg = (perCharPx * 180.0) / (Math.PI * r.toFloat());
                                var needed = perCharDeg * nChars * 1.20;
                                if (needed > estSpan) { estSpan = needed; }
                            }
                        }
                    } catch (exSpan) { /* fall back to provided arcSpan */ }
                }
                var startAngle = angle - (estSpan / 2);
                var dir = (angle <= 180)
                    ? Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE
                    : Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE;
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                // Per-character arcing: split text and draw each char at its own angle
                        try {
                    var n = drawTextStr.length();
                    // Instead of relying on `drawRadialText` (which appears to
                    // produce inconsistent orientation across devices), compute
                    // per-character polar positions and draw each character flat
                    // at the computed point. This keeps characters spaced along
                    // the arc while avoiding the vector radial API quirks.
                    var start = angle - (estSpan / 2.0);
                        if (n <= 1) {
                        var rad = angle.toFloat() * (Math.PI / 180.0);
                        // Use annulus outer for bottom-half single-char, centre for top-half
                        var baseR = (angle <= 180) ? radiusCenter : radiusOuter;
                        var px = (cx.toFloat() + baseR * Math.cos(rad)).toNumber();
                        var py = (cy.toFloat() - baseR * Math.sin(rad)).toNumber();
                        dc.drawText(px, py, roundedFontSmall, drawTextStr,
                            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                    } else {
                        // Per-character angled drawing so glyphs follow the bezel tangent.
                        // angledOk=false when preferRadial — skip the angled loop entirely.
                        // IMPORTANT: must guard the loop with angledOk, otherwise when
                        // preferRadial=true BOTH this loop AND the radial fallback run,
                        // drawing every character twice and producing the visible duplicate.
                        var angledOk = !preferRadial;
                        if (angledOk) {
                            try {
                                for (var ci = 0; ci < n; ci++) {
                                    var ch = drawTextStr.substring(ci, ci + 1);
                                    // Top-half labels (angle 0-180°): in screen coords, increasing
                                    // angle goes RIGHT→LEFT, so character 0 at lowest angle lands
                                    // on the right side — producing a mirrored string.  Fix: reverse
                                    // the character index for top-half labels so char 0 appears on
                                    // the screen-left (highest angular position).
                                    var effectiveCi = (angle <= 180) ? (n - 1 - ci) : ci;
                                    var chAngle;
                                    if (slotDeg > 0.0) {
                                        // Fixed-grid: each char in exactly one slot, group centred
                                        var firstSlotOff = (estSpan - n.toFloat() * slotDeg) / 2.0;
                                        chAngle = start + firstSlotOff + (effectiveCi.toFloat() + 0.5) * slotDeg;
                                    } else {
                                        chAngle = start + ((effectiveCi.toFloat() + 0.5) * (estSpan.toFloat() / n.toFloat()));
                                    }
                                    // screen position along the arc
                                    var chRad = chAngle.toFloat() * (Math.PI / 180.0);
                                    // drawAngledText anchors at the TOP of the glyph (in rotated local frame).
                                    // Top half (angle<=180): after normT flip, glyph top faces OUTWARD →
                                    //   anchor must be placed further OUT so the glyph centre lands on r.
                                    // Bottom half: glyph top faces INWARD → anchor placed further IN.
                                    var fontHalfH = 6;
                                    // Use annulus centre for character anchor, offset by glyph half-height
                                    // For top-half use annulus centre; for bottom-half use annulus outer edge
                                    var rChBase = (angle <= 180) ? radiusCenter : radiusOuter;
                                    var rCh = (angle <= 180)
                                        ? (rChBase + fontHalfH)
                                        : (rChBase - fontHalfH);
                                    var chPx = (cx.toFloat() + rCh * Math.cos(chRad)).toNumber();
                                    var chPy = (cy.toFloat() - rCh * Math.sin(chRad)).toNumber();
                                    // Tangent: chAngle-90 gives the clockwise tangent in screen coords.
                                    var normT = chAngle - 90.0;
                                    while (normT > 180.0)  { normT -= 360.0; }
                                    while (normT <= -180.0) { normT += 360.0; }
                                    // Flip glyphs that would appear upside-down (|tilt|>90°)
                                    if (normT > 90.0)       { normT -= 180.0; }
                                    else if (normT < -90.0) { normT += 180.0; }
                                    dc.drawAngledText(chPx, chPy, roundedFontSmall, ch,
                                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER, normT);
                                }
                            } catch (angEx) {
                                // angled API unavailable; fall through to radial
                                angledOk = false;
                            }
                        }
                        if (!angledOk) {
                            var radialOk = true;
                            try {
                                for (var ci2 = 0; ci2 < n; ci2++) {
                                    var ch2 = drawTextStr.substring(ci2, ci2 + 1);
                                    var chAngle2 = start + ((ci2 + 0.5) * (estSpan / n));
                                    dc.drawRadialText(cx, cy, roundedFontSmall, ch2,
                                        Graphics.TEXT_JUSTIFY_CENTER, chAngle2, r, dir);
                                }
                            } catch (radEx) {
                                radialOk = false;
                            }
                            if (!radialOk) {
                                for (var ci3 = 0; ci3 < n; ci3++) {
                                    var ch3 = drawTextStr.substring(ci3, ci3 + 1);
                                    var chAngle3 = start + ((ci3 + 0.5) * (estSpan / n));
                                    var chRad3 = chAngle3.toFloat() * (Math.PI / 180.0);
                                    var chPx3  = (cx.toFloat() + r.toFloat() * Math.cos(chRad3)).toNumber();
                                    var chPy3  = (cy.toFloat() - r.toFloat() * Math.sin(chRad3)).toNumber();
                                    dc.drawText(chPx3, chPy3, roundedFontSmall, ch3,
                                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                                }
                            }
                        }
                    }
                    // trailing pipe removed here — group separators drawn centrally
                    return;
                } catch (exChars) {
                    // fallback: draw whole text centered at angle
                    dc.drawRadialText(cx, cy, roundedFontSmall, drawTextStr,
                        Graphics.TEXT_JUSTIFY_CENTER, angle, r, dir);
                    dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
                    // radial fallback: draw short radial line instead of rotated glyph
                    var pAngle = (angle + 6).toFloat() * (Math.PI / 180.0);
                    var pHalf = 8.0;
                    var prInner = r.toFloat() - pHalf;
                    var prOuter = r.toFloat() + pHalf;
                    return;
                }
            }
        } catch (ex) { }
        // Fallback to flat placement (no rotation): compute base position and draw pipe
        // Standard polar -> screen: x = cx + r * cos(theta), y = cy - r * sin(theta)
        var rad = angle.toFloat() * (Math.PI / 180.0);
        var px  = (cx.toFloat() + r.toFloat() * Math.cos(rad)).toNumber();
        var py  = (cy.toFloat() - r.toFloat() * Math.sin(rad)).toNumber();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(px, py, Graphics.FONT_XTINY, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        // no trailing pipe in flat fallback — group separators drawn below
    }

    function saveState() as Dictionary {
        var d = new Dictionary();
        d["running"] = running;
        d["startTime"] = startTime;
        // When running, 'elapsed' field is 0; compute live elapsed for persistence
        d["elapsed"] = running ? (System.getTimer() - startTime) : elapsed;
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
        d["subTimerElapsed"] = subTimerElapsed;
        // Save trip start/end times as epoch numbers if available
        // Save simple hour/min snapshots for display on restore
        if (tripStartUtcHour >= 0) { d["tripStartUtcHour"] = tripStartUtcHour; }
        if (tripStartUtcMin  >= 0) { d["tripStartUtcMin"]  = tripStartUtcMin; }
        if (tripEndUtcHour   >= 0) { d["tripEndUtcHour"]   = tripEndUtcHour; }
        if (tripEndUtcMin    >= 0) { d["tripEndUtcMin"]    = tripEndUtcMin; }
        return d;
    }

    // ── drawLabelInQuadrant ────────────────────────────────────────────────
    // Mathematical model (see LESSONS_LEARNT.md):
    //   48 global slots uniformly spaced around the full circle.
    //   Slot k:  θ_k = 90° − k × 7.5°  (math/CCW convention; k=0 at 12 o'clock)
    //   Position: x = cx + R·cos(θ_k),  y = cy − R·sin(θ_k)   (screen y-down)
    //   Rotation: normT = θ_k − 90°, folded into [−90°, +90°]  (drawAngledText degrees)
    //   Font size: charWidth ≤ 0.80 × arc-length-per-slot
    //
    //   quadAngle is in standard math/CCW degrees (e.g. angleHDG = 135°).
    //   The quadrant's start slot is derived from quadAngle so that the centre
    //   of the 12-slot band aligns with quadAngle.
    // reverseChars: pass true for SW (ALT) and SE (QNH) quadrants — CW slot order
    // runs right-to-left from the viewer at bottom positions, so we reverse the
    // character assignment.  NW (HDG) and NE (GS) pass false.  Each quadrant is
    // explicitly independent; changing one cannot affect the others.
    function drawLabelInQuadrant(dc as Dc, cx as Number, cy as Number,
            quadAngle as Float, prefix as String, suffix as String,
            color as Number, radiusCenter as Float, reverseChars as Boolean) as Void {
        if (bezelLblFont == null) { return; }

        // ── 1. Build label string, centre within 12 slots ─────────────────
        var combined = prefix;
        if (suffix != null && suffix.length() > 0) { combined = combined + " " + suffix; }
        var QUAD_SLOTS = 12;
        if (combined.length() > QUAD_SLOTS) { combined = combined.substring(0, QUAD_SLOTS); }
        var nChars = combined.length();
        var startOffset = Math.floor((QUAD_SLOTS - nChars) / 2).toNumber();  // integer, left-pad in slots
        if (startOffset < 0) { startOffset = 0; }

        // ── 2. Map quadAngle → global start slot ──────────────────────────
        // Convert math-CCW angle to clock-CW degrees (0 = 12 o'clock).
        // Float % Float is not supported in Monkey C → use while-loop normalise.
        var clockDeg = 90.0 - quadAngle;
        while (clockDeg <    0.0) { clockDeg += 360.0; }
        while (clockDeg >= 360.0) { clockDeg -= 360.0; }
        // Quadrant occupies 12 slots centred on clockDeg; start slot = centre − 6.
        // Align quadrant centre to slot CENTER: subtract 0.5 so the
        // rounded result maps to the slot index whose centre is nearest
        // the requested clockDeg. (Required Fix #2)
        var quadCentreSlot = Math.round((clockDeg / 7.5) - 0.5).toNumber() % 48;  // nearest slot center
        var quadStartSlot  = (quadCentreSlot - 6 + 48) % 48;

        // ── 3. Compute slot font (cached; sized so glyph fits in arc length) ─
        if (bezelSlotFont == null && bezelLblFace != null && bezelLblFaceSize > 0) {
            // Arc length per global slot = R × Δθ = R × 2π/48
            var arcLen = (radiusCenter.toFloat() * (2.0 * Math.PI / 48.0)).toFloat();
            // Use 75 % of arc for the glyph (slightly more spacing); glyph width ≈ 0.55 × fontSize
            var tgtSize = (arcLen * 0.75 / 0.55).toNumber();
            if (tgtSize < 8)               { tgtSize = 8; }
            if (tgtSize > bezelLblFaceSize) { tgtSize = bezelLblFaceSize; }
            try {
                var f = Graphics.getVectorFont({:face => bezelLblFace, :size => tgtSize});
                bezelSlotFont = (f != null) ? f : bezelLblFont;
            } catch (fe) { bezelSlotFont = bezelLblFont; }
        }
        var useFont = (bezelSlotFont != null) ? bezelSlotFont : bezelLblFont;

        // ── 4. Draw each character ─────────────────────────────────────────
        // Single formula for ALL positions: normT = theta_deg - 90, folded
        // into [−90, +90].  The fold naturally makes tops point outward in the
        // top half and toward the centre in the bottom half, so characters are
        // always readable.  Slot order is always CW (increasing k) — that is
        // left-to-right from the viewer's perspective for every quadrant.
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        for (var si = 0; si < nChars; si++) {
            // reverseChars: bottom quadrants (SW/SE) must read chars in reverse order
            // so that the label reads left-to-right from the viewer despite CW slot
            // traversal going right-to-left at those positions.
            var readIndex = reverseChars ? (nChars - 1 - si) : si;
            var ch = combined.substring(readIndex, readIndex + 1);
            if (ch.equals(" ")) { continue; }

            // Global slot index (0–47) — always clockwise
            var k = (quadStartSlot + startOffset + si) % 48;

            // Slot angle in standard math/CCW degrees: compute using slot
            // CENTER (k + 0.5) so characters are placed at the middle of
            // each 7.5° slot. (Required Fix #1)
            var theta_deg = 90.0 - (k.toFloat() + 0.5) * 7.5;
            var theta_rad = theta_deg * (Math.PI / 180.0);

            // Screen position (y increases downward → subtract sin)
            var px = (cx.toFloat() + radiusCenter * Math.cos(theta_rad)).toNumber();
            var py = (cy.toFloat() - radiusCenter * Math.sin(theta_rad)).toNumber();

            // Tangent rotation: theta - 90, folded into [−90°, +90°].
            // The fold flips the direction for the bottom half automatically,
            // keeping all characters upright and readable from outside.
            var normT = theta_deg - 90.0;
            while (normT >  90.0) { normT -= 180.0; }
            while (normT < -90.0) { normT += 180.0; }

            try {
                dc.drawAngledText(px, py, useFont, ch,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER, normT);
            } catch (e) {
                dc.drawText(px, py, bezelLblFont, ch,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        }
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
        elapsed = System.getTimer() - startTime;
        tripEndUtcMoment = Time.now();
        try {
            var einfo = Gregorian.utcInfo((tripEndUtcMoment as Time.Moment), Time.FORMAT_SHORT);
            tripEndUtcHour = einfo.hour;
            tripEndUtcMin = einfo.min;
        } catch (ex) { }
        checkpointActive = false;
        zeroSpeedStartMs = 0;
        if (_session != null) {
            if (_session.isRecording()) { _session.stop(); }
            _session.save();
            _session = null;
            System.println("ActivityRecording session saved (autoStop)");
        }
        saveBackupProperties(); // persist so summary survives a kill
        // Notify phone of flight stop
        var commsStop = getApp().getComms();
        if (commsStop != null && tripEndUtcMoment != null) {
            try { commsStop.sendFlightStop((tripEndUtcMoment as Time.Moment).value().toNumber()); } catch (ex) {}
        }
        WatchUi.pushView(new VFRSummaryView(self), new VFRSummaryDelegate(self), WatchUi.SLIDE_UP);
    }

    // Clear the on-disk backup (call on reset so no stale resume prompt appears)
    function clearBackupProperties() as Void {
        try {
            Application.Properties.setValue("vfr_backup_hasBackup", false);
        } catch (ex) {
            System.println("clearBackupProperties failed: " + ex.getErrorMessage());
        }
    }

    // Save/Load backup to Application.Properties as individual keys
    function saveBackupProperties() as Void {
        try {
            // When running, the 'elapsed' field is 0; compute live elapsed instead
            var liveElapsed = running ? (System.getTimer() - startTime) : elapsed;
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
            Application.Properties.setValue("vfr_backup_lapMode", lapMode);
            Application.Properties.setValue("vfr_backup_lapElapsed", lapElapsed);
            Application.Properties.setValue("vfr_backup_lapKm", lapKm);
            Application.Properties.setValue("vfr_backup_lapNm", lapNm);
            Application.Properties.setValue("vfr_backup_subTimerState", subTimerState);
            Application.Properties.setValue("vfr_backup_subTimerStart", subTimerStart);
            Application.Properties.setValue("vfr_backup_subTimerElapsed", subTimerElapsed);
            Application.Properties.setValue("vfr_backup_tripStartUtcHour", tripStartUtcHour);
            Application.Properties.setValue("vfr_backup_tripStartUtcMin", tripStartUtcMin);
            Application.Properties.setValue("vfr_backup_tripEndUtcHour", tripEndUtcHour);
            Application.Properties.setValue("vfr_backup_tripEndUtcMin", tripEndUtcMin);
        } catch (ex) {
            System.println("saveBackupProperties failed: " + ex.getErrorMessage());
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
            v = Application.Properties.getValue("vfr_backup_lapMode"); if (v != null) { lapMode = v as Boolean; }
            v = Application.Properties.getValue("vfr_backup_lapElapsed"); if (v != null) { lapElapsed = v as Number; }
            v = Application.Properties.getValue("vfr_backup_lapKm"); if (v != null) { lapKm = v as Float; }
            v = Application.Properties.getValue("vfr_backup_lapNm"); if (v != null) { lapNm = v as Float; }
            v = Application.Properties.getValue("vfr_backup_subTimerState"); if (v != null) { subTimerState = v as Number; }
            v = Application.Properties.getValue("vfr_backup_subTimerStart"); if (v != null) { subTimerStart = v as Number; }
            v = Application.Properties.getValue("vfr_backup_subTimerElapsed"); if (v != null) { subTimerElapsed = v as Number; }
            v = Application.Properties.getValue("vfr_backup_tripStartUtcHour"); if (v != null) { tripStartUtcHour = v as Number; }
            v = Application.Properties.getValue("vfr_backup_tripStartUtcMin"); if (v != null) { tripStartUtcMin = v as Number; }
            v = Application.Properties.getValue("vfr_backup_tripEndUtcHour"); if (v != null) { tripEndUtcHour = v as Number; }
            v = Application.Properties.getValue("vfr_backup_tripEndUtcMin"); if (v != null) { tripEndUtcMin = v as Number; }
        } catch (ex) {
            System.println("loadBackupProperties failed: " + ex.getErrorMessage());
        }
        // Timer cannot continue across a kill; pause and let user resume manually
        running = false;
        if (elapsed > 0) { needsResumePrompt = true; }
        WatchUi.requestUpdate();
    }

    // Open the on-device settings menu (called from DOWN shortcut and main menu).
    function openSettingsMenu() as Void {
        var curGps = 3;
        try {
            var rawGps = Application.Properties.getValue("GpsMode");
            curGps = (rawGps != null) ? (rawGps as Number) : 3;
        } catch (ex) { System.println("openSettingsMenu: GpsMode read failed: " + ex.getErrorMessage()); curGps = 3; }
        if (curGps < 0 || curGps > 3) { curGps = 3; }
        var gpsLabel = curGps == 0 ? "GPS"
                     : curGps == 1 ? "GPS+GLONASS"
                     : curGps == 2 ? "All Systems"
                     : "Aviation";
        var curTimerMin = timerIntervalMs / 60000;
        var curKts = 30;
        try {
            var rawSpd = Application.Properties.getValue("TakeoffSpeed");
            curKts = (rawSpd != null) ? (rawSpd as Number) : 30;
        } catch (ex) { System.println("openSettingsMenu: TakeoffSpeed read failed: " + ex.getErrorMessage()); curKts = 30; }
        var curTrans = 6000;
        try {
            var rawTrans = Application.Properties.getValue("TransitionAltitudeFt");
            curTrans = (rawTrans != null) ? (rawTrans as Number) : 6000;
        } catch (ex) { System.println("openSettingsMenu: TransitionAltitudeFt read failed: " + ex.getErrorMessage()); curTrans = 6000; }
        var menu = new WatchUi.Menu2({:title => "Settings"});
        menu.addItem(new WatchUi.MenuItem("GPS Mode",      gpsLabel,                        "setting_gps",     null));
        menu.addItem(new WatchUi.MenuItem("Timer",         curTimerMin.toString() + " min", "setting_timer",   null));
        menu.addItem(new WatchUi.MenuItem("Takeoff Speed", curKts.toString() + " kts",      "setting_takeoff", null));
        menu.addItem(new WatchUi.MenuItem("Transition Altitude", curTrans.toString() + " ft", "setting_transition", null));
        WatchUi.pushView(menu, new VFRSettingsMenuDelegate(self), WatchUi.SLIDE_UP);
    }

    // DOWN button behavior:
    //   initial state (!running, elapsed==0)  → open settings (held)
    //   stopped but has elapsed time          → reset
    //   running                               → toggle lap
    function onDownPressed() as Void {
        var now = System.getTimer();
        // debounce spurious repeated press events (200 ms)
        if (lastDownEventAt != 0 && (now - lastDownEventAt) < 200) { return; }
        lastDownEventAt = now;
        if (!running && elapsed == 0) {
            // start timing the press; actual action happens on release
            if (downPressAt == 0) {
                downPressAt = now;
                System.println("DOWN pressed: starting hold timer");
            }
        } else if (!running) {
            reset();
            System.println("DOWN pressed: reset (main stopped)");
        } else {
            // When running, don't toggle lap on immediate press.
            // Start the hold timer so release triggers shortDownAction (quick-info),
            // and a long hold is still available if desired.
            if (downPressAt == 0) {
                downPressAt = now;
                System.println("DOWN pressed while running: starting hold timer for quick-info");
            }
        }
    }

    // Short-press action (first press): show quick info overlay
    function shortDownAction() as Void {
        if (quickInfoShown) { return; }
        quickInfoShown = true;
        // Show heading/GS summary first, then allow navigating to wind/temp
        quickInfoLastNavAt = System.getTimer();
        WatchUi.pushView(new VFRQuickInfoHdgGsView(self), new VFRQuickInfoHdgGsDelegate(self), WatchUi.SLIDE_UP);
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
            System.println("Vibrate EXCEPTION: " + ex.getErrorMessage());
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
            System.println("HR vibrate EXCEPTION: " + ex.getErrorMessage());
        }
    }

    // Fuel alert: single short pulse to indicate 30-minute fuel check
    function doFuelAlert() as Void {
        if (!(Attention has :vibrate)) { return; }
        try {
            var pattern = [ new Attention.VibeProfile(100, 400) ];
            Attention.vibrate(pattern);
        } catch (ex instanceof Lang.Exception) {
            System.println("Fuel vibrate EXCEPTION: " + ex.getErrorMessage());
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
            System.println("Tendency up vibrate EXCEPTION: " + ex.getErrorMessage());
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
            System.println("Tendency down vibrate EXCEPTION: " + ex.getErrorMessage());
        }
    }

    function onHide() as Void {
        if (Position has :enableLocationEvents) {
            Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
        }
    }

}

// Quick info view: four evenly spaced large lines showing key flight info.
class VFRQuickInfoView extends WatchUi.View {
    private var _main    as VFRStopWatchView;
    private var _bigFont as Graphics.VectorFont? = null;
    function initialize(main as VFRStopWatchView) {
        View.initialize();
        _main = main;
    }

    function onShow() as Void {
        WatchUi.requestUpdate();
        // Debug: log comms and Weather provider when quick-info shown
        try {
            var commsDbg = getApp().getComms();
            if (commsDbg == null) {
                System.println("QuickInfo.onShow: comms = null");
            } else {
                try { System.println("QuickInfo.onShow: comms wind=" + (commsDbg.windDirDeg as Number).toString() + "/" + (commsDbg.windSpeedKt as Number).toString() + " tmp=" + (commsDbg.tempC as Number).toString()); } catch (e) { System.println("QuickInfo.onShow: comms present but fields missing"); }
            }
            try {
                var wr = VFRWeather.read(getApp().getComms());
                if (wr == null) {
                    System.println("QuickInfo.onShow: VFRWeather.read() = null");
                } else {
                    try { System.println("Weather.temp=" + wr.temp.toString()); } catch (e) {}
                    try { System.println("Weather.windSpd=" + wr.windSpd.toString()); } catch (e) {}
                    try { System.println("Weather.windDir=" + wr.windDir.toString()); } catch (e) {}
                    try { System.println("Weather.dew=" + wr.dew.toString()); } catch (e) {}
                }
            } catch (we) { System.println("QuickInfo.onShow: VFRWeather read error: " + we.getErrorMessage()); }
        } catch (ex) { System.println("QuickInfo.onShow debug failed: " + ex.getErrorMessage()); }
    }

    function onLayout(dc as Dc) as Void { }

    function onUpdate(dc as Dc) as Void {
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
        try { System.println("QuickInfoView: sepR=" + sepR.toString() + " cx=" + cx.toString() + " cy=" + cy.toString() + " w=" + w.toString() + " h=" + h.toString()); } catch (e) {}
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillCircle(cx, cy, sepR);

        // --- Lazy-init medium vector font for large display values ---
        if (_bigFont == null) {
            var sz    = (minWh * 0.24).toNumber(); // 62px on 260px screen
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
        } catch (we) { System.println("Weather helper failed: " + we.getErrorMessage()); }

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
            var tStr = (tmp != -999) ? (tmp.toString()) : "--";
            var dStr = (dew != -999) ? (dew.toString()) : "--";
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

        // Debug: show raw weather payload from phone (truncated)
        try {
            var rawMsg = "";
            if (comms != null) { try { rawMsg = (comms.lastRawWeather as String); } catch (e) { rawMsg = ""; } }
            if (rawMsg != null && rawMsg != "") {
                if (rawMsg.length() > 40) { rawMsg = rawMsg.substring(0, 40) + "..."; }
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, cy - 100, Graphics.FONT_SMALL, rawMsg, jc);
            }
        } catch (e) {}

        WatchUi.requestUpdate();
    }
}

// Heading / GS quick-info (shown before wind/temp)
class VFRQuickInfoHdgGsView extends WatchUi.View {
    private var _main as VFRStopWatchView;
    private var _bigFont as Graphics.VectorFont? = null;
    function initialize(main as VFRStopWatchView) {
        View.initialize();
        _main = main;
    }
    function onShow() as Void { WatchUi.requestUpdate(); }
    function onLayout(dc as Dc) as Void { }
    function onUpdate(dc as Dc) as Void {
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
        try { System.println("QuickInfoHDG: sepR=" + sepR.toString() + " cx=" + cx.toString() + " cy=" + cy.toString() + " w=" + w.toString() + " h=" + h.toString()); } catch (e) {}
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
        try {
            var hdg = VFRHeading.getHeadingDeg();
            if (hdg >= 0) {
                var hdgInt = Math.round(hdg).toNumber();
                if (hdgInt < 10)       { hdgStr = "00" + hdgInt.toString(); }
                else if (hdgInt < 100) { hdgStr = "0"  + hdgInt.toString(); }
                else                   { hdgStr = hdgInt.toString(); }
            }
        } catch (ex) {}

        var gsStr = "--";
        try {
            var actInfoLocal = Activity.getActivityInfo();
            if (actInfoLocal != null && actInfoLocal.currentSpeed != null) {
                gsStr = ((actInfoLocal.currentSpeed as Float) * 1.94384).toNumber().toString();
            }
        } catch (ex) {}

        // Draw labels and values
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 60, Graphics.FONT_SMALL, "HDG", jc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 20, bigFont, hdgStr, jc);

        // Draw GS value above its label (label below digits), nudged down 5px
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 25, bigFont, gsStr + " kt", jc);
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 65, Graphics.FONT_SMALL, "GS", jc);

        WatchUi.requestUpdate();
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
        } catch (ex) { System.println("Failed to push wind/temp view: " + ex.getErrorMessage()); }
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
                    System.println("Map push failed: " + ex.getErrorMessage());
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
        } catch (ex) { System.println("Failed to push weather2 view: " + ex.getErrorMessage()); }

        // Fallback: if maps are available, push the map view
        if (WatchUi has :MapView) {
            try {
                var mapView = new VFRMapView(_main);
                WatchUi.pushView(mapView, new VFRMapDelegate(_main, mapView), WatchUi.SLIDE_IMMEDIATE);
            } catch (ex) {
                System.println("Map push failed: " + ex.getErrorMessage());
            }
        }
        return true;
    }
}
