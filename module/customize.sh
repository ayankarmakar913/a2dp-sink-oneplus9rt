#!/system/bin/sh
# Installer hook (APatch/Magisk): the installer extracts files as 0644, so make
# the module scripts executable explicitly.

MODDIR=${MODPATH:-${0%/*}}

chmod 755 "$MODDIR"/post-fs-data.sh 2>/dev/null
chmod 755 "$MODDIR"/service.sh 2>/dev/null
chmod 755 "$MODDIR"/action.sh 2>/dev/null
chmod 755 "$MODDIR"/uninstall.sh 2>/dev/null
chmod 755 "$MODDIR"/common.sh 2>/dev/null

# Start in normal output mode after installation. Press the module Action
# button once to switch to SINK (receiver) mode.
touch /data/adb/a2dp_sink_enabler.disabled 2>/dev/null || true
