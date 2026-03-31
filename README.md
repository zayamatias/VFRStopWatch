# VFRStopWatch

Compact stopwatch app for Garmin Connect IQ (FR55). Intended for VFR pilots who want a simple flight timer with optional auto-start and per-flight GPS recording.

## Overview

VFRStopWatch provides a manual stopwatch (start/stop), lap snapshots, a small sub-timer, and an optional auto-start mode that triggers when ground speed exceeds a configurable threshold (default ≈30 knots). Each start/stop cycle can create a FIT activity using the ActivityRecording API and sync to Garmin Connect.

## Features

- Manual start/stop, lap snapshot and sub-timer
- Optional auto-start when moving (configurable threshold in code)
- Per-run GPS recording: creates FIT activities that sync to Garmin Connect
 - On-device settings menu for GPS mode, timer interval and takeoff speed
 - Trip summary view: when a run is stopped, pressing UP shows start times (local & UTC), total trip time, total NM and km

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
- `source/VFRStopWatchDelegate.mc` — input delegate
- `manifest.xml` — project manifest (includes `Fit` permission required for ActivityRecording)

## Configuration

Currently configuration is in source code constants inside `source/VFRStopWatchView.mc`:

- `AUTO_START_SPEED_MS` — threshold in meters/second (default ≈15.433 m/s = 30 kt)
- `autoStartEnabled` — boolean flag controlling whether auto-start is armed on app start/reset

Runtime configuration: the app includes an on-device Settings menu (GPS Mode, Timer Interval, Takeoff Speed). Changes persist to `Application.Properties` and apply immediately.

## Limitations

- The watch does not expose a general-purpose filesystem for direct downloads; recorded activities are available after syncing to Garmin Connect.
- Altitude: the Forerunner 55 does not include a barometric altimeter; altitude is GPS-derived only and may be absent or noisy in FIT records. The app currently relies on system-provided GPS samples for ActivityRecording; if altitude is present in Position samples it will be included, otherwise not.
- GPS readings can be noisy; enabling a sustained-speed check (e.g. require N seconds above threshold) helps avoid false starts.

## Development & testing

- Use the Connect IQ simulator to run the app and inject GPS data for testing auto-start and recording.
- After edits run the build command above to regenerate `bin/VFRStopWatch.prg`.

## Contributing

Contributions are welcome. For small fixes, open a pull request. For new features, please open an issue to discuss before implementing.

## License
This project is released under the MIT License — a permissive, minimal-restrictions license.

See the full license text in the `LICENSE` file.


