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
    //
    // Split into small helpers: one oversized method here (many locals plus many
    // string literals) was the documented cause of an intermittent "Unexpected
    // Type Error / Failed invoking <symbol>" crash — first triggered when the
    // WIND page (the first weather-driven page) was drawn on the watch.
    static function read(comms) as VFRWeatherResult {
        var r = new VFRWeatherResult();
        VFRWeather.readComms(comms, r);
        if ((r.windDir < 0 || r.windSpd < 0 || r.temp == -999)) {
            try {
                var cur = Weather.getCurrentConditions();
                if (cur != null) {
                    VFRWeather.readProviderDict(cur, r);
                    VFRWeather.readProviderDot(cur, r);
                }
            } catch (wex) { }
        }
        VFRWeather.estimateCloudBase(r);
        return r;
    }

    // Copy phone-provided (companion app) values into the result, when present.
    static function readComms(comms, r as VFRWeatherResult) as Void {
        if (comms == null) { return; }
        try { r.windDir = comms.windDirDeg; } catch (e) {}
        try { r.windSpd = comms.windSpeedKt; } catch (e) {}
        try { r.temp    = comms.tempC; } catch (e) {}
        try { r.dew     = comms.dewpointC; } catch (e) {}
    }

    // Dictionary-style access, tried first because the simulator and some
    // providers hand back a raw Dictionary rather than a typed object.
    static function readProviderDict(cur, r as VFRWeatherResult) as Void {
        try { var t = cur["temperature"]; if (t != null) { r.temp = t as Number; } } catch (e) { }

        var ws = null;
        try { ws = cur["windSpeed"]; } catch (e2) { try { ws = cur["wind_speed"]; } catch (e3) { ws = null; } }
        if (ws == null) { try { ws = cur["windspd"]; } catch (e4) { ws = null; } }
        if (ws != null) {
            var kt = VFRWeather.msToKt(ws);
            if (kt >= 0) { r.windSpd = kt; }
        }

        try { var wd = cur["windBearing"]; if (wd != null) { r.windDir = wd as Number; } }
            catch (e5) { try { var wd2 = cur["wind_bearing"]; if (wd2 != null) { r.windDir = wd2 as Number; } } catch (e6) {} }
        try { var dp = cur["dewPoint"]; if (dp != null) { r.dew = dp as Number; } }
            catch (e7) { try { var dp2 = cur["dew_point"]; if (dp2 != null) { r.dew = dp2 as Number; } } catch (e8) {} }
        try { var cc = cur["cloudCover"]; if (cc != null) { r.cloudCover = cc as Number; } } catch (e9) {}
        try { var cb = cur["cloudBase"]; if (cb != null) { r.cloudAlt = cb as Number; } }
            catch (e10) { try { var cb2 = cur["cloudAltitude"]; if (cb2 != null) { r.cloudAlt = cb2 as Number; } } catch (e11) {} }
        try { var pc = cur["precipitationChance"]; if (pc != null) { r.precipChance = pc as Number; } } catch (e12) {}
        try { var cd = cur["condition"]; if (cd != null) { r.condition = cd as Number; } } catch (e13) {}
    }

    // Dot-property access, used for the fields the dictionary pass left unknown.
    static function readProviderDot(cur, r as VFRWeatherResult) as Void {
        try { if (r.temp == -999) { var t = cur.temperature; if (t != null) { r.temp = t as Number; } } } catch (e) {}
        try { if (r.windSpd < 0) { var ws = cur.windSpeed; if (ws != null) { var kt = VFRWeather.msToKt(ws); if (kt >= 0) { r.windSpd = kt; } } } } catch (e) {}
        try { if (r.windDir < 0) { var wd = cur.windBearing; if (wd != null) { r.windDir = wd as Number; } } } catch (e) {}
        try { if (r.dew == -999) { var dp = cur.dewPoint; if (dp != null) { r.dew = dp as Number; } } } catch (e) {}
        try { if (r.cloudCover < 0) { var cc = cur.cloudCover; if (cc != null) { r.cloudCover = cc as Number; } } } catch (e) {}
        try { if (r.precipChance < 0) { var pc = cur.precipitationChance; if (pc != null) { r.precipChance = pc as Number; } } } catch (e) {}
        try { if (r.condition < 0) { var cd = cur.condition; if (cd != null) { r.condition = cd as Number; } } } catch (e) {}
    }

    // Convert a wind-speed value (m/s) to knots, accepting Float or Number input.
    // Returns -1 when the value cannot be interpreted.
    static function msToKt(value as Object) as Number {
        try { return ((value as Float) * 1.943844).toNumber(); }
        catch (e) {
            try { return (((value as Number).toFloat()) * 1.943844).toNumber(); }
            catch (e2) { return -1; }
        }
    }

    // If the provider did not supply a cloud base, estimate it with the simple
    // formula (feet AGL): (Temp - DewPoint) * 400. Stored in metres to match
    // the other consumers. Only computed when both temp and dew are known.
    static function estimateCloudBase(r as VFRWeatherResult) as Void {
        try {
            if (r.cloudAlt < 0 && r.temp != -999 && r.dew != -999) {
                var delta = (r.temp - r.dew).toFloat();
                if (delta > 0.0) {
                    var cloudBaseFt = (delta * 400.0).toFloat();
                    var cloudBaseM = (cloudBaseFt / 3.28084).toNumber();
                    r.cloudAlt = cloudBaseM;
                }
            }
        } catch (ce) { }
    }

    // Convenience: read using getApp().getComms()
    static function readDefault() as VFRWeatherResult {
        // Do not trigger companion requests; read only from comms (if it
        // contains cached values) or fall back to the system provider.
        return VFRWeather.read(getApp().getComms());
    }
}
