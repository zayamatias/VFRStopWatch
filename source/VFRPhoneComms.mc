import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
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
        System.println("VFRComms TX ok: " + _msgType);
    }

    function onError() as Void {
        System.println("VFRComms TX err: " + _msgType);
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

    // Pending flight events
    private var _startPayload    as Dictionary? = null;
    private var _stopPayload     as Dictionary? = null;
    private var _startRetryCount as Number      = 0;
    private var _stopRetryCount  as Number      = 0;
    private var _startRetryAt    as Number      = 0;
    private var _stopRetryAt     as Number      = 0;

    function initialize() {
        if (Communications has :registerForPhoneAppMessages) {
            Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
        }
        // Also register the error callback so we can log receive-side failures
        if (Communications has :registerForPhoneAppMessageErrors) {
            Communications.registerForPhoneAppMessageErrors(method(:onPhoneMessageError));
        }
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
        _startRetryAt    = 0;
        System.println("VFRComms: queued start id=" + flightId);
    }

    function sendFlightStop(utcEpochSec as Number) as Void {
        _stopPayload    = { "type"      => "flight_event",
                            "event"     => "stop",
                            "flight_id" => flightId,
                            "ts"        => utcEpochSec };
        _stopRetryCount = 0;
        _stopRetryAt    = 0;
        System.println("VFRComms: queued stop id=" + flightId);
    }

    // Drive the whole state machine — call once per onUpdate frame.
    function tick(now as Number) as Void {
        var reach = _isPhoneReachable();

        // Phone disappeared → fall back to DISC
        if (!reach && _state != STATE_DISC) {
            _state           = STATE_DISC;
            connected        = false;
            connecting       = false;
            _nextHandshakeAt = 0;
            System.println("VFRComms: phone unreachable → DISC");
        }

        if (_state == STATE_DISC) {
            if (reach && now >= _nextHandshakeAt) {
                _state           = STATE_SHAKING;
                connecting       = true;
                _nextHandshakeAt = now + HANDSHAKE_RETRY_MS;
                _txHandshake();
                System.println("VFRComms: handshake sent → SHAKING");
            }

        } else if (_state == STATE_SHAKING) {
            // Resend handshake periodically until ack arrives
            if (now >= _nextHandshakeAt) {
                _nextHandshakeAt = now + HANDSHAKE_RETRY_MS;
                _txHandshake();
                System.println("VFRComms: handshake retry");
            }

        } else if (_state == STATE_CONNECTED) {
            // Periodic keepalive so phone knows watch is still alive
            if (now >= _nextKeepaliveAt) {
                _nextKeepaliveAt = now + KEEPALIVE_MS;
                _tx({ "type" => "keepalive" }, "ka");
            }
        }

        // ── Flight event retries (run regardless of connection state) ────────
        if (_startPayload != null && now >= _startRetryAt) {
            if (_startRetryCount < MAX_RETRIES) {
                _tx(_startPayload as Dictionary, "start");
                _startRetryAt = now + _backoff(_startRetryCount);
                _startRetryCount++;
                System.println("VFRComms: start attempt " + _startRetryCount.toString());
            } else {
                System.println("VFRComms: start gave up after " + MAX_RETRIES.toString());
                _startPayload = null;
            }
        }
        if (_stopPayload != null && now >= _stopRetryAt) {
            if (_stopRetryCount < MAX_RETRIES) {
                _tx(_stopPayload as Dictionary, "stop");
                _stopRetryAt = now + _backoff(_stopRetryCount);
                _stopRetryCount++;
                System.println("VFRComms: stop attempt " + _stopRetryCount.toString());
            } else {
                System.println("VFRComms: stop gave up after " + MAX_RETRIES.toString());
                _stopPayload = null;
            }
        }
    }

    // Called by VFRConnListener when a transmit fails at the BT layer.
    function onTransmitError(msgType as String) as Void {
        System.println("VFRComms TX err: " + msgType);
        if (_state == STATE_CONNECTED) {
            // Assume link dropped; restart handshake immediately
            _state           = STATE_SHAKING;
            connected        = false;
            connecting       = true;
            _nextHandshakeAt = 0;
        } else if (_state == STATE_SHAKING) {
            _nextHandshakeAt = 0; // retry immediately on next tick
        }
    }

    // Incoming message receive error from phone side.
    function onPhoneMessageError(error as Communications.PhoneAppMessageError) as Void {
        System.println("VFRComms RX err: " + error.toString());
    }

    // Incoming message from phone companion app.
    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        var data = msg.data;
        if (!(data instanceof Lang.Dictionary)) { return; }
        var d   = data as Dictionary;
        var typ = d["type"];
        if (typ == null) { return; }

        if (typ.equals("handshake_ack")) {
            _state           = STATE_CONNECTED;
            connected        = true;
            connecting       = false;
            _nextKeepaliveAt = System.getTimer() + KEEPALIVE_MS;
            System.println("VFRComms: CONNECTED (handshake_ack)");

        } else if (typ.equals("flight_ack")) {
            var ev = d["event"];
            if (ev == null) { return; }
            if (ev.equals("start")) {
                _startPayload = null;
                System.println("VFRComms: start ACK");
            } else if (ev.equals("stop")) {
                _stopPayload = null;
                flightId     = "";
                System.println("VFRComms: stop ACK");
            }

        } else if (typ.equals("keepalive_ack")) {
            // Phone is alive; reset keepalive countdown
            _nextKeepaliveAt = System.getTimer() + KEEPALIVE_MS;
        }
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private function _txHandshake() as Void {
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
        try {
            Communications.transmit(data, null, new VFRConnListener(self, msgType));
        } catch (ex) {
            System.println("VFRComms _tx ex: " + ex.getErrorMessage());
        }
    }
}
