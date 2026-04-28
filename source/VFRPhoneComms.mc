import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Application;
using Toybox.System as Sys;

// Transmit result callback — forwards errors back to VFRPhoneComms so the
// state machine can react immediately instead of waiting for the next tick.
class VFRConnListener extends Communications.ConnectionListener {
    private var _comms   as VFRPhoneComms;
    private var _msgType as String;

    function initialize(comms as VFRPhoneComms, msgType as String) {
        ConnectionListener.initialize();
        _comms   = comms;
        _msgType = msgType;
    }

    function onComplete() as Void {
    }

    function onError() as Void {
        _comms.onTransmitError(_msgType);
    }
}

// Watch → Phone messaging with a 3-state connection machine.
//
//  DISC (0)     Phone BT not reachable; retry handshake every 5 s once visible.
//  SHAKING (1)  Handshake sent; resend every 5 s until handshake_ack arrives.
//  CONNECTED(2) Fully connected; send keepalive every 30 s.
//
// Flight events are queued independently and retried with exponential back-off
// (up to MAX_RETRIES attempts) regardless of handshake state.
class VFRPhoneComms {

    // Read by the UI indicator
    var connected  as Boolean = false; // true only when handshake_ack received
    var connecting as Boolean = false; // true while handshaking (yellow dot)
    var flightId   as String  = "";
    // Was phone message callback registered successfully?
    var messagesRegistered as Boolean = false;
    // Whether we've requested weather from the companion since last connect
    var _requestedWeather as Boolean = false;
    // Weather data pushed from phone companion app
    // Sentinels: windDirDeg/windSpeedKt = -1 (unknown), tempC/dewpointC = -999 (unknown)
    var windDirDeg  as Number = -1;
    var windSpeedKt as Number = -1;
    var tempC       as Number = -999;
    var dewpointC   as Number = -999;
    // Last raw weather payload (stringified) for on-device debugging
    var lastRawWeather as String = "";
    // Timestamp (System.getTimer()) of the last handshake transmit attempt
    // UI reads this to detect extended retry/failure (>30s)
    var lastHandshakeAt as Number = 0;

    // State values (treated as constants)
    private var STATE_DISC      as Number = 0;
    private var STATE_SHAKING   as Number = 1;
    private var STATE_CONNECTED as Number = 2;
    private var _state          as Number = 0;

    // Timing (ms)
    private var HANDSHAKE_RETRY_MS as Number = 5000;
    private var KEEPALIVE_MS       as Number = 30000;
    private var MAX_RETRIES        as Number = 10;
    // Backoff schedule: 1 2 4 8 16 30 30 30 30 30 s
    private var _backoffMs as Array = [ 1000, 2000, 4000, 8000, 16000,
                                        30000, 30000, 30000, 30000, 30000 ];

    private var _nextHandshakeAt as Number = 0; // 0 → fire on first tick
    private var _nextKeepaliveAt as Number = 0;
    // Count consecutive connection/transmit errors to apply backoff
    private var _connErrorCount  as Number = 0;

    // Pending flight events
    private var _startPayload    as Dictionary? = null;
    private var _stopPayload     as Dictionary? = null;
    private var _startRetryCount as Number      = 0;
    private var _stopRetryCount  as Number      = 0;
    // -1 = not yet scheduled; set to future timestamp on sendFlight*() call
    private var _startRetryAt    as Number      = -1;
    private var _stopRetryAt     as Number      = -1;

    // Guard: only one Communications.transmit() call per tick to prevent
    // write bursts that cause remote BLE disconnects (reason code 8).
    private var _txThisTick      as Boolean     = false;

    function initialize() {
        if (Communications has :registerForPhoneAppMessages) {
            Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
            messagesRegistered = true;
        }
        // Also register the error callback so we can log receive-side failures
        if (Communications has :registerForPhoneAppMessageErrors) {
            Communications.registerForPhoneAppMessageErrors(method(:onPhoneMessageError));
        }
        try {
            var ds = null;
            try { ds = System.getDeviceSettings(); } catch (e) { ds = null; }
            try { System.println("VFRComms: messagesRegistered=" + messagesRegistered.toString()); } catch (e) { }
            try { System.println("VFRComms: Communications.transmit? " + ((Communications has :transmit) ? "yes" : "no")); } catch (e) { }
            try { System.println("VFRComms: phoneConnected? " + ((ds != null && ds.phoneConnected) ? "yes" : "no")); } catch (e) { }
        } catch (dbgEx) { }
        
        // _nextHandshakeAt = 0 → first tick immediately attempts handshake
    }

    // ── Public API ───────────────────────────────────────────────────────────

    function sendFlightStart(utcEpochSec as Number) as Void {
        flightId = "vfr-" + utcEpochSec.toString() + "-"
                 + (System.getTimer() % 99991).toString();
        _startPayload    = { "type"      => "flight_event",
                             "event"     => "start",
                             "flight_id" => flightId,
                             "ts"        => utcEpochSec };
        _startRetryCount = 0;
        // Schedule first attempt 1 s out so it doesn't collide with any
        // in-flight handshake on the same tick.
        _startRetryAt    = System.getTimer() + 1000;
        
    }

    function sendFlightStop(utcEpochSec as Number) as Void {
        _stopPayload    = { "type"      => "flight_event",
                            "event"     => "stop",
                            "flight_id" => flightId,
                            "ts"        => utcEpochSec };
        _stopRetryCount = 0;
        _stopRetryAt    = System.getTimer() + 1000;
        
    }

    // Drive the whole state machine — call once per onUpdate frame.
    function tick(now as Number) as Void {
        _txThisTick = false; // reset per-tick transmit guard
        var reach = _isPhoneReachable();

        // Phone disappeared → fall back to DISC
        if (!reach && _state != STATE_DISC) {
            _state           = STATE_DISC;
            connected        = false;
            connecting       = false;
            _nextHandshakeAt = 0;
            // Reset one-shot request so a future reconnect will request weather
            _requestedWeather = false;
            
        }

        if (_state == STATE_DISC) {
            if (reach && now >= _nextHandshakeAt) {
                _state           = STATE_SHAKING;
                connecting       = true;
                _nextHandshakeAt = now + HANDSHAKE_RETRY_MS;
                _txHandshake();
                
            }

        } else if (_state == STATE_SHAKING) {
            // Resend handshake periodically until ack arrives
            if (now >= _nextHandshakeAt) {
                _nextHandshakeAt = now + HANDSHAKE_RETRY_MS;
                _txHandshake();
                
            }

        } else if (_state == STATE_CONNECTED) {
            // Periodic keepalive so phone knows watch is still alive.
            // NOTE: some companion apps vibrate on every incoming message.
            // Avoid sending keepalive unless we have pending flight payloads
            // (start/stop) which require the phone to stay responsive.
            if (now >= _nextKeepaliveAt) {
                _nextKeepaliveAt = now + KEEPALIVE_MS;
                if (_startPayload != null || _stopPayload != null) {
                    _tx({ "type" => "keepalive" }, "ka");
                } else {
                    // Skip keepalive to avoid spurious phone-side vibrations.
                    
                }
                // _txThisTick may remain false if we skipped transmit;
                // flight event retries will run on the next tick as usual.
            }
        }

        // ── Flight event retries — only when fully connected ────────────────
        // Sending before handshake_ack creates TX errors that loop back and
        // cause tight reconnect storms (reason code 8 on the Android side).
        if (_state == STATE_CONNECTED && !_txThisTick) {
            if (_startPayload != null && _startRetryAt >= 0 && now >= _startRetryAt) {
                if (_startRetryCount < MAX_RETRIES) {
                    _tx(_startPayload as Dictionary, "start");
                    _startRetryAt = now + _backoff(_startRetryCount);
                    _startRetryCount++;
                    
                } else {
                    
                    _startPayload = null;
                }
            } else if (_stopPayload != null && _stopRetryAt >= 0 && now >= _stopRetryAt) {
                // Use else-if: only one flight event per tick
                if (_stopRetryCount < MAX_RETRIES) {
                    _tx(_stopPayload as Dictionary, "stop");
                    _stopRetryAt = now + _backoff(_stopRetryCount);
                    _stopRetryCount++;
                    
                } else {
                    
                    _stopPayload = null;
                }
            }
        }
    }

    // Called by VFRConnListener when a transmit fails at the BT layer.
    function onTransmitError(msgType as String) as Void {
        // Apply incremental backoff instead of immediate retries to avoid
        // tight connect/disconnect flapping seen on some phones/devices.
        _connErrorCount = (_connErrorCount + 1) as Number;
        var delay = _backoff((_connErrorCount - 1) as Number);
        if (_state == STATE_CONNECTED) {
            // Assume link dropped; go to SHAKING and schedule a backoffed retry
            _state           = STATE_SHAKING;
            connected        = false;
            connecting       = true;
            _nextHandshakeAt = System.getTimer() + delay;
        } else if (_state == STATE_SHAKING) {
            // Schedule next handshake attempt with backoff
            _nextHandshakeAt = System.getTimer() + delay;
        }
    }

    // Incoming message receive error from phone side.
    function onPhoneMessageError(error as Communications.PhoneAppMessageError) as Void {
    }

    // Incoming message from phone companion app.
    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        var data = msg.data;
        if (!(data instanceof Lang.Dictionary)) { return; }
        var d   = data as Dictionary;
        
        // Persist/print raw incoming message for debugging (one-line)
        try {
            var rawAll = d.toString();
            System.println("RAW PHONE MSG: " + rawAll);
            try { VFRLogger.appendRaw("phone", rawAll); } catch (eappend) { }
        } catch (eraw) { }
        var typ = d["type"];
        if (typ == null) { return; }

        if (typ.equals("handshake_ack")) {
            try { System.println("VFRComms: RX handshake_ack"); } catch (e) { }
            _state           = STATE_CONNECTED;
            connected        = true;
            connecting       = false;
            _nextKeepaliveAt = System.getTimer() + KEEPALIVE_MS;
            // Reset transient error counter on successful handshake
            _connErrorCount = 0;
            
            // Companion weather requests disabled: do not ask phone for weather.
            // Mark as requested so we don't attempt to in other code paths.
            try { _requestedWeather = true; } catch (ereq) {}

        } else if (typ.equals("flight_ack")) {
            var ev = d["event"];
            if (ev == null) { return; }
            if (ev.equals("start")) {
                _startPayload = null;
                
            } else if (ev.equals("stop")) {
                _stopPayload = null;
                flightId     = "";
                
            }

        } else if (typ.equals("keepalive_ack")) {
            // Phone is alive; reset keepalive countdown
            _nextKeepaliveAt = System.getTimer() + KEEPALIVE_MS;

        } else if (typ.equals("weather")) {
            // Fully ignore companion-sent weather. Clear any cached raw payload
            // so the app will fall back to the system provider via VFRWeather.
            try { lastRawWeather = ""; } catch (e) { }
            return;
        }
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    // Public API: request weather now if connected, otherwise ensure a
    // request is sent on the next successful handshake.
    function requestWeatherOnNextConnect() as Void {
        // NOOP: phone-based weather requests disabled — use system provider only.
        try { _requestedWeather = false; } catch (e) { }
    }


    private function _txHandshake() as Void {
        // record when we actually attempted the handshake so UI can detect retries
        try { lastHandshakeAt = System.getTimer(); } catch (ex) { lastHandshakeAt = 0; }
        try { System.println("VFRComms: TX handshake"); } catch (e) { }
        _tx({ "type" => "handshake", "app" => "VFRStopWatch", "version" => "1.0" }, "hs");
    }

    private function _backoff(attempt as Number) as Number {
        return (attempt < _backoffMs.size())
            ? (_backoffMs[attempt] as Number)
            : 30000;
    }

    private function _isPhoneReachable() as Boolean {
        try {
            var ds = System.getDeviceSettings();
            return (ds != null) && (ds.phoneConnected as Boolean);
        } catch (ex) { return false; }
    }

    private function _tx(data as Dictionary, msgType as String) as Void {
        if (!(Communications has :transmit)) { return; }
        _txThisTick = true; // mark that we've transmitted this tick
        try {
            Communications.transmit(data, null, new VFRConnListener(self, msgType));
        } catch (ex) {
        }
    }

    // Console-export helper: prints the last N entries stored in
    // Application.Properties to System.println so they can be captured
    // via `monkeydo` logs or device logging tools.
    function exportLogsToConsole(limit as Number) as Void {
        return;
    }

    /*
    // OPTIONAL: Real file write helper using Toybox.Storage.
    // NOTE: This requires the target device/SDK to expose Toybox.Storage.
    // The Connect IQ SDK on this machine does NOT include Toybox.Storage, so
    // importing and enabling this code will fail compilation locally. To
    // enable real on-watch file logging, do the following on your development
    // machine that targets the actual device runtime or a SDK with Storage:
    // 1. Uncomment the `import Toybox.Storage;` at the top of this file.
    // 2. Uncomment this function and call it instead of the Properties fallback.
    // 3. Build & install on-device — the watch will then write a real file
    //    named "VFR_lastRawWeather.log" in the app sandbox (visible to device tools).
    function _appendLogToFileStorage(entry as String) as Boolean {
        try {
            var fname = "VFR_lastRawWeather.log";
            var fh = Storage.open(fname, Storage.MODE_APPEND);
            if (fh == null) { return false; }
            fh.write(entry);
            fh.write("\n");
            fh.close();
            return true;
        } catch (ex) {
            System.println("VFRComms STORAGE write failed: " + ex.getErrorMessage());
            return false;
        }
    }
    */
}
