import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.WatchUi;

// Displays the active flight plan: required track, distance and ETE
// to the currently active waypoint.
//
// Navigation:
//   UP    → previous waypoint
//   DOWN  → next waypoint
//   BACK  → return to main stopwatch view
//
// Push with: WatchUi.pushView(new VFRTripView(), new VFRTripDelegate(), WatchUi.SLIDE_LEFT)

class VFRTripView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {}

    function onUpdate(dc as Dc) as Void {
        var now = System.getTimer();
        try { var c = Application.getApp().getComms(); if (c != null) { c.tick(now); } } catch (ce) {}
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var jc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var trip = getApp().getTrip();
        if (trip == null || !trip.active) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 14, Graphics.FONT_MEDIUM, "No Flight Plan", jc);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 16, Graphics.FONT_TINY, "Send from companion app", jc);
            return;
        }

        // ── Refresh navigation data from current GPS + GS ────────────────────
        try {
            var pos = Position.getInfo();
            if (pos != null && pos.accuracy != null && (pos.accuracy as Number) >= 3
                    && pos.position != null) {
                var degs = pos.position.toDegrees();
                if (degs != null && degs.size() >= 2) {
                    var lat  = (degs[0] as Double).toFloat();
                    var lon  = (degs[1] as Double).toFloat();
                    var gsKt = 0.0;
                    var ai   = Activity.getActivityInfo();
                    if (ai != null && ai.currentSpeed != null) {
                        gsKt = ((ai.currentSpeed as Float) * 1.94384).toFloat();
                    }
                    trip.updateFromPosition(lat, lon, gsKt);
                }
            }
        } catch (e) {}

        // ── Trip name (top) ───────────────────────────────────────────────────
        if (!trip.tripName.equals("")) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, 22, Graphics.FONT_TINY, trip.tripName, jc);
        }

        // ── WP index + name ───────────────────────────────────────────────────
        var wpLabel = "WP " + (trip.activeIdx + 1).toString() + "/" + trip.count.toString();
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 48, Graphics.FONT_SMALL, wpLabel, jc);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 74, Graphics.FONT_MEDIUM, trip.getActiveName(), jc);

        // ── Required track (large, centre) ───────────────────────────────────
        var brgStr = "---";
        if (trip.bearingDeg >= 0) {
            var b = trip.bearingDeg;
            brgStr = (b < 10)  ? ("00" + b.toString())
                   : (b < 100) ? ("0"  + b.toString())
                   :              b.toString();
        }
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 8, Graphics.FONT_NUMBER_HOT, brgStr + "\u00B0", jc);

        // ── Distance ─────────────────────────────────────────────────────────
        var distStr = "--.- nm";
        if (trip.distanceNm >= 0.0) {
            var di = trip.distanceNm.toNumber();
            var dd = ((trip.distanceNm - di.toFloat()) * 10.0).toNumber();
            if (dd < 0) { dd = 0; }
            distStr = di.toString() + "." + dd.toString() + " nm";
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 58, Graphics.FONT_SMALL, distStr, jc);

        // ── ETE ───────────────────────────────────────────────────────────────
        var eteStr = "ETE --:--";
        if (trip.eteSec >= 0) {
            var em = trip.eteSec / 60;
            var es = trip.eteSec % 60;
            eteStr = "ETE "
                   + (em < 10 ? "0" + em.toString() : em.toString()) + ":"
                   + (es < 10 ? "0" + es.toString() : es.toString());
        }
        dc.setColor(0x00FFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 82, Graphics.FONT_SMALL, eteStr, jc);

        // ── Target altitude ───────────────────────────────────────────────────
        var altFt = trip.getActiveAltFt();
        if (altFt > 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h - 22, Graphics.FONT_TINY, "ALT " + altFt.toString() + " ft", jc);
        }

        // ── Prev / Next waypoint arrows ───────────────────────────────────────
        if (trip.activeIdx > 0) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(14, cy, Graphics.FONT_SMALL, "<",
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        if (trip.activeIdx < trip.count - 1) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - 14, cy, Graphics.FONT_SMALL, ">",
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Keep refreshing while this view is shown
        WatchUi.requestUpdate();
    }
}
