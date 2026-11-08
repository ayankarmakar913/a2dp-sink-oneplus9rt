#!/system/bin/sh
# Action button / command-line helper.
# Usage: action.sh [toggle|on|off|status|diag [seconds]|restart]   (default: toggle)
#
# on   = SINK mode (phone receives audio; Bluetooth output disabled)
# off  = SOURCE mode (normal Bluetooth output; sink disabled)
# diag = capture Bluetooth/audio state and logs while you reproduce the issue

MODDIR=${0%/*}
[ -f "$MODDIR/common.sh" ] || MODDIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
. "$MODDIR/common.sh"

ACTION=${1:-toggle}

if [ "$ACTION" = "toggle" ]; then
    if [ "$(current_mode)" = "sink" ]; then
        ACTION=off
        echo "Currently in SINK mode; switching to normal output..."
    else
        ACTION=on
        echo "Currently in SOURCE mode; switching to receiver..."
    fi
fi

case "$ACTION" in
    status)
        show_status
        ;;
    off|source|normal)
        # Persist source mode across reboots until the user turns sink back on.
        touch "$MODE_MARKER" 2>/dev/null || true
        echo "Switching to SOURCE (normal Bluetooth output) mode..."
        set_source_props || {
            echo "Could not set the Bluetooth properties. Is root available?"
            exit 1
        }
        restart_bluetooth source || true
        echo
        show_status
        echo
        echo "Normal Bluetooth output is restored. Sink is disabled."
        echo "Reconnect your headphones/earbuds."
        ;;
    on|sink|receiver)
        echo "Switching to SINK (receiver) mode..."
        set_sink_props || {
            echo "Could not set the Bluetooth properties. Is root available?"
            exit 1
        }
        rm -f "$MODE_MARKER" 2>/dev/null || true
        restart_bluetooth sink || true
        echo
        show_status
        echo
        echo "Sink mode is now on. Bluetooth output (source) is disabled."
        echo "On the source device (PC/TV/phone), forget this phone if it was"
        echo "paired before, then scan and pair again."
        echo "Keep this phone's Bluetooth settings screen open while pairing so"
        echo "the phone is discoverable."
        ;;
    diag|diagnose)
        DURATION=${2:-60}
        case "$DURATION" in
            ''|*[!0-9]*) DURATION=60 ;;
        esac
        [ "$DURATION" -lt 15 ] && DURATION=15
        [ "$DURATION" -gt 600 ] && DURATION=600

        OUT=/data/adb/a2dp_sink_diag_$(date '+%Y%m%d_%H%M%S').txt
        BASE=${OUT%.txt}

        echo "Capturing diagnostics for ${DURATION}s."
        echo "Now connect the source device, select this phone as its audio"
        echo "output, and play something. Leave this running until it finishes."
        echo

        {
            echo "=== mode snapshot $(date) ==="
            show_status
            echo
            echo "=== interop ==="
            echo "-- $INTEROP_OPLUS_FILE --"
            cat "$INTEROP_OPLUS_FILE" 2>/dev/null || true
            echo "-- $INTEROP_STANDARD_FILE --"
            cat "$INTEROP_STANDARD_FILE" 2>/dev/null || true
            echo
            echo "=== relevant properties ==="
            "$ANDROID_GETPROP" |
                grep -E 'bluetooth\.profile\.(a2dp|avrcp)|a2dp_offload|a2dp\.lhdc|a2dp_sink' |
                sort
            echo
            echo "=== paired devices / policies ==="
            "$ANDROID_DUMPSYS" bluetooth_manager 2>/dev/null |
                grep -E 'profile connection policy|isActiveHfpDevice' | head -40
        } > "$OUT" 2>&1

        # Keep the existing buffer for context, then start a clean capture.
        /system/bin/logcat -d -v time > "${BASE}.before.logcat" 2>/dev/null
        /system/bin/logcat -c >/dev/null 2>&1 || true

        i=0
        while [ "$i" -lt "$DURATION" ]; do
            sleep 5
            i=$((i + 5))
            {
                echo
                echo "=== t+${i}s $(date '+%H:%M:%S') ==="
                "$ANDROID_DUMPSYS" bluetooth_manager 2>/dev/null |
                    grep -E 'A2DP Source State|A2DP Sink State|Active peer|mAudioState|Current Codec|Codec|SEP codec|Configured codec|Requested codec' |
                    head -30
                echo "--- audio outputs ---"
                "$ANDROID_DUMPSYS" audio 2>/dev/null |
                    grep -E 'Devices: (speaker|bt_a2dp|bt_sco|earpiece|headset)' |
                    head -10
                _peer=$("$ANDROID_DUMPSYS" bluetooth_manager 2>/dev/null |
                    grep -A1 'A2DP Sink State: Enabled' |
                    grep 'Active peer:' | head -1 | awk '{print $3}')
                echo "sink peer: $_peer"
                echo "--- crash tail ---"
                /system/bin/logcat -b crash -d -v time 2>/dev/null | tail -3
            } >> "$OUT" 2>&1
        done

        /system/bin/logcat -d -v time > "${BASE}.logcat" 2>/dev/null
        "$ANDROID_DUMPSYS" bluetooth_manager > "${BASE}.bluetooth.txt" 2>&1
        "$ANDROID_DUMPSYS" audio > "${BASE}.audio.txt" 2>&1
        "$ANDROID_DUMPSYS" media.audio_policy > "${BASE}.audio_policy.txt" 2>&1

        {
            echo
            echo "=== final A2DP sink section ==="
            "$ANDROID_DUMPSYS" bluetooth_manager 2>/dev/null |
                grep -A15 'A2DP Sink State: Enabled' | head -30
        } >> "$OUT" 2>&1

        echo "Saved:"
        echo "  $OUT"
        echo "  ${BASE}.logcat"
        echo "  ${BASE}.bluetooth.txt"
        echo "  ${BASE}.audio.txt"
        echo "  ${BASE}.audio_policy.txt"
        echo
        show_status
        ;;
    learn|fix|fix-aac)
        echo "Disabled: SBC enforcement removed for AAC sink testing on this build."
        echo "If you get no sound/BT issues, revert from /data/adb/a2dp_9rt_backup_20261109_024630 and/or restore the previous module version."
        ;;
    restart|restart-sink)
        # Restart Bluetooth in the current sink context to get a clean A2DP sink
        # session (useful when switching which source device connects). Stays in
        # SINK mode; source devices will need to reconnect.
        echo "Restarting A2DP sink (Bluetooth restart, SINK mode)..."
        set_sink_props || { echo "Could not set sink properties."; exit 1; }
        rm -f "$MODE_MARKER" 2>/dev/null || true
        restart_bluetooth sink || true
        echo
        show_status
        echo
        echo "Sink restarted. Reconnect the source device you want to use."
        ;;
    *)
        echo "Usage: $0 [toggle|on|off|status|diag [seconds]|restart]"
        echo "  toggle  : switch between SOURCE and SINK mode"
        echo "  on/off  : SINK (receive audio) / SOURCE (normal output)"
        echo "  status  : show current mode"
        echo "  restart : restart Bluetooth in SINK mode"
        echo "  (learn removed: SBC enforcement disabled for AAC testing)"
        echo "  diag    : capture state/logs while reproducing an issue"
                exit 1
        ;;
esac
