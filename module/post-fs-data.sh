#!/system/bin/sh
# Runs before Android starts the Bluetooth process. The Bluetooth app reads the
# A2DP profile properties only when it starts, so this is the important part.

MODDIR=${0%/*}
[ -f "$MODDIR/common.sh" ] || MODDIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
. "$MODDIR/common.sh"

if [ -f "$MODE_MARKER" ]; then
    log "post-fs-data: SOURCE mode (normal Bluetooth output)"
    set_source_props || true
else
    log "post-fs-data: SINK mode (receiver)"
    set_sink_props || true
fi
