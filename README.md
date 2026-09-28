# VFRStopWatch

Compact stopwatch app for Garmin Connect IQ (FR55). Intended for VFR pilots who want a simple flight timer with optional auto-start and per-flight GPS recording.

## Overview

VFRStopWatch provides a manual stopwatch (start/stop), lap snapshots, a small sub-timer, and an optional auto-start mode that triggers when ground speed exceeds a configurable threshold (default ≈30 knots). Each start/stop cycle can create a FIT activity using the ActivityRecording API and sync to Garmin Connect.

## Features

- **GPS-linked stopwatch** — auto-starts when the aircraft begins to roll (off-block/taxi speed, configurable take-off speed gates the auto-stop) and auto-stops after a full stop. Shows `MM:SS`, or `H:MM:SS` past an hour.
- **GPS status colour** on the big clock/timer: red = no fix, flashing orange = acquiring, **green = captured**.
- **Flight data ring** on the watch face: HDG, GS, ALT (baro or GPS; FL above transition), QNH — with colour cues (QNH amber when ≠ 1013, ALT cyan in the FL regime).
- **Persistent distance flown (NM)**; lap snapshots and a sub-timer. The distance is integrated from ground speed, and a GPS outage is repaired when the fix returns: the straight-line distance from the last good fix to the new one is added back, so a dropout no longer silently deletes the miles flown (implausible jumps are rejected as GPS glitches).
- **Callouts with distinct vibration signatures**: interval checkpoints, HR alert, fuel check, start/stop/lap/reset/turns.
- **Landing counter** (AGL-based) for the logbook — shown on the trip summary. Touch-down is detected from AGL or from taxi speed (GS < 15 kt while flagged airborne), and stopping the clock on the ground always records a final landing, so the last landing of a flight cannot be lost to baro/QNH drift or a mistimed stop.
- **Circuit practice assistant** — buzzes at each pattern turn point (upwind → crosswind → downwind → base → final).
- **Altitude alert** — buzz when approaching/reaching a target MSL altitude.
- **GPS-derived bank / turn-rate estimate** (surfaced during circuit practice).
- **Per-run FIT recording** that syncs to Garmin Connect.
- **Trip summary** — OBT/IBT, distance, max altitude, average GS, landings.
- **Flight report persisted with the recording** — the summary figures are written into the saved activity as FIT developer fields, so OBT/IBT, block time, landings, distance, max altitude, average GS, **max G**, max bank and **max pitch** appear in the **Garmin Connect** activity summary, and G-force / bank / pitch are recorded once per second as chart channels. The same figures are attached to the `flight_event` `stop` message sent to the companion app.

### The three outputs after a flight

| Where | What it contains |
|---|---|
| **On-watch summary** (shown when you stop) | OBT, IBT, **TIME** (block time), DIST, LDG, ALT (max) and **G** (peak load factor) |
| **Phone report** (`flight_event` start/stop payload) | the same figures plus max bank, max pitch, density altitude, wind, OAT/dew point and cloud cover/base; `obt` is `-1` when the time was unavailable |
| **Activity (FIT)** | standard recording + the developer fields listed above (G recorded per second for tracking) |
- **G-force / bank / pitch graphs** — three per-second FIT charts in the Garmin Connect activity page: load factor from the accelerometer magnitude, an estimated bank angle (coordinated-turn model, smoothed GPS turn rate + GS) and an estimated pitch (flight-path angle, `atan2(VS, GS)`). See the caveats below.
- **Companion-app flight-plan / waypoint support** (bearing, distance, ETE).
- **Safe interaction & battery** — reset requires a long hold; idle clock dims and redraws are throttled.

## Watch face & in-flight tools

The main face is a hand-drawn data ring (native `drawRadialText` labels), with a large central timer/clock. The centre text is the GPS-status colour. Under it: V/S, then NM flown (while running). In the ring: HDG (top-left), GS (top-right), ALT (bottom-left). **QNH is no longer on the ring** — it is set from ATIS and not read in flight; the ring fields are still fully legible because the SE quadrant is now free.

### Display modes

**Display** (Settings → Display, or Garmin Connect) selects the face layout. The face actually in use is remembered separately from that setting, so an app **update always brings up the paged face** even on an install whose stored setting still says "Bezel ring" (an updated install shows the new face once; after that your own choice sticks).

- **Pages (big)** (default) — the chrono plus **one large value per page (~26% of screen height, ≈68 px on the fēnix 7 Pro)**, its name/unit above and an optional small third line below (lap, AGL, MAX GS, local time, trip ETE, G/max bank). Type uses the boldest available face; thick strokes hold up better on a transflective display. A small `n/12` indicator at the bottom shows where you are.
- **Bezel ring** — four-quadrant ring as described above (kept unchanged). The ring's radial text is capped by its arc length, so glyphs land around 16–27 px however *Bezel Font* is set.

#### Pages (in cycle order)

| # | Page | Value | Sub-line |
|---|------|-------|----------|
| 1 | CHRONO | elapsed time / clock — **centred, largest font that fits** | sub-timer |
| 2 | DIST nm | distance flown | — |
| 3 | ALT ft | altitude, `FL` above the transition altitude | AGL |
| 4 | HDG | heading / track (3 digits) | — |
| 5 | GS kt | ground speed | MAX GS |
| 6 | V/S fpm | vertical speed (signed) | altitude-alert target |
| 7 | ZULU | UTC time (the label says ZULU, so no `Z` suffix) | local time |
| 8 | WIND | wind `ddd/ss` (from the weather provider) | — |
| 9 | OAT/DP | temperature / dew point (°C) | — |
| 10 | CLOUDS | cloud cover % | cloud base |
| 11 | DENS ALT | density altitude (ft) | `~ no QNH set` when QNH is unknown |
| 12 | FLIGHT PLAN | bearing to the active waypoint | distance nm / ETE min |
| 13 | LANDINGS | landing count | MAX G / BANK |

Pages change **only when you press UP/DOWN**. There is no automatic rotation unless you ask for one: **Auto Page Cycle** (Settings → Auto Page Cycle, or Garmin Connect) takes 0–60 s per page, where **0 = off (default)**. When set, the face advances one page every N seconds while the clock is running; any manual UP/DOWN press restarts that timer, so it never steals the page you just picked.

Pages with no data yet show `---` in grey, so a dead sensor is obvious at a glance.

**Buttons (fēnix 7 Pro):**
- **START** — start / stop (third press when checkpoints are armed stops the flight)
- **UP short** — previous page (in Pages mode) / **sub-timer** (in Bezel ring mode)
- **UP hold** — sub-timer (start → pause → back to zero)
- **DOWN short** — next page (in Pages mode) / quick-info screens (in Bezel ring mode)
- **DOWN hold** — settings (idle), **reset** (stopped with a flight — the hold is the confirmation)
- **MENU** — Start/Stop · Reset · Settings · Flight Plan · Map · Weather
- **BACK** — exit to the watch face (in the main view)

In Pages mode the quick-info *chain* is not used (every value in it is a page already), but nothing is lost: the map and the full weather detail screen (cloud cover, cloud base, precipitation-trend hint) are both in the MENU, and they remain reachable through the chain in Bezel ring mode as before.


**Buttons (fēnix 7 Pro):**
- **START** — start / stop (third press when checkpoints are armed stops the flight)
- **UP short** — previous page (in Pages mode) / **sub-timer** (in Bezel ring mode)
- **UP hold** — sub-timer (start → pause → back to zero)
- **DOWN short** — next page (in Pages mode) / quick-info screens (in Bezel ring mode)
- **DOWN hold** — settings (idle), **reset** (stopped with a flight — the hold is the confirmation)
- **MENU** — Start/Stop · Reset · Settings · Flight Plan · **Map**
- **BACK** — exit to the watch face (in the main view)

The quick-info screens (heading/GS, wind/temp, density altitude) are only reachable in Bezel ring mode, because in Pages mode every one of their values is a page already. The **map** moved to the MENU so it stays reachable in either mode.


## On-device settings

GPS mode · Timer interval · Takeoff speed · Transition altitude · HR alert · Fuel check · Altitude source (baro/GPS) · Companion app · Circuit practice · Field elevation (auto/manual) · Runway length · Altitude alert · Auto backlight · Bezel font / contrast · Display (Pages/Bezel ring) · Auto page cycle

**Takeoff (kts)** now serves two purposes: it switches auto-start on (0 = manual start only) and it is the speed that counts as "airborne", which arms the automatic stop.

## Requirements
- Connect IQ SDK (version compatible with project manifest; tested with SDK 9.x)
- A valid Garmin developer key for building with the `monkeyc` compiler

## Build (local)

Set environment variables to point to your Connect IQ SDK and developer key, then run the compiler from the project root. Replace the paths below with your actual SDK and key locations.

```bash
# Set these to your local paths (example values):
export CONNECTIQ_SDK="/path/to/connectiq-sdk/bin"
export DEVELOPER_KEY="$HOME/.connectiq/developer_key"

# From project root:
"$CONNECTIQ_SDK/monkeyc" -f monkey.jungle -o bin/VFRStopWatch.prg -d fr55 -y "$DEVELOPER_KEY"
```

After a successful build the PRG will be at `bin/VFRStopWatch.prg`.

## Usage

1. Install the generated `.prg` on your FR55 (via the SDK or device sync tooling).
2. Launch the app on the watch.
3. If auto-start is armed, the stopwatch will start automatically when ground speed exceeds the threshold.
4. Each start/stop creates a FIT activity. Sync your watch to Garmin Connect to view, analyze, or export the recording as `.fit`/`.gpx`.

## Code pointers

- `source/VFRStopWatchApp.mc` — application entry
- `source/VFRStopWatchView.mc` — main UI, auto-start logic and ActivityRecording integration
- `resources/fit/fit.xml` — FIT developer-field definitions that carry the flight report into Garmin Connect (ids must match the `FIT_FIELD_*` constants in `VFRStopWatchView.mc`; requires the `FitContributor` manifest permission)
- `source/VFRStopWatchDelegate.mc` — input delegate
- `manifest.xml` — project manifest (includes `Fit` permission required for ActivityRecording)

## Configuration

Currently configuration is in source code constants inside `source/VFRStopWatchView.mc`:

- `AUTO_START_SPEED_MS` — take-off speed in meters/second (default ≈15.433 m/s = 30 kt, from the *Takeoff (kts)* setting). Reaching it marks the flight as airborne and **arms the auto-stop**; setting it to 0 disables auto-start entirely.
- `TAXI_START_SPEED_MS` — off-block detection: the clock starts when ground speed stays above this for `TAXI_START_HOLD_MS` (default 2.57 m/s = 5 kt for 5 s). 5 kt is above walking pace (≈1.6–2.7 kt) but below normal taxi speed, so the pilot walking to the aircraft cannot start the flight, while a taxi stop after take-off has already happened does not end it.
- `autoStartEnabled` — boolean flag controlling whether auto-start is armed on app start/reset
- `hasTakenOff` — set once take-off speed is seen; the zero-speed auto-stop is ignored until then, so pausing/holding during taxi cannot stop the flight

Runtime configuration: the app includes an on-device Settings menu (GPS Mode, Timer Interval, Takeoff Speed). Changes persist to `Application.Properties` and apply immediately.

## Limitations

- The watch does not expose a general-purpose filesystem for direct downloads; recorded activities are available after syncing to Garmin Connect.
- Altitude: the Forerunner 55 does not include a barometric altimeter; altitude is GPS-derived only and may be absent or noisy in FIT records. The app currently relies on system-provided GPS samples for ActivityRecording; if altitude is present in Position samples it will be included, otherwise not.
- GPS readings can be noisy; enabling a sustained-speed check (e.g. require N seconds above threshold) helps avoid false starts.
- **G-force is measured by the wrist accelerometer**, not an aircraft g-meter: it includes wrist/arm movement, so read the graph as indicative. The magnitude used is orientation independent, so a coordinated turn does show up.
- **Bank and pitch are estimates**, not attitude: bank comes from the GPS turn rate and ground speed (coordinated-turn model — wrong in a slip/skid), pitch is the flight-path angle from vertical speed and ground speed, not the angle shown on an artificial horizon.

## Development & testing

- Use the Connect IQ simulator to run the app and inject GPS data for testing auto-start and recording.
- After edits run the build command above to regenerate `bin/VFRStopWatch.prg`.

## Contributing

Contributions are welcome. For small fixes, open a pull request. For new features, please open an issue to discuss before implementing.

## License
This project is released under the MIT License — a permissive, minimal-restrictions license.

See the full license text in the `LICENSE` file.


