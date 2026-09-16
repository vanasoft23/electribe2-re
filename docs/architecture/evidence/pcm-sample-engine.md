# PCM resources, sample analysis, and playback data

> Detailed evidence extracted from the original monolithic ARCHITECTURE.md.
> Ghidra is authoritative for current symbols, types, comments, and cross-references.

- `E2_WaveEsliData494` is the confirmed `0x494`-byte KORG `esli` payload used
  for PCM sample import, export, and editing. `Pcm_ExportResourceToWaveEsliRecord`
  (`0xC004EBD4`) builds it from oscillator metadata and the runtime PCM tables;
  `Pcm_CommitEditedWaveEsliRecord` (`0xC004EFF4`) writes an edited record back.
  Export copies the key-zone playback period/volume, playback start/loop/end,
  one-shot/reserved bytes, and the complete `0x45C`-byte runtime sample record.
  With slice-extent handling enabled it expands the exported DSP range over active
  slices, rebases the start point, and clears temporary reserved extent fields.
  Commit requires a loaded target and an unchanged edited data length, updates the
  same catalog/runtime regions, and preserves runtime-only sample-record field `+0x16`.
  The latter maps record byte `+0x34` to PCM companion byte `+0x0E`, proving
  `bOneShot`; export performs the inverse copy. Independently, the same record's
  `bStereo` is at `+0x41`, matching its use by the sample WAV writer. The
  complete record also includes 64 `E2_PcmSliceData10` records at `+0x50`, each
  containing start, length, attack length, and amplitude; the 64-byte
  active-step map at `+0x450`; and slicing summary bytes through `+0x492`.
  `Pcm_PrepareSampleEditorState` (`0xC0050094`) loads those fields into the current
  editor state before DSP capture. Its temporary editor slice buffer uses the order
  start, attack length, length, amplitude, so it explicitly swaps the middle two
  fields from the persisted ELSI order. `Pcm_BuildSliceStepMap` (`0xC00A059C`)
  clears the 64-byte map to `0xFF` and assigns slice indices to step positions from
  their start offsets, with midpoint rounding; exact product meanings of the slicing
  parameters remain unresolved. `CommitCurrentPcmSampleEditState` (`0xC004FE08`)
  copies the summary bytes, active-step map, and all 64 editor records back into the
  ELSI record with the inverse field order before calling the catalog commit boundary.
  `Pcm_InsertSliceAtStep` (`0xC00A0974`) and `Pcm_DeleteSliceAtStep` (`0xC00A0878`)
  mutate the editor's 64-step map and 0x10-byte slice-record array: insertion shifts
  later records and recalculates the two affected ranges, while deletion merges the
  neighboring range, clears the step, and shifts later records down. Both helpers copy
  the resulting array back to shared editor state; the sample-boundary table and exact
  position-parameter meanings remain unresolved. `Voice_CommitPcmEditAndRefreshSliceAvailability`
  (`0xC007EEE8`) is the VoiceTask-side finalizer: it commits the current ELSI record,
  calls `Voice_RebuildPcmSliceAvailability` (`0xC007EE20`), and notifies listener
  selector `10`. The rebuild helper stores 64 boolean step flags at shared context
   `+0x4720` and resets/increments the fixed 64-step map width at `+0x4760`, using the
   oscillator slice accessor for each step. Because the count increments on every loop
   iteration, it is not a count of true/available entries.
   `ProcessVoiceTaskControlMode15` (`0xC0043580`) reaches that finalizer from its active
   service branch. It computes the selected editor index as control-object `+0x34C` times
   a stride plus the incoming `param_2`; the stride is `0x10` when the editor beat-mode
   value is below two and `0x0C` otherwise, and the result is bounded against the current
   editor step count. The finalizer then chooses the insert/delete wrapper based on the
   selected step's current map entry. The shared
  `Pcm_AdvanceSampleEditState` (`0xC0050418`) transition is also used by the capture
  and commit command handlers: it initializes slicing data after capture and clears/
  rebuilds the editor workspace before commit. `Pcm_BuildEditorSliceRecords`
  (`0xC00A06FC`) clears the active-step map, filters shared analysis records through
  a static 32-entry threshold table `k_PcmEditorSliceThresholdTable` at `0xC00F83A4`, and recalculates affected slice
  range/amplitude metadata from the captured sample buffer. Its numeric states and
  analysis-record field meanings remain unresolved. The case-1 analysis boundary is
  `Pcm_AnalyzeSampleForEditorSlices` (`0xC00A0384`): its returned bin count is stored
  at editor control `+0x27`, while the low two bits of its companion resolution are
  packed into `+0x26` bits 6–7. The case-2 recomputation boundary
  is `Pcm_RecomputeSampleSliceAnalysis` (`0xC00A043C`). Both update shared analysis
  tables, but their interval and analysis-field semantics remain unresolved.
  The common analyzer `Pcm_DetectSampleSliceBoundaries` (`0xC009F4D0`) scans the
  captured sample through a fixed-point pipeline, records amplitude-transition
  candidates as start/length pairs, and returns the boundary count used by both
  wrappers. `Pcm_PrepareSampleEditorState` copies the ELSI sample-rate field at
  `+0x48` into editor control `+0x1C`, which is then passed as the analyzer's
  fourth argument. The analyzer accepts rates from 11025 through 48000 directly;
  values outside that range use a 11025 fallback. The constants are at
  `0xC009FD68` (11024, lower-bound-minus-one), `0xC009FD6C` (11025, default),
  and `0xC009FD70` (48000, upper bound). Its filter and interval parameters
  remain unresolved. The rate-dependent constants are passed through the
  firmware's software IEEE-754 helpers and populate a private analyzer
  workspace at `0xC06A23D0`, with observed fields through `+0x30`; individual
  remaining coefficient meanings are not yet established.
  The first coefficient is now resolved: the analyzer computes
  `c = cos(500*pi/sampleRate)` from the binary64 pair at `0xC009FD78/7C`,
  then evaluates `sqrt((c+1)*(c*c+7))`, scales `c+2+sqrt(...)` by `65536`,
  and stores the converted result at workspace `+0x00`.
  The scratch fields are then copied into parameter block `0xC06A0D2C`:
  `+0x04 = ((11-analysisOrder)*0x50000)/100`; `+0x08/+0x0C` are
  `exp(-1000/sampleRate)*65536`; `+0x10/+0x14` are
  `exp(1000/sampleRate)*65536`; `+0x18` is `exp(-100/sampleRate)*65536`;
  and `+0x1C/+0x20/+0x24/+0x28` are `sampleRate * 0.025`, `* 0.0015`,
  `* 0.006`, and `* 0.002`, respectively, with `+0x2C` duplicating the
  `0.006` result and `+0x30` duplicating the negative-exponential result.
  The block is consumed by the CPU analysis path: the sliding-difference helper at
  `0xC009EFAC` reads `+0x28` as its window width, while
  `Pcm_ComputeSliceRecordMetrics` (`0xC00A0638`) reads `+0x24` as its sample-span
  threshold. The parameter block's other fields and any overlay behavior remain
  unresolved.
  The numeric conversion layer used by this setup is software binary64: 
  `SoftDouble_FromInt32` (`0xC00027B8`) converts the selected sample rate,
  `SoftDouble_Multiply` (`0xC0002894`) and `SoftDouble_Divide`
  (`0xC0002B24`) perform the derived-parameter arithmetic,
  `SoftDouble_Add` (`0xC0002484`, reached through the `0xC0002480` thunk)
  combines binary64 values, and `SoftDouble_ToInt32`/`SoftDouble_ToUInt32`
  (`0xC0002D30`/`0xC0002D8C`) convert results back to integer domains. The
  same setup calls `SoftDouble_Cosine` (`0xC0004020`), whose `0xC000410C`
  constant is the binary64 `pi/4` threshold. It reduces larger arguments with
  `SoftDouble_ReduceTrigArgument` (`0xC0006770`) and dispatches to the
  cosine and sine polynomial kernels at `0xC0007008` and `0xC0007EF0` by
  quadrant. The analyzer then calls `SoftDouble_Sqrt` (`0xC0004AA0`), whose
  `SoftDouble_SqrtCore` (`0xC0006DC8`) performs the normalized multiword
  square-root iteration, and uses `SoftInt_DivideSigned32` (`0xC0002310`)
  for amplitude scaling. `SoftDouble_Exp` (`0xC0004118`) wraps the
  binary64 exponential core at `0xC0004BC8` for the rate-derived Q16 fields.
  The remaining analysis-field meanings are unresolved.
  The analyzer's support helpers are also bounded: `Pcm_SelectAnalysisSampleChannel`
  (`0xC009EED0`) chooses the first stream, second stream, or their average; 
  `Pcm_ResetSampleAnalysisWorkspace` (`0xC009F4AC`) restores the `0x100`/`0x40`
  defaults and clears counters; `Pcm_SortSampleAnalysisCandidates` (`0xC009EEFC`)
  orders active candidate indices by an associated record field; and
  `Pcm_InterpolateSliceAnalysisBoundaries` (`0xC009F090`) bins candidates, retains
  the strongest candidate per bin, and linearly fills missing start/length entries.
  The candidate-field and binning-parameter meanings remain unresolved.
  `Pcm_SelectSampleAnalysisResolution` (`0xC009FE84`) evaluates 4..64-bin
  candidates with eight offsets each, uses the shared boundary table and fixed-point
  contrast metrics, and returns the selected bin count plus an optional companion
  resolution. `Pcm_ComputeAnalysisLengthRatio` (`0xC009F390`) aggregates the
  boundary-record `+0x04` length fields and returns a max/min ratio scaled by
  `0x100`; `Pcm_ComputeAnalysisLengthContrastRatio` (`0xC009F294`) compares
  alternating-bin length extrema using the same scale. Both ignore lengths at or
  below the observed qualification threshold `0xCDD`. Candidate scores use the
  signed phase-weight table `k_PcmAnalysisPhaseWeightTable` at `0xC00F8424`.
  `Pcm_FindAnalysisPeakOffset` (`0xC009FDC8`) selects the best neighboring offset
  and converts it for the alternate analysis mode. The remaining score and
  fallback behavior is bounded: candidate spacing is accepted only in the
  observed `0x44F..0x4099` range. The selector then computes a sample-rate-scaled
  normalized duration and performs a second weighted pass when it falls outside
  `60..200`; the companion output observed by the editor wrapper is one of
  `0x10`, `0x18`, or `0x20`. Product-level names for these modes remain unresolved.
  The shared analyzer workspace is now bounded: `g_dwPcmAnalysisBoundaryCount`
  (`0xC06A0D6C`) counts `g_aPcmAnalysisBoundaryRecords` (`0xC06A0524`), whose
  observed records are 8-byte start/length pairs. `g_awPcmAnalysisCandidateIndices`
  (`0xC06A0D74`) is a 16-bit candidate-index table; the analyzer's sorted working
  area begins two bytes before it. `g_aPcmAnalysisBinnedBoundaryRecords`
  (`0xC06A0F74`) is another 8-byte start/length table used by the resolution metrics,
  while the sample-analysis path uses `g_PcmAnalysisScoreWorkspace`
  (`0xC06A1BB0`) as eight 32-bit scores per candidate-resolution row at a `0x20`
  stride. That address is also the target of direct branches from unrelated
  runtime-support paths, so its broader ownership or overlay behavior remains
  unresolved. `g_bPcmAnalysisAlternateMode`
  (`0xC06A0D70`) selects the alternate coordinate conversion path.
  The remaining shared state has several confirmed roles: `g_dwPcmAnalysisCandidateCapacity`
  (`0xC06A051C`) is initialized to `0x100` and bounds the candidate-record reset;
  `g_pPcmAnalysisSampleInput`/`g_dwPcmAnalysisSampleCount`
  (`0xC06A0520`/`0xC06A0518`) retain the captured-sample pointer and sample count for
  recomputation; `g_dwPcmAnalysisSampleEnd` (`0xC06A0110`) is the same sample-count
  value used as the final boundary when building or editing slices; and
  `g_dwPcmAnalysisSampleRate` (`0xC06A1384`) retains the selected analysis rate.
  `g_dwPcmAnalysisRequestedResolution` (`0xC06A1388`) and
  `g_dwPcmAnalysisPeakOffset` (`0xC06A0D60`) publish the requested resolution and
  peak-offset result during recomputation. `g_aPcmEditorSliceRecords`
  (`0xC06A0118`) is the shared `0x400`-byte, 64-record editor-slice array, with
  `g_dwPcmEditorSliceCount` (`0xC06A0D68`) updated by build/insert/delete helpers.
  Other nearby analyzer globals, including the remaining parameter fields, remain
  unresolved where their consumers or exact semantics are ambiguous.
  `Pcm_GetResourceSlicePlaybackBoundsForStep` (`0xC004EA9C`) maps a sequencer
  step through that byte map and converts the stored order to
  `E2_PcmSlicePlaybackBounds10` order: start, attack length, length, amplitude.
  The corresponding oscillator-ID wrapper is
  `Pcm_GetOscillatorSlicePlaybackBoundsForStep` (`0xC004EB24`), with predicate
  forms at `0xC004EB1C` and `0xC004EB44`. Accessors at `0xC004EB4C`,
  `0xC004EB70`, and `0xC004EBB4` expose `bSlicingNumSteps` and `bSlicingBeat`.
- `g_aPcmRuntimeSampleRecords` at `0xC036AD88` is the complete 999-entry
  runtime sample table: `E2_PcmRuntimeSample45C[999]`. Each `0x45C`-byte record
  is the exact payload copied to ELSI offset `+0x38`, so the array ends exactly
  at `g_aRuntimeOscillatorMetadata` (`0xC047B08C`). It unifies the sample data
  location/length, sample rate and tune, stereo-pair role, play/load state,
  stored slice records, active-step map, and slicing summary fields. Confirmed
  fields include `dwWaveDataLength` at `+0x04`, `bState_08` at `+0x08`,
   `bStereoPairRole` at `+0x09`, `bPlayLevel` at `+0x0A`, `bLoadState` at
   `+0x0B`, `dwSampleRate` at `+0x10`, and `wSampleIdAgain` at `+0x16`.
   `Pcm_GetLoadedWaveDataLengthInSamples` (`0xC004E50C`) returns
   `dwWaveDataLength / 4` for stereo-pair role one and `/ 2` otherwise; it returns
   zero when the resolved runtime record is not loaded.
   The allocation boundary is now explicit: `Pcm_GetCurrentSampleStorageEnd`
   (`0xC004E208`) reads the shared CPU-side storage end, `Pcm_GetAvailableSampleStorageBytes`
   (`0xC004E218`) computes remaining capacity against fixed limit `0x01C65EC0`, and
   `Pcm_GetDspSampleStorageEnd` (`0xC004E23C`) reads the BF523-side limit from DSP address
   `0xFF903210`. `Pcm_InstallLoadedRuntimeSample` (`0xC004F128`) uses that limit to allocate
   the next two- or four-byte sample-width region, initializes the runtime sample record,
   and populates playback start/length, stereo role, play level, and `bLoadState`.
   `Pcm_IsRuntimeResourceLoadedForOscillator` (`0xC004E3FC`) and
   `Osc_ResolvePcmResourceIndexForSelector` (`0xC0099634`) both require
   `bLoadState == 1`; `Pcm_ReleaseLoadedRuntimeSample` (`0xC004E558`)
   clears that state and the stereo role when releasing a loaded record.
   `Pcm_IsOscillatorSlicingEnabled` (`0xC004E478`) builds on that loaded-state
   predicate, rejects stereo-pair role one, and tests runtime-record byte `+0x458`
   (`bSlicingNumSteps`) for nonzero. It is the shared slice-mode/readiness predicate
   used by the VoiceTask compatibility and sample-edit paths.
 - `Pcm_LoadWaveEsliRecordIntoRuntime` (`0xC004EDF0`) is the CPU sample-import commit
   boundary. It accepts an ELSI record only when the selected PCM runtime entry is not loaded
   and storage is available, copies the metadata payload, writes key-zone playback period and
   volume at `g_aPcmKeyZoneRecords[].+0x04/+0x06`, installs runtime playback start/loop/end
   and one-shot state, copies the slice area, and records the runtime metadata ID at sample
 record `+0x16`. `Pcm_ClearAllRuntimeSampleLoadStates` (`0xC004F2B4`) clears `bLoadState`
 across the configured runtime range and resets the CPU storage end to `0x00365EC0`.
  - `Pcm_ParseAndLoadWaveResource` (`0xC0035B10`) is the filesystem PCM/Wave import boundary. It
    requires an outer `RIFF` followed by `WAVE`, then scans `fmt `, `data`, and optional `korg`
    chunks; the latter is accepted when it contains an `esli` subchunk. The observed format contract
    is PCM (`formatTag == 1`), one or two channels, and 16- or 24-bit samples. Sixteen-bit data keeps
    its byte length; 24-bit packed data is converted to 16-bit words and uses
    `floor(data_bytes / 3) * 2` output bytes. The parser builds the `0x494`-byte
    `E2_WaveEsliData494`, uses embedded ESLI metadata when accepted, or derives an ordinary WAV name
    from up to 16 ASCII bytes between the final slash and dot in the source selector. It checks CPU
    sample storage, commits through `Pcm_LoadWaveEsliRecordIntoRuntime`, and streams decoded words
    to BF523. `Pcm_StreamSampleWordsToDsp` (`0xC004EF28`) completes short HostDMA writes by preserving
    the rest of the destination 16-word block. Staging is bounded to at most `0x10000` bytes for
    16-bit input or `0x18000` input bytes and `0x10000` output bytes per 24-bit chunk. The reader's
    actual-byte count is not checked, so a truncated resource can contribute stale scratch/metadata
    bytes; an odd converted length can also keep the decrement-by-two loop alive. No direct linear
    overwrite is shown in this parser.
  - `CopyPcmSampleBasenameFromPath` (`0xC0035A20`) implements the ordinary-WAV naming fallback. It
    copies at most 16 bytes between the final `/` and final `.`, stops on a high-bit byte, and does
    nothing when no slash is present. The `.all` path passes no source selector and therefore depends
    on its embedded ESLI record for the name and metadata.
  - The exported single-resource layout is now confirmed by `WritePcmWaveEsliRecord` (`0xC0039B2C`):
    a 44-byte RIFF/WAVE PCM header, followed by `data`, then a `korg` chunk of length `0x49C`
    containing `esli` of length `0x494` and the complete ESLI record. Its total size is
    `data_length + 0x4D0`; the RIFF size field is `data_length + 0x4C8`.
  - `Pcm_FindUnloadedRuntimeSampleSlot` (`0xC004EF94`) scans runtime table index 499 down through
    index 1, mapping those entries to logical custom IDs 500 through 998, and tests `bLoadState == 0`.
    It returns `0xFFFF` when that custom range is full; table index 0 is not considered by this helper.
  - `ProcessPcmResourceData` (`0xC00364F0`) imports the all-sample form. Its 0x1000-byte index table
    has 999 little-endian embedded-record offsets beginning at file offset `0x10` (last offset word
    starts at `0xFAC`); the exporter initializes the first 16 bytes as ASCII `e2s sample all` plus
    `0x1A 0x00` and zeroes the remaining table words. The importer itself does not visibly validate
    that outer header. It seeks each nonzero offset and invokes the normal parser with slot `-1` and
    no source path, so each embedded `esli` record supplies its metadata. The fixed scan stays within
    the allocation, but the index read ignores actual-byte count and can retain stale offsets after
    a short read. `ExportAllPcmResourcesToWaveEsli` (`0xC0039E68`) writes the corresponding table and
    records; `ConstructPcmSampleAllPath` (`0xC0035A80`) constructs
    `SD:KORG/hacktribe/Sample/e2sSample.all` for product `0x124` and
    `SD:KORG/electribe/Sample/e2sSample.all` for product `0x123`.
  - The user-facing route is `type-0x27 directory selection -> current selector at 0xC0345A24 ->
    command-0x22`. `ProcessCommandHandler22PcmResourceEvent` (`0xC0038D80`) dispatches `.wav` to
    `Pcm_ImportWaveResourceForSlot` (`0xC003644C`) with destination minus one, or `.all` to
    `ProcessPcmResourceData`, then refreshes the affected oscillator(s). Handler `0x1F`
    (`ProcessCommandHandler1FPcmResource`, `0xC0038D34`) independently rebuilds the catalog from
    the product-aware factory all-sample path. Both filesystem routes are separate from live DSP
    sampling.
  - This import route is separate from live VoiceTask sampling. The resource parser allocates from
    the CPU-side `g_dwPcmSampleStorageEnd` and streams decoded words to the BF523 sample address;
    live sampling starts with command `0x3B` phase 1, whose packet carries that current end to the
    BF523 audio state. Completion phase 0 is followed by `Pcm_InstallLoadedRuntimeSample`, which
    reads the BF523-maintained endpoint at `0xFF903210` and reconciles it with the CPU-side end
    before committing the live-sample runtime record.
  - The command-22 PCM resource event (`ProcessCommandHandler22PcmResourceEvent`, `0xC0038D80`) calls
   `Pcm_ImportWaveResourceForSlot` (`0xC003644C`) for a selected slot, or lets it select an unloaded
   slot, then refreshes the affected voices. The free-slot helper selects the fixed logical range
   `500..998` and returns `0xFFFF` when all of those runtime records are loaded. The voice-side load
   state path is separate: `Voice_BeginPcmSampleDspLoad` (`0xC0082F1C`) sends phase 1 of
   BF523 MDMA command `0x3B` with the pending stereo/width and play-level/source values and
   current CPU storage end, while
   `Voice_ProcessPcmSampleLoadState` (`0xC0082D40`) installs the runtime record, registers the slot with
   the voice service, and emits the completion notification. The two context fields are the boolean
   sampling-mode and sampling-source selections. The BF523 command dispatcher resolves command
    `0x3B` to `0xFFA056F0`, where phase 1 turns on the MDMA state at `0xFF9031D8`
    (`g_DspAudioEngineState + 0x134`), chooses one of four fixed workspace offsets from those two
    booleans, and copies the CPU sample-storage end into state `+0x2C`; phase 0 clears the active
    state before the CPU installs the runtime record. Audio-engine initialization independently
    seeds the related pointer cells at root offsets `+0x13C` (`0xFF8029DC`) and `+0x140`
    (`0xFF802FAC`), matching the two cells modified by the command case.
    The BF523 slice maintains the resulting/current storage-end value separately at root `+0x16C`
    (`0xFF903210`), and `Pcm_GetDspSampleStorageEnd` reads that exact address through HostDMA
    before `Pcm_InstallLoadedRuntimeSample` computes the next allocation. The command's staged
   value at root `+0x160` and this maintained value are therefore distinct fields.
   `Pcm_InstallLoadedRuntimeSample` uses an increment of 4 when its stereo/width argument is 1,
   otherwise 2. It computes `endpoint - increment`, floors that result at the current CPU-side
   storage end, stores the reconciled endpoint back to the CPU allocator, and records the
   interval from the old CPU end to the pre-increment endpoint as the loaded sample length.
   Therefore each normal DSP slice advances the endpoint by one 2- or 4-byte unit; if several
   slices run before phase 0, the runtime record consumes the accumulated interval represented by
   the final endpoint. The floor prevents the CPU boundary from moving backwards if the DSP
   endpoint is stale or clamped.
   This ties the CPU load-state transition to the DSP-side state machine. The audio-state
   initializer also stores pointers for the BF523 MDMA D0 status, S0/D0 next-descriptor,
   S0/D0 X_MODIFY, and S0/D0 CONFIG registers in the audio-root fields `+0x100`, `+0x104`,
   `+0x108`, `+0x114`, `+0x118`, `+0x11C`, and `+0x120`. The audio slice polls D0 status bit 3,
   reads the descriptor-pointer registers, and writes the source/destination modify and
   configuration registers through those slots. The exact descriptor format, transfer-unit
   semantics, and product-level meaning of configuration values 2/4 remain unresolved.
   The shared helper `ResolveVoiceTaskPcmOscillatorResource` (`0xC007F208`) resolves an
   eight-byte PCM descriptor, stores the resolved resource ID at shared-context `+0x3FC`,
   and stores the resource-index result minus one at `+0x4714`; its return value depends on
   the third argument. `UpdateVoiceTaskPcmResourceData` (`0xC007F2B4`) copies `0x4000`
   bytes into shared-context `+0x70C`, finalizes the shared `0x324`-byte state transition,
   updates control field `0x41`, initializes 16 entries with value `0x55`, resolves the
   supplied resource, and sets the shared flag at `+0x470C`. These helpers are shared by
    the type-0A event, voice PCM loading, type-0F initialization, and the PCM export path.
    The type-0F service-subobject vtable is now bounded at `0xC00E31F8`: its first virtual
    method resolves the current PCM descriptor, clears the shared latch gate, and normalizes
    incoming resource states; the adjacent methods step the subobject state in either direction,
    render/notify the associated child record, and dispatch state-dependent command records.
    The type-0F transition handler also maps compact states to the observed common-message type-8
    and command-record paths. The type-0F state/product meanings remain unresolved.
    The type-0x25 vtable is bounded at `0xC00E39C8`. Its state-gated message methods emit common
    message types `0x15` and `8`, while its PCM event method at `0xC0069364` shares the type-0A
    assignment-control, sequence-event, runtime-slot, DSP-MDMA `0x3B`, resource-installation,
  and `UpdateVoiceTaskPcmResourceData` path. Its child status gate is at `+0x1E`; when clear,
  the method first populates the child status text. These observations establish a shared
  child-record/state-machine family across type-0A, type-0F, and type-0x25, but do not establish
  their product-level UI or event meanings. The initializer-referenced helper
  `InitializeVoiceTaskServiceSubobjectType25IdleStatus` (`0xC00693F4-0xC006941B`) copies the
  observed idle-status string into its child record only when shared state `+0x308` is zero.
    The neighboring type-0x26 family is bounded at vtable `0xC00E3980`. Its state handlers
    operate on a bounded selection range `0..9`: `StepVoiceTaskServiceSubobjectType26SelectionBackward`
    (`0xC0069BB8`) and `...Forward` (`0xC0069C88`) wrap that state and call
    `ApplyVoiceTaskServiceSubobjectType26Selection` (`0xC0069538`). The selection path updates the
    shared VoiceTask context, child callback objects, three record text slots, and the derived
    event record. `ProcessVoiceTaskServiceSubobjectType26Command` (`0xC0069A58-0xC0069BAB`) handles
    the observed command selector values `0x20`, `0x21`, `0x23`, `0x24`, `0x26`, and `0x2C` after
    resetting its child/resource records; the paths update shared state, selection text, listener
    notifications, or guarded common messages. Its command/product meanings remain unresolved. Its
    other handlers map observed control values to shared states or command records, including command
     `0x21`.
     The type-0x26 child path is now bounded further. `InitializeVoiceTaskType26SharedContextChild`
     (`0xC0084DD8-0xC0084EBF`) initializes the `0x60`-byte child, stores the shared-context pointer,
     builds two text descriptors, and registers the child with the supplied listener source.
     `RefreshVoiceTaskType26SharedContextText` (`0xC0084ECC-0xC0084F47`) rebuilds child text for
     shared states `0x11`, `0x12`, and `0x13` through the state-specific value-record builders
     `BuildVoiceTaskState11ValueRecord` (`0xC007EB0C-0xC007EB3B`),
     `BuildVoiceTaskState12ValueRecord` (`0xC007EB3C-0xC007EB6B`), and
     `BuildVoiceTaskState13ValueRecord` (`0xC007EB6C-0xC007EB9B`). Those builders perform the
     observed PCM/resource-position calculation and wrap the result with
     `CreateVoiceTaskValueRecord` (`0xC007B168-0xC007B197`); they are also used by a broader
     VoiceTask state-comparison path. The same value-record family includes
     `BuildVoiceTaskState5ValueRecord` (`0xC007EB9C-0xC007EBCB`),
     `BuildVoiceTaskState8ValueRecord` (`0xC007EBCC-0xC007EBFB`), and
     `BuildVoiceTaskSharedContextValueRecord` (`0xC007EAF4-0xC007EB0B`), plus the sample-edit
     records `BuildVoiceTaskSampleEditBeatModeRecord` (`0xC007EBFC-0xC007EC23`),
     `BuildVoiceTaskSampleEditStepCountRecord` (`0xC007EC24-0xC007EC4B`), and
     `BuildVoiceTaskSampleEditModeRecord` (`0xC007EC4C-0xC007EC73`). Their exact state and
     product meanings remain unresolved. The state-5 and state-8 builders use
     `GetVoiceTaskPcmResourceState5Byte` (`0xC007E3FC-0xC007E453`) and
     `GetVoiceTaskPcmResourceState8ScaledValue` (`0xC007E468-0xC007E4CB`), respectively; both
     gate on PCM-resource availability and traverse unresolved nested resource tables.
     The underlying state-11/state-12/state-13 calculations are now bounded as
      `UpdateVoiceTaskPcmResourceState11Position` (`0xC007E360-0xC007E393`),
      `UpdateVoiceTaskPcmResourceState12Position` (`0xC007E394-0xC007E3C7`), and
      `UpdateVoiceTaskPcmResourceState13Position` (`0xC007E3C8-0xC007E3FB`). Each resolves the
      runtime PCM resource, clamps and updates a per-resource `0x10`-byte position record, sets its
      completion byte, and emits the corresponding divided value. Position and product meanings
      remain unresolved. `SetVoiceTaskSharedContextPcmResourceIndex`
      (`0xC007E4E4-0xC007E593`) adjusts the shared-context selection at `+0x3FC` by a supplied
      delta, clamps it to `0..0x3E6`, resolves a loaded fallback when needed, stores the selected
      resource, and writes the resolved sample length minus one at `+0x4714`. Its optional path
      invokes the observed PCM/resource helper and then notifies listener records at context `+4`;
       numeric and product meanings remain unresolved. The parallel
       `UpdateVoiceTaskSharedContextPcmSelection` (`0xC007E778-0xC007E7F7`) applies the same
       bounded selection, loaded-fallback, and listener-notification pattern without updating
       the sample-length field; its numeric and product meanings remain unresolved.
       `UpdateVoiceTaskType26SelectionDisplay`
      (`0xC0084F48-0xC0084FBB`) updates the selected index and indexed display byte; and
     `RefreshVoiceTaskType26SelectionChild` (`0xC0084FF8-0xC008501B`) resets that index and marks
     the child active for those three states. Product and field meanings remain unresolved.
    The type-0x27 family is bounded at vtable `0xC00E3A18` and is the confirmed CPU sample-import
    control path. `ProcessVoiceTaskServiceSubobjectType27ResourceEvent` (`0xC006A7AC`) processes
    state `+0x3C`, routes resource records through the command-0x12 directory scanner, and emits
    command records `0x12`/`0x22` on the observed paths. `UpdateVoiceTaskServiceSubobjectType27SampleImportState`
  (`0xC006A3C4`) handles the idle, import, and confirmation phases, activating the child status
  records and using the confirmed strings `IMPORT SAMPLE`, `Import All Samples`, `Are you sure?`,
  and `Select Destination`. `UpdateVoiceTaskServiceSubobjectType27SampleSelectionStatus`
  (`0xC006A224`) advances the selected oscillator/resource and formats its loaded-resource status.
    Its vtable slot `+0x40` is the bounded wrapper `DispatchVoiceTaskServiceSubobjectType27IndexedValueAdjustment`
  (`0xC006A394-0xC006A3B3`), which accepts selector values `0` and `1` and tail-dispatches to the
  shared `AdjustVoiceTaskIndexedValueWindow` body (`0xC008639C-0xC0086463`). That body maintains the
    indexed window at `+0x35C/+0x360`, queues up to three derived child values, and notifies listeners;
    the indexed value/product meanings remain unresolved. Its startup-table entry
    `InitializeVoiceTaskType27StorageLabelRecords` (`0xC006AF10-0xC006AF93`, table slot
    `0xC00F89B8`) builds the parallel resource label records at `0xC0691294/0xC0691298/0xC0691290`
    from the observed `SD:` literal and an empty string record.
  `ProcessVoiceTaskServiceSubobjectType27DirectoryResponse` (`0xC006AAFC-0xC006AB5F`) handles
  response command records `0x12` and `0x22`: the `0x12` path rebuilds the directory-value list through
  `PopulateVoiceTaskServiceSubobjectType27DirectoryValues` (`0xC006A990-0xC006AAEF`), while the `0x22`
  path initializes mapped-state/DSP-control resources and advances the import state. The response and
  product meanings remain unresolved.
    The type-0x28 family is a CPU text-editor/control object at vtable `0xC00E37D0`. Its shared
    text buffer is at `+0x308`, with cursor/index at `+0x30C` and the observed upper bound at
    `+0x310`. `InsertVoiceTaskTextCharacterAtCursor` (`0xC008B89C`),
    `AdvanceVoiceTaskTextCursor` (`0xC008B7E0`), and
    `DeleteVoiceTaskTextCharacterBeforeCursor` (`0xC008B808`) mutate that buffer and notify the
  active listeners; `NormalizeVoiceTaskTextInputCharacter` (`0xC008B858`) filters the candidate
  character. Type-0x28 dispatches these through its character, cursor, delete, and commit methods,
  and `CommitVoiceTaskServiceSubobjectType28TextEdit` (`0xC0068780`) copies the buffer into the
  owning context and emits command record `0x25`. Its initialization-time display helper,
  `InitializeVoiceTaskServiceSubobjectType28DisplayState` (`0xC00682EC-0xC00683DB`), selects the
  observed child/LCD/status path from local mode `+0x20`; the edit path also copies the shared buffer
  into a child record. The prompt meaning remains unresolved.
    The type-0x2A mapped-state service uses the vtable at `0xC00E3AA8`. Its sampling controls are
    bounded by `StepVoiceTaskMappedStateServiceParameterBackward`/`Forward`
    (`0xC006B354`/`0xC006B37C`), which update child display records from shared sampling values and
    PCM-load state `0x0B/0x0C`. `UpdateVoiceTaskMappedStateServiceSamplingToggle`
    (`0xC006B484`) publishes the two boolean selections at shared-context `+0x704/+0x708`, while
    the mapped-state event/message handlers route event IDs `8`/`0x0C`, command `0x24`, and the
    observed common-message type `0x10`. Higher-level product meanings remain unresolved.
    The shared record layer is now bounded: `SetVoiceTaskServiceRecordEventAndActivate`
    (`0xC008A8A8`) writes event values at record `+0x38/+0x3C` and sets active byte `+0x14`;
    `UpdateVoiceTaskServiceRecordTextSlot0` (`0xC00857E4`) derives metadata from source text
    `+0x6C` into slot `+0x4C/+0x50`; and the neighboring helpers
    `UpdateVoiceTaskServiceRecordTextSlot1`/`2` (`0xC0085828`/`0xC0085888`) update slots
    `+0x8C/+0x54/+0x58` and `+0xAC/+0x5C/+0x60`, respectively. All three text helpers set the
    same active byte. `RenderVoiceTaskServiceSubobjectStateRecord` (`0xC0061988`) is the shared
    compact-state renderer that selects these slots and event fields for type-0F and neighboring
    service subobjects; its state/text meanings remain unresolved.
    `BuildVoiceTaskServiceRecordEventText` (`0xC008A708`) derives the record text at `+0x40` from
    event fields `+0x38/+0x3C`, using a formatted numeric path when `+0x3C` is nonzero and a static
    fallback string otherwise. The formatting is confirmed; the resulting text's product meaning
    remains unresolved. Its derived metadata is measured by `MeasureVoiceTaskTextAdvanceWidth`
    (`0xC003F89C`) and `MeasureVoiceTaskTextMaxGlyphHeight` (`0xC003F940`), which use the active
    glyph/kerning lookup path.
 - The persistent PCM resource-image path is also bounded. `Pcm_PersistRuntimeResourceRecord`
   (`0xC004FB6C`) copies the selected runtime resource plus its associated catalog records into
   the shared `0xA0000`-byte image and writes it through `Pcm_WritePersistentResourceImage`
  (`0xC004C3D4`). `Pcm_ClearPersistentResourceImage` (`0xC004FDB8`) fills that image with
  `0xFF` before writing it and can synchronize the in-memory tables through
  `Pcm_SynchronizePersistentResourceState` (`0xC004F340`). Raw ARM establishes the image
  serializer layout: `SIST` is written at image offset `+0`; current blocks are copied as follows:
  runtime oscillator metadata from `0xC047B08C` to `+0x04` (`0x3E80` bytes), key-zone groups
  from `0xC035F06C` to `+0x3E90` (`0x1F40`), key-zone records from `0xC0350644` to
  `+0x5DD0` (`0x0FA0`), playback points from `0xC0362EE8` to `+0x6D70` (`0x1F40`),
  velocity maps from `0xC035738C` to `+0x8CB0` (`0x3E80`), and runtime sample records from
  `0xC036AD88` to `+0xCB30` (`0x883B0`). `SIED` is written at `+0x9FFFC`.
  `IsPersistentPcmImageComplete` (`0xC004AEC4`) checks that footer,
  and synchronization deserializes those blocks when it is present, otherwise serializes the
  in-memory state and creates the markers. The individual serialized subrecord meanings remain
  only partially resolved.
 - The image-load validation path is bounded as well: `ReadPersistentPcmResourceImageAndValidateSignature`
   (`0xC004C0E0-0xC004C13F`) reads `0xA0000` bytes from the selector-`0x6B` persistent PCM region and
   validates word `0x44454953` at image offset `0x9FFFC` (little-endian bytes `SIED`). The footer is
   also the completeness marker used by the synchronization direction test; its product-level
   meaning remains unresolved. A related selector-`0x23` path,
   `WritePersistentRecordImage` (`0xC004C1B4-0xC004C217`), copies exactly `0x100` bytes into a
   lazily allocated `0x118`-byte object before writing the persistent record. `GetPersistentRecordContext`
   (`0xC00316D4-0xC0031703`) supplies the shared four-byte context used by handler-0x11 and LCD-reset
   callers; the record payload semantics remain unresolved.
 - The persistence entry points also expose two lazily allocated four-byte contexts.
   `GetVoiceAssignmentModePersistenceContext` (`0xC00380EC-0xC003811B`) is used by three
   voice-assignment mode-block command handlers and initializes its context through
   `InitializeVoiceAssignmentModePersistenceContext` (`0xC004C27C-0xC004C287`), which stores the
   descriptor at `0xC00CFE10` before the context is passed to the mode-block writer.
   `GetPcmPersistentResourceContext` (`0xC004FB38-0xC004FB67`) is shared by the persistent-resource
   persist/clear paths and initializes through `InitializePcmPersistentResourceContext`
   (`0xC004C3C4-0xC004C3CF`), storing the descriptor at `0xC00CFE30`. Both descriptor records contain
   paired lifecycle-like code pointers and zero metadata words; their indirect dispatch semantics remain
   unresolved.
- `g_aPcmRuntimePlaybackPoints` at `0xC0362EE8` is the adjacent complete
  999-entry table `E2_PcmRuntimePlaybackPoints10[999]`. Record `+0x00` is the
  absolute BF523/DSP sample start address, `+0x04/+0x08` are the KORG loop/end
  point values, `+0x0E` is raw `oneShot`, and `+0x0F` is the reserved ELSI byte
  copied to/from record `+0x35`; word `+0x0C` remains unresolved. Export turns
  the runtime start address back into an ELSI-relative start point, while
  commit adds the live sample base again. The sample-editor HostDMA loader
   independently confirms the address/extent interpretation: it reads from
   `Pcm_GetOscillatorDspSampleStartAddress` (`0xC004E9DC`) for
   `Pcm_GetOscillatorEndPoint` (`0xC004EA18`) plus one 16-bit sample.
   The runtime editor/control path mutates these same fields through
   `Pcm_AdjustPlaybackStartPoint` (`0xC004E63C`), which rebases loop/end after
   moving `+0x00`, `Pcm_AdjustPlaybackEndPoint` (`0xC004E710`), which changes
   `+0x08` while clamping `+0x04`, and `Pcm_AdjustPlaybackLoopPoint`
   (`0xC004E7E8`), which changes `+0x04` against the existing `+0x08`.
   Their voice-task callers emit event codes `0x40`, `0x41`, and `0x42`,
   respectively, and notify the voice listeners after applying a changed value.
 - `Pcm_ResolveResourceToRuntimeSampleIndex` (`0xC004E2F0`) performs the shared
   catalog indirection used by PCM state, slice, playback-point, and metadata
   accessors. For logical resource `r`, it reads the halfword at
   `C035738C[r].+0x10`, uses that as an index into `C035F06C[].+0x08`, then uses
   the resulting halfword as an index into `C0350644[].+0x02`; that last
   halfword is the runtime sample-record index. The confirmed table strides are
   `0x20`, `0x10`, and `0x08`, respectively, and this path intentionally uses
   the first/zero velocity layer and first key zone. `Pcm_GetLogicalResourceIndexFromOscillator`
   (`0xC004E4EC`) reads runtime oscillator metadata `+0x12` and subtracts `0x32`
   to recover the signed logical resource index; negative results are rejected
   by the PCM helpers. `Pcm_GetRuntimeOscillatorMetadata` (`0xC004E890`) follows
   runtime sample-record `+0x16` back into the 0x20-byte oscillator catalog, and
   `Pcm_CopyResourceNameToRuntimeOscillatorMetadata` (`0xC004E8C8`) copies the
   16-byte resource name into that catalog record's `+0x00` field. The other
   fields in all three indirection tables remain unresolved.
   `FindLoadedVoicePcmOscillatorResource` (`0xC007DF24`) searches upward from a
   requested 16-bit oscillator selector through the observed maximum, then wraps
   through lower selectors, returning the first runtime record whose `bLoadState`
   is one or the original selector when no loaded candidate exists.
   `FindPreviousLoadedVoicePcmOscillatorResource` (`0xC007DFA8-0xC007E01F`) performs
   the corresponding backward search, wrapping through the same selector range whose
   maximum is `0x3E6`; it is used for negative shared-context selection deltas and
   returns the original selector if no loaded candidate exists.
   `Pcm_GetLoadedOscillatorSampleLength` (`0xC004E60C`) resolves the same catalog
   path and returns the loaded wave-data length in frames: division by four for
   stereo-pair role one and division by two for other roles, with `-1` for invalid
   or unloaded records.
- `voice_t.bOscillatorResourceMode` at `+0x39` is copied to live slot
  `bOscillatorResourceMode` at `+0x43`. `Voice_ConfigureOscillatorFromTimbre`
  proves PCM mode 0 is an unsliced mono resource; mode 1 selects slices through
  a generated per-voice index map; mode 2 selects a fixed slice with the signed
  oscillator-edit value; modes 3 and 4 are the two sides of a paired-stereo
  resource selected by voice parity; and `0xFE` is unavailable. Non-resource
  oscillators use `0xFF`; audio input uses mode 0 or 3.
  `Voice_BuildSlicedPlaybackIndexMap` (`0xC009A934`) expands the sample's
  `bSlicingNumSteps`/`bSlicingBeat` metadata through the current pattern length
  and beat permutation into `voice_t.abSlicedPlaybackIndexMap[64]` at `+0x108`;
  invalid slicing metadata fills it with `0xFF`.
  `Voice_ConfigureOscillatorSlotResourcePlayback` (`0xC0099A40`) consumes the
  mode, gets mode-1 indices from that map or mode-2 indices from the slot's
  `nOscillatorEditValue` at `+0x3C`, chooses PCM or slice bounds, sends the
  normalized one-shot state, and programs the BF523 resource playback fields.
  Its CPU-side resource helpers are now named `SendPcmResourcePlaybackFields`
  (`0xC0094C14`), `SendPcmSlotModeValue` (`0xC0094E74`),
  `SendAudioInputSlotModeValue` (`0xC0094E98`),
  `SendOscillatorSlotModeCommand` (`0xC0094EC0`),
  `SetOscillatorResourcePlaybackState` (`0xC0094EE4`), and
  `ComputeAndSendOscillatorSliceScalar` (`0xC0094F10`). The observed token offsets
  are `+0x03` for command `0x2E`, `+0x04/+0x06/+0x07/+0x08/+0x0A/+0x0C/+0x12/+0x13`
  for command `0x01`, `+0x0E/+0x0F` for command `0x01`, and `+0x10` for command
  `0x31`; the field-level musical meanings remain unresolved.
  `Osc_GetMetadataRecordById` (`0xC0099788`) resolves records from this runtime
  array. It admits normal IDs 0-420 and custom IDs 500-998; IDs 421-499 are
  rejected even though backing records exist. `Osc_FindRuntimeIdForPcmResourceIndex`
  (`0xC004DF24`) first tests the resource's same-number runtime record, then
  scans the generated runtime-ID region backward for the selector matching
  resource index plus 50. It returns that runtime ID, while
  `Osc_GetDspSelectorForOscillatorId` (`0xC00997F8`)
  returns the selector
  at `+0x12`. `Osc_ResolvePcmResourceIndexForSelector` (`0xC0099634`) maps
  selectors 50 and above through the PCM resource tables and returns `-1` for
  unavailable records; the exact resource-table structure remains unresolved.
  Following the selector through the ARM preset blocks and the
  BF523 pointer table proves the callback meanings below; these names are not
  inferred solely from DSP arithmetic.

  | DSP selector(s) | Metadata display name(s) | BF523 callback index/implementation |
  | --- | --- | --- |
  | 1, 2 | SAW, PULSE | 1, 2: shared saw/pulse renderer |
  | 3, 4 | TRIANGLE, SINE | 3: triangle; 4: sine |
  | 5 | LOFI NOISE | 5: lo-fi noise |
  | 6-8 | LPF NOISE, HPF NOISE, REZ NOISE | 6-8: shared filtered-noise renderer |
  | 9, 10 | DUAL/OCT SAW, DUAL/OCT SQUARE | 9, 10: shared dual/octave saw-square renderer |
  | 11, 12 | DUAL/OCT TRIANGLE, DUAL/OCT SINE | 11: triangle; 12: sine |
  | 13-16 | UNI-SAW, UNI-SQU, UNI-TRI, UNI-SINE | 13-16: four unison renderers |
  | 17, 18 | SYNC-SAW, SYNC-SQU | 17, 18: shared sync saw-square renderer |
  | 19, 20 | SYNC-TRI, SYNC-SINE | 19: triangle; 20: sine |
  | 21, 22 | RING-SAW, RING-SQU | 21, 22: shared ring saw-square renderer |
  | 23, 24 | RING-TRI, RING-SINE | 23: triangle; 24: sine |
  | 25, 26, 29, 30 | X-SAW, X-SQUARE, VPM-SAW, VPM-SQUARE | 25, 26, 29, 30: shared X/VPM saw-square renderer |
  | 27, 31 | X-TRI, VPM-TRI | 27, 31: shared X/VPM triangle renderer |
  | 28, 32 | X-SINE, VPM-SINE | 28, 32: shared X/VPM sine renderer |
  | 33-36 | CHIP-NOISE, CHIP-PULSE, CHIP-TRI 1, CHIP-TRI 2 | 36-39: four chip renderers |
  | 45 | Audio In Mn, Audio In St | 35: audio-input renderer |
  | greater than 49 | PCM/sample oscillator records | 34: PCM renderer in this build |

  Selector 0, selectors 37-44, and selectors 46-49 use callback index 0. The
  52-entry table's indices 40-51 also repeat callback 0. Callback index 33 is a
  separate PCM implementation at `0xFFA0314E`, but
  `Osc_IsAlternatePcmOscillatorSelector` (`0xC009989C`) returns false
  unconditionally in this build; `Osc_IsPcmOscillatorSelector` (`0xC00998A4`)
  returns true for selectors greater than 49, routing those records to callback
  34 at `0xFFA02EDE`.
