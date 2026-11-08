#!/system/bin/sh
# Action button / command-line helper.
# Usage: action.sh [toggle|on|off|status|diag [seconds]|learn [addr]|restart|codec ...]   (default: toggle)
#
# on   = SINK mode (phone receives audio; Bluetooth output disabled)
# off  = SOURCE mode (normal Bluetooth output; sink disabled)
# diag = capture Bluetooth/audio state and logs while you reproduce the issue
# codec= experimental codec negotiation control (SBC is the safe default)

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
        # Learn bonded/active source addresses and force SBC for them (fixes AAC
        # sink decoder crashes on this ROM). Usage: action.sh learn [aa:bb:cc:dd:ee:ff]
        _addr=${2:-}
        if [ -n "$_addr" ]; then
            _p=$(echo "$_addr" | tr 'A-F' 'a-f' | awk -F: '{if(NF>=3) print $1":"$2":"$3}')
            if [ -n "$_p" ]; then
                _cur=""; [ -f "$LEARNED_INTEROP_FILE" ] && . "$LEARNED_INTEROP_FILE" 2>/dev/null && _cur=$A2DP_SINK_LEARNED
                printf 'A2DP_SINK_LEARNED=%s\n' "$(echo "${_cur},${_p}" | tr ',' '\n' | awk 'NF && !seen[$0]++{out=(out==""?$0:out "," $0)} END{print out}')" > "$LEARNED_INTEROP_FILE"
                echo "Learned prefix: $_p"
            else
                echo "Invalid address: $_addr"
                exit 1
            fi
        fi
        echo "Learning A2DP source addresses and forcing SBC..."
        _disc=$(discover_sink_blacklist_addrs 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        [ -n "$_disc" ] && echo "Discovered prefixes: $_disc"
        if [ "$A2DP_SINK_CODEC_POLICY" = "auto-experimental" ]; then
            echo "NOTE: codec policy is auto-experimental (SBC not forced). Use 'codec sbc' to restore reliable SBC."
        fi
        ensure_sink_interop || { echo "Could not update interop config."; exit 1; }
        if [ "$(current_mode)" = "sink" ]; then
            echo "Restarting Bluetooth to apply codec policy..."
            restart_bluetooth sink || true
        else
            echo "Applied (SOURCE mode; will take effect in SINK mode)."
        fi
        show_status
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
    codec)
        # Experimental: control sink codec negotiation. SBC is the only reliable
        # sink codec on this ROM (AAC sink decoder crashes with SIGSEGV).
        _sub=${2:-status}
        case "$_sub" in
            status)
                echo "codec policy: $A2DP_SINK_CODEC_POLICY"
                echo "safe default: sbc (forces SBC; avoids AAC sink crash)"
                echo "experimental: auto-experimental (lets stack negotiate; AAC may CRASH / no sound)"
                echo "backups: $CODEC_EXPERIMENT_BACKUP_DIR (and full module/config backups may exist under /data/adb/a2dp_sink_backup_*)"
                show_status
                ;;
            backup)
                backup_codec_state "$CODEC_EXPERIMENT_BACKUP_DIR" && echo "Backed up interop/config to $CODEC_EXPERIMENT_BACKUP_DIR" || echo "Backup failed"
                ;;
            revert)
                echo "Reverting codec/interops to backup and restoring SBC policy..."
                revert_codec_state "$CODEC_EXPERIMENT_BACKUP_DIR" || echo "WARNING: could not restore from $CODEC_EXPERIMENT_BACKUP_DIR (continuing with SBC defaults)"
                set_codec_policy sbc
                ensure_sink_interop || true
                if [ "$(current_mode)" = "sink" ]; then
                    restart_bluetooth sink || true
                fi
                echo "Reverted to SBC (safe)."
                show_status
                ;;
            sbc|safe)
                backup_codec_state "$CODEC_EXPERIMENT_BACKUP_DIR" >/dev/null 2>&1 || true
                set_codec_policy sbc
                ensure_sink_interop || { echo "Could not apply SBC policy."; exit 1; }
                if [ "$(current_mode)" = "sink" ]; then
                    echo "Restarting Bluetooth to apply SBC policy..."
                    restart_bluetooth sink || true
                fi
                echo "Codec policy: SBC forced (safe)."
                show_status
                ;;
            auto-experimental|auto|experimental)
                echo "WARNING: AUTO-EXPERIMENTAL codec mode."
                echo " - This ROM's AAC A2DP *sink* decoder is known to CRASH (SIGSEGV)."
                echo " - Other codecs (LDAC/aptX/LHDC) may not be supported as sink and can cause no sound."
                echo " - If things break: su -c '/data/adb/a2dp-sink codec revert' or 'codec sbc'"
                backup_codec_state "$CODEC_EXPERIMENT_BACKUP_DIR" || { echo "Backup failed; aborting."; exit 1; }
                set_codec_policy auto-experimental
                ensure_sink_interop || true
                if [ "$(current_mode)" = "sink" ]; then
                    echo "Restarting Bluetooth to apply experimental codec policy..."
                    restart_bluetooth sink || true
                fi
                echo "Codec policy: auto-experimental. Reconnect source and test. Check: dumpsys bluetooth_manager | grep 'Configured codec'"
                show_status
                ;;
            *)
                echo "Usage: $0 codec [status|backup|sbc|auto-experimental|revert]"
                echo "  sbc             : SAFE default - force SBC (avoids AAC sink crash)"
                echo "  auto-experimental: let stack negotiate codecs (RISKY: AAC may crash; others may not work)"
                echo "  backup          : backup interop/config before experiments"
                echo "  revert          : restore backup and return to SBC"
                exit 1
                ;;
        esac
        ;;
    *)
        echo "Usage: $0 [toggle|on|off|status|diag [seconds]|learn [addr]|restart|codec ...]"
        echo "  toggle  : switch between SOURCE and SINK mode"
        echo "  on/off  : SINK (receive audio) / SOURCE (normal output)"
        echo "  status  : show current mode + codec policy"
        echo "  restart : restart Bluetooth in SINK mode"
        echo "  learn   : force SBC for bonded/active sources (fixes no-sound/AAC crash)"
        echo "  diag    : capture state/logs while reproducing an issue"
        echo "  codec   : [status|backup|sbc|auto-experimental|revert] (EXPERIMENTAL; SBC is safe default)"
        exit 1
        ;;
esac
