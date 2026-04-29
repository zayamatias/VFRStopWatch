import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Additional quick-info: clouds and forecast trend
class VFRQuickInfoWeather2View extends WatchUi.View {
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
        // We'll align content relative to a top-start so it sits closer to the top
        // Adjusted down slightly to avoid being too close to the bezel
        var topStart = 40; // start ~28 px from top
        var jc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        _main.drawBezelBackground(dc);

        // Inner circle background (keep as before)
        var minWh = (w < h) ? w : h;
        var sepR  = ((minWh.toFloat() / 2.0) - 27.0).toNumber();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillCircle(cx, h / 2, sepR);

        // Use a slightly smaller big font to preserve space
        if (_bigFont == null) {
            var sz    = (minWh * 0.14).toNumber(); // reduced from 0.20 -> 0.14
            var faces = ["RobotoCondensed", "Roboto", "RobotoBlack", "Swiss721Bold", "TomorrowBold"];
            for (var fi = 0; fi < faces.size() && _bigFont == null; fi++) {
                try { _bigFont = Graphics.getVectorFont({:face => faces[fi], :size => sz}); } catch (e) {}
            }
        }
        var bigFont = (_bigFont != null) ? _bigFont : Graphics.FONT_NUMBER_HOT;

        // Read normalized weather
        var wr = VFRWeather.read(getApp().getComms());

        // Cloud cover line
        var cloudStr = "--%";
        try { if (wr.cloudCover >= 0) { cloudStr = (wr.cloudCover.toString() + "%"); } } catch (e) {}

        // Cloud base: show in feet
        var cloudAltStr = "--";
        try {
            if (wr.cloudAlt >= 0) {
                var altM = wr.cloudAlt.toFloat();
                var altFt = (altM * 3.28084).toNumber();
                var altInt = Math.floor(altFt).toNumber();
                cloudAltStr = altInt.toString() + " ft";
            }
        } catch (e) {}

        // Forecast trend heuristic: use precipitation chance as proxy
        var trend = "UNCHANGED";
        try {
            if (wr.precipChance >= 0) {
                if (wr.precipChance > 50) { trend = "WORSEN"; }
                else if (wr.precipChance < 20) { trend = "IMPROVE"; }
                else { trend = "UNCHANGED"; }
            }
        } catch (e) {}

        // Layout: place items starting at topStart and spaced compactly
        var y = topStart + 6; // slight inset
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_SMALL, "CLOUDS", jc);

        y += 26;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, bigFont, cloudStr, jc);

        y += 34;
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_SMALL, "BASE", jc);

        y += 26;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, bigFont, cloudAltStr, jc);

        y += 38;
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_SMALL, "TREND", jc);

        y += 22;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_SMALL, trend, jc);

        WatchUi.requestUpdate();
    }
}

class VFRQuickInfoWeather2Delegate extends WatchUi.BehaviorDelegate {
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
    function onKeyPressed(keyEvent as WatchUi.KeyEvent) as Boolean {
        if (keyEvent.getKey() == WatchUi.KEY_DOWN) { return true; }
        return false;
    }
    function onKeyReleased(keyEvent as WatchUi.KeyEvent) as Boolean {
        if (keyEvent.getKey() == WatchUi.KEY_DOWN) {
            var now = System.getTimer();
            if ((now - _main.quickInfoLastNavAt) < 300) { return true; }
            if (WatchUi has :MapView) {
                try {
                    var mapView = new VFRMapView(_main);
                    WatchUi.pushView(mapView, new VFRMapDelegate(_main, mapView), WatchUi.SLIDE_IMMEDIATE);
                } catch (ex) {
                }
            }
            return true;
        }
        return false;
    }
    function onNextPage() as Boolean {
        try {
            _main.quickInfoLastNavAt = System.getTimer();
            WatchUi.pushView(new VFRQuickInfoDensityAltView(_main), new VFRQuickInfoDensityAltDelegate(_main), WatchUi.SLIDE_UP);
            return true;
        } catch (ex) { }

        if (WatchUi has :MapView) {
            try {
                var mapView = new VFRMapView(_main);
                WatchUi.pushView(mapView, new VFRMapDelegate(_main, mapView), WatchUi.SLIDE_IMMEDIATE);
            } catch (ex) { }
        }
        return true;
    }
}
