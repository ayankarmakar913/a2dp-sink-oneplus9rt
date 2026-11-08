# A2DP Sink/Src Switcher — OnePlus 9RT (APatch/Magisk)

A Magisk/APatch module for **OnePlus 9RT (MT2111 / OP5155L1)** on **ColorOS 16 / Android 16 (Oplus/ColorOS Bluetooth stack)** that switches the phone between:

- **SOURCE mode** (normal): phone sends audio to Bluetooth headphones/earbuds.
- **SINK mode** (receiver): phone receives A2DP audio from a PC/TV/phone and plays it through the phone (speaker), while Bluetooth output is disabled.

This ROM’s stack is unreliable with both A2DP roles active, so the module enforces **one mode at a time**.

> **Targeted/tested setup:** OnePlus 9RT, ColorOS 16 / Android 16, APatch (root). It *may* work on very similar Oplus-stack ROMs for the same device, but **compatibility is not guaranteed** on other/custom ROMs or different Bluetooth stacks.

## ⚠️ WARNING — DO THIS AT YOUR OWN RISK

**READ THIS. SERIOUSLY. (BUT ALSO NOT THAT SERIOUSLY.)**

This module touches Bluetooth profile properties, interop configs, overlays, and restarts the Bluetooth stack as root. You are choosing to flash random code from the internet onto your rooted phone.

- **Do this at your own risk. Don’t blame me.**
- I am not responsible for bootloops, broken Bluetooth, lost pairings, bad audio, weird bugs, corrupted data, dead devices, thermonuclear incidents, alien invasions, timeline splits, or any other chaos that may or may not occur.
- **If you somehow start a nuclear war because of an A2DP sink module, I don’t care — I will laugh at you.**
- You are the captain now. Back up your stuff, know how to disable/remove Magisk/APatch modules, and only proceed if you understand what you’re doing.

## What it does
- Toggles **A2DP SOURCE/SINK** cleanly (restarts Bluetooth as needed) and re-applies the selected mode on boot.
- Enables the A2DP sink **audio-focus overlay** required for playback on this ROM.
- **Forces SBC for sink sources** to avoid this ROM’s broken AAC A2DP-sink decoder (`aacDecoder_Fill` SIGSEGV → “plays but no sound” / Bluetooth crash). **AAC sink is not supported on this ROM.**
- **Learns/remembers** new source devices (`learn`) so SBC forcing applies to them.
- Bundles **A2DP-QS.apk** (companion app) providing 2 Quick Settings tiles: **A2DP Mode** (toggle) and **Restart A2DP Sink**. The module attempts to install it on boot.

## Install
1. Download the latest zip from [**Releases**](../../releases).
2. Flash in **APatch/Magisk**.
3. Reboot if needed.
4. **One-time QS setup (Android limitation):** Quick Settings → Edit/Customize → add **“A2DP Mode”** and **“Restart A2DP Sink”**. Grant **root/su** to **A2DP Sink QS** when prompted. (Android does not allow auto-adding QS tiles.)

## Usage
```sh
su -c /data/adb/a2dp-sink status     # mode, props, peer/codec hints
su -c /data/adb/a2dp-sink toggle     # SOURCE <-> SINK
su -c /data/adb/a2dp-sink on         # SINK/receiver mode
su -c /data/adb/a2dp-sink off        # SOURCE/normal output mode
su -c /data/adb/a2dp-sink restart    # restart Bluetooth in SINK mode (clean reconnect)
su -c /data/adb/a2dp-sink learn      # fix a new device that has no sound, then reconnect it
su -c '/data/adb/a2dp-sink learn AA:BB:CC:DD:EE:FF'
su -c /data/adb/a2dp-sink diag 60    # capture logs/state while reproducing an issue
```

APatch module **Action** button toggles SOURCE/SINK.

## New device connects but no sound?
1. Connect/pair it in **SINK** mode.
2. Run `su -c /data/adb/a2dp-sink learn`
3. Reconnect and play. Learned prefixes are saved in `/data/adb/a2dp_sink_learned.conf`.

Check negotiated codec (should be **SBC**):
```sh
su -c 'dumpsys bluetooth_manager 2>/dev/null | sed -n "/A2DP Sink State/,/BTA AV State/p; /AVDTP Stack State/,/Socket Events/p"'
```

## Known limitations
- **AAC sink not supported** on this ROM; SBC is forced.
- **~10s delay** after connecting before audio may start (setup/focus/decoder/routing).
- **Multipoint handover is flaky** on this vendor stack: two devices may connect, but automatic “pause A, play B” switching may not move the active audio path. Use **Restart A2DP Sink** or reconnect the device you want.
- **ROM compatibility is limited** — depends on Oplus/ColorOS BT stack paths/behavior. Test carefully.

## Uninstall / recovery
Disable/remove the module in APatch/Magisk and reboot. Uninstall attempts to restore SOURCE mode and clean up helpers. If Bluetooth gets weird: `su -c /data/adb/a2dp-sink off`, or disable the module and reboot.

## Repo contents
- `module/` — module source
- Release assets — flashable zip(s)

## Disclaimer
Provided **as-is**, with **no warranty**. Use at your own risk. Don’t blame me. If international diplomacy collapses over a Bluetooth codec negotiation, I will still laugh at you.
