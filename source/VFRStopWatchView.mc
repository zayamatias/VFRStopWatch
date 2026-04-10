import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Lang;
import Toybox.Attention;
import Toybox.Activity;
import Toybox.Position;
import Toybox.Time;
import Toybox.Time.Gregorian;

class VFRStopWatchView extends WatchUi.View {

    // --- Stopwatch state ---
    var running     as Boolean = false;
    var startTime   as Number  = 0;    // System.getTimer() value at (re)start
    var elapsed     as Number  = 0;    // accumulated ms

    // --- GPS distance accumulation ---
    var lastUpdateTimer  as Number = 0;   // System.getTimer() at last onUpdate
    var totalDistanceM   as Float  = 0.0; // meters accumulated since reset

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

    // --- GPS fix quality (Position.QUALITY_* values 0-4) ---
    // 0=not available, 1=last known, 2=poor/acquiring, 3=usable, 4=good
    var gpsQuality as Number = 0;
    // Last time (System.getTimer()) we received a Position.onPosition callback
    var lastPositionMillis as Number = 0;
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

    function initialize() {
        View.initialize();
    }

    // No XML layout — everything drawn manually
    function onLayout(dc as Dc) as Void {
    }

    // Read the three user-configurable properties and update runtime variables.
    // Safe to call at any time; GPS restart is handled separately by restartGps().
    function loadSettings() as Void {
        // GPS mode
        var rawMode = Application.Properties.getValue("GpsMode");
        gpsMode = (rawMode != null) ? (rawMode as Number) : 3;

        // Timer interval (minutes → ms; 0 = disabled)
        var rawInterval = Application.Properties.getValue("TimerInterval");
        var intervalMin = (rawInterval != null) ? (rawInterval as Number) : 5;
        if (intervalMin < 0) { intervalMin = 0; }
        if (intervalMin > 30) { intervalMin = 30; }
        timerIntervalMs = intervalMin * 60000;

        // Takeoff speed (knots → m/s; 0 = disable auto-start)
        var rawSpeed = Application.Properties.getValue("TakeoffSpeed");
        var speedKts = (rawSpeed != null) ? (rawSpeed as Number) : 30;
        if (speedKts <= 0) {
            AUTO_START_SPEED_MS = -1.0; // sentinel: auto-start disabled
        } else {
            AUTO_START_SPEED_MS = speedKts.toFloat() * 0.514444; // kts → m/s
        }

        // Sync nextVibrateAt default in case loadSettings() is called before first run
        if (!running && timerIntervalMs > 0) {
            nextVibrateAt = timerIntervalMs;
        }
        System.println("loadSettings: gpsMode=" + gpsMode.toString() +
            " timerIntervalMs=" + timerIntervalMs.toString() +
            " AUTO_START_SPEED_MS=" + AUTO_START_SPEED_MS.toString());
    }

    // (Re)start GPS with the current gpsMode setting. Called from onShow and
    // after settings change.
    function restartGps() as Void {
        if (!(Position has :enableLocationEvents)) { return; }
        if (gpsMode == 3 && (Position has :POSITIONING_MODE_AVIATION)) {
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

    // GPS position callback — updates fix quality used for timer colour
    function onPosition(info as Position.Info) as Void {
        // Update cached quality and timestamp so we can detect stale fixes
        if (info != null) {
            if (info.accuracy != null) { gpsQuality = info.accuracy; }
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
        if (autoStartEnabled && !running && AUTO_START_SPEED_MS > 0.0 && actInfo != null) {
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
        var displayNm  = lapMode ? lapNm  : nmAtCheckpoint;
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

        // --- Draw ---
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        // Background: flash red when HR alert active, otherwise black
        if (hrAlertActive && hrFlashOn) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_RED);
        } else {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        }
        dc.clear();

        // --- Build clock strings (UTC and local) ---
        var localTime = System.getClockTime();
        var lh = localTime.hour;
        var lm = localTime.min;
        var lhStr = lh < 10 ? "0" + lh.toString() : lh.toString();
        var lmStr = lm < 10 ? "0" + lm.toString() : lm.toString();
        var ltStr = "LT  " + lhStr + ":" + lmStr;

        var utcMoment = Time.now();
        var utcInfo = Gregorian.utcInfo(utcMoment, Time.FORMAT_SHORT);
        var uh = utcInfo.hour;
        var um = utcInfo.min;
        var uhStr = uh < 10 ? "0" + uh.toString() : uh.toString();
        var umStr = um < 10 ? "0" + um.toString() : um.toString();
        var utcStr = "UTC " + uhStr + ":" + umStr;

        // --- ROW 1 (top): HR — always; red when alert, white when normal ---
        var hrColor = hrAlertActive ? Graphics.COLOR_RED : Graphics.COLOR_WHITE;
        var hrStr = lastHr > 0 ? (lastHr.toString() + " bpm") : "-- bpm";
        dc.setColor(hrColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 9 / 100, Graphics.FONT_SMALL, hrStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // --- ROW 2: NM — blue after checkpoint ---
        if (showDist) {
            var nmInt = displayNm.toNumber();
            var nmDecFloat = displayNm - nmInt.toFloat();
            var nmDec = (nmDecFloat * 10.0).toNumber();
            if (nmDec < 0) { nmDec = 0; }
            var nmStr = nmInt.toString() + "." + nmDec.toString() + " NM";
            dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 20 / 100, Graphics.FONT_SMALL, nmStr,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // --- ROW 3: LT — light gray, always ---
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 31 / 100, Graphics.FONT_SMALL, ltStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // --- ROW 4 (centre): MM:SS stopwatch ---
        dc.setColor(timerColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h / 2, Graphics.FONT_NUMBER_HOT, mStr + ":" + sStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // --- ROW 5: UTC — light gray, always ---
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 73 / 100, Graphics.FONT_SMALL, utcStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // --- ROW 6 (bottom): km — yellow after checkpoint;
        //     or "↓ Settings" hint in initial state ---
        if (showDist) {
            var kmInt = displayKm.toNumber();
            var kmDecFloat = displayKm - kmInt.toFloat();
            var kmDec = (kmDecFloat * 10.0).toNumber();
            if (kmDec < 0) { kmDec = 0; }
            var kmStr = kmInt.toString() + "." + kmDec.toString() + " km";
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 91 / 100, Graphics.FONT_SMALL, kmStr,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (!running && elapsed == 0) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 91 / 100, Graphics.FONT_TINY, "DOWN = Settings",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // --- Phone connection indicator (top-right corner) ---
        // Green "PHN" = fully connected; Yellow "CONN" = handshaking
        var commsIndicator = getApp().getComms();
        if (commsIndicator != null) {
            if (commsIndicator.connected) {
                dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
                dc.drawText(w - 8, h * 9 / 100, Graphics.FONT_TINY, "PHN",
                    Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            } else if (commsIndicator.connecting) {
                dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
                dc.drawText(w - 8, h * 9 / 100, Graphics.FONT_TINY, "CONN",
                    Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        }

        if (running || subTimerState == 1 || hrAlertActive || fuelFlashActive || autoStartEnabled || gpsQuality < 3) {
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

    // Persistable state helpers ------------------------------------------------
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
        var rawGps = Application.Properties.getValue("GpsMode");
        var curGps = (rawGps != null) ? (rawGps as Number) : 3;
        if (curGps < 0 || curGps > 3) { curGps = 3; }
        var gpsLabel = curGps == 0 ? "GPS"
                     : curGps == 1 ? "GPS+GLONASS"
                     : curGps == 2 ? "All Systems"
                     : "Aviation";
        var curTimerMin = timerIntervalMs / 60000;
        var rawSpd = Application.Properties.getValue("TakeoffSpeed");
        var curKts = (rawSpd != null) ? (rawSpd as Number) : 30;
        var menu = new WatchUi.Menu2({:title => "Settings"});
        menu.addItem(new WatchUi.MenuItem("GPS Mode",      gpsLabel,                        "setting_gps",     null));
        menu.addItem(new WatchUi.MenuItem("Timer",         curTimerMin.toString() + " min", "setting_timer",   null));
        menu.addItem(new WatchUi.MenuItem("Takeoff Speed", curKts.toString() + " kts",      "setting_takeoff", null));
        WatchUi.pushView(menu, new VFRSettingsMenuDelegate(self), WatchUi.SLIDE_UP);
    }

    // DOWN button behavior:
    //   initial state (!running, elapsed==0)  → open settings
    //   stopped but has elapsed time          → reset
    //   running                               → toggle lap
    function onDownPressed() as Void {
        if (!running && elapsed == 0) {
            openSettingsMenu();
            System.println("DOWN pressed: open settings (initial state)");
        } else if (!running) {
            reset();
            System.println("DOWN pressed: reset (main stopped)");
        } else {
            lap();
            System.println("DOWN pressed: lap toggled");
        }
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

    function onHide() as Void {
        if (Position has :enableLocationEvents) {
            Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
        }
    }

}
