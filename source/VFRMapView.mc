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

    // Five zoom levels: dLat in degrees (half bounding-box height).
    // Smaller = more zoomed in.  Level 2 (0.009 ≈ 1 km) is the default.
    private const ZOOM_LEVELS = [0.002, 0.005, 0.009, 0.020, 0.050];
    private var _zoomIdx as Number = 2; // start at level 2

    function initialize(main as VFRStopWatchView) {
        MapView.initialize();
        _timer = null;
        _zoomIdx = 2;
        // MUST call both setMapVisibleArea AND setScreenVisibleArea before pushView.
        var settings = System.getDeviceSettings();
        setScreenVisibleArea(0, 0, settings.screenWidth, settings.screenHeight);
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
        MapView.onUpdate(dc);
        _drawHeadingArrow(dc);
    }

    // Draw a filled arrow + short tail at screen centre pointing in GPS heading direction.
    // If heading is unknown, draw a simple + cross instead.
    function _drawHeadingArrow(dc as Graphics.Dc) as Void {
        var cx = dc.getWidth()  / 2;
        var cy = dc.getHeight() / 2;

        var pInfo  = Position.getInfo();
        var hdgRad = 0.0;
        var hasHdg = (pInfo != null && pInfo.heading != null);
        if (hasHdg) {
            hdgRad = pInfo.heading.toFloat();
        }

        dc.setPenWidth(2);

        if (!hasHdg) {
            // No heading data — draw a white cross
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx - 10, cy, cx + 10, cy);
            dc.drawLine(cx, cy - 10, cx, cy + 10);
            return;
        }

        // Heading is in radians, 0 = north, clockwise positive (standard GPS convention).
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

    function initialize(main as VFRStopWatchView, view as VFRMapView) {
        BehaviorDelegate.initialize();
        _view = view;
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
}
