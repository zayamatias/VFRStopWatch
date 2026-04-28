# Lessons Learnt

- 2026-04-27: `monkeyc -f monkey.jungle` must be used instead of `manifest.xml` to avoid jungle parser StackOverflowError.
- 2026-04-27: Connect IQ does NOT support reflection or dynamic symbol lookup on typed objects. Typed objects such as `Position.Info` must be accessed with dot syntax (for example `pInfo.course`, `pInfo.heading`). Using `pInfo["course"]` or `pInfo[:course]` will return `null`, cause an "Undefined symbol" compile error, or crash at runtime depending on SDK version. The correct portable pattern is to read `pInfo.course` and check for `null` before using.
- 2026-04-27: Monkey C arrays created with `[]` are zero-size; index-assigning (e.g., `slots[0] = x`) crashes with Array Out Of Bounds — use `new [N]` for fixed-size or `.add()` for dynamic growth.
- 2026-04-27: `new Array()` in Monkey C returns an Object, not an Array, so `.add()` fails with UnexpectedTypeException; always use `[]` + `.add()` or `new [N]` literals.
- 2026-04-27: `dc.getTextWidth()` / `Graphics.getTextWidth()` are not available in SDK 9.1; use per-character pixel estimation instead.
- 2026-04-27: `monkeydo` uses positional args only: `monkeydo <prg_path> <device_id>` — no `-f` or `-d` flags.
- 2026-04-27: The ConnectIQ simulator must be launched via `open ConnectIQ.app` before calling `monkeydo`; otherwise the app won't connect.
- 2026-04-27: Passing a `Graphics.FONT_*` integer constant to a `font as Graphics.VectorFont` parameter causes a runtime UnexpectedTypeException; guard with a null-check on the VectorFont and access it as a class member instead of a function parameter.
- 2026-04-27: `Math.floor()` returns a Float in Monkey C; call `.toNumber()` before using the result as an array index or integer.
- 2026-04-27: You can run the emulator and capture crashes by running `cd ~/Documents/VFRStopwatch/VFRStopWatch && "/Users/matiaszayamendez/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b/bin/monkeydo" bin/VFRStopWatch.prg fenix7pro`.
- 2026-04-27: Reverted `drawLabelInQuadrant` after runtime crash: UnexpectedTypeException: Expected Array, given Object — reverted to `drawRotatedMetric` while root cause is investigated.
 - 2026-04-27: Fixed crash in `drawBezelBackground` caused by casting an unexpected object to Float when sanitizing QNH; now sanitize QNH by operating on the string form to avoid invalid cast.
- 2026-04-27: BEZEL LABEL CHARACTER ORDER — CW slot traversal reads LEFT-to-RIGHT from the viewer only for the NW (HDG) and NE (GS) quadrants; for SW (ALT) and SE (QNH) it reads RIGHT-to-LEFT, so those two quadrants MUST pass `reverseChars=true` to `drawLabelInQuadrant`. NEVER use a shared computed flag (e.g. derived from theta_center) that applies to all quadrants — it always breaks the quadrants that work. Each quadrant call MUST have an explicit, independent `reverseChars` argument: HDG=false, GS=false, ALT=true, QNH=true.
- 2026-04-27: CRASH DEBUGGING — to capture a full crash log run: `open ConnectIQ.app && sleep 6 && monkeydo bin/VFRStopWatch.prg fenix7pro 2>&1 | tee /tmp/vfr_crash.log` then `cat /tmp/vfr_crash.log`; a clean run exits 0 with only VFRComms/backup messages; a crash prints a stack trace with "UnhandledExceptionError" or "UnexpectedTypeException" before exit.
- 2026-04-27: "Unable to connect to simulator" from `monkeydo` means the ConnectIQ.app is not yet running; always open it and wait at least 5–6 seconds before invoking `monkeydo` — a reported "crash on launch" may actually be this connection failure, not a real runtime crash.
- 2026-04-27: SHOW_BEZEL_ANGLE_DEBUG must be set to `false` in production; leaving it `true` draws yellow slot dots, a red crosshair, and orange quadrant radial guides over the watch face — disable after calibration is complete.
- 2026-04-27: BEZEL ANCHORS (current implementation) — angles and per-quadrant text radii as coded in `drawBezelBackground`:
	- angleHDG = 135.0°, angleGS = 45.0°, angleALT = 225.0°, angleQNH = 315.0°.
	- rTextHDG = radiusText, rTextGS = radiusText, rTextALT = radiusText + 10.0, rTextQNH = radiusText + 10.0.
	- `reverseChars` flags: HDG=false, GS=false, ALT=true, QNH=true.
	Note: These values were chosen by visual nudging and MUST be verified on a real device with live sensor values; keep this entry as a reference for future recalibration.
