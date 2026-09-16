# Boot, startup, board initialization, and interrupts

> Detailed evidence extracted from the original monolithic ARCHITECTURE.md.
> Ghidra is authoritative for current symbols, types, comments, and cross-references.

## DDR address map

- The AM1802 has 64 MiB of physical DDR. Its cached CPU window is
  `0xC0000000` through `0xC3FFFFFF`; `0xC4000000` through `0xC7FFFFFF` is an
  uncached alias of the same physical memory, with an address delta of
  `0x04000000`.
- The loaded firmware occupies `0xC0000000` through `0xC01FFFFF`. `main`
  clears the following BSS region, `0xC0200000` through `0xC08A293F`.
  Ghidra maps the rest of the cached window as uninitialized writable DDR.
- Ghidra also maps the complete uncached window as an uninitialized block
  named `ddr_uncached_alias`. It is documented as an alias rather than
  separate physical storage; the current database representation must not be
  used as evidence for an additional 64 MiB of RAM.

## Boot and runtime entry

- The ARM vector image begins at `0xC0000000`. Its reset entry is an
  `ldr pc, [pc, #0x18]` whose literal target is `0xC0000070`.
- The reset stub at `0xC0000070` loads `sp = 0xC274AA40`, calls the runtime
  entry at `0xC00296B0`, and loops at `0xC000007C` if that call returns.
- The runtime entry is currently named `main` at `0xC00296B0`. It:
  1. clears BSS from `0xC0200000` to `0xC08A2940`;
  2. fills the reserved runtime stack region from `0xC274AA40` to
     `0xC274EA3C` with the sentinel word `0xEEEEEEEE`;
  3. fills ten task stack regions from the descriptor table at `0xC00A37A8`
     with distinct sentinel words (`0x11111111` through `0xAAAAAAAA`);
  4. performs early SoC, GPIO, AINTC, RTOS, and UART initialization; and
  5. tail-branches through `0xC0000110` to the scheduler entry at
     `0xC00017A8`.
- The sentinel-filled runtime/idle stack span is labeled in Ghidra at
  `g_dwRuntimeIdleStackStart` (`0xC274AA40`), with
  `g_pRtosIdleStackTop` at `0xC274EA3C`.
- The application entry executes from the cached DDR window but does not
  configure CP15, construct a translation table, or call any cache/MMU helper.
  The existing `SBL.bin` program identifies the earlier stage: SBL entry calls
  `config_mmu` (`0x80005484`) at `0x80000090`, after `_init_psc_pll_ddr` and
  before the DDR memtest and `Init_MCU_and_Boot` path.
- SBL's `_construct_page_table` (`0x800051A8`) writes the first-level table at
  runtime address `0x8001C000`. It initializes entries `0x000..0xBFF` as
  identity sections with descriptor suffix `0xC12`, entries `0xC00..0xC3F`
  with identity section bases and suffix `0xC1E`, and entries `0xC40..0xC7F`
  with physical section bases `0x000..0x03F` and suffix `0xC12`. It then
  overrides entry `0` with `0xC0000000 | 0xC1E` and entry `0x800` with
  `0x80000000 | 0xC1E`. These are the observed raw descriptors; cacheability
  names are not inferred beyond the established address-window contract.
- SBL `config_mmu` writes TTBR0, sets domain access control to `3`, invalidates
  instruction/data caches and the unified TLB, and writes the SBL control value
  `EnablesMMUandCaches` to CP15. `Init_MCU_and_Boot` later copies 16 words from
  `0x80000000` to `0xC0000000` before loading the 2 MiB application image.
- A linked but unreferenced ARM926EJ-S CP15 helper cluster is present at
  `0xC00016A4` through `0xC000172B`. It contains
  `InvalidateAndEnableInstructionCache`, `InvalidateAndEnableDataCache`,
  `EnableMmuWithTranslationTable`, three data-cache line-maintenance helpers,
  and `DrainCpuWriteBuffer`. No call or data references to these functions
  were found. Their names record the decoded CP15 operations, not observed use
  during startup.

## Static initialization and startup sequencing

- `RunCxxStaticInitializers` at `0xC0008EA8` iterates 76 function pointers at
  `g_apfnCxxStaticInitializers` (`0xC00F88B0` through `0xC00F89DC`) in
  ascending order. The preceding pre-initializer range is empty.
- `StartupTask::taskProc` at `0xC002AB7C` runs that initializer list before
  constructing or initializing the major runtime subsystems. Confirmed steps
  include LCD initialization, DSP reset-state initialization, UART0 panel
  transport and identity-query initialization, SD-card and application-object
  construction, and conditional Timer2 initialization.
- After initializing and drawing the first LCD state, `StartupTask` calls
  `DSP::resetAndBootFromSpi1` at `0xC0015C78`. This is the complete BF523
  reset and host-boot path described below; it is not merely a reset-state
  initializer.
- At the end of startup it changes the current task's priority through
  `SetRtosTaskPriority`, starts task IDs 2 through 10 through
  `StartRtosTaskById`, and writes `1` to `g_dwHeapLockEnabled` at
  `0xC03404B0`.
- `g_dwHeapLockEnabled` is not a general "startup complete" flag. Heap lock
  acquire/release paths test it before using RTOS mutex ID 6.

## Early board and peripheral initialization

- `InitializeBoardHardware` at `0xC0015C48` is reached directly from `main`.
  It obtains the board singleton, calls
  `InitializeBoardPeripheralControllers` at `0xC00163C8`, and delays for 10
  microseconds.
- The confirmed peripheral-controller order is Timer3, EMIFA CS2, UART1,
  SPI0, UART0, and Timer1. Timer3 is first stopped by clearing TCR bits
  `0x40/0x80`, then configured with `PRD12 = 0x08F0D17F`, `TCR = 0x80`,
  `TGCR = 5`, and `INTCTLSTAT = 2`. Timer1 is configured with
  `PRD12 = 0x016E35FF`, `TCR = 0x80`, `TGCR = 0x0B`, and `INTCTLSTAT = 3`.
  The recovered AINTC registration table exposes Timer0 and Timer2 callbacks;
  no Timer1 or Timer3 callback registration has been observed. The EMIFA step
  is `ConfigureEmifaCs2ForDspHostDma` at `0xC0016A0C`; the CPU-DSP interface it
  establishes is documented below.
- `ConfigureGpio7And8InterruptEdges` at `0xC0016A70` enables only the rising
  edge for GP7[9] and only the falling edge for GP8[11]. The consumers of
  those two interrupt inputs beyond the interrupt-local event/counter paths
  have not yet been identified.
- `HandleGpioBank7Interrupt` (`0xC0025C14`, system interrupt 49) and
  `HandleGpioBank8Interrupt` (`0xC0025C54`, system interrupt 50) both write
  their interrupt number (`0x31` or `0x32`) to `0xFFFEE024`, then branch on a
  context byte at `+0x16`. In mode 1, bank 7 records source byte `0` and bank 8
  records source byte `1`; in mode 2 they increment context fields `+0x20` and
  `+0x24` respectively. Other nonzero modes return without further work, while
  mode 0 tail-branches to the shared `ProcessGpioBankInterruptEvent`
  (`0xC00292E0`) with source `0` or `1`. The bank-8 wrapper's authoritative
  instruction range is `0xC0025C54-0xC0025C6B`; its following literal pool and
  adjacent helper are not part of that interrupt callback. The shared mode-0
  path resets GPIO interrupt routing, checks the shared service state, starts
  the VoiceTask timer/GPIO pulse path, and updates a timer deadline; its deeper
  timer callback/product ownership remains unresolved.
- The shared mode-0 continuation is now separately identified as
  `ProcessGpioBankMode0TimerService` (`0xC002918C-0xC0029207`). It lazily creates
  the shared `0x118`-byte service object, accepts service states 1 and 4, starts
  the timer/GPIO pulse context, and updates a separate 64-bit timing object
  before invoking virtual callbacks. The callback targets and product role of
  that timing object remain unresolved.
- The mode-0 service reaches the shared timing layer at
  `UpdateSharedTimingObject` (`0xC002C1C4`), which is also called by three
  branches of the MIDI-byte parser. `ComputeSharedTimingElapsed`
  (`0xC002BAE0`) forms a signed 64-bit elapsed value from the shared clock;
  `QuantizeSharedTimingInterval` (`0xC002C15C`) rounds a derived interval to
  tens, clamps it to a minimum of `2000`, and caps it at the literal maximum
  `30000`; `StoreSharedTimingValue` (`0xC002BAD8`) writes the resulting 64-bit
  sample. `UpdateSharedTimingObject` dispatches the quantized interval through
  vtable slot `+0x10` (mode-specific rate sample) and then the reference delta
  through slot `+0x0C` (mode-specific adjustment/state operation). The timing
  unit and product ownership remain unresolved.
- `InitializeVoiceTaskTimerRateSourceRecord` (`0xC002B894-0xC002B8B7`) is the
  common initializer reached by the wrapper at `0xC002B9F4`. It stores initial
  rate `0x2EE0`, clears the accumulator, sets two halfword sentinels to `-1`,
  and clears the trailing state byte in the 0x10-byte timer-rate source record.
- `BeginGpioEventTimestampCapture` (`0xC0029430`) resets the ring and enters mode 1;
  `EndGpioEventTimestampCapture` (`0xC002944C`) returns the context to mode 0 after
  the handler finishes. The mode-one path uses `g_pGpioEventRingState` at
  `0xC002934C`. Its pointed-to state uses dword `+0x80C` as a modulo-`0x100` write
  index. Each indexed
  8-byte slot stores the bank byte at slot `+0x08` and a timestamp delta at
  slot `+0x0C`. The first sample establishes a baseline in the shared state;
  subsequent samples pass through `AppendGpioEventTimestampRecord` at
  `0xC00294CC`, which calls `UpdateGpioEventTimestamp` at `0xC00294A8`, stores
  the new timestamp, returns the elapsed difference, and adds `0x08F0D181` when
  the timestamp wraps below the previous value. The append helper advances the
  modulo-`0x100` write index and emits no record until the baseline exists.
  `ResetEventTimestampRing` at `0xC00293D0` initializes 0x100 records and clears
  the read/write indices; `ReadNextEventTimestampRingRecord` at `0xC002945C`
  advances the read side and returns the next record when the ring is nonempty.
  `InitializeEventTimestampRing` at `0xC0029410` installs the observed vtable
  pointer before resetting the ring. The allocation, vtable ownership, and
  remaining fields of the ring-state object are unresolved.
- `ProcessEventTimestampRingState` at `0xC00388B4` is an entry in the function
  table rooted at `0xC00A7AD8`. It consumes records from the shared ring, compares
  their timestamp deltas with the observed thresholds `3000` and `30000`, and
  returns state codes while updating handler bytes at `+0x18` through `+0x1A`.
  Its terminal/default branch calls `ApplyPendingEventPayload` (`0xC0038838`), which
  obtains the pending source at `0xC0684038` through `GetPendingEventPayload`
  (`0xC0050FB4`). Reported payload state `3` applies a direct `0x4000`-byte block
  through the shared `0x324`-byte VoiceTask state object; state `4` calls
  `DecodeAndApplySqezVoiceTaskState` (`0xC003879C`). That path validates `SQEZ`, bounds
  decoded output extent word `+0x08` against the shared scratch capacity, decodes into
  scratch, and applies the result to the same VoiceTask object. The pending-payload
  producer is `ProcessEventPayloadRecords` at `0xC0050DE4`, called from the terminal
  event/timestamp path at `0xC003891C`. It feeds decoded bytes to
  `ConsumeSystemFileTransferByte` at `0xC0050AC0`, which validates a `KORG SYSTEM FILE`
  header and CRC16, accepts header words `0xFF002FD1` and `0xFA002FD1`, and writes
  sixteen or size-derived `0x400`-byte blocks into `0xC0684038`. The `0xFF` variant
  records source size zero and therefore selects the direct state-3 `0x4000`-byte path;
  the `0xFA` variant records a nonzero header-derived source size and selects state 4,
  which then expects SQEZ data. The handler displays `Wait Signal..` on entry,
  `Receiving..` when it enters the observed receive branch, and `Analyzing..`
  before the terminal/default payload-application branch. The transport record
  ownership, owning task/object, and exact numeric state-code meanings remain
  unresolved. Before the transfer parser, the producer
  passes each record's word at `+0x04` through `DecodeEventTimestampSample`
  (`0xC0050710`). That decoder uses paired sample sums and configured lower/upper
  thresholds to classify bits and emits one byte after eight classifications;
  `AccumulateEventTimestampSamplePairs` (`0xC0050648`) performs the pair accumulation.
  `InitializeEventPayloadDecoderSession` (`0xC0051028`) enables the decoder gate
  and clears the associated parser/ring bookkeeping before each handler run;
  `DeactivateEventPayloadDecoder` (`0xC0051014`) clears that gate on the handler's
  stop/exit path. The sample units, encoding/polarity, and returned-code meanings
  remain unresolved. The producer also retains paired source-byte/timestamp-delta
  records in `g_aEventPayloadRecordHistory` at `0xC048402C`, with write offset
  `g_dwEventPayloadHistoryWriteOffset` at `0xC0483BEC`; this appears to be a
  bounded diagnostic/history buffer, and no higher-level consumer has been found.
  At the handler boundary, producer results `1`/`2` remain in the wait loop, `3`
  selects `Receiving..`, `4` selects `Analyzing..` and payload application, `5`/`7`
  map to handler state `0x0C`, and `6` maps to `0x0E`; the observed timeout branch
  maps to `0x0D`. These are control-flow mappings only, not product-level meanings.
- `InitializeEventTimestampStateMachine` at `0xC00386A4` constructs the object
  using that table. It stores the handler ID at `+0x04`—the registry supplies
  ID `0x0F`—allocates four 8-byte child records at `+0x08`, `+0x0C`, `+0x10`,
  and `+0x14`, and initializes handler bytes at `+0x18` through `+0x1A`. The
  child-record roles remain unresolved; the object is registered in the CPU
  command-handler table at ID `0x0F`.
- `ConfigureGpioInterruptMode` at `0xC00292C0` writes a requested mode to
  context `+0x16`. Mode 1 is the event/timestamp-ring capture mode; mode 2 is the
  type-0 service diagnostic counter mode; mode 0 selects event bit `0x80` or
  `0x100` according to context `+0x17`. Modes 1 and 2 also call the shared
  event-bit helpers at `0xC001704C` and `0xC00170B8`, which set bits `0x80` and
  `0x100` in the supplied object's word at `+0x08`, and write controller values
  `0x31` and `0x32`. Values above two return. The mode-1 caller pair is
  `BeginGpioEventTimestampCapture`/`EndGpioEventTimestampCapture`; the mode-2
  caller is `RunVoiceServiceGpioTransitionTest`. The helpers are also called by
  CPU paths at `0xC009A780` and `0xC009A7CC`, confirming that this
  event/configuration path is shared beyond the two bank interrupt callbacks.
- `InitializePeripheralInterruptSources` at `0xC0000084` enables USB0 through
  `EnableUsb0InterruptSource`, initializes the panel UART0 and MIDI UART1
  paths, and then enables the MMCSD0 interrupt source. The USB0, UART1, and
  MMCSD0 AINTC indices are 58, 53, and 16 respectively.
- The separate startup cleanup sequence `AcknowledgeStartupInterruptSources` at
  `0xC00000AC-0xC00000F3` writes the pending-source cleanup values for GPIO bank 8
  (50), GPIO bank 7 (49), MMCSD0 (16), MIDI UART1 (53), panel UART0 (25), USB0
  (58), and Timer2 (68), then tail-calls `AcknowledgeTimer0InterruptSource`
  (`0xC0025814`) for Timer0 (21). Its current Ghidra body had incorrectly absorbed
  the later AINTC setup function; the authoritative range now ends at the branch
  at `0xC00000F0`.
- The source-specific startup helpers are now bounded separately: GPIO bank 7
  `AcknowledgeGpioBank7InterruptSource` (`0xC0025C30-0xC0025C4F`), GPIO bank 8
  `AcknowledgeGpioBank8InterruptSource` (`0xC0025C70-0xC0025C8F`), MMCSD0
  `ResetMmcsd0InterruptSourceState` (`0xC0025BE0-0xC0025C0B`), MIDI UART1
  `AcknowledgeMidiUart1InterruptSource` (`0xC0025700-0xC0025727`), panel UART0
   `AcknowledgePanelUart0InterruptSource` (`0xC0025904-0xC002591F`), USB0
   `ResetUsb0InterruptSourceState` (`0xC0025CE4-0xC0025D23`), and Timer2
   `AcknowledgeTimer2InterruptSource` (`0xC0025B7C-0xC0025B93`). The MMCSD0
   enable tail helper is `EnableMmcsd0InterruptSource` (`0xC0025B98-0xC0025BC7`);
 - The low ARM vector-area helpers are now bounded independently of the vector
   stubs: `DisableCpuIrqAndReturnCpsr` (`0xC0000040-0xC000004F`) reads CPSR,
   sets CPSR bit 7 (IRQ disable), and returns the original CPSR in `r0`;
   `RestoreCpuIrqMask` (`0xC0000050-0xC0000067`) restores only bit 7 from that
   saved value while preserving the other current CPSR control bits. The
   `mov pc,lr` returns at `0xC000004C` and `0xC0000064` had been misreported by
   the decompiler as indirect jumptable calls; raw ARM instructions confirm
   ordinary function returns. This explains the Pcode warnings seen in callers
   such as `FUN_c00990A0` and does not represent an unresolved callback.
  it writes system interrupt 16 to AINTC_EISR once. The EICR/SICR writes are
  documented as observed register operations; their exact reset-versus-acknowledge
  semantics are not inferred beyond the hardware register names.

## ARM exception vectors and IRQ dispatch

- `CacheExceptionVectorState` at `0xC000022C` iterates the eight ARM vector
  entries at offsets `0x00` through `0x1C`. It decodes each
  `ldr pc, [pc, #imm12]`, caches the address of the vector's literal slot in
  the array at `0xC06A283C`, and caches the slot's current handler target in
  the array at `0xC06A2874`.
- `RestoreExceptionVectorState` at `0xC0000284` copies the eight cached handler
  targets at `0xC06A2874` back into the literal slots at `0xC06A283C`.
- `InitializeInterruptDispatchTable` at `0xC00001AC` clears 101 callback
  entries at `0xC06A26A8` through `0xC06A2838`, then replaces cached vector
  slot 6 (the IRQ vector at offset `0x18`) with `0xC0001560`.
- `HandleIrqException` at `0xC0001560` is the installed ARM IRQ handler. It
  saves exception state, reads `HIPIR[1]` at `0xFFFEE904` to obtain the
  prioritized system-interrupt index for the IRQ host, and disables that source
  through `EICR` at `0xFFFEE02C`. It then saves and updates `GNLR` at
  `0xFFFEE01C`, dispatches through the callback table at `0xC06A26A8`, restores
  `GNLR`, re-enables the source through `EISR` at `0xFFFEE028`, optionally
  transfers into the scheduler, and returns from IRQ mode. Register identities
  are from the AM1802 AINTC memory map in `docs/am1802 datasheet.pdf`.
- `SetInterruptCallback` at `0xC00001EC` installs a callback in the 101-entry
  table at `0xC06A26A8`, indexed by AM1802 system-interrupt number.
- A static table at `g_aRtosInterruptRegistrations` (`0xC00A365C`) contains
  eight `RtosInterruptRegistration` records of 12 bytes. Field `+0x04` is zero
  in every record. `InitializeRtosKernelObjects` installs these mappings:

  | System interrupt | AM1802 source | Callback |
  | ---: | --- | --- |
  | 16 | MMCSD0_INT0 | `HandleMmcsd0Interrupt` (`0xC0025BD0`) |
  | 21 | Timer0 TINT12 | `HandleTimer0Interrupt` (`0xC0025798`) |
  | 25 | UART0 | `HandlePanelUart0Interrupt` (`0xC0025888`) |
  | 49 | GPIO bank 7 | `HandleGpioBank7Interrupt` (`0xC0025C14`) |
  | 50 | GPIO bank 8 | `HandleGpioBank8Interrupt` (`0xC0025C54`) |
  | 53 | UART1 | `HandleMidiUart1Interrupt` (`0xC0025670`) |
  | 58 | USB0 | `HandleUsb0Interrupt` (`0xC0025CCC`) |
  | 68 | Timer2 combined | `HandleTimer2Interrupt` (`0xC0025B1C`) |

- Each callback explicitly acknowledges its source through the AINTC SICR.
  The callback functions and table records are named, typed, commented, and
  cross-referenced in Ghidra.

