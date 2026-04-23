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
