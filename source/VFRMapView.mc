import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// VFRMapView – north-up map that follows the aircraft's GPS position.
//
// MapTrackView (the auto-tracking subclass) was tried first but caused
// crashes on the real device because pushView throws UnexpectedTypeException
// for any MapView subclass if the visible area parameters are ever considered
// invalid.  To be safe we use plain MapView + call setMapVisibleArea before
// the push in initialize(), with a wide fallback area when GPS is unavailable.
//
// Track-up rotation is NOT possible via the Connect IQ MapView API —
// confirmed in the official docs; there is no setHeading() or rotation method.
class VFRMapView extends WatchUi.MapView {
    private var _timer as Timer.Timer?;
    private var _main  as VFRStopWatchView;

    // Five zoom levels: dLat in degrees (half bounding-box height).
    // Smaller = more zoomed in.  Level 2 (0.009 ≈ 1 km) is the default.
    private const ZOOM_LEVELS = [0.002, 0.005, 0.009, 0.020, 0.050];
    private var _zoomIdx as Number = 2; // start at level 2

    function initialize(main as VFRStopWatchView) {
        MapView.initialize();
        _main  = main;
        _timer = null;
        _zoomIdx = 2;
        // MUST call both setMapVisibleArea AND setScreenVisibleArea before pushView.
        // Restrict the map to the inner circle so the bezel can be drawn over the annulus.
        var settings = System.getDeviceSettings();
        var sw = settings.screenWidth;
        var sh = settings.screenHeight;
        var minWh = sw < sh ? sw : sh;
        var radiusInner = (minWh / 2) - 26; // matches drawBezelBackground: R-2-24
        var ix = sw / 2 - radiusInner;
        var iy = sh / 2 - radiusInner;
        setScreenVisibleArea(ix, iy, radiusInner * 2, radiusInner * 2);
        _updateArea();
        setMapMode(WatchUi.MAP_MODE_BROWSE);
    }

    // Advance to the next zoom level (wraps back to 0 after the last).
    function cycleZoom() as Void {
        _zoomIdx = (_zoomIdx + 1) % ZOOM_LEVELS.size();
        _updateArea();
        WatchUi.requestUpdate();
    }

    function onShow() as Void {
        var t = new Timer.Timer();
        _timer = t;
        t.start(method(:onTick), 3000, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    // Re-centre every 3 s as the aircraft moves.
    // setMapVisibleArea() is NOT called from onUpdate() — docs warn it causes flicker.
    function onTick() as Void {
        _updateArea();
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        // 1. Draw bezel background (clears screen to black, draws annulus labels + ring).
        // 2. MapView renders the map only within the inner-circle visible area set in initialize().
        // 3. Heading arrow drawn on top.
        _main.drawBezelBackground(dc);
        MapView.onUpdate(dc);
        _drawHeadingArrow(dc);
    }

    // Draw a filled arrow + short tail at screen centre pointing in GPS heading direction.
    // If heading is unknown, draw a simple + cross instead.
    function _drawHeadingArrow(dc as Graphics.Dc) as Void {
        var cx = dc.getWidth()  / 2;
        var cy = dc.getHeight() / 2;

        var hdgRad = 0.0;
        var hasHdg = false;
        var hdgDeg = VFRHeading.getHeadingDeg();
        if (hdgDeg >= 0) {
            hdgRad = (hdgDeg * (Math.PI / 180.0)).toFloat();
            hasHdg = true;
        }

        dc.setPenWidth(2);

        if (!hasHdg) {
            // No heading data — draw a white cross
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx - 10, cy, cx + 10, cy);
            dc.drawLine(cx, cy - 10, cx, cy + 10);
            return;
        }

        // Heading (GPS course converted to radians): 0 = north, clockwise positive.
        // Screen convention: north = up, so:
        //   nose direction  = (sin(hdg), -cos(hdg))
        //   wing direction  = (cos(hdg),  sin(hdg))
        var sinH = Math.sin(hdgRad).toFloat();
        var cosH = Math.cos(hdgRad).toFloat();

        var noseLen = 22; // nose tip distance from centre
        var tailLen = 14; // tail distance from centre
        var wingW   = 10; // half-wingspan of arrowhead

        // Nose tip
        var noseX = cx + (sinH * noseLen).toNumber();
        var noseY = cy - (cosH * noseLen).toNumber();

        // Tail centre point (back from centre)
        var tailX = cx - (sinH * tailLen).toNumber();
        var tailY = cy + (cosH * tailLen).toNumber();

        // Arrowhead base corners (wing tips, set back from nose by wingW * 0.9)
        var baseBackLen = wingW * 0.9;
        var baseCx = cx + (sinH * (noseLen - baseBackLen)).toNumber();
        var baseCy = cy - (cosH * (noseLen - baseBackLen)).toNumber();
        var wL_x = baseCx - (cosH * wingW).toNumber();
        var wL_y = baseCy - (sinH * wingW).toNumber();
        var wR_x = baseCx + (cosH * wingW).toNumber();
        var wR_y = baseCy + (sinH * wingW).toNumber();

        // Draw filled yellow arrowhead (nose + two wing tips)
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[noseX, noseY], [wL_x, wL_y], [wR_x, wR_y]]);

        // Draw tail line (stem)
        dc.drawLine(cx, cy, tailX, tailY);

        // Thin black outline on the arrowhead for contrast over light map tiles
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(noseX, noseY, wL_x, wL_y);
        dc.drawLine(noseX, noseY, wR_x, wR_y);
        dc.drawLine(wL_x, wL_y, wR_x, wR_y);
    }

    // Re-centre the map on the current GPS fix.
    // If GPS is unavailable use a wide global fallback so the visible area is
    // always valid and pushView never throws.
    function _updateArea() as Void {
        var lat  = 0.0;
        var lon  = 0.0;
        var dLat = 45.0; // wide fallback (~5000 km) when no GPS
        var dLon = 45.0;

        try {
            var pInfo = Position.getInfo();
            if (pInfo != null && pInfo.position != null) {
                var deg = pInfo.position.toDegrees();
                lat  = deg[0].toFloat();
                lon  = deg[1].toFloat();
                dLat = ZOOM_LEVELS[_zoomIdx];
                var cosL = Math.cos(lat * Math.PI / 180.0);
                if (cosL < 0.001) { cosL = 0.001; }
                dLon = dLat / cosL;
            }
            setMapVisibleArea(
                new Position.Location({
                    :latitude  => lat + dLat,
                    :longitude => lon - dLon,
                    :format    => :degrees
                }),
                new Position.Location({
                    :latitude  => lat - dLat,
                    :longitude => lon + dLon,
                    :format    => :degrees
                })
            );
        } catch (ex) {
            System.println("VFRMapView _updateArea: " + ex.getErrorMessage());
        }
    }
}

// Delegate: BACK/SELECT pops the map; UP (onPreviousPage) cycles zoom.
class VFRMapDelegate extends WatchUi.BehaviorDelegate {
    private var _view as VFRMapView;
    private var _main as VFRStopWatchView;

    function initialize(main as VFRStopWatchView, view as VFRMapView) {
        BehaviorDelegate.initialize();
        _view = view;
        _main = main;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        return true;
    }

    function onSelect() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        return true;
    }

    // UP button — cycle through 5 zoom levels
    function onPreviousPage() as Boolean {
        _view.cycleZoom();
        return true;
    }

    // DOWN (next page) — close map and the quick-info stack, returning to stopwatch
    function onNextPage() as Boolean {
        try {
            // Pop the map view itself
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            // Pop any remaining quick-info views (hdg, weather1, weather2)
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            // Mark quick-info as closed
            try { _main.quickInfoShown = false; } catch (e) {}
        } catch (ex) {
            System.println("Error popping quick-info stack: " + ex.getErrorMessage());
        }
        return true;
    }
}
