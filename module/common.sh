#!/system/bin/sh
# Shared helpers for the A2DP Sink Enabler module.
#
# The ROM cannot run A2DP source and A2DP sink reliably at the same time, so
# this module switches between two exclusive modes:
#
#   source mode (default) : normal Bluetooth output to headphones/earbuds
#   sink mode             : phone receives audio from a PC/TV/phone
#
# Marker semantics:
#   /data/adb/a2dp_sink_enabler.disabled exists -> source mode
#   marker absent                               -> sink mode

SELF=$0
if command -v readlink >/dev/null 2>&1; then
    _resolved=$(readlink -f "$SELF" 2>/dev/null) && [ -n "$_resolved" ] && SELF=$_resolved
fi
MODDIR=${MODDIR:-$(dirname "$SELF")}
case "$MODDIR" in
    /*) ;;
    *) MODDIR=$(cd "$MODDIR" 2>/dev/null && pwd) || MODDIR=${0%/*} ;;
esac

LOG_FILE=${LOG_FILE:-/data/adb/a2dp_sink_enabler.log}
MODE_MARKER=/data/adb/a2dp_sink_enabler.disabled
PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:/debug_ramdisk:$PATH

# ---------------------------------------------------------------------------
# SINK-mode workarounds
#
# 1. Audio focus
#    A2dpSinkStreamHandler only starts decoding after the sink receives
#    FOCUS_GRANTED. This ROM's resource default is false, so the sink never
#    asks for focus. A small fabricated overlay flips
#    bool/a2dp_sink_automatically_request_audio_focus to true.
#
# SINK mode: A2DP codecs are negotiated by the stack. Use WebUI "Restart A2DP
# Sink" or `diag` if you hit connection/audio issues.
# ---------------------------------------------------------------------------
[ -f /data/adb/a2dp_sink_enabler.conf ] && . /data/adb/a2dp_sink_enabler.conf
INTEROP_STANDARD_FILE=/data/misc/bluedroid/interop_database_dynamic.conf
INTEROP_OPLUS_FILE=/data/misc/bluedroid/bt_oplus_iot_list.conf

# APatch/Magisk run Action scripts with a BusyBox ash that has a built-in
# "svc" applet. That applet is NOT Android's /system/bin/svc, so calling plain
# "svc" from the Action button can silently fail. Always use absolute paths.
ANDROID_SVC=/system/bin/svc
ANDROID_AM=/system/bin/am
ANDROID_CMD=/system/bin/cmd
ANDROID_DUMPSYS=/system/bin/dumpsys
ANDROID_GETPROP=/system/bin/getprop

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null
}

resetprop_bin() {
    if command -v resetprop >/dev/null 2>&1; then
        command -v resetprop
        return 0
    fi
    for p in /data/adb/ap/bin/resetprop /data/adb/magisk/resetprop \
             /data/adb/ksu/bin/resetprop /debug_ramdisk/resetprop; do
        if [ -x "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

set_prop() {
    "$_rp" "$1" "$2"
}

# Sink mode: phone is a Bluetooth receiver. Source output is turned off so the
# vendor stack does not have to run both A2DP roles at once.
set_sink_props() {
    _rp=$(resetprop_bin) || {
        log "ERROR: resetprop not found"
        return 1
    }
    set_prop bluetooth.profile.a2dp.source.enabled false
    set_prop bluetooth.profile.a2dp.sink.enabled true
    # A sink is the device being controlled by the source, so it needs the
    # AVRCP target role. This is also the phone's normal AVRCP role.
    set_prop bluetooth.profile.avrcp.target.enabled true
    set_prop bluetooth.profile.avrcp.controller.enabled false
    ensure_audio_focus_overlay || log "WARNING: audio focus overlay is not active"
    ensure_sink_interop || log "WARNING: could not write the sink interop list"
    log "mode=sink props: source=$("$ANDROID_GETPROP" bluetooth.profile.a2dp.source.enabled) sink=$("$ANDROID_GETPROP" bluetooth.profile.a2dp.sink.enabled) avrcp.target=$("$ANDROID_GETPROP" bluetooth.profile.avrcp.target.enabled) avrcp.controller=$("$ANDROID_GETPROP" bluetooth.profile.avrcp.controller.enabled)"
    [ "$("$ANDROID_GETPROP" bluetooth.profile.a2dp.sink.enabled)" = "true" ] &&
        [ "$("$ANDROID_GETPROP" bluetooth.profile.a2dp.source.enabled)" = "false" ]
}

# Source mode: normal phone behavior. Sink is turned off and A2DP output works
# exactly as it did before the module was installed.
set_source_props() {
    _rp=$(resetprop_bin) || return 1
    set_prop bluetooth.profile.a2dp.source.enabled true
    set_prop bluetooth.profile.a2dp.sink.enabled false
    set_prop bluetooth.profile.avrcp.target.enabled true
    set_prop bluetooth.profile.avrcp.controller.enabled false
    remove_sink_interop || true
    log "mode=source props: source=$("$ANDROID_GETPROP" bluetooth.profile.a2dp.source.enabled) sink=$("$ANDROID_GETPROP" bluetooth.profile.a2dp.sink.enabled) avrcp.target=$("$ANDROID_GETPROP" bluetooth.profile.avrcp.target.enabled) avrcp.controller=$("$ANDROID_GETPROP" bluetooth.profile.avrcp.controller.enabled)"
    [ "$("$ANDROID_GETPROP" bluetooth.profile.a2dp.source.enabled)" = "true" ] &&
        [ "$("$ANDROID_GETPROP" bluetooth.profile.a2dp.sink.enabled)" = "false" ]
}

# Kept for compatibility with older copies of the scripts.

# The focus overlay is installed and enabled once, then left enabled. It has
# no effect while sink mode is off because A2dpSinkService is not running.
overlay_list() {
    "$ANDROID_CMD" overlay list --user 0 2>/dev/null
}


ensure_audio_focus_overlay() {
    [ -x "$ANDROID_CMD" ] || return 1

    # system_server may still be starting when this runs from service.sh.
    _i=0
    while [ "$_i" -lt 5 ]; do
        if overlay_list >/dev/null 2>&1; then
            break
        fi
        sleep 1
        _i=$((_i + 1))
    done

    if ! overlay_list | grep -q 'A2dpSinkFocus'; then
        _out=$("$ANDROID_CMD" overlay fabricate --target com.android.bluetooth \
            --name A2dpSinkFocus \
            com.android.bluetooth:bool/a2dp_sink_automatically_request_audio_focus \
            0x12 0xffffffff 2>&1)
        [ -n "$_out" ] && echo "$_out" >> "$LOG_FILE"
    fi

    _i=0
    while [ "$_i" -lt 5 ]; do
        if "$ANDROID_CMD" overlay enable --user 0 com.android.shell:A2dpSinkFocus \
            >> "$LOG_FILE" 2>&1; then
            break
        fi
        sleep 1
        _i=$((_i + 1))
    done

    _val=$("$ANDROID_CMD" overlay lookup --user 0 com.android.bluetooth \
        com.android.bluetooth:bool/a2dp_sink_automatically_request_audio_focus \
        2>/dev/null | tail -1)
    if [ "$_val" = "true" ]; then
        log "audio focus overlay enabled (value=true)"
        return 0
    fi
    log "WARNING: audio focus overlay lookup returned '$_val'"
    return 1
}

disable_audio_focus_overlay() {
    [ -x "$ANDROID_CMD" ] || return 1
    overlay_list | grep -q 'A2dpSinkFocus' || return 0
    "$ANDROID_CMD" overlay disable --user 0 com.android.shell:A2dpSinkFocus \
        >> "$LOG_FILE" 2>&1 || true
    log "audio focus overlay disabled"
    return 0
}

interop_perms() {
    [ -f "$1" ] || return 0
    chown bluetooth:bluetooth "$1" 2>/dev/null || true
    chmod 660 "$1" 2>/dev/null || true
    [ -x /system/bin/chcon ] && /system/bin/chcon u:object_r:bluetooth_data_file:s0 "$1" 2>/dev/null || true
}

ensure_sink_interop() {
    log "sink interop: neutral"
    return 0
}

remove_sink_interop() {
    log "sink interop: neutral"
    return 0
}

bt_service_cmd() {
    _out=$("$ANDROID_SVC" bluetooth "$1" 2>&1)
    _rc=$?
    echo "$_out" >> "$LOG_FILE"
    [ "$_rc" -eq 0 ] && echo "$_out" | grep -q 'Success'
}

force_stop_bluetooth() {
    _out=$("$ANDROID_AM" force-stop com.android.bluetooth 2>&1)
    _rc=$?
    [ -n "$_out" ] && echo "$_out" >> "$LOG_FILE"
    return "$_rc"
}

sink_state_is() {
    # dumpsys prints "Enabled"/"Disabled", callers pass either case.
    "$ANDROID_DUMPSYS" bluetooth_manager 2>/dev/null |
        grep -qi "A2DP Sink State: $1"
}

current_mode() {
    if [ "$("$ANDROID_GETPROP" bluetooth.profile.a2dp.sink.enabled)" = "true" ]; then
        echo sink
    else
        echo source
    fi
}

# restart_bluetooth <sink|source>
# The Bluetooth app caches profile sysprops, so the process must be restarted.
# The mode is re-applied after the force-stop and again right after enabling,
# because this ROM can rewrite the profile props while Bluetooth restarts.
restart_bluetooth() {
    _mode=${1:-sink}
    case "$_mode" in
        sink|enabled)    _mode=sink;   _expect=Enabled ;;
        source|disabled) _mode=source; _expect=Disabled ;;
        *)
            log "ERROR: restart_bluetooth: unknown mode $_mode"
            return 1
            ;;
    esac

    _attempt=1
    while [ "$_attempt" -le 2 ]; do
        log "restarting Bluetooth for $_mode mode (attempt $_attempt)"

        _ok=0
        i=0
        while [ "$i" -lt 3 ]; do
            if bt_service_cmd disable; then
                _ok=1
                break
            fi
            sleep 1
            i=$((i + 1))
        done
        [ "$_ok" -eq 1 ] || log "WARNING: could not disable Bluetooth cleanly"

        sleep 2

        i=0
        while [ "$i" -lt 3 ]; do
            if force_stop_bluetooth; then
                break
            fi
            sleep 1
            i=$((i + 1))
        done

        sleep 1

        # The new Bluetooth process reads these values at startup, so set them
        # after the old process is gone and before it is allowed to start.
        if [ "$_mode" = sink ]; then
            set_sink_props >/dev/null 2>&1 || log "WARNING: could not set sink props"
        else
            set_source_props >/dev/null 2>&1 || log "WARNING: could not set source props"
        fi

        _ok=0
        i=0
        while [ "$i" -lt 3 ]; do
            if bt_service_cmd enable; then
                _ok=1
                break
            fi
            sleep 1
            i=$((i + 1))
        done
        [ "$_ok" -eq 1 ] || log "WARNING: could not enable Bluetooth cleanly"

        # Some ROMs rewrite the profile props as Bluetooth starts. Re-apply
        # them once more immediately after the enable command.
        if [ "$_mode" = sink ]; then
            set_sink_props >/dev/null 2>&1 || true
        else
            set_source_props >/dev/null 2>&1 || true
        fi

        i=0
        while [ "$i" -lt 30 ]; do
            if sink_state_is "$_expect"; then
                sleep 2
                if sink_state_is "$_expect"; then
                    log "A2DP Sink is $_expect"
                    return 0
                fi
                log "WARNING: A2DP Sink reverted away from $_expect"
            fi
            sleep 1
            i=$((i + 1))
        done

        log "WARNING: A2DP Sink did not become $_expect (attempt $_attempt)"
        _attempt=$((_attempt + 1))
        sleep 2
    done

    return 1
}

show_status() {
    _mode=$(current_mode)
    echo "=== A2DP mode status ==="
    if [ "$_mode" = "sink" ]; then
        echo "mode:                      SINK (phone receives audio)"
    else
        echo "mode:                      SOURCE (normal Bluetooth output)"
    fi
    echo "sink codec:                negotiated by stack"
    echo "source property:           $("$ANDROID_GETPROP" bluetooth.profile.a2dp.source.enabled)"
    echo "sink property:             $("$ANDROID_GETPROP" bluetooth.profile.a2dp.sink.enabled)"
    echo "AVRCP target property:     $("$ANDROID_GETPROP" bluetooth.profile.avrcp.target.enabled)"
    echo "AVRCP controller property: $("$ANDROID_GETPROP" bluetooth.profile.avrcp.controller.enabled)"
    _peer=$("$ANDROID_DUMPSYS" bluetooth_manager 2>/dev/null |
        grep -A1 'A2DP Sink State: Enabled' |
        grep 'Active peer:' | head -1 | awk '{print $3}')
    case "$_peer" in
        ""|null|00:00:00:00:00:00) _peer=none ;;
    esac
    echo "sink active peer:          $_peer"
    echo
    "$ANDROID_DUMPSYS" bluetooth_manager 2>/dev/null |
        grep -E 'A2DP Source State|A2DP Sink State|SDP A2DP sink'
}
