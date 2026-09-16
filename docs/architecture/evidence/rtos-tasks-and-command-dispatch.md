# RTOS tasks and CommandTask dispatch

> Detailed evidence extracted from the original monolithic ARCHITECTURE.md.
> Ghidra is authoritative for current symbols, types, comments, and cross-references.

## RTOS task state and scheduling

- A static table at `0xC00A37A8` contains ten records of `0x20` bytes; the
  record count `10` is stored at `0xC00A38E8`. The task initialization-order
  array at `0xC00A3780` contains the task IDs 1 through 10.
- Confirmed descriptor fields are:

  | Offset | Meaning | Evidence |
  | --- | --- | --- |
  | `+0x00` | flags | bit 1 makes a task initially runnable; it is set only for the startup task |
  | `+0x04` | initial `r0` argument | copied into the synthetic initial register frame by `StartRtosTask` |
  | `+0x08` | task entry address | copied into the synthetic initial PC by `StartRtosTask` |
  | `+0x0C` | priority | its low byte is copied to task-control-block offset `+0x0D` |
  | `+0x10` | stack-region size in bytes | `main` divides it by four when sentinel-filling the region; `StartRtosTask` adds it to the base to place the initial frame |
  | `+0x14` | stack-region base address | `main` writes the stack sentinel beginning at this address |
  | `+0x18` | reserved/zero descriptor slot | zero in all ten records and not consumed by the task initialization, start, priority, or ready-queue paths examined |
  | `+0x1C` | reserved/zero descriptor slot | zero in all ten records and not consumed by the task initialization, start, priority, or ready-queue paths examined |

- The descriptor's `+0x18/+0x1C` slots must not be confused with the runtime
  task-control block (TCB) at `0xC06A24E4`. `StartRtosTask` writes the synthetic
  saved stack pointer to TCB `+0x18` and the context-restore PC `0xC0001828`
  to TCB `+0x1C`. The restore path loads `HandleRtosTaskReturn` (`0xC000066C`)
  into LR before popping the initial `r0`/PC frame. Those are runtime context
  fields, not descriptor fields.

- Task-start safety audit: `StartRtosTaskById` rejects nonzero IDs outside the
  image count (`10`) and handles ID `0` as the current task. Its ten recovered
  callsites are all in `StartupTask` and pass literal IDs (`8`, then `2..10`);
  no application path passes panel, MIDI, SD-card, or other external data into
  this API. The stack base/size values are therefore fixed image metadata. The
  function still has no generic descriptor-stack validation, so a future image
  change or database patch that corrupts those static fields would make
  `main`'s sentinel loop and `StartRtosTask`'s `base + size` calculation unsafe.

- The ten descriptors and their entry points are:

  | ID | Task | Entry | Priority | Stack base | Stack size |
  | --- | --- | --- | ---: | --- | ---: |
  | 1 | `StartupTask` | `StartupTask::taskProc` (`0xC002AB7C`) | 8 | `0xC0200000` | `0x23A8` |
  | 2 | `PeriodicTask` | `ProcessPeriodicTask` (`0xC002AA34`) | 1 | `0xC02023A8` | `0x2400` |
  | 3 | `CentralServiceTask` | `CentralServiceTask::taskProc` (`0xC002A3C0`) | 3 | `0xC02047A8` | `0x4800` |
  | 4 | `UiTask` | `UiTask::taskProc` (`0xC002B144`) | 4 | `0xC0208FA8` | `0x2400` |
  | 5 | `CommandTask` | `CommandTask::taskProc` (`0xC002A598`) | 6 | `0xC020B3A8` | `0x100000` |
  | 6 | USB device-controller worker | `ProcessUsbDeviceControllerTask` (`0xC00245F0`) | 0 | `0xC030B3A8` | `0x2400` |
  | 7 | `USBMidiInTask` | `USBMidiInTask::taskProc` (`0xC002C980`) | 0 | `0xC030D7A8` | `0x2400` |
  | 8 | `SDCardDriverTask` | `SDCardDriverTask::taskProc` (`0xC001DA9C`) | 5 | `0xC030FBA8` | `0x2400` |
| 9 | `VoiceTask` | `VoiceTask::taskProc` (`0xC002B220`) | 7 | `0xC0311FA8` | `0x2400` |
| 10 | `SeqTask` | `SeqTask::taskProc` (`0xC002AACC`) | 2 | `0xC03143A8` | `0x2400` |

- `StartupTask` is the only initially runnable descriptor. Its confirmed
  initialization sequence is described above; it starts task IDs 2 through
  10 after constructing the required subsystems.
- The `PeriodicTask` identity is supported by the source-path string
  `././src/task/PeriodicTask/CPeriodicTask.cpp` reached from its error path.
  `0xC002AA34` was a missed function boundary and is now defined and named
  `ProcessPeriodicTask` in Ghidra.
- The task at `0xC00245F0` initializes the AM1802 USB controller at peripheral
  base `0x01E00000`, reaches the source path
  `././src/MCU/Component/AM180xUSB.cpp`, and runs the controller service loop.
  It is therefore named `ProcessUsbDeviceControllerTask`; it is distinct from
  `USBMidiInTask`.
  Its allocated 0x10-byte task object is constructed by
  `ConstructUsbControllerTaskObject` (`0xC00210D4`), which installs vtable
  `0xC00A3FA0`, stores the shared hardware-context pointer at object `+0x08`,
  and stores the callback-state storage pointer at `+0x0C`.
  `InitializeUsbControllerTaskHardware` (`0xC00211CC`) passes the `+0x08`
  context to `InitializeUsbControllerHardwareContext` with mode `0`;
  vtable slot `+0x08` is the non-returning `RunUsbControllerTaskLoop`
  (`0xC00211F8`), and slot `+0x04` is the exceptional destructor path
  `DestroyUsbControllerTaskObject` (`0xC002119C`).
- The `RtosTaskDescriptor` structure has been defined in Ghidra with the field
  layout above. It has not been applied across the static table because doing
  so would replace useful existing labels at addresses inside the table. Each
  entry function is tagged `RTOS Task Entry` instead.

- `CommandTask::taskProc` uses `InitializeCommandTaskDispatcher` at
  `0xC002D988` to allocate a `0x410`-byte dispatcher state. Its embedded state
  contains 0x40 sixteen-byte command records, initialized by
  `InitializeCommandTaskSlotArray` at `0xC002D944`; each record has an active
  byte and two payload words. Separately, `InitializeCommandHandlerRegistry`
  at `0xC002D9C8` constructs the 45 handler objects indexed `0x00..0x2C` in
  `g_aCommandHandlerObjects` at `0xC03404C8`. The event/timestamp state machine
  is handler ID `0x0F`. `SendCommandHandlerMessageById` at `0xC002D8F0`
  resolves a handler ID, builds common-message type `0x11` from the child record
  rooted at handler `+0x10`, and forwards it through that handler.
  `SetCommandHandlerStatusTextAndNotify` at `0xC0038668` writes a temporary text
  object into the same child record's `+0x04` field before emitting type `0x11`.
  The handler child at `+0x14` is an eight-byte scalar object initialized to zero;
  its observed vtable supports initialization, teardown, equality comparison,
  and cloning through `0xC002D334`, `0xC002D434`, `0xC002D344`, and
  `0xC002D4A0`. The scalar's product meaning remains unresolved.
- The CommandTask execution loop is now bounded. After waking on event object 4,
  `ProcessPendingCommandRecords` (`0xC002D844`) repeatedly calls
  `DequeueCommandRecord` (`0xC003B81C`) until the dispatcher queue is empty.
  `ExecuteCommandRecordThroughHandler` (`0xC002D684`) uses record byte `+0x04`
  as an index into `g_aCommandHandlerObjects` (`0xC03404C8`), passes the two
  payload words at `+0x08/+0x0C` as temporary eight-byte message objects to the
  selected handler's vtable method at `+0x08`, and brackets execution with the
  handler methods at `+0x0C` and `+0x10`. It emits common-message state/status
  notifications afterward; `EmitCommandHandlerCompletionMessage`
  (`0xC002D238`) specifically builds message type `0x10` from the task state and
  handler state byte `+0x18`. Handler-ID and payload meanings remain unresolved.
  Handler ID `0x10` has a distinct vtable at `0xC00A7CE8`. Its operational method
  `PollSdCardCommandHandlerState` (`0xC003A14C`) polls the SD-card driver, maps the
  observed status result into handler byte `+0x18`, and on the zero-state path
  initializes a `0xB40`-byte SD-card operation object, retries its operation up to
  five times, then invokes two string/path-based fallback helpers. The exact status
  codes and path meanings remain unresolved.
  Handler ID `0x11` has a distinct vtable at `0xC00A7608`. Its operational method
  `ProcessCommandHandler11VoicePcmState` (`0xC003128C`) resets all oscillator-slot
  state, runs two staged persistence operations that return observed failure code
  `0x24`, and then calls `RebuildCommandHandler11PcmCatalog` (`0xC0031234`). Stage 0
  (`RunCommandHandler11ResourceStage0`, `0xC0030FFC`) reads a selector-`0x64` stream
  whose header begins with `SQEZ`, validates the declared extent against the shared
  `0x01000100`-byte scratch buffer at `0xC0D3A940`, expands it with
  `DecodeSqezPayload` (`0xC0034E14`) into runtime voice-assignment table mode 0, and
  persists the expanded `0x3E8000`-byte image. The confirmed SQEZ fields are magic
  at `+0x00`, serialized-input length used by stage 0 at `+0x04`, decoded-output
  extent at `+0x08`, a 16-bit CRC target at `+0x0C`, and bitstream state beginning
  at `+0x0E`; the field semantics beyond these observed uses remain unresolved. The
  decoder constructs dynamic canonical Huffman tables and emits both literal bytes and
  length/distance back-references, so SQEZ is a custom LZ/Huffman stream rather than a
  raw table image. `SqezReadDynamicHuffmanTable` first reads a serialized-entry count using
  a caller-selected width (5 bits for the 19-entry primary table, 4 bits for the 14-entry
  secondary table). Listed code lengths use a 3-bit value; prefix 7 extends through a run
  of one bits terminated by zero. The primary form inserts a 2-bit zero-length run after
  its first three lengths; unused tail entries are zero-filled. A zero serialized-entry
  count selects a uniform-table fallback. The resulting lengths feed the canonical-table
  builder with observed root widths of 8 and 12 bits. Its output checksum uses the reflected
  CRC-16 lookup table at `0xC00A7750`, with an observed initial accumulator of zero. Stage 1
  (`RunCommandHandler11ResourceStage1`, `0xC0031128`) reads a `0x100`-byte selector-`0x63`
  record into the shared CPU scratch buffer, validates its `GLDE` object marker, and
  applies that scratch image through the `0x30C`-byte VoiceTask state object. It then
  passes that `+0x04` payload from the shared `0x118`-byte object at backing pointer slot
  `0xC033E6A0` through the selector-`0x23` path. The handler's pointer literal at
  `0xC0031228` resolves to the same slot used by the shared control object and the
  selector-`0x23` writer. The intermediate `ApplyVoiceTaskStateObject324AndNotify`
  call reaches `LoadVoiceTaskControlImage`, which copies the selector-`0x63` scratch
  image into that shared object's `+0x04` payload before the write. The proven data flow
  is therefore selector `0x63` → shared object `+0x04` → selector `0x23`. The catalog stage clears the observed
  `0xA0000`-byte resource buffer,
  reads/parses flash-backed data, and calls `Pcm_RebuildRuntimeSampleCatalog`. In the
  handler-0x11 call sequence, `Pcm_LoadAndDecodeResourceData(0,0)` then loads the
  8-MiB PCM image from selector `0x80`, validates the `KORG` magic at image offset
  `+0`, the `X11100PC` or `elec2PCM` format identifier at `+4`, and the `DRUM`
  section magic reached through the header's `+0x14` offset, decodes its resource
  sections, and streams the resulting sample words to
  the BF523 through Host DMA; the subsequent selector-`0x6B` read and catalog rebuild
  operate on the persistent PCM-resource image and selector-`0x75` SLICE metadata.
  The command, SQEZ fields, and state-code meanings remain unresolved. Ghidra's
  unreachable-block warnings for Stages 0 and 1 are decompiler artifacts: each function
  writes the scratch-capacity result through a stack-local output pointer before branching
  on it, and the decompiler incorrectly treats the stack slot as the earlier zero constant.
  Handler ID `0x12` has a distinct vtable at `0xC00A7638`. Its operational method
  `PollCommandHandler12DirectoryState` (`0xC00313B8`) lazily creates a directory/
  resource scanner child whose vtable is at `0xC00A7F30`. The child scans filesystem
  entries, retries with the observed volume label `SD: KORG e2sampler electribe
  hacktribe`, filters path/flag records, and compacts a linked-record buffer bounded
  by `0x328` bytes. Handler state mapping is confirmed for child results `0` -> `0`,
  `3`/`0x0C` -> `2`, and other observed results -> `4`; the command meanings remain
  unresolved. `GetOrCreateCommandHandler12DirectoryScanner` (`0xC00610B8`) returns
  the same singleton scanner through pointer storage `0xC03405CC`; its vtable entry
  `GetCommandHandler12DirectoryRecordRange` (`0xC003CFD4`) exposes the embedded
  begin/end range used by the voice-task event recorder's indexed-value path. That
  path (`ProcessVoiceTaskEventRecorderIndexedValues`, `0xC0063C04`) iterates the
  scanner's eight-byte records and maps each record byte at `+0x04` through the
  observed three-entry classification table before appending recorder values.
  The scanner record buffer is an array of eight-byte records with a retained
  string/reference field at `+0x00` and a classification byte at `+0x04`.
  `AppendCommandHandler12DirectoryRecord` (`0xC003D3C8`) fills spare capacity or
  calls `GrowCommandHandler12DirectoryRecordBuffer` (`0xC003D2DC`) to expand the
  buffer. `CompareCommandHandler12DirectoryRecords` (`0xC003CFF8`) orders records
  by classification and then by the retained string; `SortCommandHandler12DirectoryRecords`
  (`0xC003D79C`) applies the scanner-specific recursive/heap-sort implementation.
  `ClearCommandHandler12DirectoryRecordBuffer` (`0xC003D480`) releases the retained
  fields and resets the write pointer, while the separate linked-record list rooted
  at child `+0x10` is cleared by `ClearCommandHandler12DirectoryLinkedRecords`
  (`0xC003D134`). `AppendCommandHandler12DirectoryLinkedRecord` (`0xC003D198`)
  adds a retained record to that list; `ReconcileCommandHandler12DirectoryLinkedRecords`
  (`0xC003D284`) delegates to the shared linked-list merge helper, which compares
  retained strings and removes or inserts nodes to reconcile the lists. The additional
  vtable argument roles remain unresolved. `SetCommandHandler12DirectoryScannerPath`
  (`0xC003CFF0`) assigns the scanner's retained path/context field at `+0x18` through
  the common reference-assignment helper.
  Handler ID `0x13` has a distinct vtable at `0xC00A7A28`. Its operational method
  `LoadCommandHandler13PatternSet` (`0xC0037414–0xC00375D8`) queries the filesystem
  resource, allocates a temporary `0x4100`-byte buffer, reads the resource, and
  closes it. It requires exact `KORG` and `e2sampler` fields at buffer offsets `+0`
  and `+0x10`, passes the `0x4000`-byte payload at `+0x100` to the shared
  VoiceTask transition path, and maps a zero transition result to handler state
  `0x11`; other paths produce state `0` or `4`. Its runtime path pointer is stored
  at `0xC0345A0C` and initialized to `0xC06A1BAC`; the actual filename is not
  recovered here. The separate handler-0x19 path below owns the PatternSet state
  application routine.
  Handler ID `0x14` has vtable `0xC00A75E8`; `ProcessCommandHandler14State`
  (`0xC0030D5C`) reads a child selector and dispatches observed branches for values
  `0`, `2`, `3`, and `4`, including reset/load helpers and an event notification path.
  Handler ID `0x15` has vtable `0xC00A75C8`; `LoadCommandHandler15ValidatedResource`
  (`0xC0030E90`) opens a filesystem resource and delegates to
  `ValidateCommandHandler15Resource` (`0xC003C33C`). The validator reads a resource
  larger than `0x11F`, checks payload length/alignment and the four-byte markers
  `EVST`/`EVED`, and returns observed codes `0`, `2`, `4`, `0x13`, or `0x14`.
  Nearby firmware strings include `e2sev`; the product-level meanings remain
  unresolved.
  Handler ID `0x16` has vtable `0xC00A7468`; its constructor/destructor are
  `InitializeCommandHandler16` (`0xC002DF80`) and `DestroyCommandHandler16`
  (`0xC002DFA0`). Its operation `WriteCommandHandler16AllPatternResource`
  (`0xC002DFBC–0xC002E214`) creates the exact path
  `SD:KORG/hacktribe/electribe_sampler_allpattern.e2sallpat` in this sampler
  image. On the zero-state path it writes a `0x100`-byte local header whose
  fields are exact `KORG` at `+0`, `e2sampler` at `+0x10`, word `1` at `+0x20`,
  and `0xDC` bytes of `0xFF` from `+0x24` through `+0xFF`. It then writes a
  `0x10000`-byte persistent-record block, lazily creates the observed `0x118`-
  byte resource object and `0x4274`-byte VoiceTask DSP/control object, and
  writes `0xFA` voice-assignment blocks of `0x4000` bytes from the mode table.
  Thus the generated resource span is `0x3F8100` bytes (`0x100 + 0x10000 +
  0x3E8000`). The operation maps filesystem results `3`/`0x0C` to handler
  state `2`, other open failures to state `4`, and performs the observed
  close/status cleanup. This establishes an all-pattern resource exporter;
  finer field semantics remain unresolved.
  Its shared pointers are explicit in the CPU data: the `0x118`-byte resource/header
  object storage is at `0xC033E6A0`, the `0x4274`-byte VoiceTask DSP/control backing
  storage is at `0xC033E6A4`, and the four-byte mode-persistence context storage used
  by the related handler-`0x17` path is at `0xC0340580`.

  Handler ID `0x17` has vtable `0xC00A7488`; its constructor/destructor are
  `InitializeCommandHandler17` (`0xC002E2E8`) and `DestroyCommandHandler17`
  (`0xC002E308`). Its operation `ProcessCommandHandler17ResourceState`
  (`0xC002E41C–0xC002E70C`) opens a separately configured resource, validates a `0x100`-byte
  header, reads a `0x10000`-byte block, applies that block to VoiceTask state, and
  writes it through the selector-`0x23` persistent-record path. It then reads the
  `0x3E8000`-byte mode image, persists it through selector `0x24`, and applies the
  resulting mode state to the shared `0x324`-byte VoiceTask object. The combined
  header/block extent check is `0x10100`. Observed error states are `0x11` for
  header/extent/read failures, `0x24` for persistence failure, and `4` for close
  failure. Its `0x100`-byte header identity is now resolved: offset `+0` must
  compare exactly as `KORG`, and offset `+0x10` must compare exactly as
  `e2sampler`. The checks use `CompareCpuManagedStringToCString`
  (`0xC00A2034`), whose zero result requires both content and length to match;
  this is not a prefix-only test. The payload/resource path semantics and
  command-level meaning remain partially unresolved. The configured resource
  path is held through a runtime object at `0xC06A1BAC`, outside the initialized
  memory currently loaded in the Ghidra program, so its filename is not inferred.
  The selector-`0x23` write uses the shared four-byte context at `0xC0340584`, while
  the selector-`0x24` image write uses the separate mode-persistence context at
  `0xC0340580`; the final apply uses the handler-`0x17` `0x324`-byte state storage
  at `0xC034029C`.
  Handler ID `0x18` has vtable `0xC00A7AF8`; its full constructor is
  `InitializeCommandHandler18` (`0xC0038C64`), its vtable constructor/destructor
  targets are `0xC0038C28`/`0xC0038C48`, and its operation is
  `ResetAndInitializeLcdPanelHardware` (`0xC0038A54`). The operation emits common
  message types `0x10` and `0x09`, lazily constructs the 0x28-byte panel-identity
  state, obtains the AM1802 GPIO register block, configures the observed GPIO path,
  drives the LCD red/green/blue pins low, dispatches LCD state `(7,0)`, and toggles
  the LCD reset and GPIO7P14 pins with 100 ms delays. It stores zero in handler
   state byte `+0x18`. `RequestLcdPanelHardwareReset` (`0xC0028C18`) is the
   confirmed zero-payload CommandTask trigger for handler ID `0x18`; the battery
   monitor's deepest state-0 branch is one confirmed caller, alongside a periodic
   recovery countdown path. The periodic object reuses the singleton 0x1C-byte
   `g_pPanelActivityContext` (`0xC033E6B4`), obtained through
   `GetOrCreateVoiceTaskPanelActivityContext` (`0xC00269F0`) and constructed by
   `ConstructVoiceTaskPanelActivityContext` (`0xC0028B7C`); its `+0x04` field is the
   GPIO0 register pointer and its `+0x08` field points to the shared 0x118-byte state
   child. Startup calls `InitializeVoiceTaskGpioInputAndAutoPowerOffCountdown`
   (`0xC0028D80`), which samples the GPIO input and sets context `+0x18` to
   `0x006DDD00` when control field `+0x25` (`AUTO POWER OFF`) is nonzero, or `-1`
   when disabled. Each `ProcessPeriodicServiceTick` (`0xC002A818-0xC002A8A3`) calls
  `UpdateVoiceTaskGpioInputAndResetCountdown` (`0xC0028C58`) and
  `DecrementVoiceTaskAutoPowerOffCountdown` (`0xC0028C30`); expiry of either
   countdown enqueues handler `0x18`. The GPIO sample is the active-low state of
   register offset `+0x98` (`GPIO_IN_DATA67`) bit 31 through
   `ReadActiveLowGpio67Bit31` (`0xC00172D0`), and a state change emits common
   message type `1`/code `0x23`; its board-level signal identity remains unresolved.
   The direct `AUTO POWER OFF` editor (`0xC007A820`) and its deferred/control-state
   callers write shared field `+0x25` and issue command `0x34`, but no recovered
   direct call from those paths invokes `0xC0028D80` or otherwise reloads context
  `+0x18`. A separate `ReloadVoiceTaskAutoPowerOffCountdownFromControl`
  (`0xC0028D58-0xC0028D7B`) performs that same field-`+0x25` to `+0x18` reload and
  is reached from a shared-state update path and a resource reconciliation path,
  but no direct Global selector-editor edge to it was recovered. Therefore the
  active-countdown reload behavior immediately after a runtime setting edit remains
  unproven; the confirmed startup and non-selector reload paths are documented above.
  The alternate StartupTask panel-identity/variant fallback instead calls
  `InitializeVoiceTaskGpioInputCountdownOnly` (`0xC0028BF0`), which initializes
  only context `+0x10`/`+0x14` and leaves `+0x18` untouched. Thus the recovered
  fallback path does not enable the `AUTO POWER OFF` countdown; this is a
  call-graph observation, while the product-level variant policy remains unresolved.
  Handler ID `0x19` installs a secondary vtable beginning at `0xC00A7A48`; its full
  constructor is `InitializeCommandHandler19` (`0xC0037804`), the vtable lifecycle
  targets are base destructor `DestroyCommandHandler19Base` (`0xC00379C0`) and
  `DestroyCommandHandler19` (`0xC0037A2C`), and its operation is
  `ProcessCommandHandler19PatternSetState` (`0xC0037F78`). The operation chains two
  status helpers and then calls `ApplyCommandHandler19PatternSetState` (`0xC0037A48`).
  That routine uses the literal `PatternSet`, iterates the observed voice-state
  range, grows two dynamic record arrays in `0x300`-byte blocks, updates associated
  resource records, and emits the observed change notification when enabled. When
  the tracked association set changes and the export flag is enabled, it also
  constructs and serializes an Ableton project container. The exact PatternSet
  record fields and file-level format remain unresolved.
  Within that operation, `PrepareVoiceAssignmentModeTransitionBuffer`
  (`0xC00378F0`) snapshots the current `0x4000`-byte mode block into handler offset
  `+0x44`; `ApplyVoiceAssignmentModeTransition` (`0xC003796C`) resolves and applies
  a selected runtime mode block through the shared `0x324`-byte VoiceTask state,
  refreshes the SeqTask tick quantum, and delays by `1000` units. The paired
  `FinalizeVoiceAssignmentModeTransition` (`0xC0037930`) applies and frees the
  temporary buffer, with an observed RTOS ready-queue/timer-heap branch. The exact
  command-level meaning of these transitions remains unresolved.
  Handler ID `0x1A` has vtable `0xC00A7588`; its constructor is
  `InitializeCommandHandler1A` (`0xC002F9A4`), its base/deleting destructors are
  `DestroyCommandHandler1ABase` (`0xC002FD38`) and `DestroyCommandHandler1A`
  (`0xC002FDB0`), and its operation is `ProcessCommandHandler1AState`
  (`0xC0030630`). The operation chains the two shared status helpers and invokes
  `ApplyCommandHandler1AState` (`0xC0030060`). That routine derives a temporary
  name using the embedded literal `Chain_From_`, resets and grows two dynamic
  record collections, iterates the observed VoiceTask state entries, invokes the
  shared record-processing path, and emits the observed change notification when
  enabled. The collection and command meanings remain unresolved.
  Handler ID `0x1B` has vtable `0xC00A7978`; its constructor is
  `InitializeCommandHandler1B` (`0xC0036AE8`), its base/deleting destructors are
  `DestroyCommandHandler1BBase` (`0xC0036AAC`) and `DestroyCommandHandler1B`
  (`0xC0036ACC`), and its operation is `LoadDefaultPatternSetIntoVoiceTask`
  (`0xC0036A0C`). The operation copies the embedded `0x4000`-byte `PTST` block at
  `0xC00CFF58` into a temporary buffer, initializes sixteen groups of sixty-four
  records with the observed default bytes `0x48` and `0x60`, and applies the buffer
  through the shared `0x324`-byte VoiceTask state object. A failed application
  produces handler state `0x24`; success produces state `0`.
  `InitializeDefaultPatternSetBuffer` (`0xC0036BDC-0xC0036BE7`) installs vtable
  `0xC00A7998` on the temporary four-byte buffer object. Its base/deleting destructor
  entries are `DestroyDefaultPatternSetBufferBase` (`0xC0036BAC`) and
  `DestroyDefaultPatternSetBuffer` (`0xC0036BBC`); both the handler-0x1B path and the
  mode-image fallback path release the temporary object through the deleting entry.
  Handler ID `0x1C` has vtable `0xC00A7DA8`; its constructor is
  `InitializeCommandHandler1C` (`0xC003B0A8`), its base/deleting destructors are
  `DestroyCommandHandler1CBase` (`0xC003B06C`) and `DestroyCommandHandler1C`
  (`0xC003B08C`), and its operation is `SyncPanelA0A1RecordToFlash`
  (`0xC003B1E8`). The operation reads an eight-byte record from serial flash, queues
  a panel-UART request beginning with `0xA0` through `RequestPanelA0RecordAndWait`
  (`0xC003B15C`), obtains the updated two-word A0/A1 response pair, and writes the
  eight-byte record back. The response pair at `0xC03404A0` is polled every 10 ms for
  up to 1000 iterations; timeout returns `0x19`. Observed handler states include
  `0`, `0x19`, and `0x24`; the record's product-level meaning remains unresolved.
  Handler ID `0x1D` has vtable `0xC00A7DE8`; its constructor is
  `InitializeCommandHandler1D` (`0xC003B660`), its base/deleting destructors are
  `DestroyCommandHandler1DBase` (`0xC003B5AC`) and `DestroyCommandHandler1D`
  (`0xC003B5CC`), and its operation is
  `SendPanelIdentityHandshakeAndWaitForResponse` (`0xC003B514`). The operation
  lazily creates an 8-byte child state, queues a five-byte panel request beginning
  with `0x80` through the panel UART0 transmit queue, and polls the shared packed
  word at `0xC03404A8` every 10 ms for up to 100 iterations. That word is written
  by the CentralServiceTask panel record type `0x80` path. Response `0x96` succeeds;
  another nonzero response stores handler state `0x1C`; timeout stores `0x1D`.
  The vendor-level command meaning remains unresolved.
  Handler ID `0x1E` has vtable `0xC00A7D88`; its constructor is
  `InitializeCommandHandler1E` (`0xC003AFAC`), its base/deleting destructors are
  `DestroyCommandHandler1EBase` (`0xC003AE98`) and `DestroyCommandHandler1E`
  (`0xC003AEB8`), and its operation is
  `ProcessCommandHandler1EVoiceTaskState` (`0xC003AED4`). The operation lazily
  initializes the shared `0x4368`-byte state object at `0xC03405D0`, invokes
  `ProcessVoiceTaskExtendedStateTransition` (`0xC0090128`), and invokes the observed
  RTOS wait/scheduling helper with argument `1000`. The dispatcher selects handlers
  from state field `+0x308`, then sets that field to `8`, notifies registered listeners
  on successful processing, and marks its ready byte. The operation returns `0` on
  dispatcher success and `0x1B` on failure; the numeric states, wait units, and
  product-level command meaning remain unresolved.
  Handler ID `0x1F` has vtable `0xC00A7B38`; its constructor is
  `InitializeCommandHandler1F` (`0xC0039238`), its base/deleting destructors are
  `DestroyCommandHandler1FBase` (`0xC0038F2C`) and `DestroyCommandHandler1F`
  (`0xC0038F4C`), and its operation is
  `ProcessCommandHandler1FPcmResource` (`0xC0038D34`). The operation clears handler
  state byte `+0x18`, builds a temporary `0x124`-byte resource context from the
  command payload, checks the resource-service predicate, and on success invokes
  `ProcessPcmResourceData` (`0xC00364F0`). That shared routine reads an observed
  `0x1000`-byte resource block, walks resource entries, and updates the shared
  resource-record registry; the file format and command-level meaning remain
  unresolved.
  Handler ID `0x20` has vtable `0xC00A7B18`; its constructor is
  `InitializeCommandHandler20` (`0xC0039264`), its base/deleting destructors are
  `DestroyCommandHandler20Base` (`0xC0038F68`) and `DestroyCommandHandler20`
  (`0xC0038F88`), and its operation is
  `ExportCommandHandler20PcmResource` (`0xC0039514`). The operation obtains a
  32-bit PCM/resource value from its temporary context, masks it to a 16-bit oscillator
  ID, and calls `Pcm_ExportResourceToWaveEsliRecord` with the shared `0x494`-byte
  output record at `0xC0345A2C`, output DSP start/length locals, and slice-extent
  handling disabled. It stores the boolean result at `0xC0345A20`, releases the
  temporary service value, and returns zero. The command-level trigger remains
  unresolved.
  Handler ID `0x21` has vtable `0xC00A7C38`; its constructor is
  `InitializeCommandHandler21` (`0xC0039284`), its base/deleting destructors are
  `DestroyCommandHandler21Base` (`0xC0038FA4`) and `DestroyCommandHandler21`
  (`0xC0038FC4`), and its operation is
  `FinalizeCommandHandler21PcmWaveEsliEdit` (`0xC0039420`). When the shared export
  result flag at `0xC0345A20` is set, it commits the `0x494`-byte record at
  `0xC0345A2C` through `Pcm_CommitEditedWaveEsliRecord` and clears that flag. It
  then checks and clears the pending PCM sample-edit flag at `0xC0345A28`, runs the
  observed cleanup path when set, refreshes shared PCM/VoiceTask state, and returns
  zero. The command trigger and pending-edit cleanup semantics remain unresolved.
  Handler ID `0x22` has vtable `0xC00A7B58`; its constructor is
  `InitializeCommandHandler22` (`0xC00392A4`), its base/deleting destructors are
  `DestroyCommandHandler22Base` (`0xC0038FE0`) and `DestroyCommandHandler22`
  (`0xC0039000`), and its operation is
  `ProcessCommandHandler22PcmResourceEvent` (`0xC0038D80`). The operation initializes
  handler state byte `+0x18` to `0x24`, receives service message type `0x2E`, extracts
  the linked resource index, and branches between resource-specific oscillator refresh,
  all-oscillator refresh, and runtime PCM-catalog rebuild paths. Successful service
  results replace the handler state; the command-level trigger and service predicates
  remain unresolved. The secondary table at `0xC00A7C58` belongs to handler ID `0x29`,
  documented below.
  Handler ID `0x23` has vtable `0xC00A7CC8`; its constructor is
  `InitializeCommandHandler23` (`0xC00398A0`), its base/deleting destructors are
  `DestroyCommandHandler23Base` (`0xC0039864`) and `DestroyCommandHandler23`
  (`0xC0039884`), and its operation is
  `ExportCommandHandler23PcmWaveEsli` (`0xC003A108`). The operation reads the linked
  command record's resource value at offset `+4`, exports one selected 16-bit resource
  through `ExportOnePcmResourceToWaveEsli` (`0xC0039CC4`), or selects the all-resource
  path `ExportAllPcmResourcesToWaveEsli` (`0xC0039E68`) when that value is negative. The
  single-resource path allocates a `0x494`-byte Wave/ESLI record, calls
  `Pcm_ExportResourceToWaveEsliRecord` with slice-extent handling enabled, builds a sample
  filename, and writes RIFF/WAVE/ESLI output. The all-resource path enumerates IDs
  `0..0x3E6`, maintains a `0x1000`-byte offset table, writes each available resource, and
  reports progress. Exact output-container naming and command trigger remain unresolved.
  Handler ID `0x24` installs a secondary vtable at `0xC00A7B78`; its constructor is
  `InitializeCommandHandler24` (`0xC00392D0`), its base/deleting destructors are
  `DestroyCommandHandler24Base` (`0xC003901C`) and `DestroyCommandHandler24`
  (`0xC003903C`), and its operation is
  `ProcessPcmResourceOperationCompletion` (`0xC0039588`). The operation wraps the
  completion payload in the shared PCM-resource context, resolves its runtime resource
  index, obtains the PCM operation result, stores that result at handler offset `+0x18`,
  refreshes voices mapped to the completed resource, and updates the related CPU resource
  service state. The completion-message trigger remains unresolved.
  Handler ID `0x25` has vtable `0xC00A7B98`; its constructor is
  `InitializeCommandHandler25` (`0xC00392FC`), its base/deleting destructors are
  `DestroyCommandHandler25Base` (`0xC00390D0`) and `DestroyCommandHandler25`
  (`0xC00390F0`), and its operation is
  `CommitCommandHandler25PcmSampleEdit` (`0xC0038E8C`). The operation initializes
  handler state `+0x18` to `0x24`, checks `g_bPcmSampleEditPending` at `0xC0345A28`,
  advances the observed PCM edit sequence, and calls `CommitCurrentPcmSampleEditState`.
  It returns state `0` after the pending edit is committed; with no pending edit, the
  `0x24` status remains. The command trigger and exact edit-sequence ownership remain
  unresolved.
  Handler ID `0x26` has vtable `0xC00A7C78`; its constructor is
  `InitializeCommandHandler26` (`0xC0039328`), its base/deleting destructors are
  `DestroyCommandHandler26Base` (`0xC0039058`) and `DestroyCommandHandler26`
  (`0xC0039078`), and its operation is
  `ProcessCommandHandler26PcmResourceExport` (`0xC00396D8`). The operation resolves a
  resource ID from the shared PCM context, calls `Pcm_ExportResourceToWaveEsliRecord`
  with slice-extent handling disabled, writes the shared `0x494`-byte record at
  `0xC0345A2C`, and stores the boolean result at `0xC0345A20`. It then checks the
  observed PCM-resource synchronization result, stores handler status `0` or `0x24`,
  refreshes resource-service state, lazily creates the shared `0x4368`-byte VoiceTask
  extended state, and drives that state to selector `8`. The product-level command
  meaning remains unresolved.
  Handler ID `0x27` has vtable `0xC00A7BB8`; its constructor is
  `InitializeCommandHandler27` (`0xC0039380`), its base/deleting destructors are
  `DestroyCommandHandler27Base` (`0xC0039094`) and `DestroyCommandHandler27`
  (`0xC00390B4`), and its operation is
  `PrepareCommandHandler27PcmSampleEdit` (`0xC00395E4`). The operation resolves the
  PCM resource ID, initializes handler state `0x1F`, and invokes
  `CapturePcmSampleFromDspForEdit` (`0xC0050208`), which exports the current sample
  metadata, prepares the editor slice state through `Pcm_PrepareSampleEditorState`
  (`0xC0050094`), and reads only mono DSP sample payload through Host-DMA. State `0x1E`
  indicates the edit-mode predicate failed; successful capture sets `g_bPcmSampleEditPending` at
  `0xC0345A28`, advances the edit sequence, notifies VoiceTask DSP control field `0x2A`,
  and returns state `0`; failed capture leaves state `0x1F`. The product-level command
  meaning remains unresolved.
  Handler ID `0x28` has vtable `0xC00A7C98`; its constructor is
  `InitializeCommandHandler28` (`0xC00393A0`), its base/deleting destructors are
  `DestroyCommandHandler28Base` (`0xC003910C`) and `DestroyCommandHandler28`
  (`0xC003912C`), and its operation is `ProcessCommandHandler28NoOp`
  (`0xC0038D24`). The operation returns `0` unconditionally with no observed side
  effects; its product-level purpose remains unresolved.
  Handler ID `0x29` has a secondary vtable at `0xC00A7C58`; its constructor is
  `InitializeCommandHandler29` (`0xC00393C0`), its base/deleting destructors are
  `DestroyCommandHandler29Base` (`0xC0039184`) and `DestroyCommandHandler29`
  (`0xC00391A4`), and its operation is
  `CommitCommandHandler29PcmSampleEdit` (`0xC0038EDC`). The operation initializes
  handler state `+0x18` to `0x24`, checks `g_bPcmSampleEditPending` at `0xC0345A28`,
  calls `CommitCurrentPcmSampleEditState` when an edit is pending, and returns state `0`
  after that commit. With no pending edit, the `0x24` status remains.
  Handler ID `0x2A` uses the same vtable `0xC00A7B98` and operation
  `CommitCommandHandler25PcmSampleEdit` (`0xC0038E8C`) as handler ID `0x25`. Its registry
  constructor is `InitializeCommandHandler2A` (`0xC0039354`), which also sets the first
  child scalar to `1`; the shared vtable ownership and product-level distinction between
  IDs `0x25` and `0x2A` remain unresolved.
  Handler ID `0x2B` has vtable `0xC00A7C18`; its constructor is
  `InitializeCommandHandler2B` (`0xC00393E0`), its base/deleting destructors are
  `DestroyCommandHandler2BBase` (`0xC00391C0`) and `DestroyCommandHandler2B`
  (`0xC00391E0`), and its operation is
  `EmitSampleSaveNewSampleCommandLog` (`0xC0038F14`). The operation writes the observed
  firmware string `Sample Save New Sample Command I` through the CPU output/log writer
  and returns zero; its relationship to the product command remains unresolved.
  Handler ID `0x2C` has vtable `0xC00A7BF8`; its constructor is
  `InitializeCommandHandler2C` (`0xC0039400`), its base/deleting destructors are
  `DestroyCommandHandler2CBase` (`0xC00391FC`) and `DestroyCommandHandler2C`
  (`0xC003921C`), and its operation is
  `ResetCommandHandler2CPcmResource` (`0xC00396A0`). The operation resolves a PCM
  resource ID and invokes `ResetPcmRuntimeResourceState` (`0xC00359E0`), which clears the
  resource's 64 runtime slice records and associated flags and resets current PCM edit
  selection state. The operation's product-level command meaning remains unresolved.
  The event/timestamp handler's observed status strings include `Wait Signal`,
  `Receiving`, and `Analyzing`; the remaining handler and message meanings are
  unresolved.

