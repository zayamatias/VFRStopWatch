import Toybox.Weather;
import Toybox.Lang;
import Toybox.System;

class VFRWeatherResult {
    var temp as Number;
    var windDir as Number;
    var windSpd as Number;
    var dew as Number;
    var cloudCover as Number;
    var cloudAlt as Number;
    var precipChance as Number;
    var condition as Number;

    function initialize() {
        temp = -999;
        windDir = -1;
        windSpd = -1;
        dew = -999;
        cloudCover = -1;
        cloudAlt = -1;
        precipChance = -1;
        condition = -1;
    }
}

class VFRWeather {
    // Read normalized weather values. Prefers `comms` if present, otherwise falls
    // back to Toybox.Weather.getCurrentConditions(). Returns a VFRWeatherResult
    // with sentinels matching existing code: temp=-999, windDir=-1, windSpd=-1, dew=-999.
    static function read(comms) as VFRWeatherResult {
        var r = new VFRWeatherResult();

        // Try comms first (phone-provided) — comms is a VFRPhoneComms object, use dot access
        if (comms != null) {
            try { r.windDir = comms.windDirDeg; } catch (e) {}
            try { r.windSpd = comms.windSpeedKt; } catch (e) {}
            try { r.temp    = comms.tempC; } catch (e) {}
            try { r.dew     = comms.dewpointC; } catch (e) {}
        }

        // If any critical fields missing, fallback to system Weather provider
        if ((r.windDir < 0 || r.windSpd < 0 || r.temp == -999)) {
            try {
                var cur = Weather.getCurrentConditions();
                if (cur != null) {
                    // Try dictionary-style access first (common for simulator/provider)
                    try { r.temp = (cur["temperature"] as Number); } catch (e) { }

                    try {
                        var ws = null;
                        try { ws = cur["windSpeed"]; } catch (e2) { try { ws = cur["wind_speed"]; } catch (e3) { ws = null; } }
                        if (ws == null) { try { ws = cur["windspd"]; } catch (e4) { ws = null; } }
                        if (ws != null) {
                            try { r.windSpd = ((ws as Float) * 1.943844).toNumber(); }
                            catch (e5) { try { r.windSpd = (((ws as Number).toFloat()) * 1.943844).toNumber(); } catch (e6) {} }
                        }
                    } catch (we) { }

                    try { r.windDir = (cur["windBearing"] as Number); } catch (e) { try { r.windDir = (cur["wind_bearing"] as Number); } catch (e7) { } }
                    try { r.dew = (cur["dewPoint"] as Number); } catch (e) { try { r.dew = (cur["dew_point"] as Number); } catch (e8) { } }
                    try { r.cloudCover = (cur["cloudCover"] as Number); } catch (e) { }
                    try { r.cloudAlt = (cur["cloudBase"] as Number); } catch (e) { try { r.cloudAlt = (cur["cloudAltitude"] as Number); } catch (e9) { } }
                    try { r.precipChance = (cur["precipitationChance"] as Number); } catch (e) { }
                    try { r.condition = (cur["condition"] as Number); } catch (e) { }

                    // If dictionary access yielded no results, try dot-property access
                    try { if (r.temp == -999) { r.temp = (cur.temperature as Number); } } catch (e10) { }
                    try { if (r.windSpd < 0) { var wsd = cur.windSpeed; if (wsd != null) { r.windSpd = ((wsd as Float) * 1.943844).toNumber(); } } } catch (e11) { }
                    try { if (r.windDir < 0) { r.windDir = (cur.windBearing as Number); } } catch (e12) { }
                    try { if (r.dew == -999) { r.dew = (cur.dewPoint as Number); } } catch (e13) { }
                    try { if (r.cloudCover < 0) { r.cloudCover = (cur.cloudCover as Number); } } catch (e14) { }
                    try { if (r.precipChance < 0) { r.precipChance = (cur.precipitationChance as Number); } } catch (e16) { }
                    try { if (r.condition < 0) { r.condition = (cur.condition as Number); } } catch (e17) { }
                }
            } catch (wex) { }
        }

        // If cloud base is not provided by the provider, estimate it using
        // the simple formula (feet AGL): (Temp - DewPoint) * 400
        // Store cloudAlt in meters to match other usages (wr.cloudAlt expected
        // to be in meters elsewhere). Only compute when we have valid temp/dew.
        try {
            if ((r.cloudAlt == null || r.cloudAlt < 0) && r.temp != -999 && r.dew != -999) {
                var delta = (r.temp - r.dew).toFloat();
                if (delta > 0.0) {
                    var cloudBaseFt = (delta * 400.0).toFloat();
                    var cloudBaseM = (cloudBaseFt / 3.28084).toNumber();
                    r.cloudAlt = cloudBaseM;
                }
            }
        } catch (ce) { }

        return r;
    }

    // Convenience: read using getApp().getComms()
    static function readDefault() as VFRWeatherResult {
        // Do not trigger companion requests; read only from comms (if it
        // contains cached values) or fall back to the system provider.
        return VFRWeather.read(getApp().getComms());
    }
}
