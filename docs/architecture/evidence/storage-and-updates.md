# Serial flash, SD resources, and VSB updates

> Detailed evidence extracted from the original monolithic ARCHITECTURE.md.
> Ghidra is authoritative for current symbols, types, comments, and cross-references.

## CPU SPI1 SerialFlash

- `GetOrCreateSerialFlashContext` (`0xC0029A40`) lazily allocates a 0x38-byte
  CPU-side wrapper. `ConstructSerialFlashContext` (`0xC0029A10`) initializes
  observed sentinel bytes at wrapper `+0x0D` and `+0x35`, allocates an 8-byte
  hardware context, and stores it at wrapper `+0`. `ConstructSerialFlashSpi1`
  (`0xC001E3F0`) binds GPIO0 and SPI1, releases chip select, and initializes
  SPI1 with format index 0. The wrapper is consumed by panel identity, PCM
  resource loading, persistent-resource writes, project/resource handlers, and
  DSP-counter persistence.
- Ghidra now models that wrapper as `SerialFlashContext` (size `0x38`), with
  `pHardware_context` at `+0`, cached 16-byte views at `+0x04`, `+0x14`, and
  `+0x24`, and the two-byte Slice view at `+0x34`. The embedded 8-byte
  `serial_flash_t` remains the SPI1/GPIO register-pointer object. The shared
  pointer slot at `0xC0029A70` is typed as `SerialFlashContext **`.
- The embedded context contains GPIO0 and SPI1 register pointers. The SPI1
  configuration uses `SPI1_Init` (`0xC0018DDC`) and format value `0x00010308`.
  `AssertSerialFlashChipSelect` (`0xC001EB7C`) drives the SPI1 flash-select
  GPIO low and delays 2 ms; `ReleaseSerialFlashChipSelect` (`0xC001EBBC`)
  delays 2 ms and drives it high.
- `ReadSerialFlashBytes` (`0xC001E4AC`) validates a 24-bit address, rejects a
  busy device using status bit 0, sends opcode `0x03` plus a three-byte
  big-endian address, receives the requested byte range, and releases chip
  select. `ReadSerialFlashStatus` (`0xC001E9CC`) sends opcode `0x05` and
  returns one status byte. `EnableSerialFlashWrite` (`0xC001EA70`) sends
  opcode `0x06` and requires status bit 1 to become set.
- `WriteSerialFlashSectors` (`0xC001E57C`) operates on 4-KiB sectors. Each
  sector is erased with opcode `0x20` and a sector address shifted by 12 bits,
  then filled by sixteen 256-byte page programs using opcode `0x02` and page
  addresses shifted by 8 bits. `WaitForSerialFlashReady` polls status bit 0
  with one-microsecond delays, and `DisableSerialFlashWrite` sends opcode
  `0x04` and verifies that status bit 1 cleared.
- `ReadSerialFlashMutexed` (`0xC0029A74`) and `WriteSerialFlashMutexed`
  (`0xC0029AB8`) serialize access with RTOS mutex 2. The write wrapper handles
  arbitrary byte ranges by preserving partial 4-KiB sectors in the shared
  scratch buffer at `DAT_c0029c10`; aligned full sectors use the sector writer
  directly. `MapSerialFlashRegionIndex` (`0xC0029C14`) maps selectors below
  `0x100` to selector `<< 16` addresses. Confirmed wrapper regions include
  selector `0x80` (`0x800000`) for the PCM image, selector `0x6B`
  (`0x6B0000`) for the persistent PCM image, selector `0x23`
  (`0x2300000`) for a 0x100-byte persistent record, selector `0x24`
  (`0x2400000`) with optional 0x4000-byte bank offsets for the voice-assignment
  image, selector `0x22` (`0x2200000`) for a 16-byte signature record, and selector
   `0x63` (`0x630000`) for the 0x100-byte record read by handler-0x11 stage 1, and
   `0x64` (`0x640000`) for the SQEZ stream read by handler-0x11 stage 0. Handler-0x11
   stage 1 copies the selector-`0x63` image through the shared control object before
   writing the resulting 0x100-byte payload to selector `0x23`.
- `ReadPcmSerialFlashImage` (`0xC0029F54`) reads the PCM region at `0x800000`
  plus a caller offset; `GetPcmSerialFlashImageSize` (`0xC0029F88`) returns
  the observed 0x800000-byte image span. `ReadPersistentPcmFlashImage`
  (`0xC002A1E8`) and `WritePersistentPcmFlashImage` (`0xC002A218`) access the
  `0x6B0000` region. `WriteVoiceAssignmentSerialFlashImage`
  (`0xC002A0C4`) writes the large selector-`0x24` image, while
  `WritePersistentProjectFlashImage` (`0xC002A128`) writes the selector-`0x23`
  image. `WriteAndVerifySerialFlashRegion` (`0xC0029CBC`) writes a selected
  region, reads it back in chunks up to 0x10000 bytes, and compares each chunk.
- The CPU's diagnostic/version display reads separate metadata records from
  SerialFlash. `ReadMainVersionRecord` (`0xC0029DEC`) reads selector `0x21`
  offset `0xFFF0` (the 16 bytes immediately preceding selector `0x22`) and
  its returned bytes `+4/+5/+6` are formatted as `Main : %02d.%02d.%02d`.
  `ReadPcmVersionRecord` (`0xC0029E20`) reads the first `0x40` bytes of the
  selector-`0x80` PCM region; `ReadSliceVersionRecord` (`0xC0029E98`) reads
  selector `0x75` offset `0x70000` and uses its first two bytes; together they
  feed `PCM/Slice : %02d.%02d/%02d.%02d`. `ReadUserVersionRecord`
  (`0xC0029EDC`) reads selector `0x22` and feeds the displayed User version.
  In Ghidra, the Main/PCM/User readers now return a generic 16-byte
  `SerialFlashVersionRecord16 *`, while the Slice reader returns a two-byte
  `SerialFlashVersionRecord2 *`; these names document cache extent and byte
  offsets only, not vendor field semantics. The mutexed read/write wrappers
  are typed against `SerialFlashContext *`, which matches their dereference of
  the wrapper's embedded hardware-context pointer.
  The displayed `Boot : %02d.%02d.%02d` line does not use a recovered CPU
  flash reader: the diagnostic consumer obtains its three values from the
  first three dwords of `GetPanelDiagnosticRecord` (`0xC002CA0C`), whose
  pointer targets `0x8001B000` outside the loaded CPU image. This is likely
  boot-stage/panel diagnostic state, but the producer is absent, so it cannot
  be equated with the `BOOT.VSB` payload version from CPU code alone.
  `BuildVoiceServiceDiagnosticsReport` (`0xC0075A24`) assembles these values
  into the type-0 service's `Diagnostics` report and then sets the observed
  indicator state; this is a diagnostic-display path, not an additional VSB
  loader.
   These display records are distinct from the VSB header revision pair at
   `+0x2A/+0x2B`; their vendor-level layouts remain unresolved.
  - The ARM runtime division helpers now have evidence-backed prototypes in
    Ghidra. `UnsignedDivide32` (`0xC00021FC`) and
    `SoftInt_DivideSigned32Core` (`0xC0002318`) each take two 32-bit operands;
    `UnsignedDivide32WithRemainder` (`0xC00022F0`) and
    `SignedDivide32WithRemainder` (`0xC0002438`) return the quotient in `r0`
    and remainder in `r1`, represented by Ghidra as a 64-bit pair. The 64-bit
    signed divider at `0xC0003698` consumes two register-pair operands and
    returns a register-pair quotient. `CountLeadingBitsForDivide`
    (`0xC0003FD8`) is the one-argument lookup helper used by the dividers.
    These corrections remove the former zero-parameter/`extraout_r1` artifacts
    from LCD metrics, timing, PCM-resolution, and flash-metadata paths.
  - The flash-metadata construction path also has corrected call boundaries:
    `FUN_c005713c` (`0xC005713C`) takes an input offset and destination buffer,
    `FUN_c00574BC` (`0xC00574BC`) takes only the flash offset and returns a
    status, `memset` (`0xC0009A84`) and `optimized_copy` (`0xC000985C`) use
    their observed three-argument memory ABIs, and `FUN_c0056b1c`
    (`0xC0056B1C`) stores one 32-bit value through a two-argument wrapper.
  - A separate 0x28-byte `LcdTextContext` class is now recovered in Ghidra for
   the LCD diagnostic text renderer. `GetOrCreateLcdTextContext`
   (`0xC0075C38`) owns a singleton pointer slot, allocates 0x28 bytes on first
   use, and calls `LcdTextContext::ConstructLcdTextContext`
   (`0xC0075C18`). The constructor installs the dispatch-table pointer from
   `DAT_c0075c34` (target `0xC00E4460`) and calls
   `LcdTextContext::InitializeLcdTextContextState` (`0xC0075B90`), which obtains
   the current glyph metrics, initializes the 128x64 viewport, and invokes the
   diagnostics builder. The recovered structure layout is: `+0x00` dispatch
   table pointer; `+0x04/+0x08` origin X/Y; `+0x0C` glyph advance width;
   `+0x10` glyph height; `+0x14/+0x18` cursor X/Y; `+0x1C` parser state;
   `+0x20/+0x24` two ANSI cursor parameters. The class members recorded in the
   Ghidra database are `AppendCharacter` (`0xC0072020`), `AppendString`
   (`0xC007220C`), `AppendFormatted` (`0xC007223C`),
   `UpdateLcdTextDisplayAfterScroll` (`0xC0071E3C`), `EraseLcdTextLine`
   (`0xC0071F78`), and `ClearLcdTextDisplay` (`0xC0071FDC`), plus the
   constructor and initializer above. `AppendFormatted` is a variadic
   `__thiscall` method that wraps the firmware formatter with an 81-byte local
   buffer before appending the result; its apparent extra parameters are
   preserved register/stack varargs, not additional object state.
 - `BuildVoiceServiceDiagnosticsReport` (`0xC0075A24`) is a free function with
  one explicit parameter, `LcdTextContext *context`. Its first append emits
  the control-prefixed `Diagnostics` title and has no conversions; subsequent
  calls pass the version values described above. The earlier four-parameter
  prototype was corrected in Ghidra. The character path still copies the
  incoming `r3` low byte into a temporary glyph buffer; no caller establishes
  a stable semantic for that residual register value, so it remains
  explicitly unresolved.
  The recovered call chain now types the serial-flash context and version
  records, the external `PanelDiagnosticRecord *`, the `PanelCommandGateState *`
  used to queue the `0x80` identity request, the `uint` response getter, and
  the `gpio_regs_t *` indicator helpers. The remaining `in_r2`/`in_r3` shown
  at the title append are the uninitialized ARM variadic registers passed to
  `LcdTextContext::AppendFormatted`; they are not additional
  `BuildVoiceServiceDiagnosticsReport` parameters.
 - A 0x1C-byte `VoiceServiceStep` worker object is recovered in Ghidra. Its
   initializer `VoiceServiceStep::InitializeVoiceServiceStepObject`
   (`0xC0075C6C`) stores the worker dispatch pointer at `+0x00`, the owning
   voice-service pointer at `+0x04`, the singleton `LcdTextContext *` at `+0x08`,
   and the `FUN_c0072964` result at `+0x0C`; it clears the byte/word state at
   `+0x10`, `+0x14`, and `+0x18`. `ProcessVoiceServiceStateMachine`
   (`0xC0076D98`) allocates 0x1C bytes and installs this worker at service
   `+0x78` for selected states. `RunVoiceServiceStep` (`0xC0076060`) now has
   the evidence-backed signature `uint (VoiceServiceStep *step, uint stage,
   int phase)`. The owner pointer is now typed as
   `MainCommonMessageService *`; the shared-context concrete type and the
   worker dispatch slots remain unresolved.
 - A polymorphic `VoiceServiceStateBase` prefix is recovered in Ghidra as a
   0x10-byte common structure: dispatch pointer at `+0x00`, owning
   voice-service pointer at `+0x04`, `LcdTextContext *` at `+0x08`, and the
   `FUN_c0072964` result at `+0x0C`. Its base initializer
   `VoiceServiceStateBase::InitializeVoiceServiceStateObjectBase`
   (`0xC0075CAC`) installs the base dispatch table at `0xC00E44E8` and is
   reused by `SelectVoiceServiceStateObject` (`0xC0075E68`) before
   variant-specific dispatch tables are installed. The selector allocates
   variants from 0x14 through 0x58 bytes, and the service invokes their
   virtual slots. The owner pointer is typed as `MainCommonMessageService *`.
   Selector-based derived classes are recorded in Ghidra as
    `VoiceServiceStateVariant0` through `VoiceServiceStateVariant7`,
    `VoiceServiceBatteryDcDiagnosticsState` (factory selector 8), plus
    `VoiceServiceStateVariantDefault`. The selector-8 class name is
    evidence-backed by its battery/DC diagnostic strings and message flow.
    Their recovered allocation sizes
   are `0x18`, `0x18`, `0x1C`, `0x20`, `0x58`, `0x18`, `0x40`, `0x28`, `0x18`,
   and `0x14` for the default path. The unique vtable processing methods are
   associated with those classes in the Ghidra database. `Variant3`, `Variant4`,
   `Variant5`, `Variant6`, `Variant7`, and `Variant8` have evidence-backed
   initializers; selectors 0–2 and the default path use the common base
   initializer followed by selector-specific table/field initialization in
    the factory. All recovered derived initializers now explicitly take the
    owning `MainCommonMessageService *` parameter in Ghidra; the former
    `undefined` owner parameters were ABI artifacts.
 - The main 0x1E8-byte object is recorded in Ghidra as
   `MainCommonMessageService`. Its vtable at `0xC00E43D8` has the verified
   constructor/destructor, activation, receiver-queue, dispatcher, and
   type-handler members. `DispatchVoiceServiceCommonMessage` (`0xC00773FC`)
   has effective prototype `void (MainCommonMessageService *this,
   CommonMessage *message)`; the `CommonMessage` structure is 0x10 bytes with
   a wrapper vtable pointer at `+0x00`, a type byte at `+0x04`, and payload
   words at `+0x08` and `+0x0C`. The packed payload's subtype bytes are read
   from its `+0x09` and `+0x0A` byte positions where required.
   `ProcessCommonMessageReceiverQueue` (`0xC00713B4`) takes only `this` and
   supplies the message pointer to the dispatcher. The type-1, type-4, type-5,
   type-6, type-7, and type-0x0C vtable handlers retain the message pointer as
   their second argument. `SelectVoiceServiceStateObject` (`0xC0075E68`) is a
   free helper with effective prototype `void (MainCommonMessageService *service,
   uint state_index)`; apparent third-argument use was a register/varargs artifact.
   `ProcessVoiceServiceStateMachine` (`0xC0076D98`) is entered by a tail branch
   from the type-0 dispatcher path and consumes only the service pointer.
- The shared common-message service boundary is now recovered as the
  `CommonMessageServiceBase` class in Ghidra. It is a 0x74-byte object with
  its vtable at `+0x00`, receiver pointer at `+0x0C`, an embedded
  `VoiceTaskServiceState` object at `+0x10` (0x60 bytes), active/pending
  bytes at `+0x70/+0x71`, and two reserved tail bytes. Its initializer,
  destructor, deleting-destructor wrapper, activation method, queue
  processor, and common-message dispatcher are recorded as class members.
  The destructor sequence switches through under-destruction vtables and
  tears down the embedded state; this is why the mode-specific objects below
  are modeled as derived layouts rather than unrelated 0x7C-byte records.
- `Mode2CommonMessageService` and `Mode5CommonMessageService` are recorded
  in Ghidra as separate 0x7C-byte classes. Both contain the common base at
  `+0x00`, a secondary vtable pointer at `+0x74`, and a secondary state
  pointer at `+0x78`. Mode 2 uses outer vtable `0xC00E4BB8`, a two-type
  dispatcher (`0xC00833F0`), and its own lifecycle/queue members. Mode 5
  uses outer vtable `0xC00E5598`, retains the shared dispatcher, and has
  payload-forwarding members (`0xC008EB08` and `0xC008EAE4`) that pass both
  message payload words and the wrapper to secondary-state vtable slots.
  The secondary-state fields and product-level mode meanings remain
  unresolved.
- The mode-2 secondary allocation is separately recorded as the
  `Mode2SecondaryObject` class, size 0x24. Its initializer
  (`0xC006CD18`) installs vtable `0xC00E3CE8`, clears the entry-list pointers
  at `+0x10/+0x14/+0x18`, clears activity bytes at `+0x1C/+0x1D`, allocates
  a 0x200-byte table-state object at `+0x20`, and appends that object to the
  entry range. Mode-2 type 3 (`0xC00832C8`) forwards both payload words to
  this object's secondary vtable slot `+0x20`; the table-state contract is
  unresolved.
- The mode-5 secondary allocation is recorded as the generic
  `Mode5EmbeddedState` class, size 0x80, with initializer
  `Mode5EmbeddedState::InitializeMode5EmbeddedStateObject` (`0xC006E278`).
  The initializer installs a separate vtable, creates two 0x9C-byte child
  records at `+0x20/+0x24`, and stores an alias at `+0x60` to the bound words
  at `+0x64/+0x68`. `UpdateMode5EmbeddedStateBounds` (`0xC006E41C`) tracks
  observed minima/maxima in `+0x64/+0x68/+0x6C/+0x70` and forwards a
  serialized pair to the second child record. `HandleMode5EmbeddedStateCommand`
  (`0xC006E5DC`) recognizes command IDs `9`, `0x0D`, and `0x22`, with the
  latter advancing the bounded progression index at `+0x74`. The remaining
  fields and virtual-operation meanings are intentionally unresolved.
- `ProbeSerialFlashRegion22Record` (`0xC0029D78`) reads a 16-byte selector-`0x22`
  record through the mutexed SerialFlash path. Its comparisons begin at record
  offset `+0x04`, not at the record start: `elec2USR` maps to product-version
  enum `0x123` (E2 Synth), `ele2sUSR` maps to `0x124` (E2 Sampler), and any
  other value returns zero. It is an identity/classification helper, not a
  timeout probe. `QueryPanelControllerIdentity` accepts only `0x124` from this
  fallback when the panel's UART-reported variant decodes to zero.

## CPU SD-card VSB flash-image update service

  - `ConstructSdPrefixText` (`0xC003568C`) creates the reference-counted text
  object `"SD:"`. `ConstructProductResourceRoot` (`0xC0035720`) selects the
  product resource root from the version enum: `0x123` selects
  `"KORG/electribe/"`, while `0x124` selects `"KORG/hacktribe/"`; other
  values select the observed empty string. `ConstructProductDirectoryName`
  (`0xC00356D4`) is the related component-only helper: `0x123` selects
  `"electribe"`, `0x124` selects `"hacktribe"`, and other values select an
  empty string. `ConstructSystemResourceName` (`0xC003576C`) creates the text
  object `"System"`.
- `GetSdResourceRootStatus` (`0xC0035458`) is a zero-argument status gate used
  by the pattern-resource handlers and related resource paths. It invokes the
  resource-variant builder for `SD:KORG`; if that result maps to zero, it
  retries `SD:KORG/hacktribe`. For variant results `0..12`, the observed
  handler-status map is `{0,4,4,2,4,4,4,6,0x0F,4,3,4,2}`; out-of-range
  results return `4`. This resolves the helper's control-flow mapping, but not
  the underlying variant-class meanings.
- `AppendCpuRefcountedTextObject` (`0xC00A2A68`) appends one managed text
  object to another. `BuildResourcePathWithSuffix` (`0xC003076C`) retains the
  base managed text and appends a NUL-terminated suffix. Together, the paths
  assembled by the validator are `SD:KORG/hacktribe/System/SYSTEM.VSB`,
  `SD:KORG/hacktribe/System/BOOT.VSB`, `SD:KORG/hacktribe/System/USER.VSB`,
  `SD:KORG/hacktribe/System/PCM.VSB`, and
  `SD:KORG/hacktribe/System/SLICE.VSB` in this sampler firmware image.
- `ValidateSystemResourcePackage` (`0xC0030790`) is a preflight/compatibility
  validator, not a panel query. It probes the four companion paths
  `BOOT.VSB`, `USER.VSB`, `PCM.VSB`, and `SLICE.VSB`, then opens the
  `System` resource context, reads a 0x100-byte header through the shared
  CPU resource scratch buffer, validates the header/type fields, and requires
  the six-byte record name `System` at record offset `+0x20`. It decodes the
  payload length from header bytes `+0x3C..+0x3F` and compares it with the
  serial-flash-derived selector-`0x22`/selector-`2` span of `0x200000` bytes.
  Zero from any preliminary `AcquireCpuResourceRecord` call records successful
  acquisition in the second diagnostic byte; the code later uses that byte as
  a status-reconciliation gate. Thus this is an acquisition-success flag, not
  a panel-UART timeout indicator.
- The resource record's revision pair at `+0x2A/+0x2B` is copied to the
  diagnostic bytes at `0xC03405BA..0xC03405BB`. A pair greater than or equal
  to `(2,2)` allows the System image; the global state byte at `0xC03404C4`
  equal to `3` also allows it. The four-byte diagnostic area at `0xC03405B8`
  is therefore: `+0` System-image accepted, `+1` at least one companion
  acquired, and `+2/+3` the copied System revision pair. The function writes
  its final one-byte status to the caller's object at `+0x18`, returns that
  same byte, and records the observed status mapping for the main `System`
  resource acquisition:
  lookup result `0` → `0`, result `3` or `0x0C` → `2`, result `4` or `5` →
  `0x17`, other result → `4`; short scratch capacity → `0x24`, read failure →
  `4`, malformed/incompatible header or payload length → `0x18`. The revision
  comparison is performed after sign-extending both header bytes, so it is a
  signed-byte lexicographic comparison in the implementation. After the
  System path, if the System image was not accepted but the companion-acquired
  flag is set, reconciliation overwrites the status with zero; otherwise it
  preserves the mapped/validation result. This allows a component-only update
  set to pass this preflight even when the System image is absent or
  incompatible.

- The VSB update dispatcher is `ProcessVsbUpdateSequence` (`0xC003A738`).
  Before dispatching, it applies a battery-safety gate: when shared
  listener-state `+0x308` is zero, the battery client classification at
  `+0x328` must be at least `2`; otherwise it returns status `0x1A` without
  running any bundle handler. A nonzero shared listener-state value bypasses
  this gate. Since the classification uses the chemistry-selected threshold
  table, the Ni-MH/Alkali setting affects whether an update is admitted at a
  given measured battery value. Its handlers process System, BOOT, PCM, USER,
  and SLICE bundles in that order. Each loader opens the corresponding file under
  `SD:KORG/hacktribe/System/`, validates the common 0x100-byte resource
  header, reads the payload length, and writes the payload to a dedicated
  serial-flash region with `WriteAndVerifySerialFlashRegion`.
- The software-update service also exposes a separate product-aware handler,
  `ProcessSystemVsbInstallRequest` (`0xC003AB6C`). It performs the same battery
  admission check, brackets `InstallSystemVsbForCurrentProduct` with the
  service lifecycle helpers, publishes the result at handler state `+0x18`, and
  sets a separate success latch only for installer status zero. This is not an
  alternate spelling of the five-image sequence: the sequence calls the more
  permissive `LoadSystemVsbToSerialFlash` path, while this handler calls the
  identity/revision-qualified installer.
- `BOOT.VSB` is the boot-region image: `LoadBootVsbToSerialFlash`
  (`0xC002F5A8`) writes selector `0`, whose next boundary is selector `2`,
  giving a `0x20000`-byte / 128-KiB span. This matches the known factory
  bootloader span. The code proves the destination and size, but does not by
  itself prove whether the file contains all or only part of the first-stage
  bootloader.
 - `SYSTEM.VSB` is the main CPU system/application image:
   `LoadSystemVsbToSerialFlash` (`0xC003A8A0`) writes selector `2`, bounded by
   selector `0x22`, giving a `0x200000`-byte / 2-MiB span. This matches the
   known factory firmware-image span.
 - The product-aware installer `InstallSystemVsbForCurrentProduct`
   (`0xC003AC74`) performs a stricter System update path. It classifies the
   installed selector-`0x22` identity (`0x123` Synth or `0x124` Sampler),
   decodes the candidate header identity from `+0x2C..+0x2E`, requires the
   identities to match, and applies product-specific minimum revision pairs:
   `(1,0x11)` for `0x123` and `(2,2)` for `0x124`. It then requires the exact
   0x200000-byte payload and writes/verifies selector `2`. This confirms that
   the System bundle is product/version-qualified firmware, not just arbitrary
   resource data.
- `PCM.VSB` is the PCM/sample image: `LoadPcmVsbToSerialFlash`
  (`0xC003845C`) requires exactly `0x800000` bytes and writes selector
  `0x80`, matching the CPU PCM flash-image region used by the PCM table/data
  loader.
- `SLICE.VSB` is the slice-resource image: `LoadSliceVsbToSerialFlash`
  (`0xC003A388`) writes selector `0x75` and limits the payload to the span
  between selectors `0x75` and `0x7E`, `0x90000` bytes / 576 KiB. Its header
  record name is `SLICE`. The runtime consumer is
  `ReadSliceSerialFlashImage` (`0xC002A1B8`), called by
  `Pcm_RebuildRuntimeSampleCatalog` (`0xC004F490`): it reads the selector-`0x75`
  region and treats the image as `0x444`-byte per-resource records. Eligible
  records are copied into the corresponding `0x45C` PCM runtime record at
  `+0x18`, which contains the 64 slice records, active-step map, and slicing
  summary. The `0x444` bytes match the ELSI tail from offset `+0x50` through
  `+0x493` in the project’s `0x494`-byte `WaveEsliData` layout; they map to
  runtime bytes `+0x18..+0x45B`. The surrounding image-level record
  organization remains unresolved.
 - The same update family also contains `USER.VSB`, which writes selector
   `0x22` with a maximum span of `0x490000` bytes. This connects the
   `elec2USR`/`ele2sUSR` identity record to the user-flash region, but is outside
   the three files requested here. `LoadUserVsbToSerialFlash` uses product enum
   `0x124` when constructing the sampler resource root in this image and, after
   a successful write, reloads the default serialized VoiceTask control image.
   The firmware does not establish what the acronym `VSB` expands to.

## Update-path memory-safety and authenticity audit

- `InstallSystemVsbForCurrentProduct` (`0xC003AC74`) has no direct source-buffer
  overflow in the accepted path. `GetCpuResourceScratchBuffer` returns the
  shared buffer pointer `0xC0D3A940` and reports capacity `0x01A00100` from
  `0xC0036A00`; the installer accepts only the exact
  `GetSystemVsbFlashSpan()` value `0x200000` and passes that same bounded length
  to the flash writer. `WriteAndVerifySerialFlashRegion` verifies in chunks of
  at most `0x10000` bytes. Its selector is the constant `2`, mapping to
  physical flash offset `0x200000`, so this function does not directly select
  the bootloader range.
- There is a confirmed short-read contract flaw. `ReadCpuResourceStream`
  (`0xC009DD74`) first clamps a request to the resource record's remaining
  extent, accumulates the actual count in its out-parameter, and returns zero
  when that clamped amount is consumed. Thus zero does not prove that the
  original request was completely satisfied. The VSB loaders, including
  `InstallSystemVsbForCurrentProduct` and `LoadBootVsbToSerialFlash`, test only
  the return code and ignore the actual-count out-parameter. If malformed
  resource metadata exposes an extent shorter than the requested header or
  payload, the loader can validate old bytes left in the shared scratch buffer
  and write a prefix-plus-stale-tail image. The accepted update sizes remain
  below scratch capacity, so this is an integrity/availability issue rather
  than a demonstrated linear buffer overflow; proving attacker control of the
  record extent requires the remaining resource-container parser audit.
- The bootloader write is a separate trust-boundary problem. The standard
  `ProcessVsbUpdateSequence` (`0xC003A738`) invokes
  `RunBootVsbUpdate`/`LoadBootVsbToSerialFlash` after the System step. The boot
  loader accepts a `BOOT` record with shared magic, format `0x23` or `0x24`,
  and exact payload length `0x20000`, then writes selector `0` (physical flash
  offset `0`). No product identity, public-key signature, or cryptographic
  digest verification is visible in this CPU-side path. `InstallSystemVsbForCurrentProduct`
  adds product/revision checks for `SYSTEM.VSB`, but those are not authenticity
  checks; the ordinary sequence uses the more permissive
  `LoadSystemVsbToSerialFlash` instead. Consequently, an attacker who can
  place a structurally valid update resource on the SD card and trigger the
  update flow can supply executable boot-region contents without needing a
  memory-corruption exploit. Whether an additional check exists outside this
  CPU update service remains a separate bootloader/SBL audit item.
- The shared flash sink is intentionally generic: `WriteAndVerifySerialFlashRegion`
  does not enforce a selector-specific region length. Its current VSB callers
  use constants and perform their own size checks, while the lower-level sector
  writer rejects physical sector indices outside `0..0xFFF`. Hardening should
  still move the region boundary check into the sink so future callers cannot
  turn a selector/length mistake into a cross-region write.

## SD-card block-transfer memory-safety audit

- `ReadSDCardBlocks` (`0xC001B2E0`) and `WriteSDCardBlocks`
  (`0xC001B4EC`) are the SD I/O vtable methods at the block-transfer layer.
  Both accept a caller buffer, a starting block, and a block count, but neither
  accepts a buffer capacity. Their card-range test is effectively
  `start < capacity && start + count <= capacity && count != 0`, with the
  addition performed as 32-bit unsigned arithmetic. A caller-supplied count
  that wraps `start + count` can therefore pass the check. The loop then
  transfers that count and advances the caller pointer by `0x200` bytes per
  block: the read method can overwrite past the destination, and the write
  method can read past the source. This is a confirmed defensive memory-safety
  defect in the public method contract; the direct SD-file exploitability is
  not established because the valid CPU resource path normally supplies small
  block counts.
- The normal resource path is bounded by two separate format/caller rules.
  `BuildCpuResourceRecordFromSelector` (`0xC009C0F0`) accepts record block
  sizes only in `0x200..0x800` and requires the encoded block-count byte at
  record `+0x41` to be a nonzero power of two (maximum possible byte value
  `0x80`). `ReadCpuResourceStream` then converts each requested byte count to
  `ceil(bytes / block_size)` SD blocks before the
  `FUN_c009baa0` -> `FUN_c003fe74` SD bridge. The audited fixed readers request
  bounded lengths, so their normal transfer counts remain below the `0x10000`
  controller sentinel; this does not make the generic no-capacity API safe for
  an incorrectly sized caller buffer.
- `TransferSDCardReadBlocks` (`0xC001C120`) and
  `TransferSDCardWriteBlocks` (`0xC001C2C8`) consume exactly eight `0x40`-byte
  FIFO operations per block. The callers pass at most `0xFFFF` blocks per
  chunk (with zero reserved for the controller's `0x10000` count), and the
  FIFO helpers perform no independent caller-buffer validation. They do not
  add a separate overflow in the observed transfer path; their safety depends
  on the wrapper's count check and on the caller's buffer capacity.
- `WriteZeroFilledSDBlocks` (`0xC0056B5C`) is a safer internal helper than the
  generic block API: it obtains the shared scratch capacity (`0x01A00100`),
  clears that buffer, limits each zero-fill transfer to `capacity / 0x200`
  blocks, and repeats for the remaining card range. Its scratch destination
  therefore remains bounded even when the requested zero-fill span is large.
- The command-response path is fixed-size: `MMCSD_ReadResponse`
  (`0xC0017A94`) copies eight halfwords (`0x10` bytes) into the shared response
  buffer, and the CID/CSD conversion helper copies four words (`0x10` bytes)
  into fixed 16-byte records. No variable SD response length is used in these
  paths.
- The SD controller has a class-like two-object layout. `ConstructSDCardController`
  (`0xC001DCAC`) allocates an outer `0x178`-byte object whose work/result area is
  `0x160` bytes at `+0x10`, plus a 12-byte embedded I/O object. The I/O object's
  `+0x04` pointer is populated by `PrepareSDCardControllerOperation`
  (`0xC001AC50`) with the outer `+0x10` area before an operation. This explains
  the fixed offsets used by the vtable methods and bounds the observed CSD/CID
  writes to the controller allocation.
- `ParseSDCardCsd` (`0xC001B7BC`) consumes the fixed 16-byte CMD9 record, derives
  card geometry, and writes fixed geometry fields into that `0x160`-byte area;
  card-controlled CSD values affect arithmetic and flags but do not become
  pointer offsets. `StoreSDCardCid` (`0xC001BBD4`) copies exactly 16 bytes from
  CMD10 into the same area. The shared state gate at `0xC031BE7C` is cleared
  before an operation and set on successful protocol initialization; the shared
  logical block-count bound is at `0xC031BEA0` and is derived from CMD9 data.
- The alternate `InitializeSDIOCardProtocol` path (`0xC001B1A0`) has a separate
  liveness weakness: its CMD5 polling loop has no local retry limit while the
  response readiness bit remains clear. If that path is reachable and a card
  repeatedly returns a non-error, not-ready response, the task can spin
  indefinitely. This is an availability issue, not an observed memory overwrite;
  the ordinary SD ACMD41 path does have a retry bound (`0xC34F`).
- `Pcm_ParseAndLoadWaveResource` (`0xC00362FC`) keeps its sample staging reads
  bounded to at most `0x10000` bytes for 16-bit data or `0x18000` bytes for
  24-bit data, within the shared scratch buffer. It does not reject an odd
  converted 16-bit sample length before subtracting two on each iteration. A
  malformed PCM resource with such a length can remain odd through unsigned
  underflow and spin indefinitely. This is a file-triggerable availability
  defect, not an observed linear buffer overwrite.
- The shared CPU resource reader is a second capacity boundary. It has no
  destination-size parameter and relies on each caller to constrain the
  request. The audited callers use fixed stack/heap destinations or the
  `0x01A00100` scratch buffer; `ValidateCommandHandler15Resource` checks both
  capacity and exact output count, while several fixed-size loaders check only
  the return code and remain vulnerable to short-read/stale-tail data rather
  than a demonstrated linear overwrite. Resource-container metadata and the
  direct SD block API should both be treated as untrusted until the exact-byte
  contract is enforced.
- The minimum hardening for the SD block methods is a subtraction-form range
  check, `count <= capacity - start`, after validating `start < capacity` and
  `count != 0`. A safer interface also carries the caller-buffer capacity and
  rejects `count * 0x200` unless it fits. Update loaders should additionally
  clear the scratch destination and require `actual_count == requested_count`
  before validating or committing any image.

