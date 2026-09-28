import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Time;
import Toybox.Weather;

class VFRQnhInfo {
    var hPa as Float;
    var isQnh as Boolean;

    function initialize(value as Float, sourceIsQnh as Boolean) {
        hPa = value;
        isQnh = sourceIsQnh;
    }
}

class VFRAvionicsData {
    static function readQnhInfo() as VFRQnhInfo? {
        try {
            var wcur = Weather.getCurrentConditions();
            if (wcur != null && wcur.pressure != null) {
                var fresh = true;
                try {
                    if ((wcur has :observationTime) && wcur.observationTime != null) {
                        var ageSec = Time.now().value() - wcur.observationTime.value();
                        if (ageSec > 1800) { fresh = false; }
                    }
                } catch (te) { }
                if (fresh) {
                    return new VFRQnhInfo(VFRAvionicsData.pressureToHpa(wcur.pressure), true);
                }
            }
        } catch (we) { }

        try {
            var sInfo = Sensor.getInfo();
            if (sInfo != null && (sInfo has :pressure) && sInfo.pressure != null) {
                return new VFRQnhInfo(VFRAvionicsData.pressureToHpa(sInfo.pressure), false);
            }
        } catch (se) { }

        return null;
    }

    static function pressureToHpa(rawPressure as Object) as Float {
        var value = (rawPressure as Float).toFloat();
        if (value > 5000.0) { value = value / 100.0; }
        return value;
    }

    static function readAltitudeFeet() as Number? {
        // Barometric (QNH) altitude is preferred. When the device (or simulator)
        // reports no baro altitude, fall back to GPS altitude so AGL-based
        // features (landing counter, circuit practice) still work. Field
        // elevation is captured through this same function, so the AGL datum
        // stays consistent even when falling back to GPS.
        try {
            var sInfo = Sensor.getInfo();
            if (sInfo != null && sInfo.altitude != null) {
                return ((sInfo.altitude as Float) * 3.28084).toNumber();
            }
        } catch (se) { }
        try {
            var pInfo = Position.getInfo();
            if (pInfo != null && pInfo.altitude != null) {
                return ((pInfo.altitude as Float) * 3.28084).toNumber();
            }
        } catch (pe) { }
        return null;
    }

    // Pressure altitude in feet referenced to 1013.25 hPa (standard atmosphere).
    // Used for Flight Level display above transition altitude.
    static function readPressureAltitudeFeet() as Number? {
        try {
            var sInfo = Sensor.getInfo();
            if (sInfo != null && (sInfo has :pressure) && sInfo.pressure != null) {
                var hPa = VFRAvionicsData.pressureToHpa(sInfo.pressure);
                var paFt = 145366.45 * (1.0 - Math.pow((hPa / 1013.25), 0.190284));
                return paFt.toNumber();
            }
        } catch (se) { }
        return null;
    }

    static function formatQnh(info as VFRQnhInfo?) as String {
        if (info == null) { return "----"; }
        var value = Math.round((info as VFRQnhInfo).hPa).toNumber().toString();
        if (!(info as VFRQnhInfo).isQnh) { value = value + "S"; }
        if (value.length() > 5) { value = value.substring(0, 5); }
        while (value.length() < 4) { value = "-" + value; }
        return value;
    }
}
