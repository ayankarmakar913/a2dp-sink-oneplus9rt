#!/system/bin/sh
# Runs late in boot. Re-asserts the saved mode and creates the command-line
# shortcut. It deliberately does not restart Bluetooth at boot.

MODDIR=${0%/*}
[ -f "$MODDIR/common.sh" ] || MODDIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
. "$MODDIR/common.sh"

i=0
while [ "$("$ANDROID_GETPROP" sys.boot_completed)" != "1" ] && [ "$i" -lt 120 ]; do
    sleep 1
    i=$((i + 1))
done
log "service: boot_completed=$("$ANDROID_GETPROP" sys.boot_completed)"

if [ -f "$MODE_MARKER" ]; then
    log "service: SOURCE mode (normal Bluetooth output)"
    set_source_props || true
else
    log "service: SINK mode (receiver)"
    set_sink_props || true
fi

# Convenience command for Termux / adb shell: /data/adb/a2dp-sink
rm -f /data/adb/a2dp-sink 2>/dev/null || true
{
    echo '#!/system/bin/sh'
    echo "exec sh \"$MODDIR/action.sh\" \"\$@\""
} > /data/adb/a2dp-sink 2>/dev/null && chmod 755 /data/adb/a2dp-sink 2>/dev/null || true

# Optional: install a bundled companion QS-tile app (if present in the module).
# The app is not built into v1.3 by default because on-device APK compilation
# needs Android SDK stubs; place A2DP-QS.apk in the module directory to enable.
for _apk in "$MODDIR"/A2DP-QS.apk "$MODDIR"/*.qs.apk; do
    [ -f "$_apk" ] || continue
    _pkg=$(unzip -p "$_apk" AndroidManifest.xml 2>/dev/null | strings 2>/dev/null | grep '^com\.' | head -1)
    [ -n "$_pkg" ] || _pkg=com.a2dp.sink.qs
    if ! /system/bin/pm list packages 2>/dev/null | grep -q "package:${_pkg}$"; then
        /system/bin/cmd package install -r "$_apk" >> "$LOG_FILE" 2>&1 ||
            /system/bin/pm install -r "$_apk" >> "$LOG_FILE" 2>&1 ||
            log "service: failed to install $_apk"
        log "service: attempted install of $_apk ($_pkg)"
    fi
    break
done

if [ -f "$MODE_MARKER" ]; then
    sink_state_is Disabled ||
        log "service: warning: source mode is set but A2DP Sink is not Disabled"
else
    sink_state_is Enabled ||
        log "service: warning: sink mode is set but A2DP Sink is not Enabled"
fi

show_status >> "$LOG_FILE" 2>&1
