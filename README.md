# KORG Electribe 2 Reverse Engineering

## Firmware
Firmware has been mainly reverse engineered using (Ghidra 11.1.2)[https://github.com/NationalSecurityAgency/ghidra/releases].
In the (Ghidra) project, `SBL.bin` is the E2 bootloader, where `HACKTRIBE.bin` is the firmware (I used a hacktribe patched E2 factory firmware).

## File formats
File formats have been reverse engineered using [ImHex](https://imhex.werwolv.net), which is an amazing hex editor.

### Installation & Usage

**Windows:** place under `C:\Program Files\ImHex\patterns\KORG Electribe 2\`

**Linux:** place under `~/.local/share/imhex/patterns/KORG Electribe 2/` or `/usr/share/imhex/patterns/KORG Electribe 2/`

Then, restart ImHex, and it'll auto-detect opened files that are KORG E2 related.
