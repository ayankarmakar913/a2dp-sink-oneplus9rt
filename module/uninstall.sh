#!/system/bin/sh
# Best-effort cleanup. Restore normal Bluetooth output and remove helpers.

MODDIR=${0%/*}
[ -f "$MODDIR/common.sh" ] || MODDIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
. "$MODDIR/common.sh" 2>/dev/null || true

# Clean up interop and helpers (best effort)
remove_sink_interop 2>/dev/null || true
disable_audio_focus_overlay 2>/dev/null || true
set_source_props 2>/dev/null || true
rm -f "$MODE_MARKER" /data/adb/a2dp-sink /data/adb/a2dp_sink_learned.conf
log "uninstall: restored SOURCE mode and cleaned up"
