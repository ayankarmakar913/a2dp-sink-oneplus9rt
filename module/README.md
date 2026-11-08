# A2DP Sink/Source Switcher — OnePlus 9RT (APatch/Magisk)

**THIS MODULE IS ONLY FOR OXYGENOS 16 ROM ON THE ONEPLUS 9RT (MT2111) ONLY.** **Use at your own risk — don’t blame me.**

**Tested on:** **MT2111-OOS-16.0.5.1002-20260727-ARB** (OnePlus 9RT / MT2111), APatch. Other ROMs/devices may not work.

Switches the phone between:
- **SOURCE mode** (normal): phone sends audio to Bluetooth headphones/earbuds (AAC/other codecs as supported by the target device).
- **SINK mode** (receiver): phone receives A2DP audio from a PC/TV/phone and plays it locally. Bluetooth output is disabled in SINK mode.

The ROM stack is unreliable with both A2DP roles active, so the module enforces **one mode at a time**.

## SINK codec note
**SBC enforcement has been removed**; codecs (AAC/SBC, as negotiated by the stack/devices) are allowed in SINK mode. **Note:** AAC A2DP *sink* decoding was previously observed to crash on this ROM/build (`SIGSEGV` in `aacDecoder_Fill`/`a2dp_aac_decoder_decode_packet`), causing no sound or Bluetooth instability in earlier testing. AAC sink has been tested working in recent checks on this setup, but reliability can vary by source/stream. If you experience **no sound, stutter, or Bluetooth restarts** in SINK mode, capture diagnostics (see below) and consider reverting to a previous release that forced SBC.

## Install / update
1. Flash the module zip in APatch/Magisk. Reboot if needed.
2. Control via **WebUI** (if supported): **Toggle Source/Sink** and **Restart A2DP Sink** (shown only in SINK mode). APatch **Action** button also toggles.

**Switching modes / after connecting:** changing **SOURCE ↔ SINK** restarts Bluetooth and can take **~10 seconds to 1 minute** (reconnection/service restart). After connecting in SINK mode, wait a few seconds for audio to start.

## Commands (root)
```sh
su -c /data/adb/a2dp-sink status     # show mode, properties, active peer, codec/state hints
su -c /data/adb/a2dp-sink toggle     # toggle SOURCE <-> SINK
su -c /data/adb/a2dp-sink on         # SINK/receiver mode (restarts Bluetooth)
su -c /data/adb/a2dp-sink off        # SOURCE/normal output mode (restarts Bluetooth)
su -c /data/adb/a2dp-sink restart    # restart Bluetooth in SINK mode (clean reconnect)
su -c /data/adb/a2dp-sink diag [60]  # capture logs/state while reproducing an issue
```

## No sound / troubleshooting
- **Wait 10s–1m** after connecting/switching modes — delay can look like no sound.
- **Quick fix:** toggle **Bluetooth OFF/ON on both devices**, then reconnect and play.
- **SINK mode:** open **WebUI** and tap **Restart A2DP Sink**, then reconnect. Fallback: `su -c /data/adb/a2dp-sink restart`.
- **SOURCE mode (9RT → device) codec issues:** if AAC won’t negotiate, **Forget & re-pair** the device on the 9RT and check configured codec.
- Check state/codec and crashes:
```sh
su -c 'dumpsys bluetooth_manager 2>/dev/null | grep -E "A2DP Sink State|A2DP Source State|Active peer|Connected|Streaming|Configured codec|SEP codec" | head -20; logcat -b crash -d -v time | tail -50'
```
If you see `aacDecoder`/`SIGSEGV`/`a2dp_aac_decoder_decode_packet` with SINK problems, that matches the previously observed AAC sink decoder crash on this ROM.

## Known limitations
- **Mode switching / reconnect** can take **~10 seconds to 1 minute**.
- **AAC sink stability is not guaranteed** on this ROM/build (previously unstable; SBC enforcement removed after testing). Test with your source devices.
- **Two devices can connect**, but automatic handover may not switch the sink’s active audio path on this vendor stack. Workaround: keep one active source at a time, or use **Restart A2DP Sink** and reconnect the device you want.
- **Not simultaneous source+sink** (exclusive modes). **ROM/device compatibility is limited.**

## Uninstall / recovery
Disable/remove the module in APatch/Magisk and reboot. Or: `su -c /data/adb/a2dp-sink off`. If a version causes issues, flash a previous release.

## Disclaimer
Provided **as-is**, with **no warranty**. Use at your own risk. Don’t blame me.
