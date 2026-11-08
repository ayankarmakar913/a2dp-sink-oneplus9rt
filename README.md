# A2DP Sink/Source Switcher — OnePlus 9RT (APatch/Magisk)

A Magisk/APatch module that switches the phone between:
- **SOURCE mode** (normal): phone sends audio to Bluetooth headphones/earbuds.
- **SINK mode** (receiver): phone receives A2DP audio from a PC/TV/phone and plays it through the phone, while Bluetooth output is disabled.

## BEFORE YOU FLASH — READ THIS

- **THIS MODULE IS ONLY FOR OXYGENOS 16 ROM ON THE ONEPLUS 9RT (MT2111) ONLY.** Do **NOT** flash this on other devices, other OnePlus models, or different ROM bases unless you know exactly what you are doing and accept the risk.
- **Tested on:** **MT2111-OOS-16.0.5.1002-20260727-ARB** (OnePlus 9RT / MT2111), rooted with **APatch**.
- **ROM/BT stack specific:** relies on this ROM’s Bluetooth stack/paths/behavior (Oplus-style interop/config, A2DP role props, service restart). Other custom ROMs/BT stacks may not work.
- **Root + system-level changes:** modifies Bluetooth profile properties, writes interop config, enables an overlay, and restarts the Bluetooth stack.
- **AAC sink is broken on this ROM:** the module forces **SBC** for sink sources. AAC sink is not supported here.
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
   - **Restart A2DP Sink** (appears **only in SINK mode**) — use when switching to a different source device
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

## New device connects but no sound?
The source may negotiate AAC (broken on this ROM). Run `su -c /data/adb/a2dp-sink learn`, then reconnect the device. Configured codec should be **SBC**.


## Sink codec (SBC default; experimental options)
- **Only SBC is reliably supported as A2DP sink on this ROM.** The module forces SBC because the **AAC sink decoder crashes** (`aacDecoder_Fill` SIGSEGV). Other codecs (LDAC/aptX/LHDC) may have stack symbols/libs but are **not confirmed as stable A2DP sink decoders** here — trying them can cause “plays but no sound” or Bluetooth issues.
- **Commands (root):**
  - `su -c /data/adb/a2dp-sink codec status` — show policy
  - `su -c /data/adb/a2dp-sink codec sbc` — **safe default** (force SBC)
  - `su -c /data/adb/a2dp-sink codec backup` — backup interop/config before experiments
  - `su -c /data/adb/a2dp-sink codec auto-experimental` — **RISKY:** let the stack negotiate codecs (AAC may crash; others may not work). Test, then check `Configured codec` in `dumpsys bluetooth_manager`.
  - `su -c /data/adb/a2dp-sink codec revert` — restore backup and return to SBC
- **If something breaks:** `su -c /data/adb/a2dp-sink codec revert` (or `codec sbc`), then reconnect. Full safety backups may exist under `/data/adb/a2dp_sink_backup_*`.

## Known limitations
- **AAC sink not supported** (decoder crashes); SBC is forced by default. Other sink codecs are experimental/unconfirmed on this ROM.
- **After connecting, it may take a few seconds before music starts playing** (sometimes up to ~10s). Wait a bit — after that, playback should be fine.
- **Multipoint handover is flaky** on this vendor stack. Use **Restart A2DP Sink** / reconnect the device you want.
- **ROM compatibility is limited**.

## Uninstall / recovery
Disable/remove the module in APatch/Magisk and reboot. Or: `su -c /data/adb/a2dp-sink off`.

## Repo contents
- `module/` — module source (scripts, WebUI)
- Release assets — flashable zip

## Disclaimer
Provided **as-is**, with **no warranty**. Use at your own risk. Don’t blame me. If international diplomacy collapses over a Bluetooth codec negotiation, I will still laugh at you.
