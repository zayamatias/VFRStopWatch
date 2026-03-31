# VFRStopWatch – Copilot Instructions

## Build

The project uses the Garmin Connect IQ SDK. The compiler (`monkeyc`) is **not** on `$PATH`; use the full path below.

```bash
cd ~/Documents/VFRStopwatch/VFRStopWatch && \
"/Users/matiaszayamendez/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b/bin/monkeyc" \
  -f monkey.jungle \
  -o bin/VFRStopWatch.prg \
  -d fr55 \
  -y ~/Documents/garmin/developer_key
```

**Key points:**
- Pass `monkey.jungle` to `-f`, **not** `manifest.xml` (the latter causes a `StackOverflowError` in the jungle parser).
- Target device: `fr55`.
- Developer key: `~/Documents/garmin/developer_key`.
- Output: `bin/VFRStopWatch.prg`.
