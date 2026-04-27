import Toybox.Position;
import Toybox.Lang;
import Toybox.Math;

class VFRHeading {
    // Returns heading in degrees (0..360) or -1 when unavailable.
    static function getHeadingDeg() as Number {
        try {
            var pInfo = Position.getInfo();
            if (pInfo == null) { return -1; }
            // Use runtime symbol access to avoid compile-time type errors.
            // course (API 5.0+) preferred over heading (deprecated); both in radians.
            var cval = null;
            try { cval = pInfo["course"]; } catch (e) { cval = null; }
            if (cval == null) { try { cval = pInfo["heading"]; } catch (e) { cval = null; } }
            if (cval == null) { return -1; }
            var deg = cval.toFloat() * (180.0 / Math.PI);
            deg = ((deg % 360.0) + 360.0) % 360.0;
            return deg.toNumber();
        } catch (ex) {
            return -1;
        }
    }
}
