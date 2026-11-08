# A2DP Sink/Source Switcher — OnePlus 9RT (APatch/Magisk)

**THIS MODULE IS ONLY FOR OXYGENOS 16 ROM ON THE ONEPLUS 9RT (MT2111) ONLY.** **Use at your own risk — don’t blame me.**

**Tested on:** **MT2111-OOS-16.0.5.1002-20260727-ARB** (OnePlus 9RT / MT2111), APatch. Other ROMs/devices may not work.

Switches the phone between:
- **SOURCE mode** (normal): phone sends audio to Bluetooth headphones/earbuds.
- **SINK mode** (receiver): phone receives A2DP audio from a PC/TV/phone and plays it locally. Bluetooth output is disabled in SINK mode.

The ROM stack is unreliable with both A2DP roles active, so the module enforces **one mode at a time**.

## Install / control
1. Flash the module zip in APatch/Magisk. Reboot if needed.
2. **WebUI** (if supported): **Toggle Source/Sink** and **Restart A2DP Sink** (shown only in SINK mode). APatch **Action** button also toggles.

**Switching modes / after connecting:** changing **SOURCE ↔ SINK** restarts Bluetooth and can take **~10 seconds to 1 minute** (reconnection/service restart). After connecting in SINK mode, wait a few seconds for audio to start.

## Commands (root)
```sh
su -c /data/adb/a2dp-sink status     # show mode and state
su -c /data/adb/a2dp-sink toggle     # toggle SOURCE <-> SINK
su -c /data/adb/a2dp-sink on         # SINK (receiver)
su -c /data/adb/a2dp-sink off        # SOURCE (normal output)
su -c /data/adb/a2dp-sink restart    # restart Bluetooth in SINK mode
su -c /data/adb/a2dp-sink diag [60]  # capture logs/state while reproducing an issue
```

## No sound / troubleshooting
- **Wait 10s–1m** after connecting/switching modes — delay can look like no sound.
- **Quick fix:** toggle **Bluetooth OFF/ON on both devices**, then reconnect and play.
- **SINK mode:** open **WebUI** and tap **Restart A2DP Sink**, then reconnect. Fallback: `su -c /data/adb/a2dp-sink restart`.
- **SOURCE mode codec issues:** if a target device won’t negotiate as expected, **Forget & re-pair** it on the 9RT and check configured codec.
- Diagnostics:
```sh
su -c 'dumpsys bluetooth_manager 2>/dev/null | grep -E "A2DP (Source|Sink) State|Active peer|Connected|Streaming|Configured codec|SEP codec" | head -20; logcat -b crash -d -v time | tail -50'
```

## Known limitations
- **Mode switching / reconnect** can take **~10 seconds to 1 minute**.
- **Two devices can connect**, but automatic handover may not switch the sink’s active audio path on this vendor stack. Workaround: keep one active source at a time, or use **Restart A2DP Sink** and reconnect the device you want.
- **Not simultaneous source+sink** (exclusive modes). **ROM/device compatibility is limited.**

## Uninstall / recovery
Disable/remove the module in APatch/Magisk and reboot. Or: `su -c /data/adb/a2dp-sink off`.

## Disclaimer
Provided **as-is**, with **no warranty**. Use at your own risk. Don’t blame me.
