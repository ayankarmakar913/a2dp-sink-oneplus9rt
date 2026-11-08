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

# (QS companion app removed; use WebUI / Action / commands)

if [ -f "$MODE_MARKER" ]; then
    sink_state_is Disabled ||
        log "service: warning: source mode is set but A2DP Sink is not Disabled"
else
    sink_state_is Enabled ||
        log "service: warning: sink mode is set but A2DP Sink is not Enabled"
fi

show_status >> "$LOG_FILE" 2>&1
