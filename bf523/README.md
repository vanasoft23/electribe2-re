# BF523 extraction artifacts

These files are deterministic reconstructions of the BF52x loader stream
embedded at AM1802 address `0xC00F9E10` in `HACKTRIBE.bin`.

- `HACKTRIBE_BF523.ldr` is the exact `0x422A0`-byte loader stream.
- `loader_manifest.json` records every validated 16-byte header, stored payload
  hash, target, count, flags, stage, overlap check, and initialized range.
- `init_*` files reconstruct the loader's initialization DXE.
- `app_*` files reconstruct the application DXE by BF523 memory region.

Regenerate everything from the currently open Ghidra program and MCP server:

```powershell
python tools\extract_bf523_loader.py
```

The raw binary region files begin at the hexadecimal address in each filename.
Loader fill records repeat their 32-bit header argument in little-endian order;
large unloaded gaps inside a region are zero-filled only in the flat artifact.
The authoritative initialized sub-ranges are in `loader_manifest.json`; do not
infer that every byte in a file's envelope was explicitly loaded.

The exact loader stream has SHA-256:

```text
83259e30eec2c6586c3756fa3a75d1f831f02e2436d950c4fdb648322a9ca774
```

The locally installed Analog Devices GNU toolchain can disassemble a region,
for example:

```powershell
& 'C:\Program Files (x86)\Analog Devices\GNU Toolchain\2014R1_45\elf\bin\bfin-elf-objdump.exe' `
  -D -b binary -m bfin --adjust-vma=0xFFA00000 `
  app_l1_instruction_ffa00000.bin
```

Ghidra 12.1.2 did not ship a Blackfin processor module. The source under
`third_party/ghidra-blackfin` was adapted to Ghidra 12.1's loader API and built
successfully. Its SLEIGH module provides useful disassembly, but its upstream
README warns that many DSP p-code operations and exact parallel-execution
semantics remain unimplemented. Treat decompiler output accordingly.

The persistent project `ghidra/E2_BF523.gpr` contains two reconstructed
Blackfin programs:

- `/INIT/init_l1_instruction_ffa00000.bin` contains the two INIT-stage records.
- `/APP/app_l1_instruction_ffa00000.bin` contains the 151 application-stage
  records, including typed VDK thread templates and the confirmed startup,
  exception, kernel, and thread-entry labels.

`tools/ghidra/ImportBf523Loader.java` performs the validated sparse import;
`tools/ghidra/AnnotateBf523App.java` reapplies the evidence-backed application
annotations. Unloaded gaps remain uninitialized in Ghidra and are not confused
with the repeated-dword fill records represented by initialized blocks.

The external-SDRAM image is also imported as
`ghidra/E2_BF523_Parser.gpr`. `tools/ghidra/AnnotateBf523FxCtrlParser.java`
records the confirmed UART0 FxCtrl/MRx parser state and message-buffer fields.
