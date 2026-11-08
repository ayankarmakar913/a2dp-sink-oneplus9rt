# A2DP Sink/Source Switcher — OnePlus 9RT (APatch/Magisk)

A Magisk/APatch module that switches the phone between:
- **SOURCE mode** (normal): phone sends audio to Bluetooth headphones/earbuds.
- **SINK mode** (receiver): phone receives A2DP audio from a PC/TV/phone and plays it through the phone, while Bluetooth output is disabled.

## BEFORE YOU FLASH — READ THIS

- **THIS MODULE IS ONLY FOR OXYGENOS 16 ROM ON THE ONEPLUS 9RT (MT2111) ONLY.** Do **NOT** flash this on other devices, other OnePlus models, or different ROM bases unless you know exactly what you are doing and accept the risk.
- **Tested on:** **MT2111-OOS-16.0.5.1002-20260727-ARB** (OnePlus 9RT / MT2111), rooted with **APatch**.
- **ROM/BT stack specific:** relies on this ROM’s Bluetooth stack/paths/behavior (Oplus-style interop/config, A2DP role props, service restart). Other custom ROMs/BT stacks may not work.
- **Root + system-level changes:** modifies Bluetooth profile properties, writes interop config, enables an overlay, and restarts the Bluetooth stack.
- **AAC *sink* (receiving) is broken on this ROM:** in **SINK mode** the module forces **SBC** to avoid the AAC sink decoder crash. **SOURCE mode** (normal output) is unaffected and can use **AAC/other supported codecs** to your headphones/devices.
- **Have recovery ready:** know how to disable/remove APatch/Magisk modules if Bluetooth/boot behavior becomes problematic. Back up important data.

## ⚠️ WARNING — DO THIS AT YOUR OWN RISK

You are choosing to flash random root code from the internet onto your phone.
- **Do this at your own risk. Don’t blame me.**
- I am not responsible for bootloops, broken Bluetooth, lost pairings, bad audio, weird bugs, corrupted data, dead devices, thermonuclear incidents, alien invasions, timeline splits, or any other chaos.
- **If you somehow start a nuclear war because of an A2DP sink module, I don’t care — I will laugh at you.**
- You are the captain now. Only proceed if you understand what you’re doing.

## Install & control (easy)
1. Download the zip from [**Releases**](../../releases) and flash in **APatch/Magisk**. Reboot if needed.
2. **WebUI (recommended):** APatch → module → **WebUI**.
   - **Toggle Source / Sink**
   - **Restart A2DP Sink** and **Fix no-sound device (SBC)** appear **only in SINK mode** — use when switching to a different source device
   - *If your APatch build doesn’t support module WebUI exec, the buttons may not run; use the Action button or commands below.*
3. **APatch Action button:** toggles Source/Sink.

**After connecting in SINK mode:** it may take a few seconds before music starts playing — wait a bit and it should be fine.
4. **Commands (root fallback):**
   ```sh
   su -c /data/adb/a2dp-sink status
   su -c /data/adb/a2dp-sink toggle    # Source <-> Sink
   su -c /data/adb/a2dp-sink restart   # restart Bluetooth in SINK mode
   su -c /data/adb/a2dp-sink learn     # fix a new device with no sound, then reconnect
   su -c '/data/adb/a2dp-sink learn AA:BB:CC:DD:EE:FF'
   ```

## No sound / troubleshooting
- **Quick fix:** if you get no sound, **turn Bluetooth OFF and ON once on both the source and receiver (9RT) devices**. This usually fixes it.
- **If still no sound:** open **Magisk/APatch → module → WebUI** and tap **Restart A2DP Sink** (in **SINK mode**) once, then reconnect. (Fallback: `su -c /data/adb/a2dp-sink restart`)
- **SINK mode, new device has no sound:** source may negotiate AAC (AAC *sink* crashes on this ROM). Use WebUI **Fix no-sound device (SBC, SINK)** or run `su -c /data/adb/a2dp-sink learn`, then reconnect — negotiated codec should be **SBC**.
- **SOURCE mode (9RT sending audio) — AAC/codec issues:** SBC-forcing applies only in SINK mode. If AAC won’t negotiate to a device, **Forget & re-pair** that device on the 9RT and ensure the 9RT isn’t stuck with stale BT codec/interops; then check the configured codec.



## Known limitations
- **SINK mode:** **AAC sink not supported** (decoder crashes on this ROM) — **SBC is forced** when receiving. **SOURCE mode:** normal output; **AAC/other codecs can work** (SBC not forced by the module in source mode).
- **After connecting (SINK),** it may take a few seconds before music starts (sometimes up to ~10s).
- **Multipoint handover is flaky** on this vendor stack. Use **Restart A2DP Sink** / reconnect the device you want.
- **Not simultaneous source+sink** (exclusive modes). **ROM compatibility is limited.**

## Uninstall / recovery
Disable/remove the module in APatch/Magisk and reboot. Or: `su -c /data/adb/a2dp-sink off`.

## Repo contents
- `module/` — module source (scripts, WebUI)
- Release assets — flashable zip

## Disclaimer
Provided **as-is**, with **no warranty**. Use at your own risk. Don’t blame me. If international diplomacy collapses over a Bluetooth codec negotiation, I will still laugh at you.
