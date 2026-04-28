# VFRStopWatch – Copilot Instructions

## Build

The project uses the Garmin Connect IQ SDK. The compiler (`monkeyc`) is **not** on `$PATH`; use the full path below.

```bash
cd ~/Documents/VFRStopwatch/VFRStopWatch && \
"/Users/matiaszayamendez/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b/bin/monkeyc" \
  -f monkey.jungle \
  -o bin/VFRStopWatch.prg \
  -d fenix7pro \
  -y ~/Documents/garmin/developer_key
```

**Key points:**
- Pass `monkey.jungle` to `-f`, **not** `manifest.xml` (the latter causes a `StackOverflowError` in the jungle parser).
- Target device: `fenix7pro` (API 5.2, 260×260, 8-bit colour). fr55 is removed — it was API 3.4 and lacked VectorFont/drawRadialText support.
- Developer key: `~/Documents/garmin/developer_key`.
- Output: `bin/VFRStopWatch.prg`.

**Developer workflow note:** After making any code change, run the build command above (the `monkeyc` invocation) to compile the app, then run the emulator (`monkeydo`) immediately and inspect the simulator output/logs; fix any runtime or startup issues before proceeding with further edits. Always confirm the build succeeds before making additional edits.

- **Agent responsibility (required):**
- After each code change that modifies runtime behavior, the Copilot agent MUST run the build and then start the ConnectIQ simulator (`monkeydo`) and verify the app launches without crashing. If the simulator cannot be reached from the agent's environment, capture that fact and request the user to run the simulator command locally and paste the output.
- If a crash or runtime error occurs, the agent MUST diagnose and fix the root cause (do not leave a known crash unfixed). After committing the fix the agent MUST re-run the simulator to confirm the crash is resolved and append a dated, one-line entry to `LESSONS_LEARNT.md` describing the cause and the fix. If the agent cannot fix the crash, it must add a detailed diagnostic entry to `LESSONS_LEARNT.md` and ask the developer to investigate locally.
- Example agent workflow:
  1. Run the `monkeyc` build command above.
 2. Run `monkeydo bin/VFRStopWatch.prg fenix7pro` and capture output.
 3. If the app crashes, open the stack trace/log and fix code.
 4. Add a one-line lesson to `LESSONS_LEARNT.md` with the date and short description.
 5. Rebuild and rerun until the app launches cleanly.

## Lessons Learned

When you (the Copilot agent) learn something new while working in this repository — a debugging technique, an SDK quirk, a required workflow step, or any other actionable insight — append a one-line entry to a `LESSONS_LEARNT.md` file at the repository root. Each entry should be concise (one sentence) and dated `YYYY-MM-DD`.

Before starting any non-trivial change, check `LESSONS_LEARNT.md` first to see if an existing lesson applies. Use lessons to avoid repeating known pitfalls and to speed up debugging and iteration.

Example entry:

- 2026-04-27: `monkeyc -f monkey.jungle` must be used instead of `manifest.xml` to avoid jungle parser StackOverflowError.

**Typed object access (important):**

- 2026-04-27: Connect IQ does NOT support reflection or dynamic symbol lookup on typed objects. `Position.Info` and other typed objects must be accessed with dot syntax (for example `pInfo.course`, `pInfo.heading`, `pInfo.latitude`). Attempts to use `pInfo["course"]` or `pInfo[:course]` will either return `null`, cause an "Undefined symbol" compile error, or crash at runtime depending on SDK version. The crash we observed was caused by `pInfo[:course]` triggering a runtime lookup for symbol `:course` that doesn't exist. The correct, portable pattern is:

```monkeyc
var pInfo = Position.getInfo();
if (pInfo != null && pInfo.course != null) {
  var deg = pInfo.course.toFloat();
  deg = ((deg % 360) + 360) % 360;
  // use Math.round/degs as needed for display
}
```

Replace all dynamic access with dot access to restore heading and avoid portability issues.

## BEZEL RENDERING SNAPSHOT (HISTORIC, DO NOT EDIT)

The bezel layout in this project is intentionally stable. The watchface must only show four bezel metrics in fixed quadrants: HDG (top), GS (right), ALT (bottom), QNH (left).

NEVER CHANGE the bezel rendering below without explicit review and a simulator run. If you must alter it, follow these rules:
- Leave the four metrics and their order intact: `HDG`, `GS`, `ALT`, `QNH`.
- Do not add `UTC` or `LT` or any other bezel labels.
- Run the full build and verify visually in the ConnectIQ emulator (`monkeydo`) before committing.

Historic reference (exact implementation snapshot used as canonical source):

```monkeyc
// drawBezelBackground() — core ring and four-metric bezel
var angleHDG = 90.0;
var angleGS  = 0.0;
var angleALT = 270.0;
var angleQNH = 180.0;
// Radii chosen to position label annulus correctly
var rHDG = (radiusCenter - 2.0).toNumber();
var rGS  = (radiusCenter - 6.0).toNumber();
var rALT = (radiusCenter - 6.0).toNumber();
var rQNH = (radiusCenter + 7.0).toNumber();

drawRotatedMetric(dc, cx, cy, angleHDG, "HDG " + hdgStr,         Graphics.COLOR_WHITE, rHDG, spanHDG, false, false, false, slotDeg, radiusCenter, radiusOuter);
drawRotatedMetric(dc, cx, cy, angleGS,  "GS "  + gsStr + " kt", Graphics.COLOR_WHITE, rGS,  spanGS,  false, false, false, slotDeg, radiusCenter, radiusOuter);
drawRotatedMetric(dc, cx, cy, angleALT, altLbl + " " + altStr,     Graphics.COLOR_WHITE, rALT, spanALT, false, false, false, slotDeg, radiusCenter, radiusOuter);
drawRotatedMetric(dc, cx, cy, angleQNH, "QNH " + qnhDisplay,      Graphics.COLOR_WHITE, rQNH, spanQNH, false, false, false, slotDeg, radiusCenter, radiusOuter);
```

Date snapshot: 2026-04-27

Rationale: historical regressions showed UTC/LT labels were accidentally reintroduced; the four-metric bezel is the only accepted design. Treat this block as authoritative guidance for future edits.

Note: adding this note and snapshot reduces accidental regressions but does not technically enforce immutability — use branch protections, code reviews, and emulator checks to guarantee stability.


