# MIDI, USB transport, and central message routing

> Detailed evidence extracted from the original monolithic ARCHITECTURE.md.
> Ghidra is authoritative for current symbols, types, comments, and cross-references.

- The selected service object's lifecycle is partly resolved. The shared base
  initializer at `0xC00838E0` initializes the `0x74`-byte object, clears its
  active byte at `+0x70`, and sets a pending-state marker at `+0x71` to `0xFF`.
  `0xC0083920` creates the receiver subobject at `+0x0C`, initializes embedded
  state at `+0x10`, emits common-message type `0x0B` if a pending state was
  recorded, and then sets `+0x70` active. This explains the active-byte gate in
  `ForwardCommonMessageIfActive`, but does not identify the selected object's
  higher-level subsystem.

- `ProcessMidiCentralMessage` (`0xC0026288`) consumes the first central queue.
  It accepts only records whose first byte is `7`. For second-byte class `3`,
  it recognizes subtypes `0`, `1`, `2`, `3`, and `0x11`, packing the record's
  parsed fields into a common-message type `0x16`; class `5` is packed into the
  same common-message type from its byte and 16-bit fields. Other record classes
  are ignored.
- The UART1 hardware setup is now confirmed. `UART1_Init` (`0xC00193C0`)
  disables the mode register at offset `+0x34`, writes divisor-latch values
  `DLH=1` and `DLL=0x2C` through `LCR=0x80` (divisor `0x012C`), restores
  `LCR=3`, invokes the common FIFO helper, writes the observed power-management
  value at `+0x30`, and sets `IER=5`. The UART1 register block is the AM1802
  UART1 base at `0x01D0C000`; the input clock and resulting baud rate are not
  inferred.
- `InitializeMidiUart1` (`0xC0025618`) obtains and publishes the UART1 register
  pointer, binds the transmit and receive paths, and enables AINTC system
  interrupt `53`. `HandleMidiUart1Interrupt` (`0xC0025670`) acknowledges that
  source and decodes UART IIR offset `+0x08`: cause `1` transmits one queued
  byte, causes `2` and `6` process one received byte, and cause `3` handles the
  UART status path. It allows eight causes per entry; a persistently asserted
  cause enters the observed LCD/error display path and then does not return.
- `TransmitNextMidiUart1Byte` (`0xC0025508`) dequeues from the UART1 transmit
  circular buffer, writes the byte to register offset `+0`, and clears the
  observed IER bit at offset `+0x04` when the queue becomes empty. The UART
  FIFO-control helper at `0xC00192D0` is shared by the UART0, UART1, and another
  UART initialization path; it writes `1` and then `0x0F` to the IIR/FCR
  location at offset `+0x08`.
- `ParseMidiInputByte` (`0xC0027088`) is a shared CPU MIDI-byte state machine,
  not a UART1-only routine. Its parser state includes a state byte at the
  record's `+0x0B` and a sentinel/control byte at `+0x10`; the UART1 receive
  path calls it with source selector `3`, stores record source byte `3` at
  `+0x03`, and enqueues the record only when the parser returns true. The
  routine covers channel-status classes, system-status handling, realtime
  bytes, running data states, and several device-specific multi-byte states;
  those higher-level protocol meanings are not yet assigned.
- Confirmed parser framing includes channel statuses `0x80`, `0x90`, `0xA0`,
  `0xB0`, and `0xE0` with two data bytes, `0xC0` and `0xD0` with one data byte,
  and system-exclusive entry at `0xF0`. The parser uses record bytes `+0x01`
  and `+0x02` for the first data values, `+0x04..+0x07` and `+0x08..+0x09`
  for multi-byte staging, and returns true only for selected completed or
  control records. `0xF8`, `0xFA`, `0xFB`, `0xFC`, and `0xFE` have dedicated
  realtime/control paths; their product actions remain unresolved.
- The system-exclusive state machine has confirmed byte guards for the observed
  sequences `0,1,0x24`, `0,1,0x18`, `0x7E`, `0x7F`, `0x42`, `0x22`, `0x50`,
  `0x21`, `0x78`, `0x7F`, and `0x72`. The command-byte handler at `0xC0026A8C`
  recognizes direct command cases including `0x40`, `0x41`, `0x4C`, and `0x51`;
  command `0x40` selects a lazily allocated buffer region with a `0x4000`-byte
  count limit, while `0x51` selects another region with a `0x100`-byte limit.
  A separate 0x1E8-byte control object is created for the observed finalization
  path. These buffers and commands are structurally identified, but their
  vendor/product meanings are not assigned.
- Realtime source gating is also confirmed: runtime MIDI mode 1 accepts source
  selectors 3 and 4, mode 2 accepts source 4, and mode 3 accepts source 3.
  The UART1 and USB-MIDI paths therefore share the parser while retaining
  source-specific realtime behavior.
- `ProcessMidiUart1ReceiveByte` (`0xC00252F0`) splits accepted UART1 records by
  the signed first byte: nonnegative records go to the CentralServiceTask MIDI
  queue, while negative records use `QueueMidiUart1AuxiliaryRecord`
  (`0xC0025280`) to reach the VoiceTask auxiliary queue at `0xC033E550`.
- The UART1 interrupt cause-3 path at `0xC00253B8` can also enqueue the record
  at `0xC033E5D4` to `0xC033E550`; it is reached from
  `HandleMidiUart1Interrupt` and is gated by the pending-record flag at
  `0xC033E5F8`. The periodic helper at `0xC002A818` is a third producer: when
  the timing check at `0xC0025410` expires, it initializes a 20-byte record and
  writes it to the same queue. The exact higher-level meanings of these
  status/timed records remain unresolved.
- `ProcessUsbMidiInputByte` (`0xC002C6D0`) is the USB-MIDI input callback in the
  `usbmidi/cusbmin.cpp` path. When its recognition gate is active, it collects
  six bytes and recognizes the exact prefix `F0 42 30..3F 00 01 24` (the
  firmware compares the third byte after subtracting `0x30` and bounds it to
  `0x0F`). It then calls `ParseMidiInputByte` with source selector `4` and
  stores source byte `4` in the output record at `+0x03`. Accepted records with
  a negative first byte are sent through `0xC033E4F8` (event object 1, mask 2),
  while nonnegative records use `0xC033E524` (event object 2, mask 1), both via
  the structured queue writer at `0xC0024A64`. The nonnegative path joins the
  central MIDI queue.
 - The USB-MIDI auxiliary queue consumer is now resolved.
  `DrainMidiInputQueuesToVoiceTask` (`0xC0058808`) drains up to `0x20` records
  from `0xC033E4F8` and the second queue at `0xC033E550`, passes them through
  `HandleVoiceMidiInputRecord` (`0xC0058664`) with source selectors `0` and `1`.
  The handler returns `1` when it consumes a recognized voice-input case; the
  drain loop forwards records only when it returns `0`, including signed-data
  and other unhandled status records, to `0xC033E5A8` using `0xC0024A64`. That
  destination is the VoiceTask input queue (event object 6, mask 1), consumed
  through the pointer at `0xC002B360` by VoiceTask (`0xC002B220`). The second
  source queue is also fed by the UART1 negative-record path, the UART1
  cause-3 path, and the periodic producer described above. The exact
   higher-level meaning of those additional records remains unresolved, but
   all producer-to-consumer queue edges are established.
- The paired output transport objects used by the VoiceTask/MIDI record writers
  are now partially bounded. `g_stMidiUart1TransmitQueue` (`0xC033E5FC`) is
  confirmed as the UART1 transmit circular buffer because
  `TransmitNextMidiUart1Byte` (`0xC0025508`) dequeues from it and writes each
  byte to the AM1802 UART1 data register at offset `+0`. The paired object
  `g_stUsbMidiTransportQueue` (`0xC034040C`) is constructed by
  `InitializeUsbMidiByteQueue` (`0xC002C91C`) as a 1-byte, `0x800`-entry
  circular buffer using mutex ID `4`. Its CPU-side consumer is
  `DequeueUsbMidiTransportByte` (`0xC002C908`), which is installed by
  `InitializeUsbControllerCallbacks` (`0xC00219D8`) as the USB device-controller
  transmit callback. Other CPU writers feed one or both objects with records
  ranging from one byte to longer protocol packets.
- The transport fan-out ABI is confirmed. `QueueMidiTransportByte`
  (`0xC00277D8`) and `QueueMidiTransportBytes` (`0xC0027834`) use selector `1`
  for `g_stMidiUart1TransmitQueue`, selector `2` for
  `g_stUsbMidiTransportQueue`, and other selector values for both queues.
  `QueueMidiRealtimeByte` (`0xC0027EE0`) uses the same routing and is called by
  VoiceTask timing code that emits standard MIDI realtime bytes: `F8` clock,
  `FA` start, `FB` continue, and `FC` stop. Longer generated packets pass
  through `BuildAndQueueMidiTransportPacket` (`0xC0027D84`) and the generic
  byte-sequence writer. The USB callback consumer packetizes that byte stream
  in the controller's 16 endpoint records at `controller + 0x2028`, with one
  10-byte record per endpoint. Record bytes `+0x00`, `+0x01`, and `+0x02` are
  packetizer state, assembled-byte count, and remaining payload count;
  `+0x03` retains channel running status, `+0x04` is the configured header
  prefix, `+0x05..+0x08` hold the four-byte USB-MIDI event packet, and `+0x09`
  marks a completed packet. `BeginUsbMidiEventPacket` (`0xC0021DF0`) selects
  the USB-MIDI CIN and payload length, using the status-nibble table at
  `0xC00A3FC0`; `AppendUsbMidiEventDataByte` (`0xC0022194`) fills ordinary
  channel/system packets, while `AppendUsbMidiSysExByte` (`0xC0022234`)
  emits CIN `4` for SysEx and changes the final `F7` packet to CIN `5`, `6`,
  or `7`. Completed four-byte packets are copied into the controller's
  `0x10`-entry transfer ring by `QueueUsbControllerTransferRecord`.
- The SeqTask transport transition helpers are now bounded. The static initializer
  `InitializeMidiClockStateRecord` (`0xC0025D5C-0xC0025D8B`), reached for the
  global record at `0xC033E67C` by the constructor path at `0xC0026230`, clears
  a 0x1C-byte MIDI-clock/transport state record. Its directly observed fields are
  an enable byte at `+0x04`, flags at `+0x05`, a 16-bit phase at `+0x06`, and
  transport counters/state at `+0x08`, `+0x0C`, `+0x10`, `+0x14`, and `+0x18`.
  `EnableMidiClockPulseGeneration` (`0xC0025E50`) and
  `DisableMidiClockPulseGeneration` (`0xC0025E24`) toggle flags bit 0, while
  `ResetMidiClockPhaseAndReadRate` (`0xC0025E7C`) clears the phase and returns
  the current timer-rate value. The record's static vtable is at `0xC00A44D0`;
  the vtable mechanics are identified, but its product-level class identity is
  still unresolved.
- `EmitMidiClockTransportTransition` (`0xC0025F40-0xC0025FA8`) resets that
  phase, flushes pending FC stop repeats, emits the caller's FA/FB transition,
  and emits F8 through the MIDI transport fan-out. `EmitSeqTransportStartAndAdvancePulse`
  (`0xC002C3A4-0xC002C3CF`) supplies FA and then advances the shared GPIO pulse
  context with zero elapsed input; `EmitSeqTransportContinueAndAdvancePulse`
  (`0xC002C3D8-0xC002C407`) supplies FB and advances it by the caller's elapsed
  value. Their callers are SeqTask initialization/reset and the transport-cycle
  state machine. The state high-bit guard and counter mechanics are confirmed,
  but their higher-level product meaning remains unresolved.
- The paired USB transport handoff is now established. `DequeueUsbMidiTransportByte`
  (`0xC002C908`) directly reads `g_stUsbMidiTransportQueue` (`0xC034040C`) under
  interrupt masking and returns one byte plus an availability flag. The
  `tusbmin.cpp` callback initializer at `0xC00219D8` installs it as the USB
  controller transmit callback alongside `ProcessUsbMidiInputByte`
  (`0xC002C6D0`) as the receive callback. The USB controller task iteration at
  `0xC0021214` calls `ServiceUsbControllerTransmit` (`0xC0022BA0`) once per RTOS
  tick; that routine polls the callback and feeds returned bytes into the
  endpoint/ring state machine at `0xC0022698`, which updates per-endpoint state,
  builds transfer records through `0xC002237C`, and dispatches them through
  `0xC00224BC` to the low-level USB controller routines at `0xC001FDD0` and
  `0xC001FFFC`. The `USBMidiInTask` vtable at
  `0xC00A4680` remains the separate input worker that waits on event object `4`,
  mask `1`, and processes USB receive data. The generic circular-buffer dequeue
  helper at `0xC0024D8C` still has only the confirmed UART1-TX and panel-UART0
  callers; USB-MIDI output uses its specialized callback reader instead.
- The hardware-facing USB boundary is also identified. `InitializeUsbControllerHardwareContext`
  (`0xC001FCC4`) binds controller base `0x01E00000`, the AM1802 USB register
  block, and the endpoint-state tables. It invokes `InitializeAm1802UsbController`
  (`0xC00195DC`), whose nearby source literal is `././src/MCU/Component/AM180xUSB.cpp`;
  that routine configures the controller and polls its status at context offset
  `0x460`. `WriteUsbEndpointTransferBuffer` (`0xC0019C2C`) copies variable-length
  transfer data into the endpoint-specific controller buffer used by the
  low-level transmit/control routines. Exact register-field names remain tied
  to the AM1802 documentation and are not assigned here.
- The low-level transfer split is explicit. `StartUsbEndpointTransfer`
  (`0xC001FDD0`) selects the control path for endpoint/index `0`, through
  `StartUsbControlTransfer` (`0xC00206EC`) and its `0x40`-byte chunk filler
  `FillUsbControlTransfer` (`0xC002072C`). Nonzero endpoint values use
  `StartUsbDataEndpointTransfer` (`0xC001FE48`) and
  `ServiceUsbDataEndpointTransfer` (`0xC001FEFC`), which computes available
  chunks and writes them with `WriteUsbEndpointTransferBuffer` (`0xC0019C2C`).
  The data descriptor is selected by `GetUsbEndpointDescriptor`
  (`0xC001F780`) from the controller context's one-based table at `+0x54`.
  `InitializeUsbEndpointTransferState` (`0xC001F5D0`) stores the original
  source/length at descriptor `+0x08/+0x0C` and the active cursor/remaining
  length at `+0x10/+0x14`; the service routine limits each write by descriptor
  `+0x04`. `MapUsbLogicalEndpointToHardwareEndpoint` (`0xC0019550`) maps
  logical endpoint `0` to hardware endpoint `0`, and logical endpoints `1`
  and `2` to hardware endpoint `1`; other values enter the error path.
  `FinalizeUsbEndpointTransfer` (`0xC001FFFC`) updates the endpoint completion/
  status state. This establishes the CPU-side path from the paired MIDI queue
  to the AM1802 USB controller without assigning unresolved product-level
  endpoint semantics.
- The USB setup-packet path is now bounded. `ServiceUsbControlDataTransfer`
  (`0xC0020810`) receives the control OUT data stage in chunks of at most
  `0x40` bytes, and `DispatchUsbSetupRequest` (`0xC00231E8`) records
  `bmRequestType`/`bRequest` before selecting the request handler. The initial
  eight-byte setup packet is read by the preceding control state at
  `0xC0020588`; the subsequent state at `0xC002060C` dispatches requests that
  need a device-to-host data stage through `DispatchUsbControlReadRequest`
  (`0xC00234A0`).
- The recovered device-to-host standard requests are:
  `GET_STATUS` (`0`), `GET_DESCRIPTOR` (`6`), `GET_CONFIGURATION` (`8`),
  and `GET_INTERFACE` (`10`). `HandleUsbGetDescriptorRequest`
  (`0xC00236BC`) selects device (`1`), configuration (`2`), string (`3`),
  device-qualifier (`6`), and other-speed configuration (`7`) descriptors
  from the table rooted at `0xC00A40B4`, selects the speed-specific record,
  and clamps the transfer to setup `wLength`. `GET_STATUS` returns device,
  interface, or endpoint status; the device result derives from controller
  state byte `+0x0B`, interface status is zero, and endpoint status uses the
  direction-specific endpoint-state table. `GET_CONFIGURATION` returns the
  current configuration byte at `+0x0A`, while `GET_INTERFACE` returns a zero
  alternate-setting byte.
- A class request with `bRequest == 0xFE` is handled as `GET_MAX_LUN` and
  returns one zero byte through EP0. Unsupported read requests enter the
  existing control-stall operation. The descriptor records include the
  expected USB strings (manufacturer `KORG INC.`, product `electribe2 sampler`,
  and the pad/knob variant string), confirming that this is the device's USB
  enumeration/control path.
- The no-data/status side of `DispatchUsbSetupRequest` handles standard
  `CLEAR_FEATURE` (`1`) and `SET_FEATURE` (`3`) for endpoint recipients,
  `SET_ADDRESS` (`5`), `SET_CONFIGURATION` (`9`), and `SET_INTERFACE` (`11`).
  Endpoint feature requests validate direction and endpoint-state tables;
  the recovered nonzero endpoint mapping is endpoint 1 OUT/IN, while endpoint
  zero is accepted without a nonzero-endpoint state operation. `SET_ADDRESS`
  stores the low address byte at controller state `+0x48`. `SET_INTERFACE`
  accepts only alternate setting zero for an in-range interface. Configuration
  selection accepts values `0` and `1`, stores the selected byte at `+0x0A`,
  and forwards it to the low-level controller configuration routine. The same
  configuration handler is also reached for class request `0xFF`; its
  product-level purpose is not yet resolved.
- A vendor-type control request with `bRequest == 0x22` is accepted only for
  `wValue == 1` and a two-byte data-stage signature of `0x0944` followed by
  the active descriptor record's value at `+0x1C`. The handler records state
  `0x80` or `0x81` and invokes the matching follow-up operation. This handshake
  is structurally confirmed, but its product-level meaning remains unresolved.
- The USB interrupt dispatcher is also bounded. `PollUsbControllerInterruptSources`
  (`0xC00200D0`) reads and clears the masked source register, acknowledges the
  interrupt, and maps source bits `0x1`, `0x2`, `0x200`, and `0x40000` to
  internal events 0, 1, 9, and `0x12`. These events service EP0 control work,
  logical endpoint-2 transmit completion, logical endpoint-1 receive data,
  and controller status/configuration changes respectively. EP0 processing
  separates setup reception (`ReceiveUsbSetupPacket`, `0xC0020588`), the
  device-to-host request state, OUT-data reception, and post-status address/
  configuration application. The endpoint-1 receive path advances the same
  descriptor cursor/remaining fields used by the recovered data transfer
  service; unresolved low-level callbacks are left unnamed.
 - `HandleVoiceMidiInputRecord` (`0xC0058664`) is also a confirmed producer for
  the pending VoiceTask bitmap: high-nibble class `0x9` queues a type-`0x20` or
  type-`0x30` slot event and sets its bit, class `0x8` dispatches an already-set
  bit, and class `0xB` values `0x7B..0x7E` drain a pending sub-bank. Its return
  value is derived from the signedness of the two data bytes and controls whether
  `DrainMidiInputQueuesToVoiceTask` forwards the record to the raw VoiceTask
  input queue. Product-level MIDI meanings remain unresolved.
- `ProcessPanelUartCentralMessage` (`0xC002814C`) dispatches the second central
  queue on the record byte at `+0x0C`. Confirmed mappings are: record types `0`,
  `1`, `2`, `4`, `5`, `6`, and `7` emit common-message types `1`, `5`, `0x0C`,
  `4`, `2`, `7`, and `6` respectively; type `0x80` updates panel state through
  `0xC002CA18` and emits type `0x0E`; types `0xA0` and `0xA1` update the two words
  of the shared response state at `0xC03404A0` without forwarding. Type `0xA0`
  replaces the first word and clears the second; type `0xA1` retains the first word
  and writes the second. The type-`0x80` packed value is stored
  through `StorePanelCentralType80Value` (`0xC002CA18`) via pointer slot
  `0xC002CA24`, whose initialized target is the shared backing word
  `0xC03404A8`. `GetPanelIdentityResponse80Value` (`0xC002CA28`) reaches the same
  backing word through pointer slot `0xC002CA34`; handler ID `0x1D` and the
  fatal-error diagnostic wait poll it. The A0/A1 consumers use pointer-valued
  literals at `0xC002CA50` and `0xC002CA70`, both targeting `0xC03404A0`.
  `GetExpectedPanelIdentityResponse80Value` (`0xC002CA38`) returns
  the fixed success value `0x96`. Type `5` is gated by the shared
  `PanelIdentityState`; the higher-level protocol names for these record types
  remain unresolved.

