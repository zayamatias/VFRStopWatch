import Toybox.Lang;
import Toybox.Math;
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
        try {
            var sInfo = Sensor.getInfo();
            if (sInfo != null && sInfo.altitude != null) {
                return ((sInfo.altitude as Float) * 3.28084).toNumber();
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
