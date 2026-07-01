import Toybox.Position;
import Toybox.Sensor;
import Toybox.Math;
import Toybox.Lang;

class VFRHeading {
    // Hybrid heading: prefer GPS course when moving, then compass when stationary,
    // then compute bearing from successive GPS fixes as last resort.
    // Returns integer degrees 0..359, or -1 when heading is unknown.
    static var lastLat = null;
    static var lastLon = null;

    static function getHeadingDeg() as Number {
        // Gather GPS info once — position reused in fallback step 3.
        var pHeadingRad = null;
        var pSpeed = -1.0;
        var pLat = null;
        var pLon = null;
        try {
            var p = Position.getInfo();
            if (p != null) {
                try { if (p.heading != null) { pHeadingRad = p.heading.toFloat(); } } catch (e) {}
                try { if (p.speed   != null) { pSpeed = p.speed.toFloat(); } } catch (e) {}
                try {
                    if (p.position != null) {
                        var da = p.position.toDegrees();
                        if (da != null && da.size() >= 2) {
                            pLat = da[0].toFloat();
                            pLon = da[1].toFloat();
                        }
                    }
                } catch (e) {}
            }
        } catch (e) {}

        // 1) GPS course (direction of movement) when moving at any meaningful speed
        //    (> 1.5 m/s ≈ 3 kt).  This is "tracking" — actual direction over ground,
        //    not magnetic heading.  Covers both slow taxi and full aviation speed.
        if (pHeadingRad != null && pSpeed > 1.5) {
            var degTrack = (pHeadingRad as Float) * (180.0 / Math.PI);
            return VFRHeading.normalize(degTrack);
        }

        // 2) Compass (sensor) heading — magnetic, used only when stationary or GPS
        //    heading is unavailable.
        try {
            var s = Sensor.getInfo();
            if (s != null) {
                try {
                    if (s.heading != null) {
                        var deg = s.heading.toFloat() * (180.0 / Math.PI);
                        return VFRHeading.normalize(deg);
                    }
                } catch (e) {}
            }
        } catch (e) {}

        // 3) Last-resort: compute bearing from two successive GPS fixes.
        //    Only used when no GPS heading AND compass unavailable.
        //    Guard: require at least ~5 m of movement between fixes to avoid
        //    atan2(0,0) returning north when stationary (which is meaningless).
        if (pLat != null && pLon != null) {
            if (VFRHeading.lastLat != null && VFRHeading.lastLon != null) {
                var dLatDeg = pLat - (VFRHeading.lastLat as Float);
                var dLonDeg = pLon - (VFRHeading.lastLon as Float);
                // ~5 m in degrees at equator ≈ 0.000045°; use 0.00005° as minimum
                var moved = (dLatDeg * dLatDeg) + (dLonDeg * dLonDeg);
                if (moved >= 0.00005 * 0.00005) {
                    var lat1r = (VFRHeading.lastLat as Float) * (Math.PI / 180.0);
                    var lat2r = pLat * (Math.PI / 180.0);
                    var dLonR = dLonDeg * (Math.PI / 180.0);
                    var y = Math.sin(dLonR) * Math.cos(lat2r);
                    var x = Math.cos(lat1r) * Math.sin(lat2r) - Math.sin(lat1r) * Math.cos(lat2r) * Math.cos(dLonR);
                    var bearing = Math.atan2(y, x).toFloat();
                    var deg3 = (bearing * (180.0 / Math.PI)).toFloat();
                    VFRHeading.lastLat = pLat;
                    VFRHeading.lastLon = pLon;
                    return VFRHeading.normalize(deg3);
                }
            }
            // Store current position for next call (don't update if we computed a bearing).
            VFRHeading.lastLat = pLat;
            VFRHeading.lastLon = pLon;
        }

        return -1;
    }

    static function normalize(d as Float) as Number {
        var q = Math.floor(d / 360.0);
        var res = d - (q * 360.0);
        if (res < 0.0) { res = res + 360.0; }
        return res.toNumber();
    }
}
