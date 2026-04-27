import Toybox.System;
import Toybox.Application;
import Toybox.Lang;
// Storage disabled for local SDK compatibility. To enable on-device
// file writes uncomment the following import and the helper below.
// import Toybox.Storage;

class VFRLogger {
    // Config
    static var LOG_FILENAME as String = "VFR_app.log";
    static var MAX_PROP_ENTRIES as Number = 2000;

    // Append a raw UTF-8 payload line. Attempts Storage append first,
    // falls back to Application.Properties circular buffer. Returns true
    // if Storage write succeeded, false otherwise (Properties always used).
    static function appendRaw(channel as String, payload as String) as Boolean {
        var wroteToStorage = false;
        try {
            var ts = System.getTimer();
            var line = ts.toString() + " " + (channel != null ? channel : "?") + " " + (payload != null ? payload : "");

            // Attempt Storage append when available; fall back to Properties.
            // Storage not used in this build; rely on Application.Properties
            wroteToStorage = false;

            // Always persist into Application.Properties circular buffer as a reliable fallback
            try {
                var maxEntries = MAX_PROP_ENTRIES;
                var idx = -1;
                try { var idxVal = Application.Properties.getValue("VFR_log_index"); if (idxVal != null) { idx = (idxVal as Number); } } catch (e) { idx = -1; }
                if (idx == null || idx < 0) { idx = -1; }
                idx = (idx + 1) % maxEntries;
                Application.Properties.setValue("VFR_log_index", idx);
                Application.Properties.setValue("VFR_log_" + idx.toString(), line);
                Application.Properties.setValue("VFR_lastRawPayload", line);
                Application.Properties.setValue("VFR_lastRawPayload_ts", ts);
            } catch (pex) {
                try { System.println("VFRLogger: APPPROP write failed: " + pex.getErrorMessage()); } catch (e) { }
            }

        } catch (ex) {
            try { System.println("VFRLogger.appendRaw top-level error: " + ex.getErrorMessage()); } catch (e) { }
            return false;
        }
        return wroteToStorage;
    }

    static function exportToConsole(limit as Number) as Void {
        try {
            var maxEntries = MAX_PROP_ENTRIES;
            if (limit == null || limit <= 0 || limit > maxEntries) { limit = maxEntries; }
            var idxVal = -1;
            try { idxVal = (Application.Properties.getValue("VFR_log_index") as Number); } catch (e) { idxVal = -1; }
            if (idxVal == null || idxVal < 0) { idxVal = -1; }
            System.println("VFRLogger: exporting up to " + limit.toString() + " entries (current index=" + idxVal.toString() + ")");
            var printed = 0;
            var start = (idxVal + 1) % maxEntries;
            for (var i = 0; i < maxEntries && printed < limit; i++) {
                var pos = (start + i) % maxEntries;
                try {
                    var entry = Application.Properties.getValue("VFR_log_" + pos.toString());
                    if (entry != null) {
                        System.println("LOG[" + pos.toString() + "] " + (entry as String));
                        printed++;
                    }
                } catch (eget) { }
            }
            if (printed == 0) { System.println("VFRLogger: no entries"); }
        } catch (ex) { try { System.println("VFRLogger export failed: " + ex.getErrorMessage()); } catch (e2) { } }
    }
    // Helper: write to app sandbox file via Toybox.Storage. Returns true
    // on success. The Storage API is available on-device; on SDKs that
    // don't support Storage this call will raise — caller should handle.
    /*
    // OPTIONAL: enable on-device file writes by uncommenting Storage import
    // and this helper when building against an SDK that exposes Toybox.Storage.
    static function _appendLogToFileStorage(entry as String) as Boolean {
        try {
            var fname = LOG_FILENAME;
            var fh = Storage.open(fname, Storage.MODE_APPEND);
            if (fh == null) { return false; }
            fh.write(entry);
            fh.write("\n");
            fh.close();
            return true;
        } catch (ex) {
            try { System.println("VFRLogger STORAGE write failed: " + ex.getErrorMessage()); } catch (e) { }
            return false;
        }
    }
    */
}
