# BF523 boot, VDK startup, and audio processing

> Detailed evidence extracted from the original monolithic ARCHITECTURE.md.
> Ghidra is authoritative for current symbols, types, comments, and cross-references.

## BF523 reset and SPI1 boot

- `InitializeDspHardwareInterface` at `0xC00119AC` initializes the static
  eight-byte `g_stDspHardwareInterface` object at `0xC031BB24` with the AM1802
  SPI1 and GPIO register pointers.
  Those two fields are typed as `spi_regs_t *` and `gpio_regs_t *` in Ghidra.
- `DSP::resetAndBootFromSpi1` is called once from `StartupTask`. It first calls
  `DSP::assertReset`, which configures SPI1, drives the active-low BF523 reset
  signal on GP6[10] low, and delays for `0x834` microseconds (2100 us). It then
  calls `DSP::releaseResetAndBootFromSpi1`, which drives GP6[10] high, waits
  1000 us, and starts the boot-image transfer.
- `DSP::streamBootImageOverSpi1` sends one byte at a time through AM1802 SPI1.
  GP2[15] is held low around the complete transfer and released high afterward,
  establishing it as the active-low DSP boot chip-select. Before every byte,
  the loop waits for GP2[12] to be low. This access pattern matches the BF52x
  SPI host-boot `HWAIT` requirement that the host observe HWAIT before sending
  each byte.
- The exact image passed to the streamer begins at `g_aBf523BootStream`
  (`0xC00F9E10`), has size `0x422A0` (271,008) bytes, and ends immediately
  before `g_Bf523BootStreamEnd` (`0xC013C0B0`). The first word has the BF52x
  boot-header signature and every record follows the documented 16-byte layout
  of block code, target address, byte count, and argument.
- Parsing ordinary blocks by their byte counts and treating flag `0x0100`
  blocks as dword-fill records reaches the exact image end after 157 headers.
  The fill dword is the block-header argument. Of the 75 fill blocks, 27 use
  zero and 48 repeat a nonzero dword. The remaining distribution is 78 ordinary blocks, two
  `FIRST|IGNORE` count headers (`0x5000`), one `INIT` execution header
  (`0x0800`), and one `FINAL` header (`0x8000`). The stored image is accounted
  for exactly by `0x9D0` bytes of headers and `0x418D0` bytes of payload. No
  additional compressed-payload layer or compression-flagged block is
  observed; compact repeated-dword regions are represented without stored
  payload bytes.
- The first count header reports an initialization image length of `0x330`.
  Its blocks load eight bytes at BF523 address `0xFF900000` and `0x2F8` bytes
  of code at `0xFFA00000`; the `BFLAG_INIT` record at stream offset `0x330`
  invokes that code. Blackfin disassembly using the installed Analog Devices
  GNU toolchain confirms that this is executable initialization code. It calls
  the BF523 ROM `bfrom_SysControl` entry at `0xEF000038` twice with action
  flags `0x711` (`WRITE|VRCTL|PLLCTL|PLLDIV|LOCKCNT`). The first
  `ADI_SYSCTRL_VALUES` structure contains `VR_CTL=0x0000`,
  `PLL_CTL=0x2A00`, `PLL_DIV=0x0005`, and `PLL_LOCKCNT=0x0200`; the second
  call changes only `PLL_DIV` to `0x0004`. It then writes
  `EBIU_AMGCTL=0x01F8`, `EBIU_SDBCTL=0x0013`, `EBIU_SDRRC=0x07D6`, and
  `EBIU_SDGCTL=0xC09199CD`. The `SDBCTL` value explicitly enables a 32 MiB
  BF523 external SDRAM bank with nine column-address bits. This BF523 memory
  is distinct from the AM1802's 64 MiB DDR described above. The routine probes
  external memory at `0x01000000` and `0x02000000`; depending on aliasing, it
  stores the detected boundary through the two pointers initially supplied at
  BF523 addresses `0xFF900000` and `0xFF900004`. A second `FIRST|IGNORE`
  header at offset `0x340` reports an application-image length of `0x41F50`.
  The last record at offset `0x42290` has `BFLAG_FINAL`, zero payload length,
  and target `0xFFA00000`.
- Reconstructing the application records in loader order produces four
  non-overlapping target images: external SDRAM beginning at `0x00000004`, L1
  data bank A beginning at `0xFF800000`, L1 data bank B beginning at
  `0xFF900000`, and L1 instruction SRAM beginning at `0xFFA00000`. The FINAL
  target is a genuine Blackfin reset/startup stub: it clears the loop/length
  registers, initializes event-vector entries, sets `SP`, `USP`, and `FP` to
  `0xFF904600`, calls external code at `0x01F10878`, invokes an L1 routine at
  `0xFFA095F0`, enables self-nesting in `SYSCFG`, and raises interrupt 15
  before installing an `RTI` continuation at `0xFFA00090`.
- `tools/extract_bf523_loader.py` reads the source bytes through Ghidra MCP,
  revalidates every header, and writes the exact stream, reconstructed stage
  images, and `bf523/loader_manifest.json`. The source-stream SHA-256 is
  `83259e30eec2c6586c3756fa3a75d1f831f02e2436d950c4fdb648322a9ca774`.
  The manifest preserves every block target/count/flag and the initialized
  sub-ranges, avoiding assumptions based on the sparse range envelopes.
- Non-empty block targets cover BF523 external SDRAM addresses
  `0x00000004` through `0x01F11B3F`, L1 data SRAM A at `0xFF800000` through
  `0xFF803FCF`, L1 data SRAM B at `0xFF900000` through `0xFF903FEF`, and L1
  instruction SRAM at `0xFFA00000` through `0xFFA0BFF7`. These are target
  bounds from the loader records, not a claim that every byte in each span is
  populated.
- `Bf52xBootBlockHeader` is defined in Ghidra and applied at all 157 verified
  record addresses. The special count, init, and final headers are labeled and
  commented; the reset, SPI transfer, HWAIT, chip-select, and byte-write
  functions are named, prototyped, commented, and tagged `DSP Boot`. Ghidra's
  ARM analyzer had also created 203 autogenerated `FUN_*`/thunk functions
  inside the serialized Blackfin payload; all were removed after the loader
  stream accounted for that exact range as data.
- Stock Ghidra 12.1.2 has no Blackfin language module. The open-source
  `sualk/ghidra-blackfin` extension was checked out at commit
  `a616ee2b80956b2c0e1065acad4f57939b5c2470`, adapted only for Ghidra 12.1's
  `ImporterSettings` loader API, and built successfully against this exact
  Ghidra installation. Both SLEIGH languages compile successfully. The
  persistent Ghidra project `ghidra/E2_BF523.gpr` now contains separate
  `/INIT/init_l1_instruction_ffa00000.bin` and
  `/APP/app_l1_instruction_ffa00000.bin` programs using
  `blackfin:LE:32:BF52x:default`. `tools/ghidra/ImportBf523Loader.java`
  constructs each program from the exact loader records: explicitly loaded
  ranges are initialized and intervening address-space gaps remain
  uninitialized. The extension's upstream README notes incomplete
  DSP-instruction p-code and imperfect parallel-instruction semantics, so all
  names below were checked against ADI GNU Blackfin disassembly rather than
  accepted from decompiler output alone.

### BF523 application startup and VDK threads

- `BF523_ApplicationEntry` at `0xFFA00000` initially installs
  `BF523_DefaultInterruptHandler` (`0x01F108B8`) in EVT2 through EVT14, then
  replaces EVT3 with `BF523_ExceptionHandler` (`0xFFA0950C`) and sets EVT15 to
  `BF523_IVG15Handler` (`0xFFA00092`). The default handler reads `SEQSTAT` and
  enters the common error path with reason code 9. The exception handler saves
  the full machine context, decodes the `SEQSTAT` cause, handles the
  CPLB-related cases or selects the default error path, and returns with
  `RTX`.
- The application entry calls `BF523_ConfigureCplbAndCaches` at `0xFFA095F0`
  with flags `0x3B`, sets `RETI` to the `RTI` trampoline at `0xFFA00090`, and
  raises IVG15. The IVG15 handler calls the current no-op startup hook at
  `0x01F0EC38`, then `BF523_RunInitFunctionTable` (`0x01F108C8`), which walks
  a null-terminated function-pointer table rooted through `0xFF803DC4`, and
  then `BF523_StartVdkKernel` (`0xFFA0BFC0`).
- `BF523_InstallPeripheralEventVectors` at `0x01F0EB30` uses
  `BF523_SetEventVector` (`0x01F0EBB6`) to populate the following Blackfin EVT
  slots. The setter indexes the EVT table at `0xFFE02000` and optionally masks
  or unmasks the corresponding `IMASK` bit around replacement:

  | EVT/IVG | Handler | Direct hardware evidence |
  | ---: | --- | --- |
  | 6 | `VDK_CoreTimerInterruptHandler` (`0xFFA0A6D8`) | updates VDK timer state and raises IVG14 at the configured interval |
  | 8 | `BF523_HostDmaReadCompletionHandler` (`0xFFA09BD8`) | tests and acknowledges `HOST_STATUS.HOSTRD_DONE` / `HSHK` |
  | 9 | `BF523_Sport0RxDmaInterruptHandler` (`0xFFA09C20`) | acknowledges `DMA3_IRQ_STATUS` and posts audio VDK ISR signals |
  | 10 | `BF523_Uart0RxAndDma11InterruptHandler` (`0xFFA09A20`) | reads `UART0_IIR/RBR` or acknowledges DMA11 completion |
  | 12 | `BF523_HostDmaPortInterruptHandler` (`0xFFA09AE8`) | handles Host DMA/DMA status and command-buffer state |
  | 13 | `BF523_MdmaD1InterruptHandler` (`0xFFA09B90`) | acknowledges `MDMA_D1_IRQ_STATUS` |
- The MDMA-D1 interrupt handler is a completion-side hardware boundary, but its
  short body only writes `1` to `MDMA_D1_IRQ_STATUS` at `0xFFC00FA8`, then calls
  `0xFFA000BC` with `R0=1` before returning from interrupt. The call is consistent
  with posting a VDK/ISR signal, but the available static image does not identify
  its receiving thread or prove that this signal is the completion event for
  HostDMA command `0x3B`. The CPU PCM path currently advances by its own state
  polling/processing path before sending command `0x3B` phase 0.
- `VDK_CreateThreadEx` at `0xFFA0B23C` consumes the official 28-byte
  `VDK_ThreadCreationBlock`, supplies template defaults for stack size and
  priority where required, invokes the internal creator, and records the
  returned thread ID. `VDK_CreateThread` at `0xFFA0B2AC` accepts a template ID
  and indexes a firmware-specific table of 32-byte descriptors beginning at
  `0x01F00180`. The corresponding `VDK_ThreadCreationBlock` and
  `E2_VDK_ThreadTemplate` structures are defined in Ghidra. The VDK guide
  confirms that thread stack sizes are expressed in 32-bit words.
- Five firmware thread templates are present:

  | Template ID | Name | Priority | Stack words | Create wrapper | Constructor | `Run` method |
  | ---: | --- | ---: | ---: | --- | --- | --- |
  | 0 | `kAudioIoThread` | `0x1C` | `0x200` | `BF523_CreateAudioIoThread` (`0x000000CC`) | `BF523_AudioIoThread_Constructor` (`0x00000004`) | `BF523_AudioIoThread_Run` (`0x00000038`) |
  | 1 | `kSystemBootThread` | `0x1A` | `0x200` | `BF523_CreateSystemBootThread` (`0x01F0EAB4`) | `BF523_SystemBootThread_Constructor` (`0x01F0E9A4`) | `BF523_SystemBootThread_Run` (`0x01F0E9D8`) |
  | 2 | `kHostDPMTxThread` | `0x1A` | `0x200` | `BF523_CreateHostDPMTxThread` (`0x01F0E928`) | `BF523_HostDPMTxThread_Constructor` (`0x01F0E890`) | `BF523_HostDPMTxThread_Run` (`0x01F0E8C4`) |
  | 3 | `kFxCtrlMRxThread` | `0x1A` | `0x200` | `BF523_CreateFxCtrlMRxThread` (`0x01F0E778`) | `BF523_FxCtrlMRxThread_Constructor` (`0x01F0E62C`) | `BF523_FxCtrlMRxThread_Run` (`0x01F0E660`) |
  | 4 | `Idle Thread` | `0` | `0x100` | zero | not present | not present |

- Confirmed descriptor fields are name pointer at `+0x00`, initial priority at
  `+0x0C`, stack size in 32-bit words at `+0x10`, and thread-create-wrapper
  pointer at `+0x14`. Each non-idle wrapper allocates a `0xC4`-byte derived
  VDK thread object and invokes its constructor. The constructor calls the
  common VDK base constructor and writes its class-specific vtable pointer at
  object offset `+0xC0`; vtable slot `+0x14` identifies the actual `Run`
  method listed above. Fields `+0x04`, `+0x08`, `+0x18`, and `+0x1C` remain
  unidentified and retain unknown names in the Ghidra structure.
- `BF523_CreateConfiguredVdkThreads` at `0xFFA0AB68` walks the configured
  boot-thread list; this firmware's list selects the SystemBoot template.
  Instruction-level data flow in `BF523_SystemBootThread_Run` confirms later
  calls to `VDK_CreateThread` with template IDs 2 and 3, creating the Host-DPM
  transmit and effects-control receive threads. After further initialization
  it sets the byte at `0xFF800050`, creates template ID 0
  (`kAudioIoThread`), waits, and enables the SPORT0 DMA path. The thread names
  establish useful subsystem boundaries, but do not by themselves identify
  the shared-memory message formats used by either communication thread.

### BF523 SPORT0 audio I/O

- `BF523_AudioIoThread_Run` passes the L1-data-B address `0xFF900CCC` to
  `BF523_ConfigureSport0AudioDma` at `0x00000164`. The function divides that
  storage into six contiguous `0x40`-byte buffers and builds two cyclic rings
  of three DMA descriptors at `g_aSport0TxDmaDescriptors` (`0xFF900E4C`) and
  `g_aSport0RxDmaDescriptors` (`0xFF900E7C`). The buffer base is labeled
  `g_aSport0AudioDmaBuffers` in Ghidra.
- The configuration function installs the receive ring in DMA3 and the
  transmit ring in DMA4, sets both channels' X count to `0x10` and X modify to
  4, and writes peripheral-map values `0x3000` and `0x4000`. It programs
  SPORT0 `RCR1/RCR2` to `0x4404/0x031F` and `TCR1/TCR2` to
  `0x4400/0x031F`. The DMA direction and SPORT register identities come
  directly from the BF52x MMR definitions.
- `BF523_InitializeTwiController` at `0x01C76DA0`, called by the SystemBoot
  thread before it creates AudioIo, writes `TWI_CONTROL=0x008D`,
  `TWI_CLKDIV=0x3C3C`, resets the TWI FIFOs with writes 3 then 4, disables
  slave mode, and assigns the TWI interrupt field in `SIC_IAR2` the value 5.
  This confirms controller initialization; the device on the two-wire bus has
  not yet been established from data flow.
- `BF523_EnableSport0AudioDma` at `0x000002C0` assigns the DMA3 interrupt in
  `SIC_IAR2`, enables `SIC_IMASK0` bit 16, enables DMA3 and DMA4 descriptor
  processing, then sets the enable bits in SPORT0 receive and transmit control
  registers. Its conditional middle path performs TWI master-status recovery
  only when the byte at `0xFF800050` is zero; the observed SystemBoot path sets
  that byte to one immediately before creating AudioIo and later calling this
  function. The byte's broader semantics remain unresolved.
- The AudioIo thread then enters the non-returning
  `BF523_RunSport0AudioDmaServiceLoop` at `0xFFA0010C`. This loop waits on VDK
  interrupt ID 6, obtains the active DMA3/DMA4 descriptors, divides each DMA
  buffer into four slices, and calls `BF523_ProcessAudioDmaSlice`
  (`0xFFA0141A`) once for each slice. Between buffers it services Host DMA
  commands using processing-mode value `0x0104`. It also increments the dword
  `g_dwDspAudioFrameCounter` at `0xFF800054` once per wakeup; the external-state
  controller compares this counter's low halfword against its timing field while
  advancing state.
- Before entering that loop, `BF523_AudioIoThread_Run` calls
  `BF523_InitializeAudioEngineObjects` (`0x01F0C8D4`) through `P1` at
  `0x00000062`; this indirect call edge is recorded explicitly in Ghidra. The
  initializer calls `BF523_InitializeAudioEngineState`, clears the active
  oscillator workspace, initializes seventeen indexed `0x68`-byte oscillator
  templates through `BF523_InitializeOscillatorTemplate`
  (`0x01F0C06A`),
  initializes all sixteen voice-state records through
  `BF523_InitializeDspVoiceStateRecord` (`0x01F0BF3C`), and calls
  `BF523_InitializeDspVoicePointerTables` (`0x01F0C140`). The last function's
  `0x01F0C140`-through-`0x01F0C55A` extent is confirmed by the ADI Blackfin
  disassembler; the Ghidra Blackfin module cannot decode one parallel bundle
  at `0x01F0C2B4`, so its body range is preserved explicitly, including the
  tail loop that branches through `0x01F0C548`.
- `BF523_InitializeDspVoiceStateRecord` clears each `0x1B4`-byte record through
  interleaved cursors at offsets `0` and `+0xCC`, then seeds fixed tail values
  at `+0x198` (`0x07290361`), `+0x19C` (`0`), `+0x1A0` (`0x7FB90000`),
  `+0x1A4` (`0`), and `+0x1A8` (`0x07290361`), while clearing `+0x1AC` and
  `+0x1B0`. The same initialization explicitly clears the initial control region
  through `+0x2C`, including the later audio-dispatch selector at `+0x28`.
  These are initialization constants only; their product-level
  meanings remain unresolved.
- `BF523_ProcessAudioDmaSlice` walks both confirmed sixteen-entry voice arrays
  and invokes `BF523_ApplyStereoSoftSaturation` at `0xFFA0135C` on its output
  pair. The helper applies an identical symmetric, thresholded cubic transfer
  to two consecutive 32-bit fixed-point samples: excess above absolute
  threshold `0x361962E9` contributes a sign-preserving cubic reduction, after
  which coefficient `0x1E81084D` supplies fixed makeup gain. This establishes
  a final nonlinear saturation stage without assigning it an unproven product
  or effect name.
- `BF523_InitializeAudioEngineState` at `0x01F0C55C` initializes the state
  rooted at `g_DspAudioEngineState` (`0xFF9030A4`). It proves both loop bounds
  used by the slice processor: `g_dwDspOscillatorVoiceSlotCount` at `+0xD0` is 17
  when byte `0xFF800050` is zero and 24 otherwise, while
  `g_dwDspVoiceRecordCount` at `+0xE8` is explicitly 16. The normal SystemBoot
  path sets the controlling byte to one before AudioIo starts, selecting 24
  oscillator voice slots. The initializer also seeds the pointer at engine offset `+0x138`
  (`0xFF9031DC`) to `0xFF90197C`, exactly voice record 0 field `+0x110`; Host
  DMA command `0x37` can subsequently replace that selection.
- `g_aDspOscillatorVoiceWorkspaces` occupies `0xFF800748` through
  `0xFF800B07`, immediately before the voice-state array, and provides capacity
  for twenty-four `0x28`-byte oscillator-voice scratch records. The
  engine-object initializer clears
  `g_dwDspOscillatorVoiceSlotCount * 0x28` bytes, and the slice processor
  receives this base in `r1` and advances it by `0x28` once per oscillator
  callback. The paired `g_aDspOscillatorVoiceDescriptors` array spans
  `0xFF900EAC` through `0xFF90186B`: exactly twenty-four `0x68`-byte records
  ending at the voice-record array. The service loop supplies that base in
  `r0`; the slice processor skips a descriptor when its first dword is zero,
  otherwise it reads the oscillator callback-table index at descriptor offset
  `+0x0C`, invokes that callback, and advances to the next `0x68`/`0x28` pair.
  The separate `g_aDspOscillatorTemplates` array at `0xFF800060` contains
  seventeen source records initialized with fixed defaults and their indices.
  The ARM helper `DspIf_CopyOscillatorTemplateToVoiceSlot`
  (`0xC00933E0`) sends HostDMA command `0x09` with source token
  `0x0018 + template*0x1A` and destination token
  `0x43AB + voice_slot*0x1A`. Those translate exactly to a selected template
  and a live oscillator descriptor, and the BF523 copies all 26 dwords (one
  complete `0x68`-byte record). Confirmed callers select templates 0-15 with a
  voice index and copy them into allocated slots among the twenty-four
  descriptors; the role of template 16 remains unresolved. The pointer state rooted at
  `g_DspVoicePointerTables` (`0xFF902B7C`) is a pointer lattice rather than a plain
  array of voice rows. `BF523_InitializeDspVoicePointerTables` emits sixteen output
  positions at `0x50`-byte spacing, deriving pointers from
  `g_aDspVoiceStateRecords` with `0x1B4`-byte stride,
  `g_aDspVoiceRecords` with `0x118`-byte stride, and a companion region beginning at
  `0x0001A2C0` with `0x1B4`-byte stride. The initializer then fills additional
  `0x50`-spaced pointer columns through at least root `+0x4D4`, plus shared control
  pointers through root `+0x524`. These columns are consumed by later DSP control/audio
  paths, but their individual field ownership and product semantics remain unresolved.
  The command-`0x37` selection is consumed by two L1 fixed-point audio-record
  kernels. `BF523_ProcessAudioRecordTransformA` (`0xFFA00AD0`) and
  `BF523_ProcessAudioRecordTransformB` (`0xFFA00C80`) use a common context
  shape: `+0x04` is the selected record/buffer pointer and `+0x08` is a
  coefficient/input region. They write transformed fixed-point values through
  the selected pointer and publish linked output fields; transform B explicitly
  folds selected-record `+0x08/+0x0C` into that output. This is a structural
  audio-path consumer. Both kernels are reused by external-SDRAM effect
  descriptors named `[I/Dbl] SR1 Comp`, `[I/Dbl] Limiter`, and `[I/Dbl] Ring
   Mod`; this association is strong, but does not prove a one-kernel/one-effect
   mapping or resolve the individual field semantics.
   The surrounding external descriptor table is indexed through `0x00004C30`
   using the masked per-slot effect byte at `0xFF9007CC + slot`. In the named
   `[I/Dbl] SR1 Comp` and `[I/Dbl] Limiter` records, the transform pair occupies
   offsets `+0x18/+0x1C`; the `[I/Dbl] Ring Mod` record visibly references
   `0xFFA00AD0` among a broader callback set. A separate callback at `+0x20` is
   loaded and called by the external
   control path around `0x00018ADA..0x00018B22`; the latter is not one of the two
   selected-record kernels. The runtime audio-slice dispatch into the pair is
   not yet resolved.
  The confirmed function body extends through `0x01F0C55A`; the earlier apparent
  endpoint at `0x01F0C546` was inside its tail loop.
- The corresponding ARM allocation array is `g_aArmOscillatorVoiceSlots` at
  `0xC06916A0`: twenty-four `E2_ArmOscillatorVoiceSlot48` records with stride
  `0x48`, matching the BF523 live-slot count one-for-one. Direct accesses
  establish `owner_voice` at `+0x04`, cached `oscillator_selection_key` at
  `+0x10`, `dsp_slot_index` at `+0x14`, `oscillator_id` at `+0x3A`, and
  `dsp_selector` at `+0x40`; byte fields at `+0x3E/+0x3F/+0x42/+0x43` hold
  metadata-derived and resource state whose detailed values remain unresolved.
  `Voice_ApplyOscillatorSlotToDsp` (`0xC0098604`) consumes this record, sends
  its DSP parameters, prepares the paired BF523 variant workspace, and marks
  rendering active for the applicable update modes.
- The oscillator workspace update is now bounded at both ends of the HostDMA
  boundary. ARM command `0x32` pairs each translated oscillator descriptor
  address (`descriptor +0x0C`) with its BF523 callback workspace address
  (`workspace +0x08`). The BF523 command case (`0xFFA053B6`) reads the
  descriptor `+0x0C` dword as the callback index, passes descriptor `+0x10` as
  the source callback-parameter block, and dispatches through the 44-entry table
  at `0x01F02CD8` to update the paired workspace object. This establishes the
  descriptor-to-render-workspace data flow; the callback-index operations and
  musical meanings remain unresolved.
- The apply sequence begins by writing the slot halfword at `+0x2C` to BF523
  descriptor offset `+0x04` with command `0x2B`, then sends the slot `+0x2E`
  value with command `0x2C` to the adjacent descriptor offsets `+0x04` and
  `+0x08`. The ARM wrapper for the first write is
  `DspIf_WriteOscillatorSlotDescriptorField04` (`0xC00985B4`); both writes
  precede metadata and variant-workspace preparation. Their product-level
  meanings remain unresolved.
- The common ARM preparation helper is `Voice_PrepareOscillatorSlotState`
  (`0xC00982B4`). It is called by the slot allocation, retrigger, and refresh
  paths before the DSP apply function. For the observed update modes it copies
  voice oscillator state into slot fields `+0x10`, `+0x42`, and `+0x43`, stores
  control values at `+0x15`, `+0x17`, and `+0x19`, derives slot state at
  `+0x34`, and updates the voice/slot rate state. The subsequent lifecycle is
  `DspIf_CopyOscillatorTemplateToVoiceSlot` (command `0x09` when a new template
  is required), `Voice_ApplyOscillatorSlotToDsp`, and then the command-`0x32`/
  command-`0x1F` workspace operations. The product meaning of the remaining
  slot fields is intentionally unresolved.
- `g_abOscillatorVoiceSlotPriorityOrder` at `0xC069146B` is a 24-byte
  permutation of slot indices used by the allocation/stealing searches. Reset
  initializes it to 0 through 23; allocator operations move entries while
  preserving its extent. `Voice_FindOscillatorSlotPriorityPosition`
  (`0xC00911E0`) searches the permutation, and
  `Voice_MoveOscillatorSlotToPriorityTail` (`0xC0091598`) performs the move.
  `Voice_SelectOscillatorSlotForVoice` (`0xC00916F8`) scores all 24 entries
  using their position in this permutation, the sign bit in the note-state
  array, and bits 0 and 1 of the release-flag array. It chooses the best
  eligible slot, moves it to the tail, and returns its index or `-1`. Bit 0 is
  the confirmed released non-one-shot state and bit 1 is the released one-shot
  state. Ordinary PCM and paired-stereo slots derive this distinction from the
  KORG ELSI `oneShot` byte; valid slice playback forces one-shot behavior.
  `Voice_AssignOscillatorSlotsToVoice`
  (`0xC00913EC`) installs the `owner_voice` and timbre pointer for each selected
  slot, while `Voice_ReleaseOscillatorSlot` (`0xC0091B10`) clears the owner's
  two slot masks and queues BF523 deactivation.
  `g_dwActiveOscillatorVoiceSlotMask` at `0xC06914EC`
  is the confirmed 24-bit ARM mirror of slots marked active on the BF523.
  A separate pending mask at
  `g_dwPendingOscillatorVoiceSlotDeactivateMask` (`0xC069FEFC`) is managed by
  `Voice_QueueOscillatorSlotDeactivation` (`0xC009B8CC`) and consumed by
  `Voice_FlushOscillatorSlotDeactivations` (`0xC009B908`). The flush walks the
  selected ARM records, sends command `0x26` for each BF523 descriptor/workspace
  pair, then sends HostDMA command `0x36` with the combined 24-bit mask.
  `Voice_ResetAllOscillatorSlotState` (`0xC0091F5C`) resets all sixteen ARM
  voices and the allocation fields for all twenty-four slot records, restores
  the priority permutation, and performs the same BF523 cleanup with mask
  `0xFFFFFF`.
- Five side arrays and one global counter preserve the note-event and allocation state for the same 24
  oscillator slots:
  `g_abOscillatorVoiceSlotReleaseFlags` (`0xC069143B`),
  `g_abOscillatorVoiceSlotTriggerSourceKeys` (`0xC0691453`),
  `g_abOscillatorVoiceSlotPriorityOrder` (`0xC069146B`),
  `g_acOscillatorVoiceSlotNoteState` (`0xC0691486`), and
  `g_awOscillatorVoiceSlotAllocationGenerations` (`0xC06914B6`) all have one
  element per slot. The global
  `g_wOscillatorVoiceAllocationGeneration` (`0xC0691484`) advances once per
  received note event. Assignment clears a slot's release flags, records the
  current generation, stores the transposed MIDI note in note-state bits 0-6,
  sets bit 7 while the note is down, and stores a packed trigger-source key
  whose low nibble is the MIDI status/channel source and whose high nibble is
  the event source group. Note release clears note-state bit 7 and sets either
  release-flag bit 0 for a non-one-shot slot or bit 1 for a one-shot slot.
  `Voice_MarkOscillatorSlotNonOneShotRelease` (`0xC0091298`),
  `Voice_MarkOscillatorSlotOneShotRelease` (`0xC009120C`), and
  `Voice_ClearOscillatorSlotReleaseState` (`0xC0091328`) are the corresponding
  state transitions. `Voice_FilterOneShotOscillatorSlots` (`0xC009B9C0`)
  selects slots using the same copied one-shot flag.
  `Voice_IsOscillatorSlotInUse` (`0xC009115C`) therefore treats a slot as live
  while its note-state sign bit or either release flag remains set.
- `voice_t +0x2E` is the one-byte `E2_VoiceAssignMode` enum. The value-to-label
  mapping is confirmed directly by the UI dispatcher at `0xC0080B4C` and its
  four static strings: `MONO1=0` (`0xC00A70BA`), `MONO2=1`
  (`0xC00A70C0`), `POLY1=2` (`0xC00A70C6`), and `POLY2=3`
  (`0xC00A70CC`). `Pattern_GetPartVoiceAssignMode` (`0xC0048D10`) reads this
  setting from pattern-part offset `+0x806`. Allocation tests bit 1 to choose
  the Poly per-note-slot path or the Mono held-note-priority path; bit 0
  distinguishes variant 1 from variant 2. `Voice_ShouldUseHardRetriggerPath`
  (`0xC00917B8`) always rejects its hard-retrigger path for Mono2, while Mono1
  accepts it only when the voice and all of its current slots are non-one-shot.
  `Voice_RetriggerHeldSlotsHard` (`0xC0091604`) and
  `Voice_RetriggerHeldSlotsSoft` (`0xC0091684`) describe the two proven state
  transition behaviors; “hard” and “soft” are behavioral names, not UI labels.
- `Voice_HandleMidiNoteEvent` (`0xC0092648`) is the allocation path reached
  from the MIDI ingress routine at `0xC0026418`. Its confirmed arguments are a
  voice pointer, status/channel byte, transposed note, velocity, source group,
  and an auxiliary note value. On note-off, Poly1 and Poly2 voices
  match slots by owner, packed trigger-source key, and the low seven note bits,
  then group all matching records by their allocation generation. This keeps
  multi-slot allocations from one note event together during release. The
  adjacent byte array at `0xC069149E` is reset to `0xFF` and cleared during
  owner removal, but no non-reset reader has yet established its purpose, so it
  remains deliberately unnamed.
- Every `voice_t` also contains six `E2_HeldNotePriorityEntry` records at
  `+0xFC..+0x107`. Each two-byte entry stores a packed trigger-source key
  followed by a note-state byte whose low seven bits are the MIDI note and whose
  bit 7 marks an active held note. The records are a newest-first priority
  stack used by Mono1 and Mono2, not a FIFO.
  `Voice_PushHeldNotePriorityEntry` (`0xC0092B50`) inserts a
  note at the head, shifts five prior entries down, drops the old sixth entry,
  and returns the former head through its in/out arguments.
  `Voice_RemoveHeldNotePriorityEntry` (`0xC0092A14`) removes one exact note and
  source; it returns the newly exposed head only when the removed entry was the
  old head, allowing non-head note releases to leave the sounding priority note
  unchanged. `Voice_RemoveHeldNoteEntriesByTriggerSource` (`0xC0092BB8`) does
  the same compaction for all active entries belonging to a trigger source. A
  byte-for-byte duplicate exists at `0xC0092D64` and is used by a second source
  release entry point.
- Six unsigned counters at `voice_t +0x10..+0x1B` track active notes by the
  packed trigger-source key's high nibble. `Voice_UpdateTriggerSourceNoteCount`
  (`0xC0092F60`) maps source classes `0x00`, `0x10`, `0x20`, `0x30`, and
  `0x40` to counters 0, 1, 2, 4, and 3 respectively; all other values use
  counter 5. It saturating-increments on note-on and decrements on note-off.
  `Voice_GetTotalTriggerSourceNoteCount` (`0xC0092F30`) sums the six counters,
  and `Voice_ClearTriggerSourceNoteCount` (`0xC0093008`) clears one source.
  `g_cGlobalNoteEventState` at `0xC069143A` accompanies these counters. Only
  bit 7 is confirmed: note-on and full reset clear it, while note-off/source
  clear set it; bits 0-6 remain unresolved.
- Ghidra had missed standalone functions following the main note-event body.
  The restored `Voice_ReleaseOscillatorSlotsForTriggerSource` (`0xC0092838`)
  releases in-use slots selected by owner and packed source key.
  `Voice_HandleTriggerSourceNoteOff` (`0xC0092704`) and
  `Voice_HandleTriggerSourceRelease` (`0xC00928CC`) combine the counter,
  held-note-priority, retrigger, and per-slot release paths for two independently
  reached ingress cases. `Voice_FindLatestActiveSlotForVoiceIndex`
  (`0xC0092984`) walks the 24-slot priority order from its tail and returns an
  in-use slot whose owner has the requested voice index, or `-1` when none is
  eligible.
- The ARM and BF523 sides agree on the oscillator command object contract.
  ARM token `0x43AE + voice_slot*0x1A` translates to descriptor `+0x0C`, while
  token `0x01D4 + voice_slot*0x0A` translates to the paired workspace `+0x08`.
  Commands `0x32` and `0x1F` pass those two objects to bounded 44-entry BF523
  dispatchers. The corresponding ARM helpers are
  `DspIf_InitializeOscillatorVoiceVariantWorkspace` (`0xC0093514`) and
  `DspIf_CopyOscillatorVoiceVariantFieldsToWorkspace` (`0xC009374C`). The BF523
  cases use the first object's `+0x00` dword as the dispatch index, first `+0x04`
  as the source block, and the second object as the destination. Thus the
  oscillator pair dispatches on descriptor `callback_index` at `+0x0C`, passes
  descriptor `+0x10` as the source callback-parameter block, and writes the
  selected implementation's fields/defaults into workspace `+0x08`. The audio
  callback receives the same descriptor `+0x10` block in `P2` and workspace
  `+0x08` in `P3`; descriptor `+0x10` is not a standalone variant selector.
  The musical meanings of the 44 callback-index cases remain unresolved.
- The template initializer stores its array index at template `+0x64`, and
  command `0x09` preserves it in the live descriptor. The ARM helper
  `DspIf_DeactivateOscillatorVoiceSlotAndResetWorkspace` (`0xC00985CC`) sends
  command `0x26` for a descriptor/workspace pair after clearing its ARM-side
  allocation bit. The BF523 clears descriptor `active_word`, copies descriptor
  `template_index` at `+0x64` into workspace `+0x00`, and clears workspace
  `+0x04`. This confirms the template identity is retained across allocation
  and deactivation; the more specific meaning of workspace `+0x04` remains
  unresolved.
- ARM HostDMA command `0` controls the confirmed active words. Token
  `0x43AB + voice_slot*0x1A` with value one stores `0x00010000` at oscillator
  descriptor `+0x00`; `DspIf_MarkOscillatorVoiceSlotActive` at `0xC00985C4`
  emits that operation. Tokens `0x02C2 + voice*0x6D` address voice-state record
  `+0x00`; `DspIf_MarkVoiceStateRecordsActive` (`0xC00985D4`) writes one, and
  `DspIf_ClearVoiceStateRecordsActive` (`0xC0093A20`) writes zero. The BF523
  audio loop tests each first dword and skips the corresponding oscillator slot
  or voice-record processing path when it is zero.
- `BF523_LoadDspRuntimeTablesIntoL1Memory` at `0x01F0BD48` copies a static
  52-entry callback-pointer table from `g_apDspOscillatorCallbackSource`
  (`0x01F02474`) into L1 scratchpad `g_apDspOscillatorCallbackTable`
  (`0xFFB00010`) before the audio loop begins. The oscillator descriptor's
  `+0x0C` index is multiplied by four and used to load the indirect target from
  this runtime table. Repeated source pointers prove that several related
  oscillator selectors intentionally share render implementations.
- `DspIf_GetOscillatorTemplateToken` (`0xC009340C`) maps template index
  `i` to token `0x0018 + i*0x1A`. `DspIf_LoadOscillatorTemplatePreset`
  (`0xC0094F8C`) selects a static ARM dword block and uses command `0x31` to
  write it beginning at template `+0x0C`. The first dword is `callback_index`;
  when the selected block has additional words, its next dword begins with the
  16-bit parameter word at descriptor/template `+0x10`; it is source data for
  the selected callback rather than the command-`0x1F`/`0x32` selector. Preset selectors `0x00`-`0x20` map directly to
  callback indices 0-32, selectors `0x21`-`0x24` map to 36-39, selector `0x2D`
  maps to 35, and selectors greater than `0x31` map to 34 in this build.
  Selectors `0x25`-`0x2C` and `0x2E`-`0x31` load a single-dword callback-0
  block. A static callback-33 preset also exists, but its classifier is the
  constant-false function described below. Indices 40-51 in the 52-entry
  BF523 table all repeat `BF523_RenderSilentOscillatorSample`, the index-0
  target.
  Reading the selected ARM blocks confirms the first-dword mapping rather than
  merely inferring it from selector order: the standard families occupy callback
  indices `0..32`, `AUDIO_INPUT` uses `35`, and `CHIP_NOISE`/`CHIP_PULSE`/
  `CHIP_TRIANGLE_1`/`CHIP_TRIANGLE_2` use `36..39`. The block lengths range from
  one dword (silent/default) to 18 dwords (dual-sine); those trailing dwords are
  the source fields consumed by the command-`0x1F` copy families and command-`0x32`
  initialization families.
 - The ARM static source table `g_aBuiltinOscillatorMetadata` spans
   `0xC00D9AB0` through `0xC00DBCEF` and contains 274 records of 32 bytes. Each record has a
   16-byte display name and a 16-bit `E2_DspOscillatorSelector` at `+0x12`;
   direct callers establish byte accesses at `+0x10`, `+0x18`, `+0x19`,
   `+0x1C`, and `+0x1D` and signed-byte accesses at `+0x16/+0x17`. Their exact
   meanings and the untouched tail fields remain unresolved. Ghidra applies
   `E2_OscillatorMetadataRecord20[274]` to the whole source table.
 - The CPU-side PCM resource-table loader is now bounded. `Pcm_InitializeResourceTables`
   (`0xC004D0E8`) seeds 999 logical entries: it clears the runtime playback-point table,
   assigns each key-zone record its own index at `+0x02`, assigns each key-zone group its
   own first-key-zone index at `+0x08`, and initializes all four velocity-map layer references
   to the logical resource index. `Pcm_LoadResourceTablesFromFlash` (`0xC004D1E4`) validates
   the flash header identifiers `X11100PC` or `elec2PCM`, follows the descriptor offsets,
   and loads the observed 0x14-byte resource table at `0xC035257C`, 0x10-byte playback
   records, 0x10-byte key-zone groups, 0x08-byte key-zone records, and 0x20-byte velocity
   maps. It normalizes resource-table field `+0x10` as `(value * 12 >> 7) - 0x177`;
   the other fields remain unresolved. `Pcm_LoadAndDecodeResourceData` (`0xC004D860`)
   reads and validates the full resource image, decodes its compressed sections through
   `Pcm_DecodeResourceSection` (`0xC004D5CC`), and updates the observed sample-storage
    state. The decoder expands type-7 chunks as signed 12-bit packed values into 16-bit
    values shifted left by four and delegates other chunk types to a secondary decoder.
    That secondary routine is `Pcm_DecodeCompressedSampleChunk` (`0xC00A0ACC`): it reads
    a bit-packed stream after a six-byte chunk header, adapts its code width from embedded
    predictor state, applies the observed predictor formulas for chunk modes 0-6, writes
    shifted 16-bit values, and returns the accumulated output extent. The decoded words
    are streamed to the BF523 through `BeginDspHostDmaResourceTransfer` (`0xC0015008`)
    and `StreamDspHostDmaResourceWord` (`0xC00150BC`), which manage the aligned transfer
    window, 16-word FIFO blocks, and pending remainder.
 - `g_aRuntimeOscillatorMetadata` at `0xC047B08C` is the complete mutable
  catalog: exactly 999 `E2_OscillatorMetadataRecord20` records, ending at
  `0xC0482D6B`. `Osc_InitializeRuntimeMetadataCatalog` (`0xC004E324`) copies
  the 274 static records (`0x2240` bytes) into runtime entries 0-273 and calls
  `Pcm_InitializeRuntimeResourceRecord` (`0xC004DF90`) for entries 274-998.
  The latter creates the associated PCM/sample state and synthesizes a metadata
  selector equal to the resource index plus 50. `Pcm_RebuildRuntimeSampleCatalog`
  (`0xC004F490`) repeats this catalog construction after sample-storage changes,
  rebuilds ID associations, and also detects adjacent L/R sample-name pairs and
  merges compatible DSP sample storage through HostDMA. Its live-resource byte
  at `+0x09` is a confirmed stereo-pair role: `Pcm_GetStereoPairRole`
  (`0xC004EA54`) returns zero for unpaired resources, while the rebuild assigns
  roles 1 and 2 to compatible adjacent L/R resources. The numeric role follows
  the observed sample-length ordering, so role 1 is not inherently the filename's
  left side. A separate companion-record byte at `+0x0E`, returned by
  `Pcm_GetResourceOneShotFlag` (`0xC004EA38`), is
  the PCM sample's raw one-shot flag. It is normalized into
  `voice_t.bOscillatorOneShot` at `+0x38` and each live oscillator slot's
  `bOscillatorOneShot` at `+0x42`, where it selects the two released-slot
  priority classes. Valid slice modes set the normalized flag even if the raw
  sample flag is clear.
