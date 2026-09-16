# Voice assignment and DSP control

> Detailed evidence extracted from the original monolithic ARCHITECTURE.md.
> Ghidra is authoritative for current symbols, types, comments, and cross-references.

- `g_bUseOscillatorMetadataOverride` at `0xC0692E6D` selects the single
  `g_OscillatorMetadataOverride` record at `0xC00F9DE8` instead of the runtime
  catalog. The record's static display text is `for Voicing`.
  `Osc_SetMetadataOverrideParameter0` (`0xC009A100`),
  `Osc_SetMetadataOverrideParameter1` (`0xC009A158`), and
  `Osc_SetMetadataOverrideSelector` (`0xC009A1B0`) use it for live voice-0 edit
  preview: they copy or set the active selector, update bytes `+0x18`/`+0x1C`,
  enable the override, and reapply the result to active oscillator slots.
- `Timbre::getVoice` (`0xC009AF20`) validates indices below 16 and returns entries
  from `g_VoiceTable` (`0xC069EA44`) at `0x148`-byte stride. The returned `voice_t`
  records expose the nested oscillator/timbre pointer at `+0x08`; oscillator setup
  reads its selector, oscillator ID, edit value, and profile byte fields, while the
  key-`0x29` handler reads its `+0x1B` byte.
- `GetVoiceOscillatorProfileRecord` (`0xC0098D10`) selects a separate `0x58`-byte
  voice/oscillator profile record using the nested voice selector at `voice +0x08` plus
  `+0x10`. Selectors above `0x47` are replaced with zero. With
  `g_bVoiceOscillatorProfileUseSingleton` (`0xC06924DC`) clear it returns the indexed
  record at `0xC01A0000 + selector*0x58`; when set it returns the fallback record at
  `0xC00F9D90`. `SetVoiceOscillatorProfileField1BAndRefreshRate` (`0xC0099264`)
  writes profile `+0x1B` and, when profile flag `+0x1A` is enabled, refreshes the live
  voice rate-derived value at `voice +0x78`. `ApplyVoiceOscillatorProfileRecord`
  (`0xC002CDF0`) copies incoming fields including offsets `+0x54..+0x58` into this
  profile path. `SetVoiceOscillatorProfileField1B` (`0xC00991A0`) is the direct writer
  reached by `DispatchVoiceAndMidiRecord` for command/subcommand `(0x0B, 2, 0x35)`;
  both that path and the profile-apply path write profile `+0x1B`.
  In the same dispatcher, command `0x0C` passes its record payload pointer at `+0x04`
  to `ApplyVoiceOscillatorProfileRecord`.
  The profile fields and product meanings remain unresolved. The key-`0x29` handler reads
  `+0x1B` through the voice's nested object and makes its zero-versus-`0x7FFF` payload
  decision from that byte, not from the compact assignment record it updates at `+0x31`;
  the exact alias relationship between that nested object and the selector/fallback records
  above remains unproven.
- The key-`0x29` packet path is now split at its actual ARM boundaries:
  `HandleApplyCommand0x29` (`0xC004B864`) writes the compact-record byte and tail-branches
  through `ForwardVoiceAssignmentDspPayloadByVoiceIndex` (`0xC009A704`) to
  `ApplyVoiceAssignmentDspPayload` (`0xC0097E2C`). The shared helper applies the linked-voice
  guard, reads nested-object `+0x1B`, normalizes it to a boolean gate, selects paired versus
  ordinary resource mode, and tail-dispatches to `SendVoiceAssignmentHostPayload` (`0xC0093E14`),
  which selects zero or `0xC0093E80 == 0x7FFF` and emits the Host-DMA 5-word/7-word packet.
- A separate voice refresh packet path is now bounded. `SendVoiceTimbreField1CToDsp`
  (`0xC0097D98`) reads nested timbre/control byte `+0x1C`, selects zero or the
  separate shared dword `0xC0093E10 == 0x7FFF`, and emits a 5-halfword packet to
  token `voiceIndex*0x6D+0x31E`, or one 7-halfword packet for the even/odd pair in
  resource mode 3. This is distinct from the assignment packet's token base `0x325`.
  `UpdateVoiceTimbreRatePendingState` (`0xC0097DDC`) instead reads nested byte `+0x1E`,
  clamps it to `0x7F`, combines it with voice field `+0xB0`, evaluates the observed
  rate-field bitmaps, and marks the mapped one of 18 pending records when its voice bit
  is active. The fixed-point units and product meanings remain unresolved.
- `GetVoiceTaskRateModeBytePointer` (`0xC0097D18`) returns the entry for indices below
  16 in the cache `g_abVoiceTaskRateModeCache` (`0xC0692268`), otherwise null;
  `ResetVoiceTaskRateModeByteCache` (`0xC0097D30`) initializes all sixteen entries to
  `0xFF`. `UpdateVoiceTimbreDerivedField3CAndRatePending` (`0xC009A748`) calls the
  pending-state helper before deriving voice field `+0x3C`, while the adjacent
  `UpdateVoiceTimbreDerivedField3C` (`0xC009A764`) calls the separate `+0x1C` DSP packet
  helper before deriving the same field.
- `g_abVoiceOscillatorMetadataParameterTriplets` spans `0xC0692E6E` through
  `0xC069E9BD` and is laid out as 16 voices by 999 oscillator IDs by three
  bytes. `Osc_BuildVoiceMetadataParameterTriplets` (`0xC009A1FC`) fills each
  triplet from metadata bytes `+0x14/+0x15`; byte 2 begins at zero, receives
  metadata `+0x18` when flag `+0x19` is set, and is then replaced by metadata
  `+0x1C` when flag `+0x1D` is set. The exact UI parameter meanings of these
  three bytes remain unresolved.
- `Voice_ConfigureOscillatorFromTimbre` (`0xC0099D88`) connects the catalog to
  live voice state. It copies the oscillator ID from the voice's timbre record,
  resolves the DSP selector and any audio-input/PCM resource state, then calls
  `DspIf_LoadOscillatorTemplatePreset` for the template selected by the voice
  index. `Voice_RefreshOscillatorConfiguration` (`0xC0099FFC`) rebuilds the
  dependent voice state and DSP parameters after that selection or its backing
  resource changes. `Voice_RefreshOscillatorsForPcmResource` (`0xC009A0A8`)
  walks all sixteen voices, refreshing either every voice for a negative
  resource index or only voices mapped to the supplied resource. The two CPU
  resource-service callers are now bounded as handler ID `0x22`'s
  `ProcessPcmResourceServiceEvent` (`0xC0038D80`), which dispatches
  single-resource/all-voice refreshes or enters the runtime catalog rebuild path, and
  handler ID `0x24`'s `ProcessPcmResourceOperationCompletion` (`0xC0039588`), which
  resolves a completed operation's runtime index before refreshing the affected voices.
  The index-to-resource table layout below
  `Osc_ResolvePcmResourceIndexForSelector` is not yet documented as a concrete
  structure.
- The paired-voice refresh branch is now bounded. `Voice_IsPairedResourceMode`
  (`0xC009B124`) is the observed mode-3 predicate, while
  `Voice_IsLinkedOperationAllowed` (`0xC009B138`) rejects an odd-linked voice
  while the preceding voice remains in mode 3. `OscillatorRecordHasLinkedAudioPath`
  (`0xC0099848`) detects either an audio-input metadata link or a PCM resource
  with a nonzero stereo-pair role. When this linked path is selected,
  `Voice_ResetOscillatorSlotsForRefresh` (`0xC0098B20`) clears the relevant
  oscillator-slot masks, resets ownership/state, flushes pending deactivations,
  and includes the paired voice when requested. `Voice_ClearDspActiveState`
  (`0xC0098AD0`) then clears the corresponding DSP active record through command
  0 and clears the voice active byte. The refresh rebuilds one or both voices,
  and `Voice_ReinitializeDspParameters` (`0xC009B044`) emits the resulting
  command-0 state; its internal voice-field meanings remain unresolved.
- `Voice_ApplyDspRecordVariantCommand39` (`0xC0097A1C`) is the paired-aware
  command-0x39 producer used during that rebuild. It emits one record or the
  paired two-record form using token bases `0x02CA` and `0x461C`. This confirms
  the synchronization mechanics but does not yet establish the product meaning
  of the selected variant fields.
- `Voice_ReinitializeDspParameters` (`0xC009B044`) ends by tail-dispatching the
  shared assignment-payload helper after rebuilding its voice-derived state. Thus
  oscillator/resource refresh can also emit the same linked-operation-guarded
  5-halfword single-voice or 7-halfword paired Host-DMA packet described below.
  `RefreshVoiceTaskRateModeState` (`0xC0097E70`) is the adjacent rate-state helper:
  it combines paired mode as bit 7 with nested timbre byte `+0x1D`, obtains a
  mode-dependent rate from the shared system object or backing-state `+0x318 * 10`,
  and either tail-dispatches the 33-record rate update when an optional byte matches
  or calls the lower-level rate-state updater and records the resulting mode byte.
  The rate and mode product meanings remain unresolved.
- The full initialization and assignment-change paths are now separated.
  `InitializeAllVoiceOscillatorState` (`0xC0098C58`) configures all sixteen
  voices, reinitializes their DSP parameters, resets all 24 ARM oscillator
  slots, and initializes shared timing/resource state. In contrast,
  `Voice_ClearSlotsAndDspStateForAssignment` (`0xC009B5E0`) performs selective
  slot/DSP cleanup for one assignment and its mode-3 pair when applicable;
  `Voice_RebuildAfterAssignmentChange` (`0xC009B5EC`) then rebuilds the changed
  voice from its new timbre record. These paths are reached from voice-task
  assignment transitions and do not imply a change to the unresolved musical
  meanings of the copied control records.
- The startup-only voice/DSP runtime initializer is now bounded at
  `InitializeVoiceTaskDspVoiceRuntime` (`0xC009B6B8`), called from
  `StartupTask::taskProc` after shared runtime and assignment-control setup. It
  initializes the voice-table/DSP links, copies profile bytes `+0x16/+0x17` into
  sixteen per-voice `0x90`-byte cache records, fills sixteen `0x31`-byte control
  records with `0x40`, resets the sixteen-byte rate/mode cache, initializes the
  24 oscillator-slot indices and runtime fields, resets observed phase/status
  state, sends the locked command-`0x21` setup, and obtains the voice
  state-transition service. `InitializeVoiceTableAndDspControlLinks`
  (`0xC009AFA4`) is the nested initializer that assigns each voice's index,
  compact-record index, shared control pointer, and nested `0x24`-byte record
  pointer. Individual field meanings remain unresolved.
- The CPU voice-assignment record boundary is now explicit. The active control
  table exposes one `0x330`-byte record per index through
  `GetVoiceAssignmentControlRecord` (`0xC0048CB8`), at base `+0x804` with
  stride `0x330`; a separate mode-selected table is resolved by
  `GetVoiceAssignmentModeTableBase` (`0xC004A350`). The compatibility helpers
  `CheckVoiceAssignmentRecordCompatibility` (`0xC007DDCC`) and
  `CheckVoiceAssignmentIndexCompatibility` (`0xC007ED5C`) inspect the record's
  oscillator ID and PCM-resource state, returning the observed codes `2`, `0`,
  or the even/odd index parity. These codes are intentionally not given
  product-level names.
- `g_pVoiceAssignmentModeTableStorage` (`0xC004A368`) points to the raw mode-table storage. The
  handler-0x16 resource writer emits `0xFA` consecutive `0x4000`-byte blocks from it, and
  `GetVoiceAssignmentModeTableBase` resolves block `(mode + 4)` for valid mode values below `0xFA`.
  Export preparation consumes the same tables through fields at `+0x22`, `+0x25`, `+0x26`, and the
  assignment payload region beginning at `+0x800`; those fields' product meanings remain unresolved.
- The mode-image persistence helpers confirm the complete storage size: `PersistVoiceAssignmentModeImage`
  (`0xC004C2E4-0xC004C363`) copies `0xFA` blocks of `0x4000` bytes and persists `0x3E8000` bytes;
  `PersistVoiceAssignmentModeBlock` (`0xC004C28C-0xC004C2E3`) is the corresponding single-block path.
  Cross-caller accesses establish additional per-block boundaries without assigning product semantics:
  a 24-byte map at `+0x100`, a 24-byte companion-byte map at `+0x118`, 24 `0x40`-byte payloads at
  `+0x130`, and 24 `0x330`-byte voice-assignment records at `+0x800`.
- `ValidateVoiceAssignmentModeBlockMarkers` (`0xC004A310-0xC004A343`) confirms each `0x4000`-byte
  mode block is framed by the ASCII markers `PTST` at `+0x00` and `PTED` at `+0x3BFC`. The startup
  loader `LoadVoiceAssignmentModeImageFromFlash` (`0xC004BF8C-0xC004C067`) reads the complete image,
  validates all `0xFA` blocks, and invokes the default PatternSet-buffer preparation path when the read
  or marker validation fails. The payload semantics between the markers remain unresolved.
- Its flash-read primitive is `ReadVoiceAssignmentModeImageFromFlash` (`0xC002A090-0xC002A0C3`):
  it maps selector `0x24`, serializes access with mutex 2, and reads from the mapped region offset plus
  `block_index * 0x4000`. The startup loader supplies block index `0` and size `0x3E8000`, so the
  complete image is read in one operation before per-block validation.
- `InitializeVoiceAssignmentModeImageContext` (`0xC004BF7C-0xC004BF87`) stores descriptor `0xC00CFDB0`
  into the startup-owned four-byte context at `0xC03402AC`, published through
  `g_pVoiceAssignmentModeImageContextStorage` (`0xC002B0E0`). `StartupTask` creates this context
  immediately before calling `LoadVoiceAssignmentModeImageFromFlash`; the descriptor's indirect
  lifecycle semantics remain unresolved.
- The selector-`0x24` block-write callers are now bounded. `PersistVoiceAssignmentModeBlockFromStagedBuffer`
  (`0xC0038130-0xC003824F`) validates a staged `0x4000`-byte payload in a lazy `0x4244`-byte object,
  persists it for the child-selected mode index, and emits common message type `0x13` when that index is
  current. `PersistVoiceAssignmentModeTableBlock` (`0xC0038264-0xC00382FF`) persists the already resident
  runtime table block without copying a source buffer. `PrepareAndPersistVoiceAssignmentModeBlock`
  (`0xC0038304-0xC0038403`) copies the current block into the shared extended-state buffer at `+0x314`,
  sets that object's state at `+0x308` to `8`, persists the runtime block, and delays the RTOS task by
  `1000` units. These callbacks are referenced by adjacent vtable tables; their enclosing C++ class
  boundary remains unresolved.
 - The adjacent `PreparePersistentRecordHeaderObject` (`0xC004BE8C-0xC004BF13`) prepares the shared
   `0x118`-byte object at backing pointer slot `0xC033E6A0` and obtains the fixed persistent-record
   scratch buffer at `0xC08A2940`. It reads a `0x100`-byte header from selector `0x23` into that
   scratch buffer, accepts it when offset `+0xFC` contains the little-endian tag `GLDE`
   (`0x44454C47`), and otherwise copies the embedded `GLST` fallback header at `0xC00CFE58`.
   `GetPersistentRecordScratchBuffer` (`0xC0047180`) is the fixed-buffer accessor; remaining header
   fields are unresolved.
- The selector-based comparison family is now bounded. `DispatchVoiceAssignmentComparisonSelector`
  (`0xC004CC14-0xC004CC4F`) routes selectors 0..4 to five helpers: PCM-resource state comparison,
  active-record field comparison, mode-block header comparison, mode-block voice-record comparison,
  and global-selector comparison. The mode-block comparisons consistently use the `+0x800 + index*0x330`
  voice-record region and the header offsets documented above; selector-to-offset mappings are recorded
  in the Ghidra comments, but product-level field names remain unresolved.
 - Higher-level uses are also bounded: the function-table wrappers at `0xC007D094`, `0xC007BDFC`, and
   `0xC007A870` dispatch selectors 1, 2, and 3 respectively. `UpdateVoiceTaskType26ComparisonState`
   (`0xC008BBE0-0xC008BC1F`) dispatches selector 4 before Type-0x26 command handling and stores the
   result at its child `+0x48`. Two LCD callsites (`0xC008A2AC` and `0xC008A46C`) dispatch the
   caller-supplied selector and draw a bitmap notification only when the result changes; the selector and
   UI meanings remain unresolved.
 - All five selector paths share the same lazily initialized four-byte context at `0xC0691320`.
   `GetVoiceAssignmentComparisonContext` (`0xC008A12C-0xC008A15B`) allocates and initializes it for the
   selector-0 LCD paths, while the selector-1..4 wrappers perform the equivalent check directly. The common
   initializer `InitializeVoiceAssignmentComparisonContext` (`0xC004C48C-0xC004C497`) stores the pointer
   `0xC00CFE50` into that allocation. The pointed-to data contains code pointers `0xC004C42C` and
   `0xC004C44C`, the little-endian tag `GLST`, size-like value `0x100`, and a zero word; internal
   descriptor/object meanings remain unresolved.
- `VoiceTask_ApplyAssignmentRecord` (`0xC00667D4`) and its bounded variant
  `VoiceTask_ApplyAssignmentRecordVariant` (`0xC0066A94`) resolve source and
  target records, clear the target voice and any linked DSP/slot state, copy the
  selected `0x330`-byte record, update the compact `0x24`-byte record and
  oscillator metadata, request slot reassignment, and rebuild the target voice.
  `CopyVoiceAssignmentFieldsToCompactRecord` (`0xC004B0E0`) confirms the compact
  copy from source offsets `+0x800`, `+0x808..+0x826` into destination offsets
  `+0x16..+0x38`. The transition object context is now bounded: `+0x40` is
  the source table/mode selector captured from the current service mode, `+0x41`
  is the normalized source index, and `+0x42` is the destination voice index.
   `ProcessVoiceTaskCopyPartAssignmentTransition` (`0xC0066DB0`) captures these indices
  while moving through its state field `+0x2C`; states 10 and 11 select the
  full and variant apply paths. The full path explicitly calls
  `ReassignVoiceTaskSlotRecords`, while the variant performs only the partial
  record copy and voice rebuild. `InitializeVoiceTaskCopyPartAssignmentTransitionObject`
  (`0xC0067080`) initializes the context fields and their `0xFF` sentinels. Its vtable is now
  identified at `0xC00E36A0` as `g_vtVoiceTaskServiceSubobjectType16CopyPartUi`; the observed
   entries point to copy-part UI destruction, deletion, input normalization, backward/forward
   selection, confirmation, selection-index adjustment, and assignment-transition processing.
   `ApplyVoiceAssignmentControlRecordFields` (`0xC0049F7C`) reads the selected record's
   `+0x800` payload and forwards its observed control fields through the setter family,
   optionally dispatching and merging pending linked-control records. The transition then
   copies three correlated per-voice tables: `CopyVoiceOscillatorMetadataTriplets`
   (`0xC009A2F0`) copies a complete `0xBB5`-byte metadata-triplet table,
   `CopyVoiceProfileBytePairCacheRecord` (`0xC0099504`) copies a `0x90`-byte cache record,
   and `CopyVoiceControlRecord` (`0xC0098104`) copies a `0x31`-byte control record.
   These are confirmed state-propagation operations; their field meanings remain unresolved.
  The neighboring type-`0x03` Part Utility service uses vtable `0xC00E36E8`; its lifecycle methods
  are `0xC0067234-0xC006724F` and `0xC0067254-0xC006726F`. The vtable entries route to the already
  identified selector movement, clear-MFX-motion, control adjustment, and command-to-state callbacks.
- The transition object is driven by a distinct copy-part UI state machine.
  `UpdateVoiceTaskCopyPartUiState` (`0xC006634C`) selects the observed UI branches
  for `COPY PART`, `Select Pattern`, `Select Destination`, `COPY PART SOUND`,
  `Select Source Part`, `CLEAR SEQUENCE`, and `CLEAR MOTION`; its state field is
  `+0x2C`, with the saved global state at `+0x38` and ready flag at `+0x34`.
  `MoveVoiceTaskCopyPartSelectionBackward` (`0xC00665B4`) and
  `MoveVoiceTaskCopyPartSelectionForward` (`0xC0066608`) apply the state skip and
  wrap rules, while `NormalizeVoiceTaskCopyPartStateAfterInput` (`0xC0066728`)
  returns transient selection states to their base states and emits common message
  type `0x15` for unsupported combinations. `ConfirmVoiceTaskCopyPartSelection`
  (`0xC0066670`) dispatches the selected action. `BuildVoiceTaskCopyPartSelectionMessage`
  (`0xC00661C4`) formats selector `+0x40` and the selected mode-table label; the
  selector is adjusted by `AdjustVoiceTaskCopyPartSelectionIndex` (`0xC00662F0`),
  with the control-event `+0x358` flag selecting the observed step scale.
- The two destructive copy-part actions are now bounded. `ClearVoiceTaskSequenceDataForPart`
  (`0xC00661A4`) resets 64 subrecords in the selected `0x330`-byte assignment record,
  restoring each eight-byte payload at `+0x30 + step*0x0C`. `ClearVoiceTaskMotionDataForPart`
  (`0xC00660C8`) releases active CPU slot-assignment records whose primary key matches
  the selected part plus one. `DestroyVoiceTaskCopyPartUiObject` (`0xC0066128`)
  restores the saved global state before destroying the UI object; the numeric state
  names remain unresolved except where the firmware strings identify the action.
- A neighboring object is now identified as the Part Utility UI. `InitializeVoiceTaskServiceSubobjectType15PartUtility`
  (`0xC0066EE4`) installs the literal `PART UTILITY` title, the state-dependent
  `press [ Enter ]`/`cannot execute!` prompt, and the associated LCD/action helpers.
  `UpdateVoiceTaskPartUtilityUiState` (`0xC0067270`) renders its state at `+0x2C`,
  updates the selector and LCD prompt, and selects labels from the observed pool
  `B P M`, `LENGTH`, `PATTERN LEVEL`, `MFX TYPE`, `CLEAR MFX MOTION`, `BEAT`,
  `KEY`, `SC-14`, `ALTERNATE 15-16`, and `CHAIN TO`/`CHAIN REPEAT`. State 10
  additionally invokes the helper callback at `+0x24` with argument 1. These labels
  bound the UI surface, but the numeric state meanings and underlying operations
  remain unresolved.
- The Part Utility execution/input paths are now bounded. State 6 reaches
  `ExecuteVoiceTaskPartUtilityClearMfxMotion` (`0xC006754C`), which releases
  CPU slot-assignment records for key `0x11`, refreshes the associated control
  fields, re-dispatches special channels `0x13`, `0x0F`, and `0x10`, and marks
  the callback state updated. `AdjustVoiceTaskPartUtilityControlValue`
  (`0xC00675C4`) forwards a parameter adjustment through the shared control-event
  object, using the active-service flag to select the observed 1x/10x step scale.
  `SelectVoiceTaskPartUtilityStateFromCommand` (`0xC0067630`) maps external
  command values `0..5` to states `1`, `3`, `6`, `7`, `8`, and `10` when active.
  `MoveVoiceTaskPartUtilitySelectionBackward` (`0xC00677A8`) and
  `MoveVoiceTaskPartUtilitySelectionForward` (`0xC00677B0`) wrap the selector
  through states `0..14` when inactive. `InitializeVoiceTaskPartUtilitySelectionObject`
   (`0xC00677B8`) installs the Pattern label and registers the selector/UI children.
   The controlled parameter and numeric state meanings remain unresolved.
  - The Part Utility selector's `0x4C`-byte child is now bounded. `InitializeVoiceTaskPartUtilityTimingIndexChild`
    (`0xC0086648`) registers the child callback through `g_pVoiceTaskSharedControlObjectStorageRef`
    (`0xC008672C`), which points to the shared pointer storage `g_pVoiceTaskSharedControlObject`
    (`0xC0348870`), and stores the current selected VoiceTask timing-table index at child `+0x48`.
    Its callback, `RefreshVoiceTaskPartUtilityTimingIndexChildState` (`0xC0086624`), reads the same
    current index and sets child `+0x14` when it matches the stored target. Cross-references show the
    same shared object storage is also used by the command handler, global-state reset, copy-part
    selection, comparison, and other VoiceTask initialization paths; it is not Part Utility-exclusive.
    The child flags and product meaning of the timing-table index remain unresolved.
    - The generic listener mechanics behind the timing-index setter are now bounded.
    `NotifyVoiceTaskServiceListeners` (`0xC0048C6C`) builds a 12-byte payload with header bytes
    `0x08` and the supplied service object's `+0x33C` byte, the new value at `+0x04`, and the
    caller's third argument at `+0x08`. `NotifyVoiceTaskListenerRecords` (`0xC0070688`) walks
    32 active-capable `0x18`-byte records from owner `+0x08` through `+0x308`, while
    `InvokeVoiceTaskListenerCallback` (`0xC007061C`) decodes each record's callback metadata.
    `SetVoiceTaskListenerStateAndNotify` (`0xC006F36C-0xC006F380`) is an external wrapper
    that writes shared listener-state `+0x308` and notifies all active records;
    `NotifyVoiceTaskListenerState` (`0xC007822C-0xC0078237`) is the direct record walker.
    `RegisterVoiceTaskListener` (`0xC0070778`) fills those slots and links the callback descriptor
     into the owner's intrusive list; `UnregisterVoiceTaskListener` (`0xC00705DC`) clears the slot's
     active flag and callback fields. `AppendVoiceTaskListenerCallbackLink` (`0xC00706C8`) is the
     grow-and-append primitive for the owner's callback-link array. The B40 state setter passes its
     new `+0x308` value directly as the callback payload, while the separate service-notification
     path uses the 12-byte payload above. Instances of the generic control/listener object are initialized
     by `InitializeVoiceTaskGenericControlObject` (`0xC007D5A4`). The callback-record path at
    `DispatchVoiceTaskControlListenerNotification` (`0xC007CD54`) writes the record's value byte to
    the separate large DSP/control instance rooted at `0xC0691334` and then dispatches the owner's
    active listeners. The exact event relationship between the generic object instances and the
      VoiceTask service object remains unresolved.
    - The shared listener-state allocation path is now bounded. `GetOrCreateVoiceTaskListenerState`
      (`0xC00511B8`) lazily allocates the `0x30C`-byte object at pointer storage
      `g_pVoiceTaskListenerState` (`0xC03405C4`), and `InitializeVoiceTaskListenerState`
      (`0xC00781B4-0xC007821F`) installs its observed vtable/base pointers, clears 32 embedded
      `0x18`-byte listener records from `+0x08` through `+0x308`, and clears the terminal field.
      Cross-references show this object is shared by VoiceTask and command-handler paths; its
      product-level state meaning remains unresolved.
      The corresponding shared `0x330`-byte listener-client pointer storage is
      `g_pVoiceTaskBatteryMonitorClient` (`0xC03405C8`); the client is initialized by the same
      `InitializeVoiceTaskBatteryMonitorClient` path from multiple command handlers.
    - `InitializeVoiceTaskBatteryMonitorClient` (`0xC0077B4C-0xC0077D03`) initializes a separate
      listener client with its own 32-slot table and registers three callbacks against shared
      control/listener sources. `RefreshBatteryMonitorThresholdsFromChemistrySetting` (`0xC0077940`),
      `RefreshBatteryMonitorThresholdsFromModeEvent` (`0xC00779B4-0xC00779D3`), and
      `RefreshBatteryMonitorThresholdsFromSharedEvent` (`0xC00779D4-0xC00779EB`) update client
      state byte `+0x324` and conditionally snapshot the observed fixed values at
      `0xC00E4590/0xC00E4594` into `+0x318`. `UpdateVoiceTaskBatteryMonitorValidity`
      (`0xC00779EC-0xC0077A13`) maps shared state field `+0x308` into client `+0x31C` and clears
      `+0x32C`. These callbacks are used through the shared framework, not rate-only code; the
      event and state meanings remain unresolved.
    - The client-side input producer is now bounded. `SetBatteryMonitorMeasurement`
      (`0xC006EC88-0xC006ECC3`) lazily initializes `g_pVoiceTaskBatteryMonitorClient`, stores the input
      at client `+0x320`, and tail-dispatches `ClassifyBatteryMeasurementByChemistry`
      (`0xC0077A14-0xC0077B13`). The latter compares `+0x320` with four byte thresholds rooted at
      `+0x318`, updates state `+0x328` and latch `+0x32C`, emits common message `(0x1B,0x1A)` on
      the observed high-threshold transition while shared state `+0x308` is zero, and notifies
      active listeners. `UpdateVoiceTaskListenerGateAndIndicators` (`0xC00511EC`) consumes the
      shared/client states to derive a callback gate and drive the observed LCD/GPIO indicator
      path. Product-level state and indicator meanings remain unresolved.
    - A second listener owner is bounded by `InitializeVoiceTaskSharedControlListener`
      (`0xC0051214-0xC005131F`). It owns 32 records beginning at `+0x14`, creates or reuses the
      shared `0x118`-byte child at `g_pVoiceTaskSharedControlState` (`0xC033E6A0`), derives `+0x31C`
      from that child, mirrors shared listener-state `+0x308` into `+0x320`, and registers itself
      on the shared listener object. This is distinct from the `0x330` threshold client;
      product-level field meanings remain unresolved.
      `GetVoiceTaskSharedControlStateByte` (`0xC0047340`) is the confirmed accessor for child byte
      `+0x29`; the observed listener-owner path copies it into owner `+0x31C`.
   - The VoiceTask DSP/control subsystem is now bounded at its allocation and embedded-interface
    boundary. `GetOrCreateVoiceTaskDspControlObject` (`0xC00263E0-0xC002640F`) is the common lazy
    accessor: it allocates the `0x4274`-byte object through backing storage
    `g_pVoiceTaskDspControlObjectBacking` (`0xC033E6A4`) and initializes it through
    `InitializeVoiceTaskDspControlObject`. `GetOrCreateVoiceTaskDspControlSubsystem` (`0xC007DC9C`)
    publishes that same object through `g_pVoiceTaskDspControlObject` (`0xC0691334`) and initializes a parallel
    `0x30C`-byte listener/state object mirrored at `0xC0691338`. `InitializeVoiceTaskDspControlObject`
     (`0xC004A2A0`) constructs embedded subobjects at `+0x4004`, `+0x400C`, `+0x4014`, and `+0x401C`;
     the last is passed to `DspIf::applyCommand` by the confirmed field setters. The observed DSP-
     facing fields are `+0x26` (16-bit, command channel 0), `+0x2A` (byte, command `0x3B`), `+0x2E`
     (byte, command channel 1), `+0x48` (byte, command channel 7), and `+0x49` (byte, command
     channel 8). Their product-level names remain unresolved.
     The startup aliases at `0xC069132C` and `0xC069136C` also use the same backing storage
     `0xC033E6A4`; they are distinct published pointer slots, not proven separate allocations.
     `GetVoiceTaskDspControlField3B04` (`0xC004A3C8`) and `GetVoiceTaskDspControlField3B06`
     (`0xC004A3D8`) read the shared object's offsets `+0x3B04` and `+0x3B06`; their current-object
     wrappers are `0xC0079904` and `0xC0079914`, consumed by the type-01 primary-child refresh.
     `ClearVoiceTaskSharedListenerRegistrationByOwner` (`0xC0082788-0xC00827BF`) clears one owner
     registration in the shared `0x388`-byte listener service and is reused by type-01, type-17,
     and type-18 paths.
   - Additional startup-table entries expose several shared-object pointer caches without proving
     that they are duplicate owners. `InitializeVoiceTaskCoreObjectPointerCache`
     (`0xC00705A4-0xC00705CF`, slot `0xC00F89BC`) publishes the VoiceTask service, Part-selection
     control, and shared `0x314`-byte state pointers at `0xC06912E0`, `0xC06912E8`, and
     `0xC0348864`. `InitializeVoiceTaskSharedRecordCaches` (`0xC0079338-0xC007939F`, slot
     `0xC00F89C0`) creates a `0x43C` object through `InitializeVoiceTaskSharedRecordContainer43C`
     and a `0x308` object through `FUN_c0040CE4`, publishing them at `0xC0691310` and
     `0xC069130C`; their record/control ownership remains unresolved. The `0x43C` object's static
     vtable is `g_vtVoiceTaskSharedRecordContainer43C` at `0xC00C5BE0`, its backing pointer
     storage is `0xC0348844`, and its lifecycle pair is `ReleaseVoiceTaskSharedRecordContainer43C`
     (`0xC0041BE0-0xC0041C1F`) plus `DestroyVoiceTaskSharedRecordContainer43C`
     (`0xC0041C3C-0xC0041C57`). Both this container and the `0x428` state object begin with the
     common listener-record-array vtable `g_vtVoiceTaskListenerRecordArray308` at `0xC00A7658`;
     `InitializeVoiceTaskListenerRecordArray308` (`0xC0040B94-0xC0040BDF`) clears its `0x18`-byte
     stride records through `+0x304`. `UpdateVoiceTaskSharedRecordValue` (`0xC00423A0-0xC00426A7`)
     is the indexed update path for the `0x43C` container: it applies the state/service guards,
     derives the indexed value from the container mode at `+0x318`, stores the per-index result at
     the `+0x31C` stride area, performs the associated control/assignment side effects, and emits
     listener/common-message notifications. Numeric and product meanings remain unresolved. The
     converter family used by its mode dispatch is now bounded: `ConvertVoiceTaskSharedRecordValueDirect`
     (`0xC0041E64-0xC0041EAB`) performs direct table conversion; `ConvertVoiceTaskSharedRecordValueBounded`
     (`0xC0041F84-0xC0042093`) maintains the mode-1 reference/validity window; and
     `ConvertVoiceTaskSharedRecordValueRange` (`0xC00420A4-0xC0042383`) handles mode-2 bounds,
     endpoint clamping, and range/interpolation updates. Numeric and product meanings remain
     unresolved. The
     three paths share the 13-entry table `g_aVoiceTaskSharedRecordValueConverters` at
     `0xC00C5C24` (pointer references at `0xC0041EAC`, `0xC0042094`, and `0xC0042384`). Its
      observed entries are arithmetic right-shift converters except for clamped indices `1`, `4`,
      and `0x0B`; index `2` additionally checks current part/profile state. Product meanings remain
      unresolved. The
      mode-2 range path also calls a separate CPU software IEEE-754 single-precision runtime cluster:
      `SoftFloat_FromInt32` (`0xC0003050-0xC000312B`), `SoftFloat_Multiply` (`0xC000312C-0xC00032C3`),
      `SoftFloat_Divide` (`0xC00032C4-0xC0003423`), `SoftFloat_Add` (`0xC0002E8C-0xC0003047`),
      `SoftFloat_Subtract` (`0xC0002E88-0xC0002E8B`), and `SoftFloat_ToInt32`
      (`0xC0003538-0xC0003593`). Their bit-level handling confirms IEEE-754 single-precision
      arithmetic and integer conversion; the compare/status wrappers around `0xC0003434-0xC00034BF`
      remain unresolved. Product-level meanings of the converted values remain unresolved. The
      mode-2 bounds are backed by 13-entry halfword tables at `0xC00C5B68` (signed lower bounds)
      and `0xC00C5C08` (upper bounds). The observed upper entries are `0x3F` for indices `1`, `4`,
      and `0x0B`, `0x7F` for the other active indices, and zero at index `3`; the shared path also
      uses `0x42FE0000`/`0xC2FE0000` (`127.0`/`-127.0`) as single-precision interpolation endpoints.
      Constants `0x414` and `0x412` at `0xC0042388` and `0xC004238C` are written for indices `0x0B`
      and `0x0C`, respectively. Product meanings remain unresolved. The
      setup path stores its mode through `SetVoiceTaskSharedRecordMode` (`0xC0041E10-0xC0041E2B`)
     and refreshes the selected-part cache through `RefreshVoiceTaskSharedRecordPartFields`
     (`0xC0041E04-0xC0041E0F`), covering the observed `+0x3C4..+0x3F4` fields and
     `+0x418..+0x433` validity markers. Product meanings remain unresolved. The
     other recurring constructor family,
     `InitializeVoiceTaskStateObject428` (`0xC008241C-0xC0082497`), is reached with allocation size
     `0x428` by the control-event, service-state, PCM, and shared-control paths. It installs common
     vtable `g_vtVoiceTaskStateObject428` at `0xC00E4AE0`, clears the embedded `0x304`-byte
     record/list area, and initializes the trailing state fields; its lifecycle pair is
     `ResetVoiceTaskStateObject428` (`0xC0082394-0xC00823A7`) and
     `DestroyVoiceTaskStateObject428` (`0xC00823C8-0xC00823EB`). Product-level state meanings
     remain unresolved. `InitializeVoiceTaskSharedControlStatePointer`
     (`0xC007B8EC-0xC007B923`, slot `0xC00F89C4`) publishes the `0x118`-byte state initialized
     through `FUN_c0047170` at `0xC0691324`, which is consumed by the broad control-byte descriptor
     family. `InitializeVoiceTaskDspControlObjectPointerCache` (`0xC007CB20-0xC007CB57`, slot
     `0xC00F89C8`) publishes another `0x4274`-byte DSP-control pointer at `0xC069132C`.
     `InitializeVoiceTaskDspControlAndAuxiliaryStateCaches` (`0xC0080E38-0xC0080E9F`, slot
     `0xC00F89D4`) publishes a `0x4274`-byte DSP-control pointer at `0xC069136C` and a distinct
     `0x350`-byte state initialized by `FUN_c008179C` at `0xC0691368`. The relationships among
     these parallel DSP/control aliases remain unresolved.
     `InitializeVoiceTaskGlobalSelectorObjectPointerCache` (`0xC008017C-0xC00801B3`, slot
     `0xC00F89D0`) creates another `0x4EC`-byte object through `FUN_c007AC94` and publishes it at
     `0xC0691360`. The constructor is also used by the Global-selection backing path and by
     selector-index control paths, but the relationship between this instance and the separately
     published Global-selection backing object remains unresolved.
   - `GetVoiceTaskDspControlField26` (`0xC004A3E8`) is the exact 16-bit accessor for the
     DSP/control field at `+0x26`. The shared timing update path compares its returned
     value with the newly derived timing result before dispatching a listener
     notification; this connects the shared timing record to the command-channel-0
     control state without establishing the product-level field meaning.
  - The relevant `applyCommand` jump-table cases are now connected to concrete CPU behavior.
    `HandleApplyCommand0x01` (`0xC004B340`) stores the incoming byte at receiver `+0x256`, maps
    its inverted 7-bit value through `0xC0093EAC`, and sends the resulting payload with
    `DspIf_SendHostCommand5Words` (`0xC0011F54`) under DSP mutex 1. That builder emits a five-
    halfword Host-DMA packet beginning with header `0x0106`. `HandleApplyCommand0x3B`
    (`0xC004B32C`) refreshes sliced-playback index maps for all 16 voices whose oscillator-resource
    mode is 1. `HandleApplyCommand0x07` and `0x08` write the embedded receiver bytes `+0x0C` and
    `+0x0D`; `HandleApplyCommand0x00` updates the observed timing/voice-record path. The exact
    product meanings of these command IDs remain unresolved.
  - The `HandleApplyCommand0x00` rate path is now bounded. Its merged body region at `0xC00975B0`
    clamps the scalar to the observed range `100..3000`, stores it at `g_voiceTaskRateScalarClamped`
    (`0xC0691518`), derives a product with constant `0x1BF6` at `0xC06914F4`, refreshes all 16
    voice records through `RefreshVoiceTaskVoiceRateDerivedValue` (`0xC0096688`), and then updates
    33 records at `g_aVoiceTaskRateRecords` (`0xC0346830`) with stride `0x7C`. The final record
    value is bounded to `2000..30000`, and `MarkVoiceTaskRateRecordPending` (`0xC003E63C`) sets
    byte `+0x02` in the selected 0x18-byte rate record. The fixed-point scale table at
     `0xC00E8C00` contains the observed sequence `0x80, 0x100, 0x200, 0x400, 0x555`, through
     `0x10000`, indexed 0..16. These are confirmed data-flow facts; the product names and units
     remain unresolved.
   - `AdvanceVoiceTaskActiveRateAccumulators` (`0xC0097404`) is the next observed consumer of this
     state. It walks even voice indices `0,2,...,14`, skips inactive voices, selects a profile-
     dependent increment, advances the 0x18-byte per-channel accumulator, and on wrap refreshes
     halfwords `+0x08/+0x0A`. It then sets voice fields `+0x8E/+0x8F`; their product meaning is
     unresolved. The profile records used by this path are 9-byte entries rooted at
     `g_aVoiceTaskVoiceRateProfileRecords` (`0xC06924DD`), indexed by voice field `+0x31`.
     With the alternate profile flag clear, profile byte `+0x00` selects the increment table at
     `g_aVoiceTaskProfileByte0Increments` (`0xC00E8D24`). With that flag set, profile byte `+0x01`
     selects the interval table at `g_aVoiceTaskProfileByte1Intervals` (`0xC00E8F24`) and drives
     the accumulator-delta calculation. On initialization and accumulator wrap, both the oscillator
     assignment path and this active-voice path call `AdvanceVoiceTaskPhaseState` (`0xC009629C`),
     which updates the shared 16-bit state `g_wVoiceTaskPhaseState` (`0xC069169C`). The exact
     phase/randomization semantics remain unresolved.
   - The runtime scheduler boundary is now bounded by `ProcessVoiceTaskRateSchedulerTick`
     (`0xC009B58C`). It calls the broader voice-state refresh first, toggles a scheduler phase, and
     on alternating phases either decrements 8-byte expiry records rooted at
     `g_aVoiceTaskRateExpiryRecords` (`0xC06921E4`) or advances one even-indexed active voice. A
     bit that reaches zero moves from `g_dwVoiceTaskRatePendingMask` (`0xC0692264`) to
      `g_dwVoiceTaskRateExpiredMask` (`0xC06921E0`). The phase byte and even-voice selector are
      stored at `g_bVoiceTaskRateTickParity` (`0xC069FEF4`) and
      `g_bVoiceTaskRateVoicePairIndex` (`0xC069FEF8`).
     - The rate-component aggregation boundary is now explicit. `AccumulateAndDispatchVoiceTaskRateComponents`
       (`0xC009B3E0`) clears eleven accumulators at `g_aVoiceTaskRateComponentAccumulators`
      (`0xC069FEC8`), evaluates six profile/input components, accumulates fixed-point contributions by
      component index, and dispatches the eleven results through `g_aVoiceTaskRateComponentCallbacks`
      (`0xC00E98B8`). The callback table writes the observed voice fields `+0x94`, `+0x9C`, `+0xA0`,
      `+0xA4`, `+0xA6`, `+0xA8`, `+0xAA`, `+0xAC`, `+0xAE`, and `+0xB0`; selected changes also refresh
      dependent voice/DSP state. The callback indices and dataflow are confirmed, while their product
      meanings and fixed-point units remain unresolved.
      Its six inputs are now bounded: `GetVoiceTaskRateComponentInputByte`
      (`0xC0098F50`) reads profile-record bytes `+0x03..+0x08`, while
      `GetVoiceTaskRateComponentMode` (`0xC0098F10`) and
      `GetVoiceTaskRateComponentCurveType` (`0xC0098F30`) read paired six-entry mode/type bytes from
       the selected oscillator/profile record. These fields select the observed transforms; their
       product meanings remain unresolved.
     - The deferred VoiceTask rate-refresh chain is now bounded. After VoiceTask receives its update
       event, `ProcessVoiceTaskPendingAndRateState` (`0xC009B568-0xC009B58B`), called from
       `VoiceTask::taskProc`, performs pending voice/lifecycle and oscillator-slot housekeeping and
       tail-dispatches `ProcessVoiceTaskRateRefreshFlags` (`0xC00990CC-0xC009913F`). The latter
       scans all 16 voice records: byte `+0x8E` requests `RebuildVoiceTaskRateComponentsForVoice`
       (`0xC00990A0-0xC00990CB`), while a simultaneous `+0x8F/+0x90` pair requests the pending
       timbre-rate update for an active voice and is then cleared under IRQ masking. The flag and
       rate-field product meanings remain unresolved.
      `InitializeVoiceTaskRateProfileDerivedState` (`0xC0099088-0xC009909F`) initializes the
      six component bytes and then tail-dispatches `UpdateVoiceTaskRateProfileDerivedBytes`
      (`0xC0098FEC-0xC0099083`); `BuildVoiceTaskRateProfileComponentBytes`
      (`0xC0098F78-0xC0098FE7`) supplies those six bytes from paired profile values. These are
      profile-derived CPU-side state updates, not direct DSP or peripheral accesses.
      The lower rate-state helpers are now separated by their actual input paths. `ComputeVoiceTaskRateSlot0BaseInput`
      (`0xC0095F80`) adds nested profile byte `+0x14` to voice halfword `+0xAA`, while
      `SelectVoiceTaskRateSlot1BaseInput` (`0xC009664C`) uses the same clamped value or constant `2`
      when voice byte `+0x8A` is clear. `ComputeVoiceTaskRateSlot0DerivedInput` (`0xC0095FA8`)
      and `SelectVoiceTaskRateSlot1DerivedInput` (`0xC0096664`) add nested profile byte `+0x15`
      to voice halfword `+0xAC`; the latter suppresses the result to zero when both voice bytes
      `+0x8A` and `+0x38` are clear. `ComputeVoiceTaskRateProfileInput` (`0xC0095FD0`) is the
      shared `+0x15/+0xAC` calculation used by `SelectVoiceTaskRateStateInput` for mode 0 and its
      alternate mode-1 path. `RefreshVoiceTaskRateSlotMappedValue` (`0xC0096AA4`) maps the selected
      input into slot `+0x48`, and during the state-3 transition also mirrors slot `+0x50` into
      `+0x4C/+0x4E` and records the transition boolean at the slot base. The two slots are initialized
      by `InitializeVoiceTaskRateSlot0State` (`0xC0096E78`) and `InitializeVoiceTaskRateSlot1State`
      (`0xC0096E9C`); `InitializeVoiceTaskProfileRateState` (`0xC0096EDC`) initializes the adjacent
      profile-rate record. `ProcessVoiceTaskPerVoiceRateStateFlags` (`0xC0097054`) scans all sixteen
      voices and consumes the shared transition flags, while `InitializeVoiceTaskPerVoiceRateState`
      (`0xC00973D0`) seeds the complete per-voice rate/interpolation state. The field units and
      product meanings remain unresolved.
      The common interpolation engine is `AdvanceVoiceTaskInterpolatedState` (`0xC00963F0-0xC009646B`):
      it advances a 24-bit accumulator in a 0x18-byte state record, recomputes the interpolated
      halfword from the record's endpoint halfwords, and calls a callback when the accumulator wraps.
      The state callback table at `0xC00E8F68` is indexed by voice byte `+0x54` and maps states
      `0`, `1`, and `3` to `AdvanceVoiceTaskRateSlot0State0` (`0xC0096598`),
      `AdvanceVoiceTaskRateSlot0State1` (`0xC0096554`), and `AdvanceVoiceTaskRateSlot0State3`
      (`0xC0096510`), respectively. The table at `0xC00E8BE0` is indexed by voice byte `+0x6C`;
      its observed entries are state 0 at `0xC00964A8`, state 1 at `0xC00968A4`, state 3 at
      `0xC0096470`, state 4 at `0xC00963A8`, and state 5 at `0xC0096060`. The profile-rate callback
      table at `0xC00E8D04` begins with `AdvanceVoiceTaskProfileRateState0` (`0xC00965F8`) and
      shares the state-1/state-3 callbacks above. Several callbacks contain indirect continuation
      dispatches that Ghidra cannot recover as jump tables; the observed table indices and state
      field accesses are confirmed, while their product meanings remain unresolved.
      The adjacent profile-derived scalar path is also bounded: `GetVoiceTaskProfileShapingMode`
       (`0xC0098E84`) reads profile byte `+0x18`; `ComputeVoiceTaskProfileDerivedRateValue`
       (`0xC009735C-0xC00973C3`) maps it through `g_aVoiceTaskProfileShapingModeMap`
       (`0xC00E8570`) and `g_aVoiceTaskProfileShapingCallbacks` (`0xC00E8578`), invokes the
       selected fixed-point shaping routine, and stores its signed result at voice field `+0x8C`.
        `InterpolateVoiceTaskProfileValue` (`0xC0098D44-0xC0098DE3`) performs the bounded endpoint
        interpolation, while `ConvertVoiceTaskProfilePairToComponent` (`0xC0098DE4-0xC0098E47`)
        prepares signed profile pairs for it. The callback shapes and field product meaning remain
        unresolved.
        The callback implementations are now bounded without assigning product names: 
        `ApplyVoiceTaskProfileLookupShape` (`0xC00960E8-0xC009614F`) applies the observed lookup
        curve at `0xC00E8C80` to a folded fixed-point input and centers the result;
        `EvaluateVoiceTaskProfileThresholdGate` (`0xC0096090-0xC00960AB`) and its signed companion
        (`0xC00960B0-0xC00960D7`) select `0x7FFF` or zero around the threshold
        `0x8000 + factor*0x200`; `ApplyVoiceTaskProfileTriangleShape` (`0xC00961F8-0xC0096243`)
        performs the centered triangle-like transform; and
        `ApplyVoiceTaskProfileSineShape` (`0xC00969C4-0xC0096A6B`) builds a signed full-cycle value
        from `InterpolateVoiceTaskSineTable` (`0xC0096244-0xC0096293`) and can apply a nonlinear
        transfer. `InterpolateVoiceTaskProfileRecordEndpoints` (`0xC0096158-0xC00961F3`) selects
        or interpolates the profile record halfwords at `+0x08/+0x0A`; it is used for both ordinary
        and factor-`0x3F` entries. The mode-map index-7 callback is an unconditional zero return
        (`ReturnZeroVoiceTaskProfileShape`, `0xC00960E0`), but the observed mode map does not select
        it. The exact shape units and field meanings remain unresolved.
      - The pending-record producers are also bounded. `PopulateVoiceTaskRateRecordFromSource`
     (`0xC003EB78`) copies each 0x72-byte source record from `g_aVoiceTaskRateSourceRecords`
     (`0xC03478A8`) into a 0x7C-byte runtime record in `g_aVoiceTaskRateRecords` and marks the
     mapped 0x18-byte record in `g_aVoiceTaskRatePendingRecords` (`0xC00F934C`).
     `EvaluateVoiceTaskRateRecordBitChanges` (`0xC003EE84`) performs the corresponding encoded
     bitfield test and marks the same pending-record flag. The 33-to-18 index mapping is confirmed;
     the encoded field and event meanings remain unresolved.
   - The lower-level rate source helper, `UpdateVoiceTaskTimerRateSource` (`0xC002B95C`), stores
     the requested 16-bit value, accepts only `2000..30000`, mirrors it at timer-state `+0x2C`,
     and computes a period-like 64-bit value from the fixed constant at `0xC002BAD4` under
     interrupt masking. `CheckVoiceTaskTimerRateUpdateGate` (`0xC002B914`) initializes the related
     `0x118`-byte state object and gates updates using its observed state fields. The timer units
     and relationship to the higher-level scalar remain unresolved.
    - The previously merged rate/timer region is now split into confirmed routines. `ApplyVoiceTaskRateAcrossVoices`
      (`0xC002B988-0xC002B9AF`) forwards a tenfold rate to the lower-level helper, clamps the shared
      scalar beginning at `100`, refreshes all 16 voice-derived values, and updates 33 stride-`0x7C`
      records. `RefreshVoiceTaskRateFromBackingState` (`0xC002B9B0-0xC002B9EF`) lazily allocates a
      `0x320`-byte backing object at pointer storage `g_pVoiceTaskRateBackingState` (`0xC034036C`)
      and reapplies its field `+0x318` through that routine. `InitializeVoiceTaskTimerRateSourceState`
      (`0xC002B9F4-0xC002B9FB`) is the static initializer for `g_voiceTaskTimerRateSource`
      (`0xC0340370`). The backing object's product role remains unresolved.
    - The backing-state lifecycle is now connected to the DSP/control path. `GetOrCreateVoiceTaskRateBackingState`
      (`0xC004A7D8`) allocates the shared `0x320`-byte object at `0xC034036C` and calls
      `InitializeVoiceTaskRateBackingState` (`0xC0077F3C-0xC0078103`). The initializer
      clears its internal fields, snapshots DSP/control field `+0x26` into backing field
      `+0x318`, derives the adjacent `+0x31C` state byte, registers listeners, and creates
      the associated `0x30C`-byte listener state. This is the same backing object read by
      `RefreshVoiceTaskRateFromBackingState`; listener roles and rate units remain unresolved.
    - The backing object's callback methods are now bounded. Its primary event callback,
      `UpdateVoiceTaskRateBackingStateFromEvent` (`0xC0077DEC-0xC0077E33`), accepts
      only event type `4`, copies event byte `+0x01` into backing `+0x31C`, and
      snapshots DSP/control field `+0x26` into `+0x318` on transition to state `1`.
      `RefreshVoiceTaskRateBackingStateFromControlDescriptor`
      (`0xC0077E44-0xC0077EAF`) and `RefreshVoiceTaskRateBackingStateFromControlCallback`
      (`0xC0077EB0-0xC0077F07`) perform the same transition/snapshot operation using
      the observed control-byte descriptor path. `BuildVoiceTaskListenerDescriptor`
      (`0xC0077F08-0xC0077F3B`) writes the three-word registration descriptor; the
      nested byte descriptor is produced by `BuildVoiceTaskControlByteDescriptor`
      (`0xC007B574-0xC007B5A3`) and `AllocateVoiceTaskByteDescriptor`
      (`0xC007B4D8-0xC007B507`). The callback/event meanings remain unresolved.
   - The common rate tail is now separated from the object-specific wrappers. `ApplyVoiceTaskRateRefreshCore`
     (`0xC00975A8-0xC009760F`) clamps the shared scalar, refreshes all 16 voice-derived values, and
     tail-dispatches `ApplyVoiceTaskRateToRecords` (`0xC003EFEC-0xC003F043`), which clamps the final
     value, updates 33 stride-`0x7C` records, and marks their mapped records pending. The command-level
     and product-level rate meanings remain unresolved.
   - `InitializeVoiceTaskTimerRecord` (`0xC002BA00-0xC002BA43`) initializes one timer record's
     deadline/current snapshots and active byte. `InitializeGlobalVoiceTaskTimerRecord`
     (`0xC002BCD0-0xC002BCD7`) is its global-pointer wrapper. `CommitVoiceTaskTimerRate`
     (`0xC002BA7C-0xC002BACB`) is the lower-level bounded period commit used by the source helper;
     the period units remain unresolved.
 - The Part Utility selector's shared backing object is now bounded. `g_pVoiceTaskSharedSelectorObject`
   at `0xC0691260` points to an object whose byte `+0x480` is read/written by
   `GetVoiceTaskSharedSelectorState` (`0xC007D3B8`) and
   `SetVoiceTaskSharedSelectorStateAndNotify` (`0xC007D3C0`); updates notify active
   `0x18`-byte listeners. `ForwardVoiceTaskSharedSelectorEvent` (`0xC007D4FC`) maps
   selector values `<15` through `g_aVoiceTaskSharedSelectorEventMap` (`0xC00E49A8`),
   with mapping `[0,1,3,2,8,9,0x45,4,5,6,7,0x0C,0x0D,0x0E,0x0F,0]` and suppression
  of mapped event `0x45`. `GetOrCreateVoiceTaskPartUtilityControlObject`
  (`0xC006758C`) separately returns the lazily-created control object used by the
  Part Utility action paths. The startup-function-table entry
  `InitializeVoiceTaskPartUtilitySharedSelectorPointer` (`0xC0067984-0xC0067997`, table
  slot `0xC00F89B0`) obtains that control object and stores its returned pointer at
  `0xC0691260`; the relationship between this pointer slot and the separately named
  control storage remains structurally unresolved. The controlled parameter semantics
  remain unresolved.
 - The transition's surrounding state sources are now bounded. `GetVoiceTaskServiceModeSelector`
  (`0xC00818D8`) returns the VoiceTask service object's `+0x318` value used as the
  mode-table/source selector. `GetOrCreateVoiceTaskControlEventStateObject`
  (`0xC0040F04`) lazily creates the central control-event state object; its
  `+0x358` flag gates the active-service branch of the assignment transition and
  related control-event paths. `GetOrCreateVoiceTaskGlobalStateObject`
  (`0xC0044C00`) creates the separate `0x310`-byte global-state object, whose
  `+0x308` field is read by the transition and control dispatcher. State changes
  go through `SetVoiceTaskGlobalStateAndNotify` (`0xC0060A70`), which updates
  `+0x308` and notifies registered `0x18`-byte listener records. The numeric state
  meanings remain unresolved beyond the observed transition use of 10 and 11.
- The assignment transition's CPU-side allocator is separate from the ARM
  oscillator-slot records. `g_aVoiceTaskSlotAssignmentRecords` at
  `0xC068DB0C` and `g_aVoiceTaskSlotRuntimeRecords` at `0xC068DE78` are each
  24 entries with `0x24`-byte stride; `g_aVoiceTaskSlotAssignmentIndexMap` at
  `0xC068DE70` is a cleared `0x5A0`-byte key-pair map whose entries contain a
  slot-record index or `-1`. `InitializeVoiceTaskSlotAssignmentTables`
  (`0xC0058EAC`) seeds these tables from service-side key fields.
- `AllocateVoiceTaskSlotAssignmentRecord` (`0xC0059720`) resolves or allocates
  a record for a key pair, installs the map entry, initializes the associated
  service-side payload, and forwards the managed value through
  `ForwardVoiceTaskSlotControlUpdate` (`0xC0058B98`).
  `ReleaseVoiceTaskSlotAssignmentRecord` (`0xC0058BD4`) performs the inverse
  cleanup, while `ReleaseVoiceTaskSlotAssignmentsForKey` (`0xC0058CA8`) walks
  all 24 records for one primary key. `ReassignVoiceTaskSlotRecords`
  (`0xC0058FB0`) moves records between assignment keys while preserving the
  secondary key and 64-byte service payload. These are CPU VoiceTask records;
  they must not be conflated with `g_aArmOscillatorVoiceSlots` at `0xC06916A0`,
  whose stride is `0x48` and whose records directly own BF523 oscillator slots.
- The sequencer drives a separate update layer over the CPU slot records.
  `UpdateVoiceTaskSlotRecordsForSequencerStep` (`0xC00591C8`) matches active
  records for one part/step, reads their service-side 64-byte payloads, sets
  current/target values and an interval, and forwards immediate changes.
  `AdvanceVoiceTaskSlotRecordValues` (`0xC0059514`) interpolates eligible
  records by a tick delta and forwards changed values, while
  `FlushVoiceTaskSlotRecordUpdates` (`0xC0059678`) forwards valid pending values
  and marks the records delivered. `ResetVoiceTaskSlotRuntimeTables`
  (`0xC0058A84`), `MarkVoiceTaskSlotRecordUpdatesReady` (`0xC0058A48`), and
  `DecrementVoiceTaskSlotRecordCounters` (`0xC0058AC4`) provide the table-wide
  reset/status/counter transitions. The record status bytes, interval, and
  value fields are structurally bounded but retain unresolved musical meanings.
  `ProcessVoiceTaskSlotRecordReadyUpdates` (`0xC00589EC`) scans all 24 records
  for active entries in pending state 1, and
  `CommitVoiceTaskSlotAssignmentRecordUpdate` (`0xC0058970`) increments the
  selected record's managed value, changes its status to 2, and can capture the
  update in shared VoiceTask state under additional sequence/control gates.
  `IsVoiceTaskAssignmentControlEnabled` (`0xC005D908`) exposes the shared
  assignment-control gate at `0xC06900A4`.
- Two special assignment-key channels are now bounded without assigning feature
  names. Key `0x11` has two small mirror-update wrappers:
  `UpdateVoiceTaskSpecialState11ForPart` (`0xC00583BC-0xC00583EF`) and
  `FlushVoiceTaskSpecialState11ForPart` (`0xC0058434-0xC0058467`). Both
  tail-dispatch to `PublishVoiceTaskSpecialState11` (`0xC0087FAC-0xC0087FD3`),
  which restricts publication to the selected part, updates shared fields
  `+0xD6`/`+0x914`, and queues a five-byte record with subtype `0x11` when the
  queue gate permits. Key `0x12` follows the parallel bounded wrappers
  `UpdateVoiceTaskSpecialState12ForPart` (`0xC00583F8-0xC005842B`) and
  `FlushVoiceTaskSpecialState12ForPart` (`0xC0058474-0xC00584A7`), which
  tail-dispatch to `PublishVoiceTaskSpecialState12` (`0xC0087F80-0xC0087FA7`)
  using shared fields `+0xC6`/`+0x904` and subtype `0x0F`. Both channels only
  emit for the selected part and suppress duplicate or busy updates. The
  associated mirrors are labeled `g_abVoiceTaskSpecialState11Applied`
  (`0xC068D0AE`), `g_abVoiceTaskSpecialState11Target` (`0xC068D0CE`),
  `g_abVoiceTaskSpecialState12Applied` (`0xC068D09E`), and
  `g_abVoiceTaskSpecialState12Target` (`0xC068D0BE`).
- The allocation-time callback helpers are also bounded as
  `DispatchVoiceTaskSpecialCallback0F` (`0xC0057B98`),
  `DispatchVoiceTaskSpecialCallback10` (`0xC0057BE0`), and
  `DispatchVoiceTaskSpecialCallback13` (`0xC0057C28`). They select callback
  fields from the active table index, suppress duplicate values where observed,
  and invoke the selected callbacks. The table is now identified as
  `g_aVoiceTaskSpecialCallbackProfiles` (`0xC00E1EE8`), a static four-row table
  with 0x10-byte rows. The first word is the profile key; row 0 is empty, and
  rows 1, 2, and 3 select profile-13 handlers
  `ApplySpecialCallback13Profile1ToAllArmVoiceSlots` (`0xC0057B70`),
  `ApplySpecialCallback13Profile2ToAllArmVoiceSlots` (`0xC0057B40`), and
  `ApplySpecialCallback13Profile3ToAllArmVoiceSlots` (`0xC0057B14`). The row
  `+0x04/+0x08/+0x0C` fields are selected by channels `0x13/0x0F/0x10`;
  the observed 0x0F/0x10 callbacks in profiles 1..3 are empty functions.
  `SelectVoiceTaskSpecialCallbackProfile` (`0xC0057C70`) resolves the incoming
  profile key, treats key `9` as the row-0 fallback, clears the boolean state,
  and re-dispatches the stored channel values for a nonzero row. The selected
  row index and cached channel states are labeled at `0xC068D078`,
  `0xC068D06C`, `0xC068D070`, and `0xC068D074`; product-level meanings of the
  profile keys remain unresolved.
- The control-field fan-out callers are also bounded. `UpdateVoiceTaskControlField40AndSpecialCallbacks`
  (`0xC00488A0`) writes control field `+0x40`, issues DSP command `2`, and
  dispatches channels `0x0F/0x10/0x13`; `UpdateVoiceTaskControlField41AndSpecialCallbacks`
  (`0xC0048A64`) writes `+0x41`, issues DSP command `3`, and conditionally
  dispatches the same channels plus the active profile's boolean callback.
  `UpdateVoiceTaskControlField42AndApplyDsp4` (`0xC0048924`) and
  `UpdateVoiceTaskControlField43AndApplyDsp5` (`0xC0048984`) write `+0x42`/`+0x43`
  and issue DSP commands `4`/`5`. `UpdateVoiceTaskControlField45AndApplyDsp6`
  (`0xC00489E4`) writes `+0x45` and issues command `6`; enabling it from zero
  first reapplies `+0x40`. The getters at `0xC0048858`, `0xC0048888`,
  `0xC0048864`, and `0xC0048870` confirm the corresponding byte offsets.
  Control field `+0x45` is the confirmed enable gate for the latter callback
  fan-out; the product meanings of these five fields remain unresolved.
- `ApplyVoiceTaskPartStateAndSlotAssignments` (`0xC004AB84`) applies a per-part
  source record, rebuilds all 16 voice-slot records, and emits the CPU-side
  assignment keys `0x12`, `0x13`, `0x0F`, and `0x10`. When shared control mode
  2 is active it reuses the shared `+0x42/+0x43` values; otherwise it uses the
  source record's `+0x3C` enable byte. It stores the resulting part-state byte
  at `+0x40` and finishes through `CopyVoiceAssignmentFieldsToCompactRecord`.
  The individual source-field meanings remain unresolved.
- `GetVoiceTaskParameterValueBySelector` (`0xC004BDE8`) is a selector-based
  parameter accessor used by the VoiceTask slot-assignment layer. Selectors
  `1..19` map through `g_aVoiceTaskParameterSelectorMap` (`0xC00CFD50`) to
  `{0x19,0x1A,0x1B,0x1C,0x1E,0x1F,0x20,0x23,0x22,0x26,0x27,0x24,0x25,0x2B,4,5,0x2C,0x29,2}`;
  in the current accessor, selectors `2..14` read per-voice offsets
  `+0x828,+0x829,+0x80F,+0x811,+0x812,+0x813,+0x815,+0x816,+0x818,+0x819,+0x81C,+0x81D,+0x81F`,
  selectors `15/16` read control `+0x42/+0x43`, selector `17` reads masked `+0x826`, and
  selector `18` returns the presence of `+0x824`; selectors `1` and `19` fall through to zero.
  Signed fields use the observed `+0x40` return offset and presence fields normalize to boolean.
  Product-level selector meanings remain unresolved.
- `ForwardVoiceTaskParameterUpdateToControlDispatcher` (`0xC004BA20`) is the
  slot-update forwarding boundary. It applies the selector-indexed transform table
  `g_aVoiceTaskParameterValueTransformTable` (`0xC00CFD00`), remaps the selector through
  `g_aVoiceTaskParameterSelectorMap`, and sends the resulting zero-based part index,
  internal key, and value to the shared control dispatcher at `0xC004B208`. Only selectors
  `3`, `8`, and `12` transform values in the observed table: each subtracts `0x40` and clamps
  to `-0x3F..0x3F`; the other entries are identity no-ops. With its queue flag set, the helper
  appends a 16-byte type-1 event record containing the timestamp word, part index, internal key,
  `0xFFFF`, and the transformed value.
- The main assignment rebuild reaches this dispatcher with source selectors `0x12`, `0x13`,
  `0x0F`, and `0x10`, which the selector map converts to internal keys `0x29`, `0x02`, `0x04`,
  and `0x05`. The inline dispatcher cases for keys `0x02`, `0x04`, and `0x05` write receiver
  fields `+0x04`, `+0x06`, and `+0x07` and can update the voice-task rate records. The key-`0x29`
  handler is bounded at `0xC004B864`: it writes the incoming byte to the per-part `0x24`-byte
  compact/runtime record at `+0x31`; under the apply gate it checks linked-operation permission,
  derives either zero or the shared dword at `0xC0093E80` from the voice timbre subobject byte
  at `+0x1B` (the image initializes that dword to `0x7FFF`), and sends a Host-DMA 5-word packet
  to token `voiceIndex*0x6D+0x325`. Paired-resource voices instead receive one 7-word packet
  containing the even/odd token pair. The payload and product-level field meanings remain
  unresolved.
- The per-voice accessors establish a second bounded layout within those
  0x330-byte records: signed/unsigned bytes are read at offsets `+0x828`,
  `+0x829`, `+0x80F`, `+0x811..+0x813`, `+0x815`, `+0x816`, `+0x818`,
  `+0x819`, `+0x81C`, `+0x81D`, `+0x81F`, `+0x824`, and `+0x826`.
  `GetVoiceTaskPartRecordField826Masked` (`0xC0048F8C`) specifically maps
  values with bit 7 set to zero. These offsets are structurally confirmed;
  their product-level meanings remain unresolved.
- Four engine fields are confirmed accumulation meters. The slice processor
  maintains a combined input maximum at `g_dwDspInputPeakMax`
  (`0xFF9030EC`), a conditional second-input maximum at
  `g_dwDspConditionalInputPeakMax` (`0xFF9030F0`), and two processed-output
  maxima at `g_dwDspOutputPeak0Max`/`g_dwDspOutputPeak1Max`
  (`0xFF9030F4`/`0xFF9030F8`). The ARM helpers
  `DspIf_ReadAndClearInputPeakMax` (`0xC0013F74`),
  `DspIf_ReadAndClearConditionalInputPeakMax` (`0xC0013FD8`), and
  `DspIf_ReadAndClearOutputPeakMaxima` (`0xC0014080`) read these through Host
  DMA and then clear the same words with tokens `0x4C3B`, `0x4C3C`, and
  `0x4C3D`, respectively. `DspIf_IsInputPeakAboveThreshold` at `0xC001403C`
  tests the first returned maximum against the signed fixed threshold
  `0x5A7EF811`; its caller preserves and passes that return value in `r0`.

