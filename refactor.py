import sys

with open('source/VFRStopWatchView.mc', 'r') as f:
    src = f.read()

orig_len = len(src)

# ─── CHANGE 1: Replace huge drawing block in onUpdate with drawBezelBackground call ───
# Start: "        // --- Draw (circular/bezel layout) ---"
# End:   "        } catch (iconEx) { }" (first occurrence after start)

DRAW_START = '        // --- Draw (circular/bezel layout) ---\n'
DRAW_END   = '        } catch (iconEx) { }\n'

start_pos = src.find(DRAW_START)
if start_pos == -1: print("ERROR: draw start not found"); sys.exit(1)
end_pos = src.find(DRAW_END, start_pos)
if end_pos == -1: print("ERROR: draw end not found"); sys.exit(1)
end_pos_full = end_pos + len(DRAW_END)

NEW_DRAW_BLOCK = (
    '        // --- Draw (circular/bezel layout) ---\n'
    '        var w  = dc.getWidth();\n'
    '        var h  = dc.getHeight();\n'
    '        var cx = w / 2;\n'
    '        var cy = h / 2;\n'
    '        var minWh = (w < h) ? w : h;\n'
    '        var margin = (minWh * 8) / 100;\n'
    '        var radius = (minWh / 2) - margin;\n'
    '\n'
    '        drawBezelBackground(dc);\n'
    '\n'
)

src = src[:start_pos] + NEW_DRAW_BLOCK + src[end_pos_full:]
print(f"Change 1 OK: replaced {end_pos_full - start_pos} chars with drawBezelBackground call")

# ─── CHANGE 2: Fix drawNow → now in the requestUpdate gate ───
OLD_GATE = '(tendency != 0 && tendencyUntil > drawNow))'
NEW_GATE = '(tendency != 0 && tendencyUntil > now))'
if OLD_GATE not in src:
    print("WARNING: requestUpdate gate already uses 'now' or not found")
else:
    src = src.replace(OLD_GATE, NEW_GATE, 1)
    print("Change 2 OK: drawNow -> now in requestUpdate gate")

# ─── CHANGE 3: Add drawBezelBackground method before drawRotatedMetric ───
DRFN_MARKER = '    // Helper: draw a metric using a small radial arc to approximate rotation.\n    function drawRotatedMetric('
if DRFN_MARKER not in src:
    print("ERROR: drawRotatedMetric marker not found"); sys.exit(1)

NEW_METHOD = """\
    // Draw the static bezel background: clear, annulus labels, separator ring,
    // group separators, and phone indicator arc.
    // Pure drawing -- no state mutation and no WatchUi.requestUpdate().
    function drawBezelBackground(dc as Dc) as Void {
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var now = System.getTimer();

        // Background: flash red when HR alert active, otherwise black
        if (hrAlertActive && hrFlashOn) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_RED);
        } else {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        }
        dc.clear();

        // Build clock strings
        var localTime = System.getClockTime();
        var lh = localTime.hour;
        var lm = localTime.min;
        var lhStr = lh < 10 ? "0" + lh.toString() : lh.toString();
        var lmStr = lm < 10 ? "0" + lm.toString() : lm.toString();

        var utcMoment = Time.now();
        var utcInfo = Gregorian.utcInfo(utcMoment, Time.FORMAT_SHORT);
        var uh = utcInfo.hour;
        var um = utcInfo.min;
        var uhStr = uh < 10 ? "0" + uh.toString() : uh.toString();
        var umStr = um < 10 ? "0" + um.toString() : um.toString();

        var minWh = (w < h) ? w : h;
        var margin = (minWh * 8) / 100;
        var radius = (minWh / 2) - margin;

        // Initialize vector fonts
        if (roundedFontLarge == null) {
            var chronoSize   = (minWh * 0.30).toNumber();
            var bezelSize    = (minWh * 0.050).toNumber();
            var bezelLblSize = (minWh * 0.045).toNumber();
            var faces = ["RobotoCondensed", "Roboto", "RobotoBlack", "RobotoRegular", "Swiss721Bold", "TomorrowBold"];
            for (var fi = 0; fi < faces.size() && roundedFontLarge == null; fi++) {
                try {
                    var f = Graphics.getVectorFont({:face => faces[fi], :size => chronoSize});
                    if (f != null) {
                        roundedFontLarge = f;
                        roundedFontSmall = Graphics.getVectorFont({:face => faces[fi], :size => bezelSize});
                        bezelLblFont = Graphics.getVectorFont({:face => faces[fi], :size => bezelLblSize});
                    }
                } catch (ex) { }
            }
        }

        // Prefer a lighter, condensed/regular face for small bezel labels
        try {
            var bezelSizeLocal = (minWh * 0.050).toNumber();
            if (roundedFontSmall == null) {
                var trySmall = Graphics.getVectorFont({:face => "RobotoCondensed", :size => bezelSizeLocal});
                if (trySmall != null) { roundedFontSmall = trySmall; }
            } else {
                try {
                    var altSmall = Graphics.getVectorFont({:face => "RobotoRegular", :size => bezelSizeLocal});
                    if (altSmall != null) { roundedFontSmall = altSmall; }
                } catch (ex2) { }
            }
        } catch (ex3) { }

        // --- Bezel data strings ---
        var drawNow = now;

        // Heading
        var hdgStr = "--";
        try {
            var pInfo = Position.getInfo();
            if (pInfo != null && pInfo.heading != null) {
                var deg = (pInfo.heading.toFloat() * (180.0 / Math.PI)).toNumber();
                if (deg < 0) { deg = (deg + 360) % 360; }
                var hdgInt = Math.round(deg).toNumber();
                if (hdgInt < 10)       { hdgStr = "00" + hdgInt.toString(); }
                else if (hdgInt < 100) { hdgStr = "0"  + hdgInt.toString(); }
                else                   { hdgStr = hdgInt.toString(); }
            }
        } catch (ex) { }

        // Ground speed (knots)
        var gsStr = "--";
        try {
            var actInfoLocal = Activity.getActivityInfo();
            if (actInfoLocal != null && actInfoLocal.currentSpeed != null) {
                gsStr = ((actInfoLocal.currentSpeed as Float) * 1.94384).toNumber().toString();
            }
        } catch (ex) { }

        // QNH + Altitude
        var qnhValStr = "--";
        var altStr    = "-----";
        var altLbl    = "ALT";
        try {
            var sInfoDraw = Sensor.getInfo();
            if (sInfoDraw != null) {
                if (sInfoDraw.pressure != null) {
                    qnhValStr = Math.round((sInfoDraw.pressure as Float)).toNumber().toString();
                }
                if (sInfoDraw.altitude != null) {
                    var altFt = ((sInfoDraw.altitude as Float) * 3.28084).toNumber();
                    if (transitionActive) {
                        altStr = "FL" + (altFt / 100).toNumber().toString();
                    } else {
                        altStr = altFt.toString();
                    }
                }
            }
        } catch (ex) { }

        // Append tendency indicator to the alt string
        if (running && tendency != 0 && drawNow < tendencyUntil) {
            altStr = altStr + (tendency > 0 ? "+" : "-");
        }

        // --- Radial bezel geometry ---
        var R = (minWh / 2).toFloat();
        var radiusOuter = (R - 2.0).toFloat();
        var sepRadius = (radiusOuter - 15.0).toNumber();
        var radiusInner  = (radiusOuter - 24.0).toFloat();
        var radiusCenter = ((radiusInner + radiusOuter) / 2.0).toFloat();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(cx, cy, sepRadius);

        var slotDeg = 360.0 / 62.0;
        var numSlotsHDG = 9;
        var numSlotsGS  = 11;
        var numSlotsALT = 11;
        var numSlotsUTC = 11;
        var numSlotsQNH = 10;
        var numSlotsLT  = 10;
        var spanHDG = numSlotsHDG * slotDeg;
        var spanGS  = numSlotsGS  * slotDeg;
        var spanALT = numSlotsALT * slotDeg;
        var spanUTC = numSlotsUTC * slotDeg;
        var spanQNH = numSlotsQNH * slotDeg;
        var spanLT  = numSlotsLT  * slotDeg;
        var angleHDG = 90.0;
        var angleALT = angleHDG + (numSlotsHDG + numSlotsALT).toFloat() / 2.0 * slotDeg;
        var angleLT  = angleALT + (numSlotsALT + numSlotsLT).toFloat()  / 2.0 * slotDeg;
        var angleQNH = angleLT  + (numSlotsLT  + numSlotsQNH).toFloat() / 2.0 * slotDeg;
        var angleUTC = angleQNH + (numSlotsQNH + numSlotsUTC).toFloat() / 2.0 * slotDeg;
        var angleGS  = angleUTC + (numSlotsUTC + numSlotsGS).toFloat()  / 2.0 * slotDeg - 360.0;
        var rHDG = (radiusCenter - 2.0).toNumber();
        var rGS  = (radiusCenter - 6.0).toNumber();
        var rALT = (radiusCenter - 6.0).toNumber();
        var rUTC = (radiusCenter + 7.0).toNumber();
        var rQNH = (radiusCenter + 7.0).toNumber();
        var rLT  = (radiusCenter + 7.0).toNumber();

        drawRotatedMetric(dc, cx, cy, angleHDG, "HDG " + hdgStr,              Graphics.COLOR_WHITE, rHDG, spanHDG, false, false, false, slotDeg, radiusCenter, radiusOuter);
        drawRotatedMetric(dc, cx, cy, angleGS,  "GS "  + gsStr + " kt",      Graphics.COLOR_WHITE, rGS,  spanGS,  false, false, false, slotDeg, radiusCenter, radiusOuter);
        drawRotatedMetric(dc, cx, cy, angleALT, altLbl + " " + altStr,        Graphics.COLOR_WHITE, rALT, spanALT, false, false, false, slotDeg, radiusCenter, radiusOuter);
        drawRotatedMetric(dc, cx, cy, angleUTC, "UTC " + uhStr + ":" + umStr, Graphics.COLOR_WHITE, rUTC, spanUTC, false, false, false, slotDeg, radiusCenter, radiusOuter);

        var qnhDisplay = qnhValStr;
        if (qnhDisplay.equals("--") || qnhDisplay.equals("")) {
            qnhDisplay = "----";
        } else {
            while (qnhDisplay.length() < 4) {
                qnhDisplay = "-" + qnhDisplay;
            }
        }
        drawRotatedMetric(dc, cx, cy, angleQNH, "QNH " + qnhDisplay, Graphics.COLOR_WHITE, rQNH, spanQNH, false, false, false, slotDeg, radiusCenter, radiusOuter);
        drawRotatedMetric(dc, cx, cy, angleLT,  "LT "  + lhStr + ":" + lmStr, Graphics.COLOR_WHITE, rLT,  spanLT,  false, false, false, slotDeg, radiusCenter, radiusOuter);

        // Group separators
        try {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            var groupAngles = [0.0, 180.0, 115.0, 60.0, 295.0, 240.0];
            var innerClamp = ((sepRadius as Number).toFloat() + 1.0).toFloat();
            var outerClamp = (R - 1.0).toFloat();
            for (var gi = 0; gi < groupAngles.size(); gi++) {
                var a = (groupAngles[gi] as Float).toFloat();
                var aRad = a * (Math.PI / 180.0);
                var sx = (cx.toFloat() + innerClamp * Math.cos(aRad)).toNumber();
                var sy = (cy.toFloat() - innerClamp * Math.sin(aRad)).toNumber();
                var ex = (cx.toFloat() + outerClamp * Math.cos(aRad)).toNumber();
                var ey = (cy.toFloat() - outerClamp * Math.sin(aRad)).toNumber();
                dc.drawLine(sx, sy, ex, ey);
            }
            dc.setPenWidth(1);
        } catch (sepEx) { }

        // --- Phone connection indicator arc ---
        var commsIndicator = getApp().getComms();
        try {
            if (cachedPhoneIcon == null) {
                try { cachedPhoneIcon = WatchUi.loadResource(Rez.Drawables.PhoneIcon); } catch (rEx) { cachedPhoneIcon = null; }
            }
            if (cachedPhoneIcon != null) {
                var iconHalf = 12.0;
                var px = (cx.toFloat() - iconHalf).toNumber();
                var py = (cy.toFloat() + radius * 0.52 - iconHalf).toNumber();
                var drawColour = Graphics.COLOR_YELLOW;
                var visible = true;
                if (commsIndicator != null) {
                    if (commsIndicator.connected) {
                        drawColour = Graphics.COLOR_GREEN;
                    } else if (commsIndicator.connecting) {
                        var lastShake = 0;
                        try { lastShake = (commsIndicator.lastHandshakeAt as Number); } catch (e) { lastShake = 0; }
                        var since = (lastShake > 0) ? (now - lastShake) : 0;
                        if (since >= 30000) {
                            drawColour = Graphics.COLOR_RED;
                            visible = true;
                        } else {
                            var blinkPhase = ((now / 500).toNumber() % 2).toNumber();
                            visible = (blinkPhase == 0);
                            drawColour = Graphics.COLOR_YELLOW;
                        }
                    } else {
                        drawColour = Graphics.COLOR_RED;
                    }
                } else {
                    drawColour = Graphics.COLOR_YELLOW;
                }
                if (visible) {
                    var arcStartDeg = 10.0;
                    var arcEndDeg   = 80.0;
                    var arcStepDeg  = 4.0;
                    var arcR = (sepRadius as Number).toFloat();
                    dc.setColor(drawColour, Graphics.COLOR_TRANSPARENT);
                    dc.setPenWidth(3);
                    var prevX = 0.0;
                    var prevY = 0.0;
                    var havePrev = false;
                    for (var a = arcStartDeg; a <= arcEndDeg; a += arcStepDeg) {
                        var aRad = a * (Math.PI / 180.0);
                        var px1 = (cx.toFloat() + arcR * Math.cos(aRad)).toNumber();
                        var py1 = (cy.toFloat() - arcR * Math.sin(aRad)).toNumber();
                        if (havePrev) {
                            dc.drawLine(prevX, prevY, px1, py1);
                        }
                        prevX = px1; prevY = py1; havePrev = true;
                    }
                    var aRadEnd = arcEndDeg * (Math.PI / 180.0);
                    var endX = (cx.toFloat() + arcR * Math.cos(aRadEnd)).toNumber();
                    var endY = (cy.toFloat() - arcR * Math.sin(aRadEnd)).toNumber();
                    if (havePrev) { dc.drawLine(prevX, prevY, endX, endY); }
                    dc.setPenWidth(1);
                }
            }
        } catch (iconEx) { }
    }

"""

src = src.replace(DRFN_MARKER, NEW_METHOD + DRFN_MARKER, 1)
print("Change 3 OK: added drawBezelBackground method")

# ─── CHANGE 4: Fix VFRQuickInfoView._main.onUpdate → drawBezelBackground ───
OLD_CALL = '        _main.onUpdate(dc);\n'
NEW_CALL = '        _main.drawBezelBackground(dc);\n'
if OLD_CALL not in src:
    print("ERROR: _main.onUpdate(dc) call not found"); sys.exit(1)
src = src.replace(OLD_CALL, NEW_CALL, 1)
print("Change 4 OK: _main.onUpdate(dc) -> _main.drawBezelBackground(dc)")

with open('source/VFRStopWatchView.mc', 'w') as f:
    f.write(src)
print(f"File written: {orig_len} -> {len(src)} chars")
