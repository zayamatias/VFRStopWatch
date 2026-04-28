import Toybox.Position;
import Toybox.Sensor;
import Toybox.Math;
import Toybox.Lang;

class VFRHeading {
    // Hybrid heading: prefer compass, then GPS heading when moving,
    // then compute bearing from successive GPS fixes. Returns degrees 0..360 or -1.
    static var lastLat = null;
    static var lastLon = null;

    static function getHeadingDeg() as Number {
        // 1) Compass (sensor) heading — works when stationary
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

        // 2) GPS-provided heading when moving (use speed threshold)
        try {
            var p = Position.getInfo();
            if (p != null) {
                try {
                    if (p.heading != null && p.speed != null) {
                        if (p.speed.toFloat() > 1.5) { // ~1.5 m/s threshold
                            var deg2 = p.heading.toFloat() * (180.0 / Math.PI);
                            return VFRHeading.normalize(deg2);
                        }
                    }
                } catch (e) {}
            }
        } catch (e) {}

        // 3) Compute bearing from last GPS position to current position
        try {
            var p2 = Position.getInfo();
            if (p2 != null && p2.position != null) {
                var degArr = null;
                try { degArr = p2.position.toDegrees(); } catch (e) { degArr = null; }
                if (degArr != null && degArr.size() >= 2) {
                    var lat = degArr[0].toFloat();
                    var lon = degArr[1].toFloat();

                    if (VFRHeading.lastLat != null && VFRHeading.lastLon != null) {
                        var lat1 = VFRHeading.lastLat * (Math.PI / 180.0);
                        var lat2 = lat * (Math.PI / 180.0);
                        var dLon = (lon - VFRHeading.lastLon) * (Math.PI / 180.0);

                        var y = Math.sin(dLon) * Math.cos(lat2);
                        var x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);
                        var bearing = Math.atan2(y, x).toFloat();
                        var deg3 = (bearing * (180.0 / Math.PI)).toFloat();

                        // update last position for next call
                        VFRHeading.lastLat = lat;
                        VFRHeading.lastLon = lon;

                        return VFRHeading.normalize(deg3);
                    }

                    // store first position and return unavailable
                    VFRHeading.lastLat = lat;
                    VFRHeading.lastLon = lon;
                }
            }
        } catch (e) {}

        return -1;
    }

    static function normalize(d as Float) as Number {
        var q = Math.floor(d / 360.0);
        var res = d - (q * 360.0);
        if (res < 0.0) { res = res + 360.0; }
        return res.toNumber();
    }
}
