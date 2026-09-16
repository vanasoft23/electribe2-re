# VoiceTask control, service objects, and common messages

> Detailed evidence extracted from the original monolithic ARCHITECTURE.md.
> Ghidra is authoritative for current symbols, types, comments, and cross-references.

  immediately above the central dispatcher. It lazily creates a 0x338-byte dispatch
  object, a separate 0x324-byte control-state object, and a small published pointer
  record before forwarding the control event. The control-state constructor is
  `InitializeVoiceTaskControlStateObject324` (`0xC004CF90`), with singleton access
  through `GetOrCreateVoiceTaskControlStateObject324` (`0xC0088830`). This object is
  distinct from the reusable 0x324-byte state initialized by
  `InitializeVoiceTaskStateObject324` (`0xC0079828`).
 - `ApplyVoiceTaskParameterCode` (`0xC008EF20`) maps parameter codes `0x2D..0x3F`
   to existing indexed state setters and then dispatches active callback descriptors.
   Parameter code `0x3D` specifically re-applies shared-control byte `+0x29` through
   `SetVoiceTaskControlField29AndApplyDsp33`, matching the deferred/replay form of the
   Global POWER SAVE MODE update.
  `ResetVoiceTaskSharedStateObject` (`0xC00475CC`) handles the related reset-byte
  path, lazily constructing the reusable 0x324-byte state and clearing its `+0x31C`
  word when the supplied state byte is zero. Product-level parameter meanings remain
  unresolved.
- The parameter setter family confirms the control-object byte layout at offsets
  `+0x14..+0x2F` without yet assigning product names. The database records the
  field-offset names and the confirmed DSP command mapping: `+0x15 -> 0x2D`,
  `+0x18 -> 0x2E`, `+0x1C -> 0x2F`, `+0x1E -> 0x30`, `+0x2C -> 0x31`,
  `+0x2D -> 0x32`, `+0x29 -> 0x33`, `+0x25 -> 0x34`, `+0x2A -> 0x35`,
  `+0x22 -> 0x36`, `+0x28 -> 0x37`, `+0x2E -> 0x38`, `+0x2F -> 0x39`,
  and `+0x16 -> 0x3A`. Field `+0x21`
  dispatches pending linked records before storing; fields `+0x2E` and `+0x2F`
  invoke an auxiliary transition helper on change; field `+0x28` performs an
  additional service/callback sequence when cleared. The exact parameter meanings
  remain unresolved.
 - The voice-side PCM playback parameter path is now traced. `Voice_IsPcmOscillatorResourceLoaded`
   (`0xC007DEAC`) resolves the oscillator selector through the PCM catalog and gates
   the path on runtime sample `bLoadState == 1`. `Voice_UpdatePcmStartPointParameter`
   (`0xC007F448`), `Voice_UpdatePcmEndPointParameter` (`0xC007F53C`), and
   `Voice_UpdatePcmLoopPointParameter` (`0xC007F630`) consume the shared parameter
   value, call the corresponding playback-point mutator, refresh all 16 voice slots
   for the oscillator, and notify listener records with event types 3, 4, and 5.
   Their control-object event records use `0x40`, `0x41`, and `0x42`, respectively.
 - The remaining voice-side PCM controls are also identified. `Voice_GetPcmStartPointParameter`
   (`0xC007E0F4`), `Voice_GetPcmEndPointParameter` (`0xC007E14C`), and
   `Voice_GetPcmLoopPointParameter` (`0xC007E1A4`) read the normalized playback values
   through the same mutators with a zero delta. `Voice_GetPcmSampleTuneParameter`
   (`0xC007E1FC`) reads runtime sample-record halfword `+0x14` as signed fixed-point and
   returns its high byte, the sample-tune field at `+0x15`; the setter
   `Voice_UpdatePcmSampleTuneParameter` (`0xC007F980`) writes the incoming value shifted
   left by eight and emits control event `0x43`. `Voice_UpdatePcmPlayLevelParameter`
   (`0xC007F8A8`) updates runtime byte `+0x0A` (`bPlayLevel`) and emits event `0x44`
   when it changes. These offsets agree with the existing ELSI layout in
   `imhex/e2ssample.hexpat`.
   - The voice-side sampling controls are now tied to `g_pVoiceTaskSharedContext`
     at `0xC0345A08`, lazily allocated by `GetOrCreateVoiceTaskSharedContext`
     (`0xC0035AD8`) and initialized by `InitializeVoiceTaskSharedContext`
     (`0xC007E59C`, allocation size `0x4764`). This same context is shared by
     the PCM resource/edit paths and broader VoiceTask services.
    `Voice_SetSamplingMode` (`0xC006B3FC`) stores a boolean at context `+0x704`, and
    `Voice_SetSamplingSource` (`0xC006B440`) stores a boolean at `+0x708`; the UI path
    labels these values “Sampling Mode” and “Sampling Source” and emits listener events
    0 and 1 when they change. `Voice_GetAvailablePcmSamplingSeconds` (`0xC007DE80`)
    computes `(available_storage_bytes / 2) / 48000`, halving it again when sampling
    mode is enabled. `Voice_UpdateSamplingStatusDisplay` (`0xC008C600`) exposes these
    values alongside the sampling/memory status strings. `Voice_BeginPcmSampleDspLoad`
    sends them as the two middle payload halfwords of CPU-DSP command `0x3B`; the
    completed-load path later sends the phase-0 all-zero form before installing the
    runtime record, consuming the same values as stereo/width (`+0x704`) and
    play-level/source (`+0x708`). In the CPU runtime-install path, `+0x704 == 1`
    selects the four-byte sample width and runtime stereo-pair role one, while `+0x708`
    is stored as runtime `bPlayLevel` at `+0x0A`; the UI/source label and that runtime
    field's product meaning are not equated beyond this data flow. The DSP-side register
    interpretation remains unresolved.
  - `InitializeVoiceSamplingControlObject` (`0xC006B694`) constructs the sampling-control
    object and its two listener-backed child records. `Voice_HandleSamplingCommand0x2B`
    (`0xC006B4FC`) is the observed completion/reset command: it refreshes the sampling
    status, clears the voice state-machine value, and forwards the listener callbacks.
    The child records are initialized by `0xC008B424` and `0xC008C468`; their generic
    service fields and serialized descriptors remain unresolved.
  - `Voice_ProcessPcmSamplingControlEvent` (`0xC006F638`) is the registered sampling
    callback. With its apply gate set, event `0` checks CPU PCM capacity and emits the
    observed ready/error notifications, event `1` invokes `Voice_ProcessPcmSampleLoadState`
    for the phase-0 completion path, event `2` advances the voice sampling state machine
    and reaches `Voice_BeginPcmSampleDspLoad`, and event `3` handles the observed stop/reset
    selector path. `Voice_StartPcmSampleDspLoadIfSourceEnabled` (`0xC0082FBC`) is the shared
    helper used by the event dispatcher and timing-control paths; it only starts phase 1
    when context `+0x708 == 1`. The callback uses a distinct lazily-created `0x314`-byte
    0x314-byte VoiceTask state object from `GetOrCreateVoiceTaskStateObject314`
    (`0xC0030D28`), initialized by `InitializeVoiceTaskStateObject314` (`0xC0082848`); its
    state is at `+0x308`, and its listener records occupy the remainder of the object. Direct
    callers show that this object is shared by multiple VoiceTask control paths, with PCM
    sampling as one confirmed consumer. The shared setter
     `SetVoiceTaskStateObject314AndNotify` (`0xC0082A20`) applies the state subject to `+0x30E`,
     performs the observed side effects for states 0, 4, and 9, and notifies active listeners.
     The shared helper `SetVoiceTaskAssignmentControlEnabled` (`0xC005D918`) is a
     boolean-controlled assignment gate used by this state machine and the CPU-side
     slot-assignment layer. Enabling it can allocate special key-`0x11` records for
     subkeys `0x13`, `0x0F`, and `0x10`; disabling it clears all 24 CPU-side
     `0x24`-byte assignment records. The controlled product feature remains unresolved.
     Its companion state setter `SetVoiceTaskAssignmentControlState` (`0xC005C57C`)
     writes `0` or `3` to `g_voiceTaskAssignmentControlState` (`0xC068FC34`). The
     enable byte is `g_bVoiceTaskAssignmentControlEnabled` (`0xC06900A4`), and the
     associated control-object pointer is `g_pVoiceTaskAssignmentControlObject`
     (`0xC03404B4`); the separate marker byte touched during enable remains unnamed.
     `ResetVoiceTaskStateAndQueueCommand14` (`0xC0083C8C`) is a separate reset
     helper: it sets this shared state to 0, signals the observed control event,
     emits common-message types 8 and 9 with payloads `(0x0B,5)` and `(0x1B,0x12)`,
     and queues command-task record `0x14` with operation/value `(2,0)`.
     Its state-control callback `ProcessVoiceTaskStateControlEvent` (`0xC006F06C`) ignores
    states 6 and 7 or an active `+0x30E` gate, dispatches callback values 0, 1, and 2 to
    separate state-action helpers, and then notifies the same listeners. The action helpers
    implement the observed transitions among states 0..4, update `+0x30C`/`+0x311`, and
    invoke the shared transport-reset/bookkeeping paths; their numeric meanings remain
    unresolved.
    Event 2 additionally uses `Voice_ProcessPcmSamplingType40Transition` (`0xC006F59C`):
    state `0x0C` plus callback value one allocates/refreshes type-0x40 event `0x3C`, while
    state `0x0D` plus value zero returns to `0x0C` and dispatches that event. Numeric state,
    event, and message meanings remain unresolved.
  - The adjacent VoiceTask command-event method `ProcessVoiceTaskCommandEvent121415`
    (`0xC0063D34`) handles IDs `0x12`, `0x14`, and `0x15`: ID `0x12` rebuilds indexed child
    payloads and returns local state to 8, ID `0x15` enters local state 9 while setting shared
    state 8, and ID `0x14` advances or clears local/shared state according to its arguments.
    `ProcessVoiceTaskCommand14Completion` (`0xC0063320`) is the observed callback form that
    runs the PCM load-state processor, applies shared state 0, clears `+0x30F`, and dispatches
    command-task `0x14` event 2. Product-level command meanings remain unresolved.
  - `InitializeVoiceTaskEventRecorderObject` (`0xC0064008`) constructs the object containing the
    literal `EVENT_RECORDER`, installs `VoiceTaskEventRecorderVtable` (`0xC00E3368`), creates
    the observed event child/service records, and registers the object with both the shared
    0x314-byte VoiceTask state and a separate 0xB40-byte service object. Confirmed table entries
    include `ProcessVoiceTaskEventRecorderState` (`0xC0063F04`),
    `ProcessVoiceTaskEventRecorderDelta` (`0xC0063210`), and
    `ProcessVoiceTaskCommandEvent121415` (`0xC0063D34`); the remaining entries are no-ops
    or unresolved callbacks. `RebuildVoiceTaskEventRecorderStatePayloads` (`0xC0063378`)
    is the shared local-state payload rebuild used by these methods. Additional entries now
    bounded are `ProcessVoiceTaskEventRecorderAdvance` (`0xC0063B24`), which reaches the PCM
    phase-0 load processor when local state is 6 and shared state is 8,
    `ProcessVoiceTaskEventRecorderEvent2` (`0xC0063278`), which emits the observed command-task
    0x14 state forms, and transition helpers `AdvanceVoiceTaskEventRecorderStateA`
    (`0xC00639A8`) and `AdvanceVoiceTaskEventRecorderStateB` (`0xC00638FC`). The paired
    release/free functions are `ReleaseVoiceTaskEventRecorderContents` (`0xC0063BA4`) and
     `DestroyVoiceTaskEventRecorderObject` (`0xC0063BE8`). `ApplyVoiceTaskEventRecorderStateTransition`
     (`0xC0063AF0-0xC0063B23`) enters local state 9 and shared state 8, then applies the recorder's
     local-state branches and child/PCM/command side effects. `ProcessVoiceTaskEventRecorderIndexedValues`
     (`0xC0063C04-0xC0063D27`) obtains the command-handler-0x12 directory scanner, iterates its
     eight-byte record range, maps each record byte at `+0x04` through the observed three-entry table,
     appends the resulting values to the recorder child, clears the auxiliary indexed-value fields,
     queues derived values, and returns the recorder to local state 8 before rebuilding payloads.
     `ProcessVoiceTaskEventRecorderDirectoryCommand` (`0xC0063D60-0xC0063EEF`) is the following
     directory/scanner response path: it queries the embedded child entry, sends empty entries to the
     command-handler-0x12 scanner, dispatches command record `0x12` for scanner state `2`, and builds
     command record `0x15` for the remaining entry state. The directory and payload meanings remain
     unresolved.
  - `ProcessVoiceTaskPcmLoadAndLatchGate` (`0xC0082FE8`) runs
    `Voice_ProcessPcmSampleLoadState` and sets the shared state object's `+0x30E` latch byte;
    `ClearVoiceTaskStateObjectLatchGate` (`0xC00828FC`) clears it during control-object setup.
    The common queue path `QueueVoiceTaskIndexedValues` (`0xC0086280`) derives up to three
    values from the indexed child at `+0x358`, appends them to the `+0x34C/+0x350` dynamic
    array, and notifies listeners. `AppendVoiceTaskQueuedValue` (`0xC00861D0`) is its bounded
    grow-and-append primitive; the queued value and latch meanings remain unresolved.
  - A separate `0xB40`-byte service object is exposed through
    `GetOrCreateVoiceTaskServiceObjectB40` (`0xC00626F0`) and initialized by
    `InitializeVoiceTaskServiceObjectB40` (`0xC00822E4`). Its constructor clears the leading
    listener/state records and stores an SD-card-driver byte at `+0xC2`.
    `SetVoiceTaskServiceObjectB40StateAndNotify` (`0xC00822C4`) updates state `+0x308`,
    refreshes the selected resource state through `UpdateVoiceTaskServiceResourceState`
    (`0xC0082288`),
    and notifies the active `+0x08..+0x308` listener records. Confirmed service-state consumers
    include `UpdateVoiceTaskEventRecorderServiceState` (`0xC006447C`), which toggles the Event
    REC/PLAY object's local flag and selects the observed no-card/internal-clock status text;
    `UpdateVoiceTaskSharedContextServiceState` (`0xC0061898`), which stores a local boolean and can
    emit common-message `8/0x0E`; `UpdateVoiceTaskSampleServiceState` (`0xC0069A30`), which stores
    its local state, refreshes the shared context, and can emit `8/0x25`; and the Data Util and
    Software Update callbacks `UpdateVoiceTaskDataUtilServiceState` (`0xC006C470`) and
    `UpdateVoiceTaskSoftwareUpdateServiceState` (`0xC006C4A0`). The service's remaining fields
    and the product meaning of its state byte remain unresolved. The transition method
    `ApplyVoiceTaskServiceStateAndRefresh` (`0xC006F384`, also reached through thunk
    `0xC00837E8`) applies the state, refreshes related control records, clears the observed word at
    `0xC069128C`, and submits a common control/status update. The selector parser used by that path is
    For a nonzero service state, `PublishSDCardDriverForResourceSelection` (`0xC003FD20`) obtains
    the singleton SD-card driver and publishes its pointer before the selected resource record is
    rebuilt; the driver's remaining field contract is unresolved.
    `ParseCpuResourceSelector` (`0xC009BB80`); it advances a caller-owned token pointer
    and returns the observed selector class or `0xFFFFFFFF` for invalid input. The follow-up
    `BuildCpuResourceRecordFromSelector` (`0xC009C0F0`) resolves the selector through a
    pointer table, initializes or reuses the selected record, validates its encoded format/timing
    fields, derives data extent/block stride/element count, and follows up to four linked records
    from the record's `+0x1F6` area. Its return codes distinguish invalid selectors, missing
    records, busy/unsupported states, and capacity/format failures; the product-level resource
    meaning remains unresolved.
  - The direct callers show this is a shared selector-driven CPU resource/file engine, with PCM
    import/export as one confirmed consumer rather than its sole ownership. `SetCpuResourceRecordBySelector`
    (`0xC009DAD8`) replaces an entry in the resource pointer table and conditionally builds it;
    `AcquireCpuResourceRecord` (`0xC009DB60`) produces a caller-owned context record;
    `ResolveCpuResourceContext` (`0xC009E660`) and `RefreshCpuResourceSelection` (`0xC009E7DC`)
    resolve and optionally refresh a selected element; `CountCpuResourceElements` (`0xC009E85C`)
    counts available logical elements; `ReleaseCpuResourceContext` (`0xC009E9B8`) releases/refreshes
    the active element context; and `CreateCpuResourceVariant` (`0xC009EB00`) builds a generated
    variant. The exact ARM body is `0xC009EB00-0xC009ED84`: it selects an unused element, derives
    a six-byte identifier from the source element index and `GetCpuResourceVariantSeed`
    (`0xC009EEC4`), whose initialized image value is `0x46210000`, initializes fixed metadata and
    path buffers, duplicates the source element according to the source record's `+0x02` count, and
    commits the generated record. Its observed status gates are: parse zero -> `8`, path flag
    `0x20` -> `6`, and `FindCpuResourceElement` results `0/1/-1` -> `7/2/1`; later helper failures
    propagate. `FinalizeCpuResourceVariantRecord` (`0xC009BEE0`) performs the final resident-data
    check and backing-resource flush, with an additional type-3 metadata rewrite path. The exact
    generated variant/product meaning remains unresolved. These wrappers are reached by PCM
    import/export, pattern-resource handlers, and project-information generation. Shared helpers
    `ParseCpuResourcePath` (`0xC009CF2C`),
    `LoadCpuResourceBlock` (`0xC009BFE0`), `ReadCpuResourceElement` (`0xC009C5E4`), and
    `ReleaseCpuResourceElementChain` (`0xC009DA34`) have bounded current call sites.
    The lower SD block methods used by their stream path still have a wrap-prone
    card-range check and no caller-buffer capacity parameter; their direct
    SD-file reachability remains unresolved. Their exact filesystem, format,
    and product-level meanings remain intentionally unresolved.
  - The same record is exposed through a stream-like API: `ReadCpuResourceStream` (`0xC009DD74`)
    reads bytes while advancing packed element/block cursors; `WriteCpuResourceStream`
    (`0xC009DFB8`) performs the corresponding write and extends the tracked end; and
    `SeekCpuResourceStream` (`0xC009E404`) relocates the cursor across format-specific element
    boundaries. `WriteCpuResourceElement` (`0xC009C890`) packs one logical element into the
    observed 12-bit, 16-bit, or wider format, `AdvanceCpuResourceElementCursor` (`0xC009CB7C`)
    advances the packed cursor, `WriteCpuResourceString` (`0xC009ED8C`) emits NUL-terminated text,
    and `CloseCpuResourceContext` (`0xC009E3DC`) finalizes and clears the caller-owned context.
    These are CPU resource-I/O primitives; their on-disk container tags and higher-level product
    names remain unresolved.
    `CompleteVoiceTaskPcmLoadAndLatchGate`
    (`0xC006D314`) is a related completion callback that emits common-message type 8/0x0D,
    runs the PCM load-state processor, and sets the shared `+0x30E` latch.
 - The shared CPU command dispatcher at `0xC004B208` uses a jump table at
  `0xC004B220` for command IDs `0x00..0x3C`; entry zero is the default branch and
  out-of-range IDs take that same path. The handlers use the byte at `[sp+0x10]` as
  an apply/active gate. Confirmed handler behavior for the control-field commands is
  recorded in the database as `HandleApplyCommand0x2D` (`0xC004B8D0`, per-voice
  record/timbre update), `0x2E` (`0xC004B8F4`, shared control-state transition),
  `0x2F` (`0xC004B924`, DSP scalar 0 or `0x7FFFFFFF`), `0x30` (`0xC004B938`,
  all-voice value application), `0x31` (`0xC004B94C`, 16-voice and 24-oscillator-slot
  reset followed by host command `0x36`), `0x32` (`0xC004B960`, system-object
  selection/state update), `0x33` (`0xC004B99C`, all-voice timbre/oscillator
  reconfiguration), `0x34` (`0xC004B9B0`, callback-driven LCD/GPIO state), `0x35`
  (`0xC004B9C4`, related state `+0x18` update), `0x36` (`0xC004B9DC`, shared scalar
  `+0x14` store), `0x37` (`0xC004B9F0`, LCD state-machine event 4 with value clamp
  `0x12..0x2A`), and `0x38..0x3A` (no-op handlers). The longer implementations
  are the tail-called helpers `0xC009A764`, `0xC009A780`, `0xC009A808`,
  `0xC009A814`, `0xC009A83C`, `0xC009A840`, `0xC009A860`, `0xC009A878`,
  `0xC009A8B8`, `0xC009A8C8`, and `0xC009A904`; their evidence-backed names are
  recorded in the database. These handler names intentionally retain numeric command
  IDs because product-level meanings remain unresolved.
- The control-dispatch command `0x2F` is distinct from Host-DMA application command
  `0x2F`: its CPU path `0xC004B924 -> 0xC009A808` converts the value to either zero
  or `0x7FFFFFFF`, then calls `DspIf_SendHostCommand1WithTokenAndDword`
  (`0xC0012B4C`). That wrapper emits Host-DMA command `0x01` with token `0x4C4E`
  (`DspHostToken4C4E`) and the scalar dword payload, using the six-halfword packet
  layout `{0x0106, 0x0001, 0, token, dword_high, dword_low}` under mutex ID 1.
- `InitializeVoiceTaskControlDispatchObject338` (`0xC00447BC`) initializes the
  shared 0x338-byte dispatch object, including its `+0x32C` linked-record sentinel,
  dispatch flags around `+0x334/+0x335`, and published related 0x50-byte object at
  `+0x320`. `LoadVoiceTaskControlImage` (`0xC0047620-0xC0047787`) copies a serialized
  `0x100`-byte image into the control object at `+0x04`, snapshots the live control fields
  into `+0x104..+0x116`, preserves fields `+0x22` and `+0x2D` in its nonzero third-argument
  variant, and passes the image to the common parser/cache. Its direct callers are startup,
  the USER.VSB loader, and resource/state-loading code. `IsPersistentRecordHeaderGlde`
  (`0xC004718C`) is the corresponding `+0xFC == "GLDE"` validator. `ApplyVoiceTaskControlState`
  (`0xC0047864`) replays the stored fields through the setter family and refreshes the
  reusable callback-state object. Its field-`+0x29` replay is separate from the direct Global
  POWER SAVE command-`0x33` path.
  `FlushVoiceTaskQueuedEvents` (`0xC005AA80`) drains pending four-byte records into
  `QueueVoiceTaskEvent` before clearing the temporary range.
- The mode-handler helper paths provide additional object boundaries. Mode 2 uses
  `ClearVoiceTaskControlMode2State` (`0xC005A02C`) and
  `ApplyVoiceTaskControlMode2State` (`0xC005A9DC-0xC005A9FB`) to update the
  per-part `+0xC3` byte and tail-dispatch to `SetPartSlotStateByte26`
  (`0xC005C598-0xC005C5BB`). That shared helper writes value `3` to the indexed
  `g_aPartSlotRecords` row's `+0x26` byte for a nonzero argument, or clears only
  bit `0` for a zero argument. Mode 6 maintains 0x0C-byte auxiliary records in
  a state-object list at `+0x730` through `AppendVoiceTaskMode6AuxiliaryRecord`
  (`0xC0056838`) and `ReleaseVoiceTaskMode6AuxiliaryRecord` (`0xC00568B8`),
  with `PrepareVoiceTaskMode6Activation` (`0xC0043974`) gating the service-mode-3
  activation path.
- Mode `0x0C` lazily allocates a 0x348-byte state object through
  `InitializeVoiceTaskMode12State` (`0xC008DFFC`), which establishes its embedded
  records and registers four callback descriptors. `UpdateVoiceTaskMode12State`
  (`0xC008DA54`) stores the two-byte state at `+0x31C` and invokes active callbacks;
  `RefreshVoiceTaskMode12State` (`0xC008D994`) is the paired refresh path.
- The mode-8 path uses a lazily allocated 0x324-byte shared state object through
  `GetOrCreateVoiceTaskStateObject324` (`0xC002FAFC`) and
  `InitializeVoiceTaskStateObject324` (`0xC0079828`). That constructor is also
  called while building the mode-0x0C state, so the object boundary is shared;
   its indexed byte at `+0x7C` is exposed by
   `GetVoiceTaskStateObjectEntryByte` (`0xC004752C`) and
   `SetVoiceTaskStateObjectEntryByte` (`0xC0047538`). Mode 9 updates indexed state
   at `+0x318/+0x31C` through `UpdateVoiceTaskIndexedState` (`0xC004CEA8`)
   and emits common-message type `0x0D` on the observed change path.
   The adjacent state-processing cluster is now bounded in the database: a separate
   `0x30C` listener/state object is initialized by `InitializeVoiceTaskStateObject30C`
   (`0xC00794E0-0xC007956F`) and stores a shared `0x118` child at `+0x308`.
     `ApplyVoiceTaskStateObject30CChildState` (`0xC007957C-0xC0079633`) applies the
     observed child control-field batch. Its direct call to
     `ApplySharedControlModeAndLcdGpio` is fed by child byte `+0x29` via
     `GetVoiceTaskSharedControlStateByte` (`0xC0047340`), creating a possible indirect
     panel-UART0 packet-`0x02` refresh during this broad shared-state path. A later
     `GetVoiceTaskControlField25` (`0xC0047300`) feeds a separate paired update. This is
     distinct from the direct Global POWER SAVE selector write (`+0x29`/command `0x33`):
     the only recovered direct callers are the startup path (argument `1`) and the
     `ApplyVoiceTaskStateObject324AndNotify` transaction (argument `0`). The latter is
     used by resource/state-loading handlers, while the normal Global POWER SAVE edit
     does not call this routine. The two adjacent helper calls at `0xC009A870` and
     `0xC009A874` are literal `BX LR` no-ops. The routine also updates the separate
     timer/GPIO pulse-state path. The `ApplyVoiceTaskStateObject324AndNotify`
     (`0xC0079634-0xC007968F`) wrapper notifies active records after the batch.
     Its recovered direct callsites are `0xC002E5CC`, `0xC00317AC`, and `0xC00311D8`,
     all in resource/state-loading code; this confirms a restore/load route to the
     packet-`0x02` refresh but not a direct Global POWER SAVE edit route.
   `RefreshVoiceTaskStateObjectLcdState` (`0xC0079690-0xC00796B3`) derives and clamps
   a scalar before dispatching the observed LCD state. The 0x324-byte object's listener
   helpers clear or update `+0x31C/+0x321` through
   `ClearVoiceTaskStateObject324LatchAndNotify`,
   `SetVoiceTaskStateObject324ActiveAndNotify`,
   `UpdateVoiceTaskStateObject324FromState314`, and
   `NotifyVoiceTaskStateObject324State7`; exact event meanings remain unresolved.
   `ProcessVoiceTaskStateObject324IndexedTransition` (`0xC0079AA8-0xC0079B3B`) is the
   sequencer/control-facing transition path that gates on shared state, advances `+0x31C`,
   and emits a compact command record when `+0x318` changes. Its auxiliary 0x84-byte
    service is provided by `GetOrCreateVoiceTaskStateTransitionService` (`0xC0079B44`).
    The neighboring reset/index paths are also bounded: `ResetVoiceTaskStateObject324AndApplyAssignments`
    (`0xC0079B78-0xC0079C63`) clears transient linked records, flushes queued events, applies
    assignment state, and appends a bulk record; `ApplyVoiceTaskStateObject324IfReady`
    (`0xC0079C68-0xC0079C9F`) is its readiness-gated mode-2 wrapper, while
    `FinalizeVoiceTaskStateObject324Transition` (`0xC0079CA0-0xC0079CF7`) is the mode-1
    commit/notification wrapper. It first requires the `PTST` marker at block offset `+0x00`
    and `PTED` at `+0x3BFC`, then calls the assignment reset path with transition mode 1.
    That path clears the reusable object's transient byte at `+0x320`, detaches and frees its
    linked records at `+0x32C/+0x330`, flushes queued four-byte events, resets the sixteen-voice
    oscillator/DSP state, copies and applies the `0x4000` block, rebuilds the sixteen slot
    assignments, and appends a type-2 bulk record containing a copied `0x4000`-byte payload.
    The oscillator reset compares each assignment record's `+0x821` byte against a runtime
    sixteen-byte table and clears the corresponding DSP-active states; the table and field
    meanings remain unresolved. `ApplyVoiceTaskStateObject324IndexAndMappedState`
    (`0xC0079CF8-0xC0079DA3`) updates the 16-entry mapped-state records after an accepted
    index change. `SetVoiceTaskStateObject324IndexAndNotify` (`0xC0079DB4-0xC0079E5F`)
    clamps and publishes an index while refreshing the related service and DSP/control
    notifications. The assignment reset's follow-on refresh reapplies the shared DSP/control
    fields and all sixteen voice parameter groups through `ApplyVoiceTaskDspControlAndVoiceParameters`
    (`0xC004A8E4`), sends the observed timing host command through
    `SendVoiceTaskTimingHostCommand` (`0xC009113C`), and rebuilds a 24-entry selector-pair
    lookup through `RebuildVoiceTaskSlotAssignmentLookup` (`0xC00577EC`). These selector,
    timing, and product-level field meanings remain unresolved.
 - The mode-6 indexed state object has a per-index 0x1C-byte record. Its payload
  pointer array begins at `+0xF4` and is bounded by the count at `+0x10C` to five
  entries; the active marker is at `+0x2DC`, and the object-wide active-entry count
  is at `+0x370`. `ActivateVoiceTaskMode6IndexedEntry` (`0xC0056110`) fills this
  record from the current control payload set, while
  `DeactivateVoiceTaskMode6IndexedEntry` (`0xC005604C`) clears it.
  `ReconcileVoiceTaskMode6IndexedEntries` (`0xC00562C4`) removes stale/duplicate
  payloads and repopulates the same bounded records. The state object dispatches
  four virtual subobject methods through its pointer array at `+0x2B4`, with the
  populated count at `+0x2D8`; the method-offset wrappers are named in the database.
  `CollectVoiceTaskControlPayloads` (`0xC00547A8`) provides the temporary five-entry
  collection used by the activation/reconciliation paths, and
  `PublishVoiceTaskMode6IndexedState` (`0xC00560C0`) sends the resulting value through
  the object's `+0x388/+0x38C/+0x398` output fields. Product-level meanings remain
  unresolved.
- The mode-`0x0C` object's callback/state machine is further bounded. Its callback
  records are 0x18 bytes each across the range `+0x04..+0x303`, and the active
  byte is at record `+0x14`. `AdjustVoiceTaskMode12Selection` (`0xC008D8BC`)
  clamps the selection at `+0x318` to `1..8` and maps stages `2..5` to a compact
  value at `+0x328`; `AdjustVoiceTaskMode12Range` (`0xC008DB6C`) advances the
  major/substep pair at `+0x31C/+0x31D`, including `0..0x0F` substep rollover.
  `ApplyVoiceTaskMode12StateCommand` (`0xC008DAB8`) accepts command bytes 2/3,
  while `RebuildVoiceTaskMode12State` (`0xC008DB28`) rebuilds the current payloads.
  The derived fields at `+0x320`, `+0x324`, `+0x328`, `+0x32C`, `+0x330`,
  `+0x338`, `+0x33C`, and `+0x340` are populated by the corresponding helpers
  `BuildVoiceTaskMode12IndexedPayload` (`0xC008D614`),
  `BuildVoiceTaskMode12CallbackPayload` (`0xC008D88C`), and the resource/serialization
  paths; their product-level meanings remain unresolved.
- `SetVoiceTaskTimingAdjustment`
  (`0xC0057E24`) clamps the signed interpolation adjustment to `-100..100` and
  `SetVoiceTaskTimingPhaseLimit` (`0xC0057E4C`) clamps the phase limit to `1..4`.
  These setters' product-level meanings remain unresolved.
 - `GetSelectedVoiceTaskTimingTableIndex` (`0xC004704C`) reads the selected
   timing-table index from an active record's byte at `+0x35`; the target builder
   clamps it to `0..0x32` before indexing the table. Two upstream paths are now
   identified: `ConfigureVoiceTaskTimingParameters` (`0xC0045168`) maps caller
   parameters to the signed adjustment and phase-limit fields, while
   `UpdateVoiceTaskTimingAndType40Assignment` (`0xC0045718`) sets the adjustment,
   forces phase limit `1`, and updates a per-part type-`0x40` assignment byte when
   its computed value changes. The table and parameter product meanings remain
   unresolved.
 - The timing-index update path is now bounded. `SetVoiceTaskTimingTableIndexAndNotify`
   (`0xC004A5F8`) writes record `+0x35` and forwards the new value through the shared
   VoiceTask service update dispatcher. `AdjustVoiceTaskTimingTableIndex` (`0xC007CFA4`)
   is one table-driven input handler: it adds a signed delta, clamps the result to
   `0..0x31`, and invokes the setter only when the index changes. The dispatcher is
   shared by other record-field setters, so the event's broader semantics remain
   unresolved; the Part Utility child observes the index through its separate callback
   path described below.
 - The slot-record accessors now expose the confirmed layout in the database:
  `GetPartSlotRecordField834`, `GetPartSlotRecordField835`,
  `GetPartSlotRecordField836`, and `GetPartSlotRecordField837` read the four
  scalar bytes, while `GetPartSlotRecordPayload` returns the `+0x838` payload
  address. `GetPartStepCountByte` reads the per-part `+0x804` byte and
  `GetPartRecordField807` reads per-part `+0x807`. The previously merged
  `0xC0046F20` getter was corrected to `0xC0046F20-0xC0046F34`.
 - `0xC0024B6C` is an interrupt-safe circular-FIFO dequeue helper: it checks the
  count at queue `+0x14`, disables interrupts while copying one record, advances
  the read offset at `+0x12` using the queue stride at `+0x0C` and mask at
  `+0x18`, restores interrupt state, and returns one on success. The event wait
  helper at `0xC00010E4` validates the object ID, mask, and mode, checks for an
  already-delivered event, otherwise blocks through the RTOS scheduler path,
  and returns the delivered event word through its output pointer. Mode bit 0
  selects any-bit matching when set and all-bit matching when clear. The timed
  variant at `0xC00011F8` arms the same event wait with a relative timer record.
 - `CopyRecordIntoCircularBuffer` (`0xC0024920`) copies a record using the
  buffer's stride and write cursor. `WriteCircularBufferRecordAndSignal`
  (`0xC0024A64`) performs the empty/full check and count update, then signals
  the `0xC0000E9C` event table only on the empty-to-nonempty transition. The
  queue's `+0x08` field supplies both the one-based mutex/event-object ID and
  the queue's `+0x1C` field supplies the event mask. `MatchRtosEventCondition`
  (`0xC00020A8`) returns the full event state on a match and clears the state
  when the associated task flag requests consumption.
- The CentralServiceTask SD-card event edge is confirmed: the SD-card service
  path at `0xC001D978` calls the RTOS event-set path at `0xC0000F78` with object
  ID `2` and mask `4`, matching CentralServiceTask's bit-2 branch. The same
  event-set path is used by the Timer2 interrupt path for object ID `6`, mask
  `2`. A separate event-set path at `0xC0000E9C` is used by CommandTask for
  object ID `3`, mask `1`, and by a generic queue writer whose event object and
  mask are stored in its object fields.
- That remaining producer edge is now resolved. The CircularBuffer static
  initializer at `0xC0024EE4` constructs five 8-byte-record, 0x400-record
  queues. The two central-service queue objects are at `0xC033E524` (event
  object 2, mask 1) and `0xC033E57C` (event object 2, mask 2); the task globals
  at `0xC002A590` and `0xC002A594` point to those objects. The MIDI-UART1
  receive/parser path at `0xC00252F0` (called from
  `HandleMidiUart1Interrupt`) writes accepted parsed packets to the first
  queue, while the panel-UART0 receive path at `0xC00252AC` writes the
  receive-state record at `g_pPanelUartReceiveProtocol + 4` to the second
  queue. Both writers use the bounded retry behavior of the queue writer and
  therefore signal CentralServiceTask through event bits 1 and 2 respectively.

- The SeqTask-to-VoiceTask input edge is now bounded. `SeqTask::taskProc`
  (`0xC002AACC`) dispatches its active event buffer through
  `ProcessSeqTaskEventBuffer` (`0xC003C004`). Its type-0 path accepts records
  whose status byte at `+0x08` has high nibble `0x80` or `0x90`, packs the
  observed status/data fields, and writes them through
  `QueueVoiceTaskMidiNoteRecord` (`0xC003BE00`) to
  `g_stVoiceTaskInputQueue` (`0xC033E5A8`). `VoiceTask::taskProc`
  (`0xC002B220`) waits on event object `6` with mask `3`, drains that queue,
  and appends each dequeued record through `AppendVoiceTaskInputRecord`.
  The exact source/channel and product-level note semantics remain unresolved.

- The VoiceTask record-dispatch boundary is also separated from the wrapper.
  `PreprocessVoiceTaskMidiRecord` (`0xC01707F0`) applies the observed global
  enable/status checks, forwards selected records through the paired
  `WriteThreeByteRecordToDualCircularBuffers` (`0xC002775C`) or
  `WriteTwoByteRecordToDualCircularBuffers` (`0xC002779C`) helpers, and then
  tail-branches to `DispatchVoiceAndMidiRecord` (`0xC0026418`). The latter is
  shared by this VoiceTask path and a CentralServiceTask queue path; its first
  record byte selects standard MIDI/system handling or compact voice/control
  command branches. The complete command map and paired-buffer consumers are
  not yet established.

- The central-service consumers use a shared CPU common-message wrapper. Its
  confirmed size is 16 bytes: a vtable pointer at `+0x00`, a type byte at
  `+0x04`, and two payload words at `+0x08` and `+0x0C`. The constructors at
  `0xC0070A60`, `0xC0070AF0`, and `0xC0070A80` initialize, build, and copy this
  wrapper respectively. The panel consumer at `0xC002814C` and the MIDI
  consumer at `0xC0026288` both eventually use the type/payload form; the
  common wrappers emit types `0x00` through `0x16` with gaps.
 - `ForwardCommonMessageIfActive` (`0xC0083FE8`) is a conditional forwarding
   boundary used by the common-message wrappers. It reads the selected service
   object through `0xC0691378`, requires the object and its byte at `+0x70` to
   be nonzero, converts the message through `0xC0070A80`, and invokes the
   receiver virtual method at the object field `+0x0C` and vtable offset `+0x08`.
   That receiver is now resolved as a 256-entry byte-indexed ring: its embedded
   ring object's write and read indices are at `+0x04` and `+0x08`, and its
   16-byte common-message wrappers start at `+0x0C` with the normal wrapper
   layout (vtable, type byte at `+0x04`, and payload words at `+0x08`/`+0x0C`).
    `DequeueCommonMessageFromReceiverRing`
    (`0xC0070B10`) checks the ring's empty method, copies the front record, and
    advances the read index. `ProcessCommonMessageReceiverQueue` (`0xC00713B4`)
    drains the active service receiver at `+0x0C` and invokes the selected
    service's vtable `+0x10` dispatcher for each record.
    The adjacent service-object queue boundary is `ProcessCommonMessageServiceObjectQueue`
    (`0xC0083848-0xC0083897`), which performs the same dequeue/dispatch loop for the shared
    `+0x0C` receiver. Its object lifecycle is bounded by
     `InitializeCommonMessageServiceObject` (`0xC0083898-0xC00838BB`) and
     `DestroyCommonMessageServiceObject` (`0xC00838C4-0xC00838DF`); both wrap the embedded
     service state at `+0x10`, with the destructor freeing the outer object.
  - `SelectCommonMessageServiceMode` (`0xC0083EC8`) stores the requested mode and
    publishes the selected service object through `0xC0691378`. Modes `0`, `3`,
    and `4` share the base `0x74`-byte object at `0xC03404C0`; mode `1` selects
    the `0x1E8`-byte MIDI-SysEx control object at `0xC033E6B0`; mode `2` selects
    a separate `0x7C`-byte object at `0xC03404BC`; and mode `5` selects a
    distinct `0x7C`-byte variant at `0xC03404B8`. Product-level mode meanings
    remain unresolved.
  - `GetSelectedCommonMessageServiceMode` (`0xC0083FD8`) returns the stored mode
    from `0xC00F9D8C`. Its confirmed caller,
    `InitializeVoiceTaskServiceControlContext` (`0xC006EEC4`), uses the result
    to apply a voice-task state variant for mode `0` or modes `3`/`4`; this
    establishes a consumer of the selector without resolving the product-level
    meanings of those modes.
  - The selector is also reached from the UI task's initialization path. `UiTask::taskProc`
    (`0xC002B144`) derives an initial state from shared device state and calls
    `InitializeUiTaskState` (`0xC002D1B8`). That routine initializes the UI-state object,
    ensures the shared VoiceTask control object exists, and calls
    `InitializeUiTaskCommonMessageService` (`0xC002D07C`). `InitializeUiTaskState` stores
    the derived request in `g_uiTaskCommonMessageServiceMode` (`0xC03404C4`); the latter
    chooses the object for that request, stores it at the UI-state `+0x04` field,
    republishes the resulting mode through `SelectCommonMessageServiceMode`, and invokes
    the selected object's vtable method at `+0x08`. The request word and the published
    active-mode word are therefore distinct state boundaries; the product meanings of the
    six modes remain unresolved. Other CPU paths also consume this request directly:
    `0xC0040A50` has a mode-`2` branch, the larger handler containing `0xC0042C00`
    has a mode-`5` condition, and the resource/serial-flash path containing `0xC0030A98`
    compares mode `3`; their broader subsystem roles remain unresolved.
  - `GetOrCreateCommonMessageServiceBase` (`0xC002D048`) lazily allocates the shared
    `0x74`-byte object and initializes it through `InitializeCommonMessageServiceBase`.
  - `InitializeCommonMessageReceiverRing` (`0xC00775EC`) is the shared receiver-ring
    constructor used by the base service, mode 2, and mode 5. It installs the ring
    vtable, clears its indices/state, and constructs 256 embedded 16-byte wrapper slots
    beginning at object `+0x0C`.
  - The mode-5 object uses the vtable at `0xC00E5598`. Its `+0x08` method,
    `ActivateCommonMessageMode5Object` (`0xC008EBD4`), allocates a 256-entry ring of
    16-byte common-message wrappers at object `+0x0C`, allocates an `0x80`-byte embedded
    service-state object at `+0x78`, and sets the active byte at `+0x70`.
    `ProcessCommonMessageMode5Queue` (`0xC008EB84`) drains that ring only while active
    and dispatches each wrapper through the vtable `+0x10` slot. The mode-5 `+0x10`
    slot is the shared `DispatchCommonMessageToServiceHandler` boundary.
    Its `+0x14` and `+0x20` handlers (`0xC008EB08` and `0xC008EAE4`) forward payloads
    to embedded-state vtable slots `+0x0C` and `+0x24`, respectively. The remaining
    mode-5 type handlers are structurally mapped by the vtable, but their product-level
    message meanings remain unresolved. The embedded-state `+0x0C` handler
    (`0xC006E5DC`) accepts forwarded command IDs `0x0D`, `9`, and `0x22`, while its
    `+0x24` handler (`0xC006E41C`) consumes two payload values, maintains lower/upper
    bounds, and serializes an update into the state command sink. These are confirmed
    state operations; their product-level meanings remain unresolved.
 - The main `0x1E8` service object's vtable dispatches through
   `DispatchVoiceServiceCommonMessage` (`0xC00773FC`). Its type switch is
   confirmed to route types `1`, `4`, `5`, `6`, `7`, and `0x0C` through service
   vtable offsets `+0x14`, `+0x2C`, `+0x24`, `+0x30`, `+0x44`, and `+0x50`.
    Type `2` stores both payload words in service state, type `0x16` has a
    dedicated subtype path, and type `0` performs the main voice-task state
    transition logic. The semantic names of the individual message types and
    ownership of alternate service modes remain unresolved.
    `InitializeMainCommonMessageServiceObject` (`0xC00714D4`) clears the 0x1E8-byte
    object, installs vtable `0xC00E43D8`, clears its service fields, the observed
    indexed-value tables, and the status-mask array, and initializes the latter's
    per-entry sentinel values to `-2`. Its activation method,
    `ActivateMainCommonMessageServiceObject` (`0xC0077630`), creates the 256-entry
    receiver ring, initializes the shared VoiceTask and mapped-state contexts, derives
    selector-dependent state from `PanelIdentityState`, emits the observed start records,
    and sets the active byte at `+0x70`. The destructor path is
    `DestroyMainCommonMessageServiceObject` (`0xC0070F20`) followed by the outer delete
    wrapper. The later vtable methods now also bound primary/secondary subobject
    selection, payload forwarding, mapped-state handling, child shutdown, control-state
    updates, timed-parameter updates, and indexed selection updates. These operations are
    confirmed structurally; their product-level message meanings remain unresolved.
    The primary-subobject selector accepts exactly factory indices `3`, `4`, `7`, `8`,
    `0x0A`, `0x0C`, `0x0E`, `0x13`, `0x15`, and `0x25`, matching the accepted event set
    in `ApplyVoiceTaskServiceStateVariant`; the secondary selector can request the
    broader factory range, with the observed initial-state type-`0x17` no-op exception.
     The type-0 path keeps a step object at service offset `+0x78` and a selected
     state object at `+0x7C`. `InitializeVoiceServiceStepObject`
     (`0xC0075C6C`) initializes the former with vtable `0xC00E43A0`, the owning
     service, a shared context, a subsystem context, and state fields at `+0x10`,
     `+0x14`, and `+0x18`. `RunVoiceServiceStep` (`0xC0076060`) is called with
     that object, the current stage at `+0x88`, and the phase at `+0x8C`; its
     packed return status drives the subsequent transition logic. The selected
     state object is rebuilt by `SelectVoiceServiceStateObject` (`0xC0075E68`),
     which destroys the old object and allocates one of the observed variants for
     requested indices `0` through `8`. The stage meanings and variant names are
     not yet established.
     The bounded type-0 orchestrator is `ProcessVoiceServiceStateMachine`
     (`0xC0076D98-0xC00773E7`), reached from the type-0 branch of
     `DispatchVoiceServiceCommonMessage` (`0xC0077480`). It creates the worker or
     selected state object when absent, invokes the state-object event methods,
     calls `RunVoiceServiceStep`, decodes the packed result and publishes event
     `0x6C` for a nonnegative high-half result, then advances/restarts stages or
     destroys the worker according to the low-half status. It also handles the
     recovery flag at service `+0x92` and the pending event at `+0xCC`; individual
     stage and state-object meanings remain unresolved.
     One bounded type-0 stage is a MIDI probe. `ProbeVoiceServiceResponse`
    (`0xC00719F8`) waits for the transport buffer to empty, clears three bytes in
    the worker state area at `+0x14`, calls `SendVoiceServiceProbeSequence`
    (`0xC0071984`), and classifies the resulting state bytes as status `1` when
    byte 0 is zero, status `2` when byte 0 is nonzero and byte 1 is zero, or
    status `0` otherwise. The `VoiceServiceStep` vtable at `0xC00E43A0` is a
    small destruction-only table: its `+0x00` and `+0x04` entries target
    `0xC0070D2C` and `0xC0070E60`, while `+0x08` and `+0x0C` are null. The
    state-processing functions formerly associated with this table instead
    belong to the selector-specific state vtables installed by
    `SelectVoiceServiceStateObject`: selector 0 uses `0xC00E4328`, selector 1
    `0xC00E4350`, selector 2 `0xC00E4510`, selector 3 `0xC00E4538`, selector 4
    `0xC00E4378`, selector 5 `0xC00E4128`, selector 6 `0xC00E4470`, selector 7
     `0xC00E44C0`, and selector 8 `0xC00E43B0`. Their `+0x08` step methods are
     called with only the state object; their `+0x0C` event methods receive the
     event code returned by `FUN_c00715D8`. The selector-4 `+0x08` method
     (`0xC00735EC`) tail-calls the separate helper
     `UpdateVoiceServiceMappedStateDisplayValue` (`0xC007254C`) after restoring
     its frame; that helper compares/stores the variant's `+0x54` display value
     and updates the LCD. The two functions are kept separate in Ghidra.
    A direct UART receive-to-field connection is not established. The transmit
    sequence uses the initialized seven-byte prefix `F0 42 22 00 01 24 06` at
    `0xC00A3610` (referenced through `0xC00719F0`), then values `0..0x7F`, followed
    by `F7`; its protocol meaning is unresolved.
    Additional callback-driven voice-service paths now have confirmed mapped-state
    producers. `ApplyVoiceServiceMappedStateMask` (`0xC0073B50`) consumes a 64-bit
    mask at `+0x10/+0x14`, optionally applies it after the countdown at `+0x18`, and
    updates each selected entry in the separate secondary mapped-state object with
    the common per-entry publisher. `ProcessVoiceServiceMappedStateStep`
    (`0xC0074A70`) is a larger state machine whose `+0x10` counter drives initialization
    and updates of all `0x58` entries in that same object, including direct entry
    initialization followed by publication and generic per-entry updates. These
    paths establish the producer topology but not the product meaning of the bits,
    entry fields, or service states.
    Three adjacent callback/state-machine paths are now bounded as well:
    `ProcessVoiceServiceMappedStateSelectionStep` (`0xC0072998`) initializes or
    selects entries using a lookup table, `ProcessVoiceServiceMappedStateParameterStep`
    (`0xC0073C1C`) applies the 64-bit mask before continuing through service and display
    transitions, and `ProcessVoiceServiceMappedStateResetStep` (`0xC0073FDC`) resets or
    generically updates all `0x58` entries while also driving display/GPIO actions.
    These names describe the observed control flow only; their callback ownership and
    product-level meanings are not established.
    The shared clear-entry helper `ClearMappedStateEntryAndPublish`
    (`0xC0072E70-0xC0072EB3`) was also separated from the adjacent state-machine
    code. It clears the selected bit and entry fields, stores record value `10`, and
    tail-dispatches through `SetMappedStateEntryAndPublish`; the following code at
    `0xC0072EB8` is a distinct state-machine entry, now bounded through `0xC00732E3`.
    The following constructor-like routine `InitializeVoiceServiceMappedStateControl`
    (`0xC00732F8-0xC0073383`) installs a vtable, emits fixed service-control records,
    and clears mapped-state index `0x12`; ownership and product meaning remain
    unresolved.
  - The shared/base service vtable has a separate dispatcher,
    `DispatchCommonMessageToServiceHandler` (`0xC00834FC`). It routes the normal
    type range through fixed vtable slots and routes type `0x17` through offset
    `+0x6C`. That slot is `HandleCommonMessageType17DspCompletion`
    (`0xC0083840`) in the confirmed shared/base and mode-5 vtables. The handler
    consumes the periodic DSP-completion event, drives the voice-task state object
    at `+0x10`, performs state-dependent cleanup/command actions, and contains the
    state `0x0B` PCM runtime-sample completion path. The producer
    `PollDspStatusAndEmitCommonMessage23` (`0xC004F20C`) emits this wrapper with
    both payload words zero after the DSP status read returns `2`.
  - Mode 2 is a distinct `0x7C`-byte service. Its
    `DispatchMode2CommonMessage` (`0xC00833F0`) handles only types `0` and `3`
    through vtable offsets `+0x18` and `+0x28`; type `0x17` is ignored there.
    `ActivateMode2CommonMessageService` (`0xC00834A4`) creates the receiver at `+0x0C`
    and a 0x24-byte secondary object at `+0x78`. `InitializeMode2SecondaryObject`
    (`0xC006CD18`) clears that object's entry-list fields, installs its vtable at
    `0xC00E3CE8`, allocates a 0x200-byte table-state object, and inserts it into the
    entry range beginning at `+0x10` and ending at `+0x14`.
    `HandleMode2CommonMessageType0` (`0xC0083374`) marks the secondary object active,
    iterates that entry range, and invokes each entry's virtual method at `+0x08` before
    clearing the active marker. `HandleMode2CommonMessageType3` (`0xC00832C8`) forwards
    both payload words through the secondary object's vtable `+0x20`. The entry-level
    and table-state meanings remain unresolved.
  For type `0x16`, `ProcessMidiCentralMessage` supplies a packed class/subtype/
   value word. Class `3` subtypes `0`, `1`, `2`, `3`, and `0x11` select internal
    operation codes `5`, `6`, `7`, `8`, and `9`; class `5` subtypes `0` and `1`
    apply GPIO threshold updates and queue an 11-byte MIDI transport frame through
    `BuildAndQueueCommonControlSysEx` (`0xC00717FC`). The observed frame is
    `F0 42 22 00 01 24 05 subtype value 00 F7`; the product-level meaning of
    this control frame is unresolved.
 - The type-1 handler is now bounded at `0xC0070C54`. Its first payload word is
   a bit position and its second payload word is a set/clear selector (`1`/`0`).
   The handler constructs a 64-bit single-bit mask, updates the main service's
   active mask at `+0xD8/+0xDC`, and stores the most recent set or clear mask at
   `+0xE0` or `+0xE8`. Confirmed producers include panel-UART record type `0`
   and voice/control paths; the product-level meaning of each bit remains
   unresolved.
 - Additional main-service message handlers are bounded without assigning
   product-level names: type `4` (`0xC0070CE4`) selects an indexed entry, updates
   the enable mask at `+0x1D0`, and stores a signed upper-half value in the table
   at `+0x190`; type `5` (`0xC0070CC8`) accumulates into the indexed table at
   `+0x174`; types `6` and `7` (`0xC0070D14`/`0xC0070D20`) store selector fields at
   `+0x1D4`/`+0x1D8`; and type `0x0C` (`0xC0070CB0`) stores payload values for
   indices below `0x21` in the table at `+0xF0`.
    The selector at `0xC0083EC8` lazily constructs mode-specific objects and
    publishes the selected one. Modes `0`, `3`, and `4` use the shared/base
    vtable; mode `5` uses a `0x7C`-byte variant retaining the shared dispatch
    handlers, including type `0x17`. Mode `2` uses the separate two-type
    dispatcher described above. The owning subsystem and mode meanings remain
    unresolved.
