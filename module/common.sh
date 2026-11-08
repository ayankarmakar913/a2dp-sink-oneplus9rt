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
# 2. AAC sink decoder crash
#    The stock AAC sink decoder on this ROM crashes with SIGSEGV in
#    aacDecoder_Fill() as soon as a source sends AAC. The Bluetooth stack's
#    interop database can disable AAC for selected source devices, which
#    makes the source negotiate SBC instead. List the source devices you use
#    as comma-separated Bluetooth address prefixes. Override it by creating
#    /data/adb/a2dp_sink_enabler.conf with:
#        A2DP_SINK_AAC_BLACKLIST=aa:bb:cc,dd:ee:ff
# ---------------------------------------------------------------------------
# Comma-separated Bluetooth address prefixes to force SBC for in SINK mode.
# AAC sink decoding is broken on this ROM (SIGSEGV in aacDecoder_Fill), so
# sources that negotiate AAC produce no sound. SBC is forced via interop.
# Default includes known-good prefixes and is extended dynamically from bonded
# devices and the active peer. Override in /data/adb/a2dp_sink_enabler.conf.
A2DP_SINK_AAC_BLACKLIST=${A2DP_SINK_AAC_BLACKLIST:-22:22:47,22:22:02}
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
    log "mode=sink props: source=$("$ANDROID_GETPROP" bluetooth.profile.a2dp.source.enabled) sink=$("$ANDROID_GETPROP" bluetooth.profile.a2dp.sink.enabled) avrcp.target=$("$ANDROID_GETPROP" bluetooth.profile.avrcp.target.enabled) avrcp.controller=$("$ANDROID_GETPROP" bluetooth.profile.avrcp.controller.enabled) aac_blacklist=$A2DP_SINK_AAC_BLACKLIST"
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
    [ -x /system/bin/chcon ] &&
        /system/bin/chcon u:object_r:bluetooth_data_file:s0 "$1" 2>/dev/null || true
}

# Collect Bluetooth address prefixes (first 3 octets) from bonded devices and
# the current A2DP sink peer. Output is comma-separated, lowercase.
discover_sink_blacklist_addrs() {
    {
        # Bonded device section headers in bt_config.conf
        [ -f /data/misc/bluedroid/bt_config.conf ] &&
            grep -oE '^\[([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\]' /data/misc/bluedroid/bt_config.conf 2>/dev/null |
            tr -d '[]'
        # Active sink peer
        "$ANDROID_DUMPSYS" bluetooth_manager 2>/dev/null |
            awk '/A2DP Sink State/{f=1} f && /Active peer:/{print $3; exit}'
    } 2>/dev/null | awk '
        function lc(s,   r,i,c) { r=""; for(i=1;i<=length(s);i++){c=substr(s,i,1); if(c>="A"&&c<="Z") c=sprintf("%c",index("ABCDEFGHIJKLMNOPQRSTUVWXYZ",c)+96); r=r c} return r }
        /^[0-9A-Fa-f][0-9A-Fa-f]:/ {
            a=lc($1); if(a=="00:00:00:00:00:00") next;
            n=split(a,p,":"); if(n>=3){p3=p[1]":"p[2]":"p[3]; if(!(p3 in seen)){seen[p3]=1; print p3}}
        }'
}

_ensure_oplus_blacklist_section() {
    _sec=$1; _list=$2; _f=$3
    [ -f "$_f" ] || : > "$_f"
    if ! grep -q "^\\[${_sec}\\]" "$_f"; then
        printf '\n[%s]\nAddressBlacklist = %s\n' "$_sec" "$_list" >> "$_f"
        return 0
    fi
    _tmp="${_f}.a2dp_tmp"
    awk -v sec="[${_sec}]" -v add="$_list" '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        BEGIN { n = split(add, a, ","); for (i = 1; i <= n; i++) want[trim(a[i])] = 1 }
        /^\[/ { insec = ($0 == sec); print; next }
        insec && /^[ \t]*AddressBlacklist[ \t]*=/ {
            line = $0; sub(/^[^=]*=[ \t]*/, "", line)
            m = split(line, v, ","); out = ""
            for (i = 1; i <= m; i++) { x = trim(v[i]); if (x != "" && !(x in seen)) { seen[x]=1; out=(out==""?x:out "," x) } }
            for (x in want) { if (!(x in seen)) { seen[x]=1; out=(out==""?x:out "," x) } }
            print "AddressBlacklist = " out; next
        }
        { print }
    ' "$_f" > "$_tmp" && mv "$_tmp" "$_f"
    if ! awk -v sec="[${_sec}]" '/^\[/ { insec = ($0 == sec) } insec && /^[ \t]*AddressBlacklist[ \t]*=/ { found = 1 } END { exit(found ? 0 : 1) }' "$_f"; then
        sed -i "/^\\[${_sec}\\]$/a AddressBlacklist = $_list" "$_f"
    fi
}

_remove_oplus_blacklist_section() {
    _sec=$1; _list=$2; _f=$3
    [ -f "$_f" ] || return 0
    _tmp="${_f}.a2dp_tmp"
    awk -v sec="[${_sec}]" -v remove="$_list" '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        BEGIN { n = split(remove, a, ","); for (i = 1; i <= n; i++) drop[trim(a[i])] = 1 }
        /^\[/ { insec = ($0 == sec); print; next }
        insec && /^[ \t]*AddressBlacklist[ \t]*=/ {
            line = $0; sub(/^[^=]*=[ \t]*/, "", line)
            m = split(line, v, ","); out = ""
            for (i = 1; i <= m; i++) { x = trim(v[i]); if (x != "" && !(x in drop)) out=(out==""?x:out "," x) }
            if (out != "") print "AddressBlacklist = " out; next
        }
        { print }
    ' "$_f" > "$_tmp" && mv "$_tmp" "$_f"
}

LEARNED_INTEROP_FILE=/data/adb/a2dp_sink_learned.conf

_all_sink_interop_addrs() {
    _base=$(echo "$A2DP_SINK_AAC_BLACKLIST" | tr -d ' ')
    _learned=""
    [ -f "$LEARNED_INTEROP_FILE" ] && . "$LEARNED_INTEROP_FILE" 2>/dev/null &&
        _learned=$(echo "$A2DP_SINK_LEARNED" | tr -d ' ')
    _disc=$(discover_sink_blacklist_addrs 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    echo "${_base},${_learned},${_disc}" | awk -F, '{
        for(i=1;i<=NF;i++){gsub(/^[ \t]+|[ \t]+$/,"",$i); if($i!="" && !seen[$i]++){out=(out==""?$i:out "," $i)}}
        print out
    }'
}

_save_learned_interop_addrs() {
    _all=$(_all_sink_interop_addrs)
    [ -n "$_all" ] || return 0
    printf 'A2DP_SINK_LEARNED=%s\n' "$_all" > "$LEARNED_INTEROP_FILE" 2>/dev/null || true
}

# Add configured/discovered source devices to Bluetooth interop databases and
# force SBC instead of the crashing AAC sink decoder.
ensure_sink_interop() {
    [ -d /data/misc/bluedroid ] || return 1

    _list=$(_all_sink_interop_addrs)
    [ -n "$_list" ] || return 1
    _save_learned_interop_addrs

    # Standard AOSP dynamic interop database.
    _f=$INTEROP_STANDARD_FILE
    [ -f "$_f" ] || : > "$_f"
    if ! grep -q '^\[INTEROP_DISABLE_AAC_CODEC\]' "$_f"; then
        printf '\n[INTEROP_DISABLE_AAC_CODEC]\n' >> "$_f"
    fi
    _old_ifs=$IFS
    IFS=,
    for _addr in $_list; do
        [ -n "$_addr" ] || continue
        grep -q "^${_addr} = Address_Based$" "$_f" 2>/dev/null ||
            sed -i "/^\[INTEROP_DISABLE_AAC_CODEC\]$/a ${_addr} = Address_Based" "$_f" 2>/dev/null || true
    done
    IFS=$_old_ifs
    interop_perms "$_f"

    # Oplus interop lists (try both feature names found in this ROM).
    _f=$INTEROP_OPLUS_FILE
    _ensure_oplus_blacklist_section OplusA2dpDisableAacCodec "$_list" "$_f"
    _ensure_oplus_blacklist_section OplusA2dpResponseOnlySbc "$_list" "$_f"
    interop_perms "$_f"

    log "sink interop: SBC forced for ${_list}"
    return 0
}

# Undo the interop entries when switching back to SOURCE mode.
remove_sink_interop() {
    _list=$(_all_sink_interop_addrs)
    [ -n "$_list" ] || return 0

    _f=$INTEROP_STANDARD_FILE
    if [ -f "$_f" ]; then
        _old_ifs=$IFS
        IFS=,
        for _addr in $_list; do
            [ -n "$_addr" ] || continue
            sed -i "/^${_addr} = Address_Based$/d" "$_f" 2>/dev/null || true
        done
        IFS=$_old_ifs
        interop_perms "$_f"
    fi

    _f=$INTEROP_OPLUS_FILE
    _remove_oplus_blacklist_section OplusA2dpDisableAacCodec "$_list" "$_f"
    _remove_oplus_blacklist_section OplusA2dpResponseOnlySbc "$_list" "$_f"
    interop_perms "$_f"

    log "sink interop: SBC-forcing entries removed"
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
    echo "sink codec:                SBC (forced; AAC sink is broken on this ROM)"
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
