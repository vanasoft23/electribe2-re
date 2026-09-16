# CPU-DSP Host DMA, USB, panel, LCD, timers, and SD/MMC

> Detailed evidence extracted from the original monolithic ARCHITECTURE.md.
> Ghidra is authoritative for current symbols, types, comments, and cross-references.

## CPU-DSP Host DMA over EMIFA CS2

- The high-speed AM1802-to-BF523 interface is confirmed as the BF523 Host DMA
  Port connected to AM1802 EMIFA chip-select 2. `GetDspHostDmaPort` at
  `0xC0015C98` returns the CS2 address `0x60000000`, and the low-level transfer
  code repeatedly accesses that address. This matches the AM1802 EMIFA address
  map and the BF52x Host DMA protocol in
  `docs/am1802 technical reference manual.pdf` and
  `docs/bf523 hardware reference.pdf`.
- `ConfigureEmifaCs2ForDspHostDma` writes `0x00200101` to EMIFA `CE2CFG` at
  `0x68000010`. The documented `CEnCFG` fields select normal strobe mode,
  extended wait disabled, a 16-bit bus, one-clock read/write setup and hold,
  three-clock read/write strobe, and one-clock turnaround.
- The externally visible BF523 Host DMA port is four bytes wide in the Ghidra
  model. Offset `+0x00` is the 16-bit data port. Offset `+0x02` returns host
  status on reads and accepts host configuration on writes. The corresponding
  `Bf52xHostDmaPort` structure and the AM1802 EMIFA register block are defined,
  labeled, and commented in Ghidra at `0x60000000` and `0x68000000`.
- A CPU-to-DSP memory write emits the seven configuration halfwords beginning
  with control word `0x00AB`, followed by the DSP destination low half,
  destination high half, transfer count, modify value, zero, and zero. A
  DSP-to-CPU memory read uses the equivalent sequence beginning with `0x00A9`
  and the DSP source address. These values and the seven-word layout match the
  BF52x Host DMA configuration protocol rather than an application-defined
  packet format.
- The data paths move at most 16 halfwords per FIFO block. They poll AM1802
  GPIO GP6[1] as an active-low external FIFO-ready signal and also inspect the
  BF523 host-status bits, including `ALLOW_CONFIG` at bit 7, before emitting a
  new configuration.
- `ReadDspMemoryViaHostDma` at `0xC00141F8` and
  `WriteDspMemoryViaHostDma` at `0xC0014284` both acquire RTOS mutex ID 1 before
  the low-level transfer and release it afterward. This confirms that ID 1
  serializes these complete Host DMA memory operations. It does not establish
  that Host DMA is the mutex's only user.
- The Host DMA accessors, configuration paths, FIFO transfer paths, GPIO-ready
  helper, and mutex-guarded wrappers are named, prototyped, commented, and
  tagged `DSP Host DMA` in Ghidra.

## CPU USB device controller

- The CPU USB device-controller code is anchored by the embedded source strings
  `src/MCU/Component/AM180xUSB.cpp` and `src/usb/cusbdc.cpp`. The AM180x
  controller context uses endpoint records selected by a logical-to-hardware
  endpoint mapping; the recovered paths validate mapped endpoint values before
  accessing those records.
- `SetUsbEndpointTransferBufferParameters` (`0xC0019970`) is called during
  controller initialization and status handling. For supported sizes `0x40`
  and `0x200`, it writes the observed buffer size, derived block-size, mode,
  and buffer-control fields in the USB controller context. The remaining
  meanings of those fields are not assigned.
- The standard endpoint request wrappers are now named and bounded. The
  `GET_STATUS` endpoint path calls `ReadUsbEndpointOutStatus`
  (`0xC0020E10`) for OUT and `ReadUsbEndpointInStatus` (`0xC0020E80`) for IN;
  these read bits `0x20` and `0x40`, respectively, from the endpoint state
  record at offset `+0x02`. The `SET_FEATURE` endpoint path calls
  `SetUsbEndpointOutFeature` (`0xC0020F80`) or
  `SetUsbEndpointInFeature` (`0xC0020F18`), which set the observed `0x20`
  field at record offset `+0x06` or `0x10` field at `+0x02`.
- The `CLEAR_FEATURE` endpoint path calls
  `ClearUsbEndpointOutFeature` (`0xC002104C`) or
  `ClearUsbEndpointInFeature` (`0xC0020FE4`). The OUT helper clears bits
  `0x40` and `0x20` then sets `0x80` at record offset `+0x06`; the IN helper
  clears bits `0x20` and `0x10` then sets `0x40` at `+0x02`. These are
  controller-state transitions observed under the standard request handlers;
  the firmware does not expose vendor names for the individual bits.
- Transfer-ring and USB-MIDI paths use three additional state helpers:
  `CheckUsbEndpointTransferCompletion` (`0xC002140C`) returns bit `0x01` at
  record offset `+0x02`; `CheckUsbEndpointTransmitReady` (`0xC0021498`)
  returns bit `0x04` there and `ClearUsbEndpointTransmitReady`
  (`0xC0021528`) clears it; and `CheckUsbEndpointReceiveReady`
  (`0xC00215B0`) returns bit `0x01` at record offset `+0x06`.
- The interrupt-side transitions are also bounded. When called by
  `HandleUsbEndpoint1ReceiveInterrupt`,
  `CheckUsbEndpointReceiveStateForInterrupt` (`0xC001A82C`) tests the record
  at `+0x06`, accepts an already-set bit `0x01`, or converts `0x40` to `0x80`.
  When called by `HandleUsbEndpoint1TransmitInterrupt`,
  `CheckUsbEndpointTransmitStateForInterrupt` (`0xC001A958`) performs the
  corresponding `+0x02` transition from `0x20` to `0x40`.
- These findings establish USB endpoint record accesses, request-direction
  routing, and transfer-state transitions. They do not yet identify the
  higher-level USB-MIDI packet meanings or the vendor-specific meaning of the
  endpoint state bits.

## Panel MCU transport over UART0

- `InitializePanelUart0` at `0xC0025830` configures the panel-controller link
  on UART0 (register base `0x01C42000`), binds its protocol state, and enables
  AINTC system interrupt 25. `HandlePanelUart0Interrupt` services receive,
  transmit-ready, and line-status causes, with a bounded loop of eight causes
  per entry.
- The transmit path uses the 40-byte circular buffer
  `g_PanelUart0TxQueue` at `0xC033E648`.
  `InitializePanelUart0TransmitQueue` is reached from the C++ initializer
  table, and `TransmitNextPanelUart0Byte` dequeues one byte and writes it to
  the UART0 transmit-holding register.
- `PanelUartProtocolState` is a confirmed 0x124-byte object. Its fields include
  a five-byte packet buffer and count, a 256-byte bulk-block buffer and count,
  mode bytes selecting those receive paths, and an activity-state pointer.
  `ConsumePanelUartProtocolByte` assembles the selected input unit and
  dispatches completed packets or blocks. In normal mode it completes one
  packet every five bytes; single-byte mode stores the received byte at packet
  offset zero; bulk mode dispatches each completed 0x100-byte block through the
  observed bulk consumer. The parser also refreshes an activity-state deadline
  on each received byte. The five-entry packet-state fields and bulk-consumer
  object semantics remain unresolved.
- The completed packet source record occupies protocol-state `+0x04`. When
  CentralServiceTask dequeues a panel record, it copies the same eight-byte queue
  record into protocol-state `+0x0C`; `ProcessPanelUartCentralMessage` dispatches
  the type byte from that destination. This is distinct from the direct
  `PanelIdentityState` path used before service mode is enabled.
- `ProcessPanelUart0ReceiveEvent` (`0xC0025970`) routes a completed five-byte
  packet directly to `HandlePanelIdentityResponse` when the panel-service flag
  is clear. When that flag is set, it enqueues the packet at protocol-state `+4`
  into `g_stCentralServiceQueue2` (`0xC033E57C`) and the CentralServiceTask later
  consumes it through `ProcessPanelUartCentralMessage`. The shared enqueue helper
  (`0xC0024AFC`) signals event object 2/mask 2 on the empty-to-nonempty transition
  and resets/retries the source record when the queue is full.
  - `SetPanelUartServiceMode` (`0xC0025A14`) writes the service-mode flag used by
   both the receive and line-status paths. `CentralServiceTask::taskProc` is the
   only observed in-image caller and sets it to `1` before entering its event loop;
    no alternate value or clearing path is present in the loaded image.
  - The fixed-packet builders are now bounded. `QueuePanelCommandWithBytePayload`
    (`0xC002852C`) emits `{opcode,payload,0,0,0}` under the shared `+0x04` gate.
    `QueuePanelCommandWithTwoBytePayload` (`0xC00285C0`) emits
    `{opcode,valueA,valueB,0,0}`, and its opcode-`0x00` adapter
    (`0xC0028600`) is used by the mapped-state output path. The word-pair helper
    (`0xC0028614`) emits little-endian 16-bit pairs and is used by the `0x85`/`0x86`
    touch-calibration packets. These are packet-format findings only; they do not
    identify a backlight control.
  - A separate byte/bulk-transfer path also shares the panel-UART0 transmit
    queue. `GetOrCreatePanelIdentityHandshakeState` (`0xC002A320`) returns the
    eight-byte child stored through `g_pPanelIdentityHandshakeState`
    (`0xC033E6FC`, vtable `0xC00A4530`); its byte `+0x04` gates the fixed packet
    producers. `QueuePanelUartByte` (`0xC002868C`) and
    `QueuePanelUartBytes` (`0xC00286B4`) append raw bytes to
    `g_PanelUart0TxQueue`, while `ResetPanelUartTxQueue` (`0xC00286C0`)
    resets its indices.
  - `PanelUartProtocolState` is a confirmed polymorphic 0x124-byte parser
    class, now recorded in Ghidra with constructor `0xC0027F9C` and destructor
    entries `0xC0027F3C`/`0xC0027F5C`. Its `+0x04` five-byte packet buffer is
    assembled by `ConsumePanelUartProtocolByte` (`0xC00282D8`); its `+0x0C`
    scratch packet is consumed by `ProcessPanelUartCentralMessage`
    (`0xC002814C`). The parser also owns the single-byte flag, 256-byte bulk
    buffer, counters, and activity-state pointer. The parser and identity state
    are distinct objects.
 - `ProcessPanelUartBulkTransferState` (`0xC00462F0`) is driven by received
   panel bytes and recognizes the observed control values `0x11`, `0x01`,
   `0x7E`, `0x00`, `0x80`, and `0x1A`. It sends short framed messages and
   0x100-byte blocks through `SendPanelUartBulkBlock` (`0xC0046190`), which
   appends a one-byte additive checksum. `AdvancePanelUartBulkBlockAfterAck`
   (`0xC0046228`) compares returned 0x100-byte data, advances the block index,
   and queues byte `0xC8` between blocks. The higher-level panel boot/recovery
   or update meaning is not established from CPU code alone.
 - The associated transition helpers are explicit: `BeginPanelUartBulkHandshakeTransition`
   (`0xC00468F0`) flushes the TX queue, writes a direct UART0 control value,
   toggles GPIO group-3 mask `0x100` and GPIO direction bit `0x10000000` with
   delays, then queues byte `0x18`; `EndPanelUartBulkHandshakeTransition`
   (`0xC0046A64`) performs the complementary queue/UART/GPIO sequence and
   clears protocol flags. This is a panel transport/recovery path, not the
   Global `POWER SAVE MODE` field-`+0x29` / command-`0x33` path, and it does
   not identify a direct LCD-backlight consumer.
 - `HandlePanelUart0LineStatus` (`0xC00259C8`) is the UART0 line-status interrupt
  path. It writes status-control value `3` when the UART status has bit `7` set;
  with panel-service mode active, it also resets and enqueues the current packet
  record through the same CentralServiceTask queue path.
 - `PanelIdentityState` is a confirmed polymorphic 0x28-byte class, now recorded
  in Ghidra with non-deleting/deleting destructors at `0xC00286CC`/`0xC002870C`
  and constructor `0xC002878C`. It records response
  values and received flags for reply opcodes `0x80`, `0x91`, `0x92`, `0xA0`,
  and `0xA1`, two decoded variant bytes, and a query-failure byte.
  `HandlePanelIdentityResponse` stores the packed four-byte payload from `0x80`
  and the observed two-word response pairs for `0x91/0x92` and `0xA0/0xA1`,
   setting received flags for the `0x91` and `0x92` pair. The request helpers
   queue five-byte zero-padded requests beginning with `0x80` and `0x91`.
 - The fixed-packet gate is a separate polymorphic 8-byte `PanelCommandGateState`
  class, now recorded in Ghidra with destructor entries at `0xC00286FC` and
  `0xC002876C`. Its byte at `+0x04` suppresses packet emission when nonzero;
  the shared builders use it for opcodes `0x02`, `0x80`, `0x83`, `0x84`,
  `0x90`, `0x91`, and `0xA0`. The gate object's role is transport-side
  suppression only; it is not the 0x28-byte response accumulator.
 - `VoiceTaskPanelActivityContext` is a confirmed polymorphic 0x1C-byte class
   (vtable `0xC00A4570`)
   recorded in Ghidra with lifecycle methods at `0xC0028B1C`, `0xC0028B3C`,
   and `0xC0028B7C`. Its fields are a GPIO0 register pointer at `+0x04`, a
   shared 0x118-byte VoiceTask state pointer at `+0x08`, reset-pending byte
   `+0x0C`, GPIO recovery countdown `+0x10`, last sampled GPIO state `+0x14`,
   and AUTO POWER OFF countdown `+0x18`. Its methods initialize and reload
   those countdowns, sample the active-low `GPIO_IN_DATA67` bit 31, publish
   common-message `1`/code `0x23` on input changes, and enqueue CommandTask
   handler `0x18` when recovery or AUTO POWER OFF expiry requires the LCD/panel
   reset path. This class is distinct from the larger timer-pulse state that
   drives GPIO group 3 mask `0x800`.
- The battery-related CPU path is **panel-MCU mediated**, not a recovered
  direct AM1802 ADC/I2C path. The Global Parameter UI includes `BATTERY TYPE`,
  `AUTO POWER OFF`, and `POWER SAVE MODE`. Its value formatter
  `FormatGlobalParameterValueText` (`0xC007FABC-0xC00800DB`) identifies Global
  selector `0x0E` as the battery-chemistry choice: stored value `0` renders
  `Ni-MH`, value `1` renders `Alkali`, and other values render an unknown-value
  marker. For the type-09 Global selector, the descriptor entry at index `0x0E`
  is `ReadVoiceTaskControlField24ValueRecord` (`0xC007AB8C`), which reads shared
  control object `g_pVoiceTaskSharedControlStateCache` (`0xC0691324`) byte `+0x24`
  through `GetVoiceTaskControlField24` (`0xC00472F0`). A persistence snapshot also
  copies this shared-control byte into its observed image offset `+0x10E`.
  `AdjustVoiceTaskControlField24ByStep` (`0xC007B2D0`) is the matching value-edit
  handler: it applies a signed step, clamps the result to `0..1`, creates a value
  record, and invokes the field-24 update callback. This confirms the firmware's
  two-choice write path for the Ni-MH/Alkali byte. `UpdateVoiceTaskControlField24FromValueRecord`
  (`0xC007A7D4`) writes the byte and notifies the Global backing object's `+0x04`
  listener list; the battery client was registered there with
  `RefreshBatteryMonitorThresholdsFromModeEvent` (`0xC00779B4`). Thus a recovered
  Global chemistry edit immediately refreshes the active threshold table. The confirmed consumer is the
  battery-monitor listener path: `RefreshBatteryMonitorThresholdsFromChemistrySetting`
  (`0xC0077940`) selects `g_niMhBatteryThresholds` (`0xC00E4594`, bytes
  `{134,129,124,97}`) for value `0`, or `g_alkaliBatteryThresholds`
  (`0xC00E4590`, bytes `{127,110,104,97}`) for value `1`, and stores that table
  pointer in client `+0x318`.
   `ClassifyBatteryMeasurementByChemistry` (`0xC0077A14-0xC0077B13`) compares
   the incoming measurement at client `+0x320` against those four thresholds,
   maps it into states `0..4`, and emits guarded common-message type `9` with
   payload `(0x1B,0x1A)` on the observed low-battery transition. More exactly, for
   thresholds `{t0,t1,t2,t3}`, measurement `>t0` maps to state `4`, `t1<measurement<=t0`
   to state `3`, `t2<measurement<=t1` to state `2`, `t3<measurement<=t2` to state `1`,
   and `measurement<=t3` to state `0`. State `1` sets client `+0x328` and emits the
   warning only when latch `+0x32C` is clear and shared listener state `+0x308` is zero;
   states `2..4` clear the latch, while state `0` starts the observed timer/recovery
   context without clearing it and calls `RequestLcdPanelHardwareReset` (`0xC0028C18`).
   That helper enqueues a zero-payload CommandTask record with handler ID `0x18`; the
   registry maps it to `ResetAndInitializeLcdPanelHardware` (`0xC0038A54`), which drives
   the LCD RGB outputs low, dispatches LCD state `(7,0)`, and toggles the LCD reset and
   GPIO7P14 pins with 100 ms delays. Its measurement arrives through `SetBatteryMonitorMeasurement` (`0xC006EC88`), reached by
   `HandleCommonMessageType7BatteryMeasurement` (`0xC00837D4`) at shared/base
   common-service vtable slot `+0x44`. `ProcessPanelUartCentralMessage`
   (`0xC002814C`) creates that common-message type 7 from panel-UART packet type
   6 byte `+0x0D`; therefore the recovered CPU path is:
   `panel UART0 packet 6 -> common message 7 -> battery measurement classifier`.
   In the main common-message service mode, the emitted type-9 payload is consumed
   at vtable slot `+0x3C` by `SelectMainServiceSecondarySubobject` (`0xC00837B8`):
   selector `0x1B` creates the type-`0x1B` service subobject and passes value `0x1A`.
   `InitializeVoiceTaskServiceSubobjectType1B` (`0xC0063068-0xC00631CF`) then creates
   a `Warning` text child and a selector-indexed status child. The status table at
   `0xC00E3280` has entry `0x1A` at `0xC00E32E4`, whose literal is `Battery Low`.
    The recurring `0x9C` child record's renderer (`0xC008CC70-0xC008CCD3`) computes
    text metrics, merges the LCD update region, and calls `LCD_DrawString`; thus the
    low-battery transition has a confirmed CPU-to-LCD warning path. The measurement's
    exact units and the behavior of alternate selected common-message service modes
    remain unresolved.
   The actual type-09 Global value descriptors for the adjacent selectors are now also
   separated from the per-part formatter path below: selector `0x0F` reads shared child
   byte `+0x25` (`0xC007B540`) and edits it through `0xC007A820`, which applies command
   `0x34`; selector `0x10` reads shared child byte `+0x29` through
   `ReadVoiceTaskPowerSaveModeValueRecord` (`0xC007A9CC`) and edits it through
    `AdjustVoiceTaskPowerSaveModeByStep` (`0xC007A8B4`). The type-09 value-edit callback
    (`0xC0064878`) dispatches those handlers from the Global backing object's table at
    `+0x448`. The Global formatter confirms the numeric labels for selector `0x10`:
    `0` is `Disable`, `1` is `Auto`, and `2` is `Enable`.
    For selector `0x10`, the editor clamps the value to `0..2`, then
    `SetVoiceTaskControlField29AndApplyDsp33` (`0xC0047348-0xC0047373`) writes `+0x29` and
    invokes command `0x33`. The command jump table maps `0x33` to the veneer
    `HandleApplyCommand0x33` (`0xC004B99C`), which branches to
    `ReconfigureAllVoicesFromTimbre` (`0xC009A840`) and reconfigures all 16 voices,
    oscillator-slot state, and related timing/profile state. The changed selector also emits
     extended-state event code `0x3D`; the deferred handler `ApplyVoiceTaskParameterCode`
     (`0xC008EF20`) reads the saved `+0x29` value and re-applies the same command `0x33`.
     The Global descriptor's value-record callback,
      `ApplyVoiceTaskPowerSaveModeValueRecord` (`0xC007A904-0xC007A91F`), independently
      performs the same `+0x29` write and gated command-`0x33` apply when a value record is
      replayed. Neither direct nor value-record command path contains a direct panel operation.
      After a successful Global value edit, `ApplyVoiceTaskGlobalSelectionValueStep` also walks
      the Global backing object's `+0x04` listener records. The battery client is registered on
      that list, which explains the immediate chemistry-threshold refresh, but the shared
      packet-`0x02` panel-indicator owner is not registered there. The latter is created only by
      `InitializeVoiceTaskServiceControlContext` (`0xC006EEC4`) and is reached through the
      indirect service-event callback `ApplyServiceEventToVoiceTaskListenerState`
      (`0xC0083790`), which writes shared listener-state `+0x308` before dispatching its records.
      No recovered instruction connects the Global POWER SAVE edit to that service-event writer.
      Neither direct setter nor deferred handler contains a direct LCD, backlight GPIO, I2C,
    UART, or panel-MCU write. Separately, the shared listener owner is initialized from
    `+0x29` and its `ApplyVoiceTaskListenerPanelAndIndicatorState` callback
    (`0xC0051140-0xC00511B4`) can queue panel-UART0 packet `{0x02,payload,0,0,0}`; the
    broad `ApplyVoiceTaskStateObject30CChildState` path also passes `+0x29` to the same
    packet/GPIO helper. The immediate runtime link from the Global selector edit to that
    listener refresh is not yet proven, so the physical backlight-flicker sink remains
    unresolved. By contrast, the adjacent AUTO POWER
   OFF command `0x34` veneer (`0xC004B9B0`) branches to `ApplySharedControlModeAndLcdGpio`
   (`0xC009A878`), which stores the mode in the shared listener owner and tail-jumps through
   `SetVoiceTaskListenerControlMode` (`0xC00511B0`) to the shared packet/GPIO helper
    `ApplyVoiceTaskListenerPanelAndIndicatorState` (`0xC0051140-0xC00511A7`). For owner mode
    values `0`/`1`/`2`—the confirmed `Disable`/`Auto`/`Enable` labels—it derives payload
    `0`/`(+0x320 ^ 1)`/`1`, queues panel-UART0 packet `{0x02,payload,0,0,0}`, and drives
    the observed RGB GPIO state when the derived payload is zero. The diagnostic battery
    workflow's adjacent `Led Half Measurement` state sends `{0x02,1,0,0,0}`, making this
    packet the strongest CPU-side LED/backlight-control candidate; the exact panel command
    polarity and the immediate selector-to-listener trigger remain unresolved.
    The listener mechanics narrow the missing link further: `UpdateVoiceTaskListenerGateAndIndicators`
    (`0xC00511EC`) is installed by `InitializeVoiceTaskSharedControlListener` as a callback on
    `g_pVoiceTaskListenerState` (`0xC03405C4`). It runs when that object's `+0x308` state is explicitly
    written and its active records are walked by `SetVoiceTaskListenerStateAndNotify`/the shared
    listener dispatcher. The Global selector edit instead notifies its separate selector/parameter
    listener records after applying `+0x29`/command `0x33`; no recovered instruction in that direct
    or deferred path writes shared listener-state `+0x308`. Thus packet `0x02` is reachable through
    a shared-state notification path, but the selector-to-notification trigger is still unproven.
    Across the recovered direct callers of `GetOrCreateVoiceTaskListenerState`, the explicit
    `+0x308` writer is `SetVoiceTaskListenerStateAndNotify`; the remaining callers read or register
    listeners against that object. This makes the missing selector-to-state-notification edge a
    concrete unresolved event-dispatch boundary rather than an unidentified direct field write.
    The asynchronous Global event boundary is also now bounded: `g_pVoiceTaskExtendedState`
    (`0xC03405D0`) receives selector `6` and parameter code `0x3D` through
    `StageVoiceTaskExtendedStateTransition` (`0xC0090310`). Handler ID `0x1E` consumes that state;
    state `6` reaches `ApplyVoiceTaskParameterCode`, which reloads shared child `+0x29` and applies
    command `0x33`. The extended-state dispatcher then notifies its own listener records. No
    recovered instruction on this Global direct/deferred path calls `SetVoiceTaskListenerStateAndNotify`
    or invokes the shared packet-`0x02` callback, so any remaining selector-to-panel edge would have
    to be an unbounded indirect callback or an external event not recovered in this CPU call path.
 - There is a separate, easily conflated parameter-formatting path: its selector
  `0x0E` branch at `DispatchGlobalParameterValueFormatting` (`0xC0086848`)
  reads per-part record byte `+0x819` through `FormatVoiceTaskPartField819Value`
  (`0xC00808D4`), and the corresponding setter `0xC0049C98` applies internal
  command key `0x25`. Its surrounding label table contains the same observed
  `BATTERY TYPE`/`Ni-MH`/`Alkali` strings, but its per-part/DSP dataflow is not
  proven to be the type-09 Global selector backend. The shared-control setter
  `SetVoiceTaskControlField24` (`0xC00472F8`) is also reached by generic parameter
  code `0x3B` and by the value-edit listener callback. No traced path writes the
  setting directly to an AM1802 I2C controller or GPIO input.
 - The adjacent Global Parameter selector paths are also explicit: selector `0x0F`
   reads `+0x825` and displays the observed four-hour/Disable values, while selector
   `0x10` reads masked `+0x826` and displays Auto/Disable/Enable. Their setter path is
   now traced at `SetVoiceTaskPartRecordFields825And826AndApplyDsp2A2B`
   (`0xC0049EE4`): it clamps/stores `+0x825`, applies internal control/DSP key `0x2A`,
   looks up `g_aVoiceControlRecordTable[voice][+0x825]` through
   `GetVoiceControlRecordMappedValue` (`0xC0098148`), stores the resulting 7-bit value
   at `+0x826`, and applies key `0x2B`. The runtime mapping is a sixteen-by-`0x31`
   table at `0xC013C200`; `ApplyVoiceTaskDspControlAndVoiceParameters` repopulates it
   from the per-voice `+0x825/+0x826` pairs, while the Timbre refresh helper updates
   individual cells from nested fields `+0x1D/+0x1E`. This proves the CPU data path
   behind the selector values, but no direct LCD, GPIO, I2C, or panel-UART call has
   been found from this setter/key path. A separate timer/GPIO pulse path was traced,
   but its callers identify it as a timing/diagnostic output rather than the LCD
   backlight, so the physical backlight/flicker consumer remains unresolved.
   The setter is also reached during assignment/state restoration: byte `+0x25` of
   each selected `0x330`-byte assignment record feeds the same setter, and extended
   state entry `0x2B` reloads the corresponding byte at `+0x21` with propagation
   enabled. These restore paths likewise contain no direct display or panel operation.
   The apply-command jump table confirms key `0x2A` enters
   `HandleApplyCommand0x2A` (`0xC004B888`), which stores per-voice compact field
    `+0x33` and refreshes rate-mode state, while key `0x2B` enters
   `HandleApplyCommand0x2B` (`0xC004B8AC`), which stores an oscillator-ID/control
    field, refreshes rate-pending state, and recomputes derived field `+0x3C`.
   Neither handler contains a direct LCD, GPIO, I2C, UART, or panel-command operation.
   The service-listener fan-out was also traced: the relevant callbacks
   `RefreshVoiceTaskSelectorCacheFromServiceEvent` (`0xC0041E50`),
   `RefreshVoiceTaskSelectorCacheFromPartEvent` (`0xC0041E2C`), and
   `RefreshVoiceTaskSelectorCacheFromSharedEvent` (`0xC00426DC`) copy the masked
    `+0x826` value into an internal selector/cache field at `+0x3E0`, alongside
   neighboring per-part values. Their bodies contain no direct LCD, GPIO, I2C, UART,
   or panel-command operation, so the physical backlight/flicker sink remains outside
   this recovered path.
- `ProcessBatteryCheckWorkflowStep` (`0xC0075618-0xC007596B`) is the confirmed
  diagnostic/measurement state machine. Its strings include `Battery Check`,
  `DC Jack Pull`, `Power Measurement`, `LED Half Measurement`, `Level Low`, and
   `Level High`; state 9 specifically displays `Level Low`. The indirect worker callback is the vtable entry at
  `0xC00E43B0 + 0x08`. State 4 compares the raw panel measurement at
  owning-service `+0x1D8` with `0xB0`; above that threshold it sets mapped-state
  bit `0x40000` in entry `0x12`, otherwise it clears that entry. State 10 repeats
  the measurement operation against `0x69`, retrying with a counter at worker
  `+0x14` until the threshold is reached or the retry limit expires. State 7
  displays `LED Half Measurement` and queues panel command `0x02` with payload
  `1`; state 9 displays `Level Low` and resets the mapped-state entries. Panel
  packets have a fixed five-byte format. In the normal
  service path, packet type `6` forwards byte 1 as common-message type `7`,
  which stores the main-service field at `+0x1D8`; type `7` forwards byte 1 as
  a boolean common-message type `6`, stored at `+0x1D4`. The battery workflow
  reads both fields, compares the `+0x1D8` value with `0xB0`, and queues the
  panel packet `{ 0x02, 0x01, 0, 0, 0 }` in its observed state-7 path immediately
  after the `LED Half Measurement` display. `QueuePanelCommand02` has only one
  other caller: the shared-control path derives the payload from a mode value
  and, for payload 0, directly changes the LCD red/green GPIO pins. This supports
  —but does not prove—a panel indicator/load-control role for command `0x02`,
  rather than a raw ADC read. The strings and dataflow support the inference that
  `+0x1D8` is the panel's battery/power measurement and `+0x1D4` is the DC-jack
  condition; their electrical polarity, unit, and the exact command-`0x02` action
  remain unconfirmed.
  - `QueueVoiceServiceSysExCommand` (`0xC0071708`) constructs the nine-byte panel-MCU SysEx
    frame `{ 0xF0, 0x42, 0x22, 0x00, 0x01, 0x24, command_id, parameter, 0xF7 }`. The battery/DC
    workflow uses command `0x6D` with parameters `1` through `5`; the selector path uses command `0x6F`.
  - The automatic low-battery monitor is a separate polymorphic
   `VoiceTaskBatteryMonitorClient` object of size `0x330`, now recorded in Ghidra
   with vtable, non-deleting/deleting destructors, constructor, 32 embedded
   listener slots, chemistry byte, raw measurement, threshold pointer, level
    state, and low-battery latch fields. `GetOrCreateVoiceTaskBatteryMonitorClient`
   (`0xC0084160`) allocates it lazily; the constructor is `0xC0077B4C`, the
   destructors are `0xC00778B8` and `0xC0077914`.
 - `HandleCommonMessageType7BatteryMeasurement` (`0xC00837D4`) extracts
   common-message payload `+0x08` and sends it through `SetBatteryMonitorMeasurement`
   (`0xC006EC88`). `ClassifyBatteryMeasurementByChemistry` (`0xC0077A14`)
   stores the raw value at client `+0x320` and classifies it against the four
   bytes at client `+0x318`: `>t0 => 4`, `>t1 => 3`, `>t2 => 2`, `>t3 => 1`,
   otherwise `0`. Values 0 and 1 correspond to the observed `Ni-MH` and
   `Alkali` threshold tables; exact measurement units remain unresolved.
 - `GetPanelDiagnosticRecord` (`0xC002CA0C`) returns the record at fixed address
  `0x8001B000`, outside the loaded CPU image. The confirmed fatal-error consumer
  reads its first three dwords for diagnostic output; no producer for this buffer
  is present in the loaded image, so its ownership remains unresolved.
- `HandlePanelUart0Interrupt` acknowledges AINTC system interrupt 25 and uses
  the UART interrupt-identification register to service transmit-ready,
  receive/data-available, and line-status causes, with a maximum of eight
  causes per interrupt entry. `ProcessPanelUart0ReceiveEvent` feeds each byte
  into the parser and sends completed packets to the identity handler on the
  normal path; a separate observed service path drains a callback/record queue.
- `DecodePanelHardwareVariant` recognizes the observed `0x91` response words
  `0x18000000`, `0x28000000`, `0x48000000`, `0x88000000`, `0x14000000`,
  `0x24000000`, `0x0C000000`, `0x0A000000`, `0x00140000`, and `0x80`, mapping
  them to compact values `1` through `9` with the observed `0x0A000000` case
  mapping to `0x0B`; response word `0x400` sets the extended-variant flag.
  These values are accepted only when the recorded `0x92` response word is
  zero. Product-level panel variant names are not established.
 - `QueryPanelControllerIdentity` at `0xC00288EC` sends five-byte requests,
   waits for the `0x80` and `0x91` replies, validates that the `0x80` response
   value is `0x96`, and calls `DecodePanelHardwareVariant`. Timeout or mismatch
   sets `PanelIdentityState::bQueryFailed`. The precise vendor-level meanings
   of the request/reply opcodes are not yet established.
 - The panel-UART0 transmit pool contains additional fixed five-byte request
   producers beyond command `0x02` and the identity requests. `QueuePanelCommand83`
   (`0xC0028578`) emits `{0x83,payload,0,0,0}` from type-20 service
   initialization/reset and calibration-state paths. In the type-20 workflow,
   payload `1` is used during initialization and payload `0` is used on reset and
   around the calibration-range write; this is consistent with a calibration-mode
   control, but its exact panel action is not proven. `QueuePanelCommand84`
   (`0xC0028584`) emits `{0x84,payload,0,0,0}` from mode-2 secondary-object
   initialization and type-1F/mapped-state transitions. The type-1F producer
   toggles its local byte at `+0x28` and forwards the new value; the mapped-state
   producer uses payload `0` at entry and `1` at completion. This supports a
   panel service-mode enable/disable role, but does not prove the panel-side
   function. `QueuePanelCommand90`
   (`0xC0028590`) emits `{0x90,0,0,0,0}` during main common-message service
   activation and type-00 service state transitions. All three honor the same
   panel command gate at the supplied object's byte `+0x04`. Their exact
   panel-MCU meanings remain unresolved; the surrounding service names are
   evidence about CPU context only, not proof of packet semantics. None of
   these producers is called by the Global `POWER SAVE MODE` field-`+0x29` /
   apply-command-`0x33` path, so they do not currently identify the backlight
   flicker sink.
 - The type-20 path now exposes a separate, non-backlight panel protocol. Startup
   calls `LoadPanelTouchCalibrationBounds` (`0xC002A248`), which reads an
   eight-byte record from serial flash into four 16-bit bounds. Its observed
   validation rules turn lower bounds above `0x3FE` into `0`, turn upper bounds
   above `0x3FE` into `0x3FF`, and raise upper bounds at or below `0x1FF` to
   `0x200`.
   `SendStoredPanelTouchCalibration` (`0xC002A35C`) then sends the first pair as
   `{0x85,lo16,hi16}` and the second pair as `{0x86,lo16,hi16}` in the fixed
   five-byte packet format. During the type-20 `Touch Upper Right` / `WRITE
   CALIBRATION` workflow, the same `0x85`/`0x86` pair producers transmit the
   updated bounds and `SavePanelTouchCalibrationBounds` (`0xC002A2F0`) writes the
   four halfwords back to serial flash. This establishes `0x85` and `0x86` as
   calibration-bound packets; vendor field names and the panel-side coordinate
   transform remain unresolved.

## LCD output over SPI0

- `InitializeBoardPeripheralControllers` calls `SPI0_Init` once for the LCD
  path. `InitializeSpi0ForLcd` (`0xC0018D24`) holds `SPIGCR0` in reset during a
  five-microsecond board delay, enables the controller, writes `SPIGCR1=3`,
  `SPIPC0=0x601`, and `SPIPC1=1`, stores SPI format value `0x00011D08` in
  format slot 0, and sets the observed `SPIGCR1` enable bit `0x01000000`.
  The bit-level electrical interpretation of the format value remains tied to
  the AM1802 SPI register definition and is not guessed here.
 - The recovered board-GPIO wrappers separate several nearby signals: GP6P9
   (GPIO group 3/mask `0x200`) is the LCD reset line; GP6P10 (mask `0x400`) is
   used by the DSP reset/boot assert-release paths; and GP6P3/GP6P4/GP6P5
   (masks `0x08/0x10/0x20`) are driven together as the recovered red/green/blue
   status-indicator outputs by panel initialization, Timer2 status, error, and
   shared-control paths. None of these wrappers is called from the Global
   POWER SAVE MODE field-`+0x29`/command-`0x33` path. The CPU-side recovered
   GPIO inventory therefore still has no identified direct LCD-backlight
   consumer; a panel-MCU command remains the unresolved possibility.
 - Two additional GPIO wrappers are now assigned only to the panel byte/bulk
   handshake: `SetPanelHandshakeGpio100` (`0xC001722C`) drives GPIO group 3
   mask `0x100`, and `SetPanelHandshakeDirectionGpio` (`0xC0017274`) clears
   GPIO_DIR67 bit `0x10000000` before driving the corresponding group-3 state.
   Their only recovered callers are `BeginPanelUartBulkHandshakeTransition`
   and `EndPanelUartBulkHandshakeTransition`; their board-level pin names and
   electrical role remain unresolved. This is further evidence that these
   signals belong to panel transport/recovery, not the recovered LCD RGB/reset
   or Global POWER SAVE paths.
- The AM1802 GPIO set/clear helper uses packed register groups: group 3 is
  `GPIO67` and group 4 is `GPIO8`. The resulting pin assignments are now
  explicit for the requested masks. `SetVoiceServiceGpioPulseMask800`
  (`0xC0016F44`) drives **GP6[11]** (GPIO67 bit 11, mask `0x800`) with
  inverted polarity. It is used by the Timer0/GPIO pulse state and the
  service transition diagnostic. `SetVoiceServiceGpioDriveMask1000`
  (`0xC0016EFC`) drives **GP6[12]** (mask `0x1000`) with normal polarity;
  its recovered callers are the type-0 service stage-7 GPIO check and the
  paired transition diagnostic. `SetGp7P11Inverted` (`0xC001734C`) drives
  **GP7[11]** (GPIO67 bit 27, mask `0x08000000`) with inverted polarity;
  startup/reset paths and common-message type-0x16 class-5 subtype 0 call
  it, but the external board-net function is unresolved. A group-4 mask
  `0x8000` would be **GP8[15]**, but the CPU application contains no
  recovered access to that pin. The nearby DSP-boot `0x8000` access uses
  group 1 (`GPIO23`) and is therefore GP2[15], not GP8[15].
- The LCD object stores the board, GPIO0, and SPI0 pointers at object offsets
  `+0x14`, `+0x18`, and `+0x1C`. `ResetLcdDisplay` (`0xC0015EB8`) clears both
  the 0x400-byte page shadow and framebuffer, marks the object initialized at
  `+0x04`, and forces the first refresh. The framebuffer is eight pages of
  `0x80` bytes, i.e. 128 columns by eight page rows; the fixed page-transfer
  length is returned by `GetLcdPageTransferLength` (`0xC0015A98`).
- `ConstructLcdObject` (`0xC0015D14`) installs the LCD vtable, initializes
  the flags and page counter, sets the initial contrast byte to `0x80`, and
  clears the board/GPIO0/SPI0 pointers. The object is constructed during the
  C++ static-initializer path: `RunDspLcdStaticInitializer` (`0xC0015CC0`)
  invokes `InitializeDspAndLcdStaticObjects` (`0xC001571C`) with the
  observed selector `0xFFFF`; that wrapper initializes the DSP hardware
  interface and constructs the global LCD object at `0xC031BB2C`. The
  selector's broader meaning is unresolved.
- `RefreshLcdDisplay` (`0xC0015FA0`) emits contrast command `0x81` followed by
  the contrast byte when contrast is dirty. When refresh is pending or forced,
  it compares each framebuffer page against its shadow, copies changed pages to
  the shadow, and sends only changed pages through `SetLcdPage` (`0xC001613C`).
  Pixel writes update the framebuffer and submit one-pixel regions; the region
  tracker merges rectangles, while the confirmed transfer decision is the
  per-page framebuffer/shadow comparison.
- `SetLcdPage` selects command mode through GPIO group 4/mask 2, sends command
  bytes `page-0x50`, `0x40`, `0x10`, and `0`, waits for SPI TX readiness, delays
  two microseconds, selects data mode, transmits the page's `0x80` bytes, waits
  again, and delays two microseconds. State 0 is command mode and state 1 is
  page-data mode in `SetLcdDataCommandMode` (`0xC0016C18`).
- The shared SPI primitives are now bounded. `SpiTransmitBufferReady`
  (`0xC00117C8`) tests `SPIFLG` bit `0x200`; `SpiWaitForTransmitReady`
  (`0xC0015CDC`) spins until that bit is set. `SpiTransmitByteWithChipSelect`
  (`0xC00183CC`) writes one byte to `SPIDAT1`, while `SpiTransmitStream`
  (`0xC001851C`) sets `SPIDAT1` bit `0x10000000` on all but the last byte to
  hold chip select between bytes. Both use a 1000-iteration per-byte timeout.
  The byte helper is shared by the LCD command path and the DSP SPI1 boot path;
  the stream helper's confirmed caller is the LCD page path.
- `DispatchLcdState` (`0xC0015DD0`) maps state 0 to reset, 1 to framebuffer
  clear, 2 to refresh-pending, 3 to non-forced refresh, 4 to the contrast/
  targeted-refresh update, and 7 to the observed test sequence. State 5 calls
  `LcdStateNoOp` (`0xC0016230`), which returns immediately. State 6 calls
  `AdvanceLcdPageCounter` (`0xC001624C`), which increments object field
  `+0x10` and wraps it to zero after `7`; the field's product meaning is not
  established. Confirmed callers use states 1/2/3 for the fatal-error display
  path, state 4 for the clamped display update, and state 7 during LCD panel
  reset. The test emits command bytes `0xAC,0,0xAE,0xA5` with waits and
  two-microsecond delays; the controller-specific product meaning of those
  commands is unresolved.

## Timers and SD/MMC

- `GetTimer0RegisterBase` at `0xC00164A8`, `GetTimer1RegisterBase` at
  `0xC00164D8`, and `GetTimer3RegisterBase` at `0xC0016538` return AM1802
  Timer0 (`0x01C20000`), Timer1 (`0x01C21000`), and Timer3 (`0x01F0D000`)
  register bases. `ConfigureTimer0SystemTick` at `0xC0019070` writes
  `PRD12 = 0x00005DBF`, `TCR = 0x80`, `TGCR = 5`, and `INTCTLSTAT = 3`.
  `InitializeTimer0SystemTick` at `0xC0025754` stores its mode byte at
  `0xC033E629`, stores the Timer0 pointer at `0xC033E62C`, and enables AINTC
  system interrupt 21 (`0x15`).
- `HandleTimer0Interrupt` acknowledges Timer0/AINTC and, when the stored mode is
  zero, runs four periodic services: the timeout record at `0xC03403B8`, the
  countdown at `0xC0340358`, the VoiceTask timer state at `0xC0340380`, and the
  GPIO pulse state in the Timer2 context at `0xC033E718`. It then polls the
  SD-card driver and drains due entries from the shared RTOS timer heap,
  invoking each timer record's direct callback function at `+0x04` with
  callback argument `+0x08`. The mode's product meaning and static timer
  payload semantics remain unresolved.
- `AdvanceTimer0TimeoutCounter` increments a timeout record and marks byte
  `+0x10` as `0xFF` after the observed thresholds: deadline `+0x04` plus 3000
  in mode 0, or plus 500 in modes 1 and 2. `DecrementTimer0Countdown` decrements
  `+0x08` only while byte `+0x11` is nonzero, clearing that byte at zero.
  `UpdateTimer0GpioPulseState` decrements context `+0x38` and, on expiry,
  updates GPIO group 3/mask `0x800` using context byte `+0x28`. The surrounding
   pulse subsystem is distinct from the 0x1C-byte panel-activity context above:
   `SetVoiceTaskTimerGpioPulsePeriodMode` (`0xC0028EB0`) operates on a separate
   larger timer state and selects
  period/code pairs `0x240/0x61` or `0x480/0xC2`; `StartVoiceTaskTimerGpioPulse`
  (`0xC0028F4C`) drives the output and arms `+0x38` for `0x0F` ticks;
  `SetVoiceTaskTimerGpioPulseState` (`0xC0028F94`) immediately drives the same
  output; and `AdvanceVoiceTaskTimerGpioPulsePhase` (`0xC0028FA0`) advances the
  phase against `+0x10`. The strongest upstream is
  `ProcessVoiceTaskTimerExpiry` (`0xC002BBA4`) selector mode 0, where the pulse
  phase is advanced beside the observed MIDI-clock stop/pulse calls. The same
  GPIO output is used by the service diagnostic transition test at
  `0xC007102C` through `0xC0016F44`. This establishes a separate timer/indicator
  and diagnostic output, but does not identify it as the LCD backlight or connect
  it to the per-part `+0x826` POWER SAVE MODE setter.
- `AdvanceVoiceTaskTimerGpioPulseByElapsed` (`0xC0029044`) applies signed elapsed
  time to the pulse phase under interrupt masking, using the period at `+0x10`,
  phase at `+0x2C`, suppression byte `+0x29`, and pulse start at period
  boundaries. `AdvanceVoiceTaskTimerGpioPulseWithPendingDelta`
  (`0xC00290F0-0xC002914B`) consumes the deferred delta/marker at `+0x30/+0x34`
  and otherwise advances the phase by one Timer0 tick. These are timer/GPIO
  pulse scheduling paths; no direct Global POWER SAVE edge is present.
 - The type-0 service worker's stage-7 diagnostic phases are now bounded. In
   `RunVoiceServiceStep` (`0xC0076060`), phases 4, 5, and 6 display the observed
   synchronization-check strings; phase 4 drives GPIO group 3 mask `0x1000`, waits,
   and reads the paired GPIO state, while phases 5 and 6 call
   `RunVoiceServiceGpioTransitionTest` (`0xC007102C`) with initial values `1` and `0`.
   That test alternates the `0x1000` drive, observes bank-7/bank-8 interrupt counters
   at context `+0x20/+0x24`, and returns timeout/error bits. This confirms a service/
   diagnostic GPIO loop and further rules it out as a proven LCD-backlight consumer.
- `AdvanceVoiceTaskTimerClock` adds `1,000,000,000` to a 64-bit clock at
  `+0x10/+0x14`, then checks and processes timer records, with a maximum of 21
  records per Timer0 tick. The time unit and timer-record event meanings remain
  unresolved. `PollSDCardDriverState` compares the driver's current state with
  byte `+0x19` and invokes the state-change path when they differ.
 - The static timer initializers are now identified: `InitializeVoiceTaskSharedTimingRecord`
   (`0xC002B864-0xC002B887`) initializes the shared timing record at `0xC0340358`
   through the common 0x14-byte record initializer, and
   `InitializeTimer0TimeoutRecordState` (`0xC002BFCC-0xC002BFEF`) initializes the
   Timer0 timeout record at `0xC03403B8`. Both are registered in the CPU C++
   initializer table at `0xC00F88E8` and `0xC00F88F4`, respectively.
 - `UpdateVoiceTaskSharedTimingRecord` (`0xC002B740-0xC002B833`) is the shared-record
   update called from the VoiceTask handler with the record at `0xC0340358`. While
   byte `+0x11` is active, it derives an inter-event elapsed sample from the
   Timer0-decremented 4000-count reference at `+0x08`, rejects samples below 150,
   clamps accepted samples to at least 200,
   and smooths the change against `+0x0C` through the signed divide helper when
   the difference is within +/-100. It advances the interpolation step at `+0x10`
   up to `0x0F`; after the first step it writes the derived value at `+0x04` using
   the observed bounded-sample calculation. Failed updates reset `+0x0C`, `+0x10`,
   and `+0x08`. The VoiceTask caller wraps a nonzero result in an 8-byte callback
   record for `DispatchVoiceTaskControlListenerNotification`, which writes the
   result to DSP/control field `+0x26` through command channel 0 before invoking
   active listeners. The timing units and consumer-level meaning of `+0x04` remain
   unresolved.
- `GetTimer2RegisterBase` at `0xC0016508` returns the Timer2 base address
  `0x01F0C000`. `ConfigureTimer2PeriodicInterrupt` at `0xC0019128` writes 1 at
  register offset `+0x04`, `PRD12 = 0x124F7` at `+0x18`, `TCR = 0x80` at
  `+0x20`, `TGCR = 5` at `+0x24`, and `INTCTLSTAT = 3` at `+0x44`.
  `InitializeTimer2PeriodicInterrupt` obtains/stores the register pointer, applies
  this configuration, and enables AINTC system interrupt 68 (`0x44`). The Timer2
  source clock and resulting interrupt frequency remain unresolved.
- `HandleTimer2Interrupt` acknowledges both Timer2 and AINTC, runs the
  periodic service chain including `ProcessTimer2CountdownState`
  (`0xC0029350`), `RefreshTimer2ContextStatusBit7` (`0xC002914C`),
  `RefreshTimer2ContextStatusBit24` (`0xC002916C`),
  `ProcessVoiceTaskRateSchedulerTick` (`0xC009B58C`), and
  `UpdateTimer2StatusIndicator` (`0xC00289F4`). It then signals RTOS object/event
  ID 6 with mask 2. `ProcessTimer2CountdownState` decrements context `+0x18`.
  On expiry, mode byte `+0x16 == 0` selects event code `0x31` plus bit `0x80`,
  or event code `0x32` plus bit `0x100`, according to selector byte `+0x17`.
  Modes 1 and 2 set both bits and write `0x31` followed by `0x32`, leaving
  `0x32` as the final observed code; modes above 2 do nothing on expiry. The
  two status refreshers read status word 3 from the context's indexed 0x28-byte
  table and extract bits `0x80` and `0x01000000`. `UpdateTimer2StatusIndicator`
  advances an enabled 18-tick phase, then cycles the red/green outputs through
  remainder-modulo-3 states during the first two phase ticks and drives both off
  for later phases, followed by GPIO0 field `0x20` update. Event and indicator
  meanings remain unresolved. The indicator gate is now bounded:
  `SetTimer2StatusIndicatorEnabled` (`0xC0028AB4`) stores its enable byte at
  `0xC00F9310`; zero disables the periodic phase service and preloads the RGB/GPIO state,
  while nonzero enables it. The shared panel/indicator path and service/error diagnostics
  call this gate, and `DisableTimer2StatusIndicator` (`0xC0028B08`) is called during
  LCD/panel hardware reinitialization. This is a Timer2 status-indicator control path;
  no evidence connects it to the Global POWER SAVE selector or LCD backlight, and the
  indicator's product meaning/polarity remain unresolved.
- `GetOrCreateSDCardDriver` (`0xC001CF0C`) lazily constructs and publishes the
  0x28-byte singleton referenced by `g_pSDCardDriver` at `0xC00F9308`.
  `ConstructSDCardDriver` (`0xC001CFDC`) binds the low-level MMC/SD controller at
  wrapper `+0x10`, GPIO registers at `+0x14`, and the card-ready result at `+0x19`;
  `InitializeSDCardDriverController` (`0xC001D164`) runs the controller start sequence.
  `HandleMmcsd0Interrupt` (`0xC0025BD0`) acknowledges system interrupt 16 and
  `HandleSDCardDriverInterrupt` (`0xC001D290`) forwards it to the low-level controller.
  `ProbeSDCardReadyState` (`0xC001DE70`) supplies the constructor's readiness byte,
  `ExecuteSDCardControllerOperation` (`0xC001DEF8`) invokes the low-level operation and
  stores its 16-byte result area, and `QuerySDCardControllerErrorState` (`0xC001D200`)
  exposes the low-level error/status result. The controller command/status codes remain
  unresolved. The low-level controller itself is a singleton `0x178`-byte object from
  `GetOrCreateSDCardController` (`0xC001DC38`); `ConstructSDCardController` (`0xC001DCAC`)
  installs its vtable, initializes mode bytes and embedded state, clears `+0x10..+0x16F`,
  sets `+0x160 = -1` and `+0x20 = 1`, stores `+0x174 = 10`, and allocates a `10 * 0x200`
  byte buffer at `+0x170`. `DestroySDCardController` (`0xC001DE50`) performs the matching
  embedded cleanup/free. Its embedded 12-byte I/O object is constructed by
  `ConstructSDCardIoState` (`0xC001AB80`); `PrepareSDCardControllerOperation`
  (`0xC001AC50`) applies the selected mode and stores the caller-provided 16-byte result-area
  pointer. The confirmed protocol-facing methods are `StartSDCardInitialization`
  (`0xC001ACA0`), `InitializeSDCardProtocol` (`0xC001AE04`),
  `InitializeSDIOCardProtocol` (`0xC001B1A0`), `ReadSDCardBlocks` (`0xC001B2E0`),
  `WriteSDCardBlocks` (`0xC001B4EC`), `GetSDCardCapacityValue` (`0xC001B6F8`),
  `GetSDCardStateFlag` (`0xC001B734`), and `QuerySDCardReadyState` (`0xC001B774`).
  The card-initialization path visibly issues CMD0, CMD8, repeated ACMD41, CMD2, CMD3, CMD9,
  CMD10, CMD7, CMD16, and ACMD6; the alternate path polls CMD5 and issues CMD3, CMD7, and
  CMD52. Block transfers validate bounds, use 0x200-byte block strides, split at 0xFFFF blocks,
  and retry the underlying transfer up to three times for error `-0x0E`. Command/status field
  meanings and the units of the capacity/state values remain unresolved. The underlying read helper
  `TransferSDCardReadBlocks` (`0xC001C120`) issues command `0x12` and consumes eight `0x40`-byte
  FIFO reads per block; the write helper `TransferSDCardWriteBlocks` (`0xC001C2C8`) issues command
  `0x19` and performs the corresponding eight FIFO writes. Both wait for the data-done condition,
  convert controller status into the shared error result, and use `StopSDCardDataTransfer`
  (`0xC001C754`) for the observed stop command. `WaitSDCardFifoReady` (`0xC001C794`) has a polling
  mode and an RTOS/event-wait mode. `PrepareSDCardReadBlockCount` (`0xC001CB7C`) and
  `PrepareSDCardWriteBlockCount` (`0xC001CB48`) program the controller for 0x200-byte blocks and
  the requested count. The readiness gate reads GPIO0 offset `+0x70`, bit `1`, through
  `CheckSDCardReadyInput` (`0xC001CAE8`); the active polarity is clear/zero.
  The AM1802 register-facing layer uses MMCSD0 base `0x01C40000`: status is read at register
  offset `+0x08`, command-busy state at `+0x0C`, timeout values at `+0x14/+0x18`, FIFO read/write
  ports at `+0x28/+0x2C`, command encoding and argument at `+0x30/+0x34`, response words at
  `+0x38..+0x44`, and the observed command-state mask is maintained at `+0x50`.
  `MMCSD_BuildCmdReg` (`0xC0017C30`) maps the confirmed command groups to controller encodings;
  `MMCSD_SendCommand` (`0xC0017820`) waits for the command-busy bit, clears response state,
  writes command/argument, optionally waits for response status, and copies eight response
  halfwords. FIFO access requires status bit `0x200` for writes and `0x400` for reads; FIFO-ready
  tests use status bits `0x600`, data completion uses bit `0x01`, and status conversion maps
  response states 1/2 to errors `-0x0D/-0x0E`.

