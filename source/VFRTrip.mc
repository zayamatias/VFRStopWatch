import Toybox.Math;
import Toybox.Lang;
import Toybox.System;

// Stores a flight plan received from the companion app.
// Computes bearing, distance and ETE to the active waypoint.
//
// Companion app sends a "trip" message with this structure:
//   { "type": "trip",
//     "name": "LERGA-LEAL",          // optional
//     "waypoints": [
//       { "name": "LERGA", "lat": 40.123, "lon": -3.456, "alt_ft": 2500 },
//       { "name": "VOR-X", "lat": 40.456, "lon": -3.789, "alt_ft": 3500 },
//       { "name": "LEAL",  "lat": 40.789, "lon": -4.123, "alt_ft": 0   }
//     ]
//   }
// To clear the active plan: { "type": "trip_clear" }

class VFRTrip {

    var tripName  as String  = "";
    var count     as Number  = 0;
    var activeIdx as Number  = 0;
    var active    as Boolean = false;

    // Parallel arrays, one entry per waypoint (lat/lon in decimal degrees)
    var wpLat   as Array = [];
    var wpLon   as Array = [];
    var wpAltFt as Array = [];   // feet MSL; 0 = no altitude constraint
    var wpName  as Array = [];

    // Last computed values; updated by updateFromPosition()
    var bearingDeg as Number = -1;    // required track to active WP (0-359)
    var distanceNm as Float  = -1.0;  // distance to active WP in nm
    var eteSec     as Number = -1;    // ETE in seconds; -1 = no valid GS

    function initialize() {}

    // ── Load from companion app message ─────────────────────────────────────

    function loadFromMessage(d as Dictionary) as Boolean {
        try {
            var wps = d["waypoints"];
            if (!(wps instanceof Lang.Array)) { return false; }
            var arr = wps as Array;
            var n   = arr.size();
            if (n < 1 || n > 20) { return false; }

            var lats  = new [n];
            var lons  = new [n];
            var alts  = new [n];
            var names = new [n];

            for (var i = 0; i < n; i++) {
                var wp = arr[i];
                if (!(wp instanceof Lang.Dictionary)) { return false; }
                var w = wp as Dictionary;

                lats[i] = VFRTrip.coerceFloat(w["lat"], 0.0);
                lons[i] = VFRTrip.coerceFloat(w["lon"], 0.0);

                try {
                    var a = w["alt_ft"];
                    alts[i] = (a != null) ? (a as Number).toNumber() : 0;
                } catch (e) { alts[i] = 0; }

                try {
                    var nm = w["name"];
                    names[i] = (nm != null) ? nm.toString() : ("WP" + (i + 1).toString());
                } catch (e) { names[i] = "WP" + (i + 1).toString(); }
            }

            // Commit
            wpLat   = lats;
            wpLon   = lons;
            wpAltFt = alts;
            wpName  = names;
            count     = n;
            activeIdx = 0;
            active    = true;

            try {
                var tn = d["name"];
                tripName = (tn != null) ? tn.toString() : "";
            } catch(e) { tripName = ""; }

            _resetCache();
            System.println("VFRTrip: loaded " + n.toString() + " WPs, name=" + tripName);
            return true;
        } catch (ex) {
            System.println("VFRTrip load error: " + ex.getErrorMessage());
            return false;
        }
    }

    // ── Live navigation update ───────────────────────────────────────────────

    // Recompute bearing, distance and ETE from current GPS position and GS.
    // curLat/curLon in decimal degrees; gsKt in knots.
    function updateFromPosition(curLat as Float, curLon as Float, gsKt as Float) as Void {
        if (!active || count == 0 || activeIdx >= count) { return; }

        var tLat = (wpLat[activeIdx] as Float).toFloat();
        var tLon = (wpLon[activeIdx] as Float).toFloat();

        var d2r  = Math.PI / 180.0;
        var r2d  = 180.0 / Math.PI;

        var rlat1 = curLat * d2r;
        var rlat2 = tLat   * d2r;
        var dLon  = (tLon - curLon) * d2r;

        // Great-circle bearing
        var y   = Math.sin(dLon) * Math.cos(rlat2);
        var x   = Math.cos(rlat1) * Math.sin(rlat2)
                - Math.sin(rlat1) * Math.cos(rlat2) * Math.cos(dLon);
        var brg = Math.atan2(y, x).toFloat() * r2d;
        // atan2 → [-180, 180]; add 360 then mod (integer) to normalise to [0, 360)
        bearingDeg = ((brg + 360.0).toNumber()) % 360;

        // Haversine distance (nm)
        var dLat     = (tLat - curLat) * d2r;
        var sinDLat  = Math.sin(dLat / 2.0);
        var sinDLon2 = Math.sin(dLon / 2.0);
        var a = sinDLat * sinDLat
              + Math.cos(rlat1) * Math.cos(rlat2) * sinDLon2 * sinDLon2;
        var c = 2.0 * Math.atan2(Math.sqrt(a), Math.sqrt(1.0 - a));
        distanceNm = (3440.065 * c).toFloat();

        // ETE (seconds)
        if (gsKt > 5.0) {
            eteSec = ((distanceNm / gsKt) * 3600.0).toNumber();
        } else {
            eteSec = -1;
        }
    }

    // ── Waypoint navigation ──────────────────────────────────────────────────

    // Advance to next waypoint. Returns false if already at last WP.
    function advanceWaypoint() as Boolean {
        if (activeIdx < count - 1) {
            activeIdx++;
            _resetCache();
            return true;
        }
        return false;
    }

    // Step back to previous waypoint. Returns false if already at first WP.
    function previousWaypoint() as Boolean {
        if (activeIdx > 0) {
            activeIdx--;
            _resetCache();
            return true;
        }
        return false;
    }

    // Clear the trip entirely.
    function clear() as Void {
        active    = false;
        count     = 0;
        activeIdx = 0;
        tripName  = "";
        wpLat = []; wpLon = []; wpAltFt = []; wpName = [];
        _resetCache();
    }

    // ── Accessors ────────────────────────────────────────────────────────────

    function getActiveName() as String {
        if (!active || count == 0 || activeIdx >= count) { return "--"; }
        return wpName[activeIdx].toString();
    }

    function getActiveAltFt() as Number {
        if (!active || count == 0 || activeIdx >= count) { return 0; }
        return (wpAltFt[activeIdx] as Number).toNumber();
    }

    // ── Private ──────────────────────────────────────────────────────────────

    // JSON payloads may encode lat/lon as any numeric type (Number, Long, Float
    // or Double) depending on whether the value is integral. Normalise to Float
    // instead of a hard `as Float` cast that throws on integer/Double values.
    private static function coerceFloat(v as Object?, fallback as Float) as Float {
        if (v == null) { return fallback; }
        if (v instanceof Float)  { return (v as Float).toFloat(); }
        if (v instanceof Double) { return (v as Double).toFloat(); }
        if (v instanceof Number) { return (v as Number).toFloat(); }
        if (v instanceof Long)   { return (v as Long).toFloat(); }
        return fallback;
    }

    private function _resetCache() as Void {
        bearingDeg = -1;
        distanceNm = -1.0;
        eteSec     = -1;
    }
}
