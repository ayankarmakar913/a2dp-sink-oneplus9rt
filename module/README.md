# A2DP Sink Mode Switcher (APatch/Magisk module)

**THIS MODULE IS ONLY FOR OXYGENOS 16 ROM ON THE ONEPLUS 9RT (MT2111) ONLY.** **Use at your own risk — don’t blame me.**

**Tested on:** **MT2111-OOS-16.0.5.1002-20260727-ARB** (OnePlus 9RT / MT2111), APatch. Other ROMs/devices may not work.

This module switches the phone between:

- **SOURCE mode** (default/normal): phone sends audio to Bluetooth headphones/earbuds.
- **SINK mode** (receiver): phone receives A2DP audio from a PC/TV/phone and plays it locally (speaker), while Bluetooth output is disabled.

The ROM stack is unreliable with both A2DP roles active, so the module enforces **one mode at a time**.

## Why SBC is forced in SINK mode
On this ROM, the AAC *sink* decoder crashes (`SIGSEGV` in `aacDecoder_Fill`) when a source negotiates AAC, causing “plays but no sound” or Bluetooth restart. The module forces **SBC** for sink sources via Bluetooth interop entries (and enables the A2DP sink audio-focus overlay). SBC is stable; AAC sink is not supported here.

## Install / update
1. Flash `A2DP-Sink-OnePlus9RT-v1.3.zip` in APatch/Magisk. Reboot if needed.
2. **Easy control (no commands):** open the module **WebUI** in your manager (if supported). It provides **Toggle Source/Sink** and **Restart A2DP Sink** (shown only in SINK mode). APatch **Action** button also toggles.
3. Use **WebUI** / **APatch Action** / commands to control mode.

**After connecting in SINK mode:** it may take a few seconds before music starts playing — wait a bit and it should be fine.

## Commands (root)
```sh
su -c /data/adb/a2dp-sink status     # show mode, properties, active peer, codec state hints
su -c /data/adb/a2dp-sink toggle     # toggle SOURCE <-> SINK
su -c /data/adb/a2dp-sink on         # SINK/receiver mode (restarts Bluetooth)
su -c /data/adb/a2dp-sink off        # SOURCE/normal output mode (restarts Bluetooth)
su -c /data/adb/a2dp-sink restart    # restart Bluetooth in SINK mode (clean reconnect)
su -c /data/adb/a2dp-sink learn      # learn bonded/active source addresses, force SBC, restart in SINK
su -c /data/adb/a2dp-sink learn AA:BB:CC:DD:EE:FF  # force SBC for a specific device
su -c /data/adb/a2dp-sink diag [60]  # capture logs/state while reproducing an issue
```

APatch module **Action** button toggles SOURCE/SINK.

## No sound / troubleshooting
- **Quick fix:** if you get no sound, **turn Bluetooth OFF and ON once on both the source and receiver (9RT) devices**. This usually fixes it.
- **If still no sound:** open **Magisk/APatch → module → WebUI** and tap **Restart A2DP Sink** (in SINK mode) once, then reconnect. (Fallback: `su -c /data/adb/a2dp-sink restart`)
- **New source device has no sound (codec/interop):** run `su -c /data/adb/a2dp-sink learn`, then reconnect (or `su -c '/data/adb/a2dp-sink learn AA:BB:CC:DD:EE:FF'`). Learned prefixes are saved in `/data/adb/a2dp_sink_learned.conf`. Configured codec should be **SBC**.

## Limitations / behavior
- **AAC sink not supported** on this ROM (decoder crash). The module forces SBC for sink sources.
- **~10s delay** after connecting before audio may start is possible (A2DP setup/focus/decoder/routing).
- **Two devices can connect**, but automatic handover (pause device A, play device B) may not switch the sink’s active audio path on this vendor stack. Practical workaround: keep one active source at a time, or use `su -c /data/adb/a2dp-sink restart` and reconnect the device you want.
- Audio from a *source* device follows that device’s volume/app; the 9RT should not be muted and media volume should be up.

## Troubleshooting
Check codec/peer state:
```sh
su -c 'dumpsys bluetooth_manager 2>/dev/null | sed -n "/A2DP Sink State/,/BTA AV State/p; /AVDTP Stack State/,/Socket Events/p"; logcat -b crash -d -v time | tail -40'
```
`Configured codec` should be **SBC**. If it shows **AAC** or you see `aacDecoder`/`SIGSEGV`, run `learn` with the device address and reconnect.

## Uninstall
Remove/disable the module in APatch/Magisk and reboot. Uninstall restores SOURCE mode and removes module helpers/learned config (best effort).


