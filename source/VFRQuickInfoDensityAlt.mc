import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Density Altitude quick-info screen
class VFRQuickInfoDensityAltView extends WatchUi.View {
    private var _main    as VFRStopWatchView;
    private var _bigFont as Graphics.VectorFont? = null;
    function initialize(main as VFRStopWatchView) {
        View.initialize();
        _main = main;
    }
    function onShow() as Void { WatchUi.requestUpdate(); }
    function onLayout(dc as Dc) as Void { }
    function onUpdate(dc as Dc) as Void {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;
        var jc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        _main.drawBezelBackground(dc);

        var minWh = (w < h) ? w : h;
        var sepR  = ((minWh.toFloat() / 2.0) - 27.0).toNumber();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillCircle(cx, h / 2, sepR);

        if (_bigFont == null) {
            var sz    = (minWh * 0.12).toNumber();
            var faces = ["RobotoCondensed", "Roboto", "RobotoBlack", "Swiss721Bold", "TomorrowBold"];
            for (var fi = 0; fi < faces.size() && _bigFont == null; fi++) {
                try { _bigFont = Graphics.getVectorFont({:face => faces[fi], :size => sz}); } catch (e) {}
            }
        }
        var bigFont = (_bigFont != null) ? _bigFont : Graphics.FONT_NUMBER_HOT;

        // Obtain indicated altitude (ft) and OAT, compute pressure altitude then density altitude
        var densStr = "---";
        var label = "DENS ALT";
        try {
            var indicatedAltFt = null;
            try {
                var s = Sensor.getInfo();
                if (s != null && s.altitude != null) {
                    indicatedAltFt = ((s.altitude as Float) * 3.28084).toNumber();
                }
            } catch (se) { System.println("Density altitude sensor error: " + se.getErrorMessage()); }

            var oat = null;
            try { var wr = VFRWeather.read(getApp().getComms()); if (wr != null && wr.temp != -999) { oat = wr.temp.toFloat(); } } catch (we) { System.println("Density altitude OAT read error: " + we.getErrorMessage()); }

            // QNH from weather provider (preferred). Check freshness if observationTime exists.
            var qnh_hPa = null;
            var haveQnh = false;
            try {
                var wcur = Weather.getCurrentConditions();
                if (wcur != null && wcur.pressure != null) {
                    var fresh = true;
                    try {
                        if ((wcur has :observationTime) && wcur.observationTime != null) {
                            var ageSec = (Time.now().value() - wcur.observationTime.value());
                            if (ageSec > 1800) { fresh = false; }
                        }
                    } catch (te) { System.println("Density altitude QNH staleness check error: " + te.getErrorMessage()); }
                    if (fresh) {
                        qnh_hPa = (wcur.pressure as Float) / 100.0;
                        haveQnh = true;
                    }
                }
            } catch (qe) { System.println("Density altitude QNH read error: " + qe.getErrorMessage()); }

            // Only compute if we have indicated altitude and OAT
            if (indicatedAltFt != null && oat != null) {
                var pressureAltFt = null;
                var approx = false;
                if (haveQnh && qnh_hPa != null) {
                    pressureAltFt = (indicatedAltFt + ((1013.0 - qnh_hPa) * 27.0)).toFloat();
                } else {
                    // No QNH available: pressure altitude approximated by indicated altitude
                    pressureAltFt = indicatedAltFt.toFloat();
                    approx = true;
                }

                // Compute density altitude from (pressure) altitude and OAT
                try {
                    var altThousands = (pressureAltFt / 1000.0).toFloat();
                    var isa = (15.0 - (2.0 * altThousands)).toFloat();
                    var diff = (oat - isa).toFloat();
                    var dens = (pressureAltFt + (120.0 * diff)).toFloat();
                    densStr = Math.round(dens).toNumber().toString() + " ft";
                    if (approx) { label = "DENS ALT*"; } else { label = "DENS ALT"; }
                } catch (ce) { System.println("Density altitude compute error: " + ce.getErrorMessage()); densStr = "---"; }
            } else {
                densStr = "---";
            }

        } catch (e) { System.println("Density altitude error: " + e.getErrorMessage()); densStr = "---"; }

        // Draw only label and the integer feet value centered
        var y = (h / 2) - 18;
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_SMALL, "DENSITY ALT", jc);
        y += 30;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, bigFont, densStr, jc);

        WatchUi.requestUpdate();
    }
}

class VFRQuickInfoDensityAltDelegate extends WatchUi.BehaviorDelegate {
    private var _main as VFRStopWatchView;
    function initialize(main as VFRStopWatchView) {
        BehaviorDelegate.initialize();
        _main = main;
    }
    function onBack() as Boolean {
        try { _main.quickInfoShown = false; } catch (ex) {}
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
    function onSelect() as Boolean { return onBack(); }
    function onKeyPressed(keyEvent as WatchUi.KeyEvent) as Boolean { return false; }
    function onKeyReleased(keyEvent as WatchUi.KeyEvent) as Boolean {
        if (keyEvent.getKey() == WatchUi.KEY_DOWN) { return true; }
        return false;
    }
    function onNextPage() as Boolean {
        // After density-alt screen, fall back to map if available
        if (WatchUi has :MapView) {
            try {
                var mapView = new VFRMapView(_main);
                WatchUi.pushView(mapView, new VFRMapDelegate(_main, mapView), WatchUi.SLIDE_IMMEDIATE);
            } catch (ex) { }
        }
        return true;
    }
}
