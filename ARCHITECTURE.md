# Electribe 2 Firmware Architecture

This document describes the recovered structure and major execution/data flows of
`HACKTRIBE.bin`. It is an architectural map, not a chronological reverse-engineering
log.

The **Ghidra program database is authoritative** for current function names, prototypes,
types, namespaces, comments, labels, and cross-references. Detailed evidence and
important constants are retained in the focused documents under
[`docs/architecture/evidence/`](docs/architecture/evidence/README.md).

## Reading order

1. Start with **System overview** and **Boot and startup**.
2. Use **Runtime ownership** to locate the task or subsystem responsible for data.
3. Follow one of the **End-to-end flows**.
4. Open the linked evidence document only when addresses, layouts, constants, or proof
   are needed.
5. Inspect Ghidra before changing a symbol or treating an old note as current truth.

## System overview

```text
16 MiB serial flash
  -> AIS/SBL boot stage
  -> loads 2 MiB ARM application at cached DDR 0xC0000000
  -> ARM reset stub -> main -> RTOS scheduler -> StartupTask

AM1802 / ARM926EJ-S
  |-- VoiceTask + SeqTask + UI/service objects
  |-- CommandTask + CentralServiceTask
  |-- Serial flash and SD-card persistence/update
  |-- UART0 <-> panel MCU (buttons, knobs, pads, power/battery reports)
  |-- UART1 <-> TRS MIDI
  |-- USB0  <-> USB MIDI/control
  |-- SPI0  -> LCD controller (output only)
  |-- SPI1  -> serial flash and BF523 boot stream
  `-- EMIFA CS2 <-> BF523 Host DMA

BF523 / Blackfin
  |-- VDK threads
  |-- oscillator/voice DSP
  |-- SPORT0 + DMA audio I/O
  `-- Host DMA and UART control/message paths
```

The ARM side owns product state, sequencing, UI, persistence, MIDI routing, voice
allocation, and DSP command construction. The BF523 owns real-time audio processing and
hardware audio I/O. The panel MCU is a separate input/power/indicator endpoint; the ARM
does not directly sample battery voltage in the recovered application.

## Address spaces and loaded images

| Region | Meaning |
| --- | --- |
| `0xC0000000-0xC3FFFFFF` | 64 MiB cached DDR window |
| `0xC4000000-0xC7FFFFFF` | Uncached alias of the same physical DDR |
| `0xC0000000-0xC01FFFFF` | Loaded 2 MiB ARM firmware image |
| `0xC0200000-0xC08A293F` | ARM BSS/runtime allocations cleared by `main` |
| `0x60000000` | BF523 Host DMA port through AM1802 EMIFA CS2 |
| `0x68000000` | AM1802 EMIFA register block |
| `0x8001B000` | External diagnostic record observed by ARM code; producer not in this image |
| `0xFFA00000` | Reconstructed BF523 application entry in the extracted DSP program |

The ARM application assumes that cached DDR and its uncached alias already exist. No
executed CP15/MMU setup path is present in the loaded application; `SBL.bin` calls
`config_mmu` at `0x80000090`, constructs its first-level table at `0x8001C000`, and
enables the MMU/cache before entering the application startup path.

Detailed evidence: [boot and interrupts](docs/architecture/evidence/boot-and-interrupts.md).

## Boot and startup

The factory boot chain is:

1. The AIS boot script loads the SBL into `0x80000000`.
2. The SBL configures clocks, PSC, DDR, required GPIO, and the ARM MMU/cache mapping.
3. The SBL copies the 2 MiB system image from flash into DDR at `0xC0000000`.
4. The ARM vector reset entry reaches the stub at `0xC0000070`.
5. The stub establishes the runtime stack and calls `main` at `0xC00296B0`.
6. `main` clears BSS, fills runtime/task stacks with sentinels, initializes the board,
   interrupt controller, and RTOS state, then enters the scheduler.
7. `StartupTask` runs 76 C++ static initializers, constructs major singleton objects,
   initializes the LCD/panel/SD-card application state, boots the BF523 over SPI1, and
   starts task IDs 2 through 10.

The startup boundary is important: `main` performs low-level runtime/SoC setup;
`StartupTask` constructs the application and enables the remaining concurrent services.

## CPU runtime ownership

### RTOS tasks

| ID | Task | Primary responsibility | Priority |
| ---: | --- | --- | ---: |
| 1 | `StartupTask` | Static initialization and subsystem construction | 8 |
| 2 | `PeriodicTask` | Periodic callback/countdown service | 1 |
| 3 | `CentralServiceTask` | Routes central queues from MIDI, panel, and shared services | 3 |
| 4 | `UiTask` | UI/display-facing state processing | 4 |
| 5 | `CommandTask` | Executes asynchronous product/storage/utility commands | 6 |
| 6 | USB controller worker | Services AM1802 USB device controller | 0 |
| 7 | `USBMidiInTask` | Dequeues USB-MIDI transport bytes into the shared MIDI parser | 0 |
| 8 | `SDCardDriverTask` | SD/MMC driver state and transfers | 5 |
| 9 | `VoiceTask` | Product state, voice assignment, UI services, and DSP control | 7 |
| 10 | `SeqTask` | Sequencer timing, events, and VoiceTask handoff | 2 |

Only `StartupTask` is initially runnable. Task descriptors define initial argument,
entry, priority, and stack region; the RTOS builds an initial saved-register frame for
each task. Their trailing `+0x18/+0x1C` slots are reserved/zero in the static table;
the similarly located runtime TCB fields instead hold the saved SP and context-restore PC.

### Scheduler and synchronization

The firmware contains a compact static RTOS:

- A priority-based ready queue selects the next task.
- Wait-list operations block and wake tasks around events and timeouts.
- A one-based min-heap stores RTOS timer deadlines.
- Seven mutex objects exist. Confirmed users include DSP Host DMA, serial flash, and the
  heap allocator. Mutex IDs 3 through 5 still have no recovered callsites.
- Interrupt callbacks are registered through a 101-entry dispatch table and acknowledge
  their own AINTC sources.

Detailed evidence: [RTOS kernel](docs/architecture/evidence/rtos-kernel.md) and
[tasks/CommandTask](docs/architecture/evidence/rtos-tasks-and-command-dispatch.md).

### Message and command boundaries

The application uses several distinct asynchronous mechanisms:

- **RTOS events** wake task loops.
- **Circular queues** transfer fixed records between interrupt/task and task/task
  boundaries.
- **Common messages** carry a type plus a small payload through service objects.
- **CommandTask records** select one of 45 handler objects and carry two payload words.
- **VoiceTask records** carry sequencer, MIDI, control, and service transitions.
- **Listener lists** publish state changes to registered callbacks.
- **Factory-selected polymorphic objects** implement UI/service workflows without a
  single monolithic state machine.

These mechanisms are related by call flow but are not interchangeable. In particular,
CommandTask handler IDs, common-message types, VoiceTask event types, and DSP command IDs
belong to different namespaces.

## Application structure

### VoiceTask

`VoiceTask` is the main product-state owner. It coordinates:

- the 16-part voice/timbre state;
- 24 live oscillator-slot assignment/runtime records;
- shared Global/part control fields;
- mapped state and listener fan-out;
- PCM resource selection and editing;
- UI/service subobjects;
- MIDI-derived note and control events;
- sequencer handoff;
- command construction for the BF523.

The large VoiceTask domain is decomposed into smaller recovered objects: shared-control
state, mapped-state tables, listener clients, timing/profile records, assignment records,
service subobjects, and mode-specific state objects. A factory table constructs service
subobjects by selector; class namespaces are created in Ghidra when vtable and constructor
evidence support them.

### SeqTask

`SeqTask` owns transport progression and sequence-event production. Its recovered
state includes:

- packed transport positions;
- per-part slot tables;
- paired sequence records;
- pending event bits and auxiliary lists;
- timing target/current state;
- queues consumed by VoiceTask.

SeqTask decides **when** an event becomes active. VoiceTask decides how that event changes
voice allocation, shared state, and DSP parameters.

### CommandTask

`CommandTask` owns long-running or asynchronous operations such as:

- SD-card resource scans;
- PCM/catalog loading;
- pattern and assignment persistence;
- utility/service workflows;
- system/boot/PCM/user/slice update operations;
- project export.

Its 45 handlers are polymorphic objects with a shared execution/status protocol.
Handler-specific state belongs in Ghidra and the detailed evidence document; the root
architecture records only cross-subsystem responsibilities.

### CentralServiceTask and UI services

`CentralServiceTask` drains separate central queues and routes panel, MIDI, and shared
service messages. UI-facing operations are implemented by selected service objects and
recurring child records that render text, receive events, and publish status.

The recovered service families include warnings, data utilities, part utilities,
pattern-set operations, naming/edit workflows, software update state, and hardware
diagnostics. Product names are used only when strings and data flow agree.

Detailed evidence:

- [sequencer and mapped state](docs/architecture/evidence/sequencer-and-mapped-state.md)
- [VoiceTask control and services](docs/architecture/evidence/voice-control-and-services.md)
- [voice assignment and DSP control](docs/architecture/evidence/voice-dsp-control.md)

## Major data domains

| Domain | Primary owner | Important shape/invariant |
| --- | --- | --- |
| Task descriptors | RTOS/startup | 10 static records, one per task |
| Command handlers | CommandTask | 45 handler objects indexed `0x00..0x2C` |
| Parts/voices | VoiceTask | 16 `voice_t` records, stride `0x148` |
| Oscillator slots | VoiceTask + BF523 | 24 assignment/runtime slots on ARM with corresponding DSP workspaces |
| Sequence records | SeqTask | Paired `0x48`-byte records plus per-part slot state |
| Voice assignment image | VoiceTask/persistence | `0xFA` blocks × `0x4000` = `0x3E8000` bytes |
| PCM runtime catalog | PCM/VoiceTask | 999 records × `0x45C` bytes |
| Wave/ELSI metadata | PCM/import/export | `0x494`-byte serialized resource record |
| Panel protocol state | CentralService/panel driver | Five-byte packets plus 256-byte bulk blocks |
| LCD state | LCD singleton | 128×64 framebuffer as eight `0x80`-byte pages plus shadow |

Offsets and field-level meanings should remain in Ghidra structures and the subsystem
evidence documents. Add them here only when they establish ownership, record size, or an
important cross-subsystem contract.

## End-to-end flows

### MIDI or sequencer event to audio output

```text
UART1 MIDI or USB-MIDI
  -> transport byte queue
  -> shared MIDI parser
  -> CentralService/VoiceTask record
  -> VoiceTask note allocation and 24-slot state
  -> DSP command builder
  -> EMIFA Host DMA
  -> BF523 command consumer / oscillator workspace
  -> BF523 audio slice processing
  -> SPORT0 DMA audio output
```

SeqTask enters the same VoiceTask/DSP half of this flow through its own record queue.
Voice allocation policy, held-note priority, one-shot behavior, paired resources, and
assignment mode are ARM-side decisions; sample/oscillator processing is BF523-side.

Detailed evidence:
[MIDI/USB routing](docs/architecture/evidence/midi-usb-and-common-messages.md),
[DSP boot/audio](docs/architecture/evidence/dsp-boot-and-audio.md), and
[BF523 Host DMA/UART](docs/architecture/evidence/dsp-hostdma-and-uart.md).

### PCM resource load and playback

```text
SD:KORG/<product>/Sample/*.wav or e2sSample.all
  -> type-0x27 directory selection and command-0x22 dispatch
  -> parse RIFF/WAVE PCM and optional korg/esli metadata
  -> for e2sSample.all: read the 0x1000-byte offset table and embedded records
  -> allocate CPU sample storage and build/update the 999-entry ARM runtime catalog
  -> stream decoded sample words to BF523
serial flash PCM region (selector 0x80)
  -> persistent/resource image validation and catalog rebuild
  -> select sample/slice metadata for a voice
  -> VoiceTask finds an unloaded runtime slot and starts HostDMA command 0x3B phase 1
  -> BF523 case 0xFFA056F0 selects the sample workspace, publishes it through the
     audio-root pointer cell, and arms its transfer state
  -> transfer completes; VoiceTask sends command 0x3B phase 0 and installs the runtime record
  -> stream or reference sample state through DSP control
  -> BF523 playback workspace
```

PCM data enters the runtime through three related but distinct routes. User-facing filesystem import
starts with the type-0x27 SD directory selector and command `0x22`: `.wav` selects one destination,
while `.all` walks the fixed offset table and imports each embedded RIFF/WAVE/ESLI record. The
factory/resource rebuild path uses the product-aware `Sample/e2sSample.all` selector directly.
Both filesystem routes allocate from the CPU-side `g_dwPcmSampleStorageEnd`, commit runtime metadata,
and stream decoded sample words directly to BF523 sample memory through HostDMA. The VoiceTask
live-sampling route instead reserves a runtime slot, sends command `0x3B` phase 1 with the current
CPU end, lets the BF523 audio slice run the transfer state, then sends phase 0 and uses the
BF523-maintained endpoint to reconcile the CPU allocation before installing the runtime record.

The PCM allocation boundary is shared across the CPU/DSP boundary. The CPU sends its current
storage end in command `0x3B` to the BF523 audio state at root `+0x160`; the BF523 audio slice
maintains a separate end value at root `+0x16C` (`0xFF903210`), which the CPU reads through
HostDMA before installing the next runtime sample. The exact distinction between the staged
and maintained values is structural; their remaining product-level semantics are unresolved.
During the active slice state, BF523 advances the staged end by the command-selected 2- or
4-byte increment, clamps against its root `+0x164` limit, and publishes the resulting endpoint
to both fields. The CPU installer subtracts the same increment and floors against its previous
end when creating the runtime record, preserving the cross-chip allocation boundary.

The BF523 audio slice also synchronizes its MDMA channel through pointer slots initialized in
the audio root: D0 status, S0/D0 descriptor pointers, S0/D0 X_MODIFY, and S0/D0 CONFIG. It polls
D0 status bit 3 and updates the descriptor/transfer registers as part of the slice path. This
is the recurring audio-side setup adjacent to and sharing state with live sampling; descriptor
layout and exact transfer-unit semantics remain unresolved.

The separate BF523 helper `FUN_01F0E15C` programs MDMA D1/S1 for a bounded staging/copy path
owned by `FUN_00017EAC`; it is not the direct implementation of live command `0x3B`, whose MDMA
setup is performed directly by the BF523 audio slice.

Slice metadata is stored separately in the selector-`0x75` region and copied into the
tail of each runtime PCM record. Sample analysis and edit paths use shared scratch/state
but are distinct from normal playback selection.

Detailed evidence: [PCM sample engine](docs/architecture/evidence/pcm-sample-engine.md).

### Panel input and UI response

```text
buttons/knobs/pads or panel status
  -> UART0 interrupt
  -> five-byte panel packet parser
  -> direct identity path during startup, otherwise central queue
  -> CentralServiceTask
  -> common message / VoiceTask service object
  -> product-state update
  -> LCD framebuffer update and/or panel command
```

UART0 also supports a separate byte/256-byte-block handshake used by a panel
recovery/update-like path. That transport is distinct from normal five-byte input packets.

### Battery status and DC diagnostics

Normal monitoring is panel-MCU mediated:

```text
panel packet type 6, byte +0x0D
  -> common message type 7
  -> VoiceTaskBatteryMonitorClient raw measurement
  -> chemistry-selected threshold table
  -> level 0..4
  -> warning service ("Battery Low") or LCD/panel reset request
```

Global setting `BATTERY TYPE` selects Ni-MH or Alkali thresholds. The important tables
remain documented because they define behavior:

- Ni-MH: `{134, 129, 124, 97}`
- Alkali: `{127, 110, 104, 97}`

The separate `VoiceServiceBatteryDcDiagnosticsState` runs the service/diagnostic workflow.
It consumes the panel-provided measurement and DC-jack condition, displays diagnostic
steps, sends panel SysEx commands `0x6D`/parameters `1..5`, and exercises the observed
indicator/load-control path. Measurement units, DC polarity, and the exact electrical
meaning of panel command `0x02` remain unresolved.

The packet contract is fixed: panel type `6` byte `+0x01` becomes common-message type `7`
(battery measurement), while panel type `7` byte `+0x01` becomes type `6` with a boolean
DC/connection payload. The main service stores these at `+0x1D8` and `+0x1D4`, respectively.
The diagnostic object is a selector-8, `0x18`-byte class with workflow state/counter at
`+0x10/+0x14`; selections `1..5` map to states `1,3,5,7,9`. Detailed threshold and
state-action evidence is in [battery and panel](docs/architecture/evidence/battery-and-panel.md).

### LCD update

UI renderers modify a 128×64 framebuffer. Region tracking marks work, but the hardware
refresh compares each page against a shadow and transmits only changed pages over SPI0.
The LCD path is output-only; user input comes from the panel MCU.

### Firmware/resource update

```text
SD:KORG/hacktribe/System/*.VSB
  -> common resource-header validation
  -> battery-safety gate
  -> product/revision/length checks
  -> serial-flash write
  -> read-back verification
  -> runtime reload/rebuild where required
```

Confirmed bundle destinations:

| Bundle | Flash role | Size/limit |
| --- | --- | ---: |
| `BOOT.VSB` | Boot region | `0x20000` |
| `SYSTEM.VSB` | ARM firmware | exactly `0x200000` |
| `USER.VSB` | User/product data | up to `0x490000` |
| `PCM.VSB` | PCM image | exactly `0x800000` |
| `SLICE.VSB` | Slice metadata | up to `0x90000` |

The update dispatcher processes System, BOOT, PCM, USER, and SLICE resources. The battery
gate uses the active chemistry thresholds and normally requires classification level 2 or
higher. `SYSTEM.VSB` also has a separate product-aware install handler that checks the
installed product identity and minimum revision before writing selector 2, but the ordinary
five-image sequence calls the more permissive System loader. `BOOT.VSB` is accepted only as
its own boot-region step; it is not an alias for `SYSTEM.VSB`.

This update path is not an authenticity boundary: the CPU-side checks currently recovered are
resource format/magic/name/size checks, with no visible public-key signature or cryptographic
digest verification before the BOOT selector-0 write. The shared stream reader can also return
success after satisfying only the resource's remaining extent; update loaders ignore its
actual-byte-count output, so malformed short records can produce stale-tail images. Detailed
security evidence and hardening implications are recorded in [storage and updates](docs/architecture/evidence/storage-and-updates.md).

The SD block-transfer methods have a separate defensive boundary defect: `ReadSDCardBlocks` and
`WriteSDCardBlocks` validate `start + count` with wrap-prone unsigned addition and expose no
caller-buffer capacity. The known resource path normally supplies small, format-derived counts,
so a direct SD-file exploit is not established; the methods still require a subtraction-form
range check and an explicit buffer-capacity contract.

PCM SD-resource staging uses bounded scratch chunks, but `Pcm_ParseAndLoadWaveResource` does not
reject an odd converted 16-bit sample length before subtracting two per iteration; malformed PCM
metadata can therefore keep that service loop running indefinitely.

Detailed evidence: [storage and updates](docs/architecture/evidence/storage-and-updates.md).

### Ableton project export

Pattern-set handlers construct scene and nested slot vectors, retain reference-counted
text objects, and serialize Full or Lite Ableton project resources. The export container
owns nested vectors and their managed text fields; its destructors release those layers
explicitly.

Detailed evidence: [Ableton export](docs/architecture/evidence/ableton-export.md).

## CPU-DSP boundary

### BF523 boot

`StartupTask` resets the BF523 and streams the embedded Blackfin loader image over SPI1.
The extracted loader contains initialization and application records and is analyzed as a
separate BF523 Ghidra program. The BF523 application configures CPLBs/caches, installs
event vectors, initializes VDK, and creates its configured threads.

### Runtime Host DMA

AM1802 EMIFA CS2 exposes the BF523 four-byte Host DMA port at `0x60000000`.
Configuration records select BF523 source/destination, direction, count, and modify value.
Transfers are serialized by RTOS mutex ID 1 and move bounded FIFO chunks.

ARM command builders produce compact command records and address tokens. BF523 consumers
translate the tokens, update oscillator/control state, and acknowledge or publish runtime
state through the reciprocal path.

The voice-variant path is layered: `SendVoiceVariantDspPayload` reads the ARM `voice_t`
fields `+0x31/+0xB2/+0xB4/+0xB6` (voice index, variant selector, and two payload inputs),
which are maintained by `UpdateVoiceVariantParameterState` from the nested timbre state;
then `BuildAndSendDspVoiceVariantParameters` selects an ARM payload builder, adds `0x0A`
to the voice-state token (selecting record `+0x28`), and
`DspIf_SendHostCommand2F`/`DspIf_SendHostCommand30` transport the result. BF523 reads
the variant at that selector and uses the address of record `+0x2C` as the destination
base, then dispatches through separate 21-entry field-update families. A nonzero
repeat/count field applies the same payload to a second target at `+0x1B8`. The
command-specific payload layouts and unresolved field units are recorded in
[BF523 Host DMA/UART evidence](docs/architecture/evidence/dsp-hostdma-and-uart.md).
The normal `SendVoiceVariantDspPayload` path uses builder `packet_mode == 1`, so it
emits command `0x30` with the fixed overlay halfword `0x62`; the conditional wrapper
also has an observed mode-zero path using default halfword `0x5785`. No current
static caller of the central builder supplies mode `2` for command `0x2F`, so that
  branch remains an available but unconfirmed runtime path.
  In the conditional wrapper, the mode predicate is now reduced to a concrete test:
  IsVoiceTaskRateBaseInputZero computes the slot-0 base input, indexes the 128-entry
  table at 0xC00E8370, and compares the result with its first value 0x00B6DB6D.
  The complete table is strictly decreasing, so the predicate is true exactly for
  base input zero. The wrapper inverts that bit; therefore this special path emits
  0x5785 for base input zero and 0x62 for any other base input.

The variant path first normalizes the ARM-side variant selector through a 17-byte
class map; inputs `0x11` and above use fallback class `0x14`. This class chooses the
BF523 payload formatter, but it does not by itself establish a musical/product meaning.

Command `0x31` has two confirmed destination layouts. The voice-variant word-block
producer passes a voice-state token plus `0x0A`; BF523 translates that packet token
directly, so the first dword is written at the `0x1B4` state record's `+0x28`.
That first dword supplies the selector consumed by the BF523 variant paths, and
subsequent dwords continue at `+0x2C`; normalized-class blocks contain 12, 14, or
18 dwords, with fallback class `0x14` emitting one zero dword. The zeroing helper
uses token family `0x461C + voice*0x46` instead, which resolves to the `0x118`
voice record's `+0x04` and writes 14 zero dwords, optionally to an even/odd pair.
The same transport is therefore shared by state-variant initialization and
voice-record clearing, with the token family selecting the record type.

The voice-record command family is now structurally tied across the boundary: command
`0x33` updates variant-dependent linkage, command `0x34` initializes one or an even/odd
pair, command `0x35` refreshes the linked fields, and command `0x39` applies a variant
  update. The corresponding ARM voice index selects parallel BF523 records, while command
  `0x37` changes the BF523 selected-record pointer at `0xFF9031DC`; the sequencer maps
  ordinary voice indices to selectors `1..16` and paired voice indices to selectors
  `0x11..0x18` before sending it. Each audio slice dereferences that pointer and publishes
  the selected dword to `0xFF80004C`, tying the selector to a concrete DSP audio input.
  The same slice loop mirrors each voice-state record's active dword at `+0x00` into
  six corresponding voice-record dwords at `+0x100..+0x114`, so the command-`0x37`
  `+0x110`/`+0x114` choices are active-state mirrors.
  Before those per-voice updates, CPU `InitializeVoiceTaskDspVoiceRuntime` sends Host-DMA
  command `0x21`; BF523 case `0xFFA050EE` uses it to seed the callback-workspace fields
  within the `0x28`-byte records rooted at `0xFF800748` and the sixteen `0x118`-byte
  records at `0xFF90186C`. This is the startup topology stage for the later `0x31`–`0x39`
  record-update contract.
  Two BF523 L1 fixed-point audio-record kernels (`0xFFA00AD0` and `0xFFA00C80`) consume a
  common context whose `+0x04` field is that selected record/buffer pointer. They transform and
  write through the selected record, with the second kernel folding selected-record fields
  `+0x08/+0x0C` into linked output state. Both addresses are reused by external-SDRAM effect
  descriptors named `[I/Dbl] SR1 Comp`, `[I/Dbl] Limiter`, and `[I/Dbl] Ring Mod`; their exact
  field-level signal role remains unresolved. The DSP’s external effect descriptors
  are selected through a pointer table at `0x00004C30`, indexed by the masked
  per-slot effect byte at `0xFF9007CC + slot`. In the named `[I/Dbl]` records,
  the `[I/Dbl] SR1 Comp` and `[I/Dbl] Limiter` records contain the two
  selected-record transform addresses at descriptor offsets `+0x18/+0x1C`,
  while the `[I/Dbl] Ring Mod` record visibly references `0xFFA00AD0` among a
  broader callback set. A separate callback at `+0x20` is loaded and called by
  the external control path. This separates descriptor control callbacks from the
  shared audio-record transform pair; the exact audio-slice caller into that
  pair remains unresolved. The recovered `0x00..0x40` effect-ID/name vocabulary
  is recorded in [DSP host-DMA evidence](docs/architecture/evidence/dsp-hostdma-and-uart.md).
  The audio slice's recovered indirect callback layer is separate: audio-root `+0x18`
  is initialized to runtime table `0xFFB000E0`, a 20-entry copy of the static L1
  pointer table at `0xFF803B84`. `BF523_ProcessAudioDmaSlice` indexes it from the
  active state record's `+0x28` dispatch-selector field and calls the selected L1 kernel
  at `0xFFA01A72`. The seven
  observed targets are `0xFFA03820`, `0xFFA0383C`, `0xFFA03A1C`, `0xFFA03C3C`,
  `0xFFA03EAC`, `0xFFA0411E`, and `0xFFA042DA`; this table must not be conflated
  with the 52-entry oscillator callback table or the external descriptor transform
  fields. State `+0x2C` is the beginning of the per-record kernel context passed by
  the loop; the kernels access later context fields relative to that address. The
  instruction-level pointer walk enters the active path at `+0x10`, consumes state
  words through `+0x24`, then loads the selector at `+0x28`; its post-increment
  leaves the passed state context at `+0x2C`. The producer of the state `+0x28`
  selector is now confirmed: ARM `SendDspVoiceVariantWordBlock` emits command
  `0x31` with token `DspIf_GetVoiceStateRecordToken(voice) + 0x0A`, and BF523
  writes the first assembled dword directly at that field. The first dword's
  low halfword is then consumed by the command-`0x2F`/`0x30`/`0x33`/`0x39`
  variant dispatchers; its product/effect meaning remains unresolved.
  The previously suspected external writer at `0x01F0F630` remains excluded: its
  only caller passes a stack-local temporary as the object base, so its `+0x28`
  store is not a write to the global voice-state array.
  The command-`0x2F`/`0x30` paths are now tied across the boundary: ARM adds `0x0A`
  to the voice-state token, selecting record `+0x28`; BF523 reads that variant
  and uses the address of record `+0x2C` as the destination base. In command
  `0x30`, the variant helper's destination `+0x28` writes therefore target
  record `+0x54`, not the selector.
  At the field level, command `0x31` establishes the class-specific baseline
  beginning at `+0x28`, while command `0x30` overlays selected runtime values in
  that same context. The confirmed command-`0x30` implementations write
  `+0x14/+0x18`, `+0x2C/+0x30`, `+0x34/+0x38`,
  `+0x24/+0x28/+0x2C/+0x30/+0x34/+0x38/+0x3C/+0x40`, or
  `+0x1C/+0x20/+0x24/+0x28/+0x2C/+0x30`, depending on the selector. The
  audio-slice loop then consumes context words through `+0x44` and uses
  `+0x44` as an indirect output pointer. This is a confirmed shared record
  contract; the fixed-point/product meanings of individual words remain
  unresolved.
  The normalized ARM variant index and that low-halfword selector are distinct:
  the normalized index directly selects the 20-entry BF523 audio table
  (0 -> 0xFFA03820; 1,2,8,14 -> 0xFFA0383C; 3,9,15 -> 0xFFA03A1C;
  4,10,16 -> 0xFFA03C3C; 5,11,17 -> 0xFFA03EAC; 6 -> 0xFFA0411E;
  7,12,13,18,19 -> 0xFFA042DA), while the command-31 first dword supplies
  the separate selector sequence
  1,2,6,7,3,5,4,8,0x0C,0x0D,9,0x0B,0x0A,0x0E,0x12,0x13,0x0F,0x11,0x10,0x14.
  Variant index 20 supplies selector zero but lies outside the audio table.
  This separation is the current CPU-DSP contract; product/effect names remain
  unresolved.
  L1 helpers `0xFFA00728` and `0xFFA01260` also write `+0x28`, but on nested objects
  loaded through an input object's `+0x04/+0x08` fields. Their relationship to the
  global `0xFF800B08 + voice*0x1B4` records is unproven, so they are not selector
  producers yet.
  The descriptor-control side is separate: external `0x17C78` selects a per-slot
  descriptor and calls its `+0x2C` callback with pointer-lattice and voice-record
  state, while `0x17DC4` writes per-slot parameter state and follows descriptor
  `+0x14` control entries. These paths do not directly call the selected-record
  audio kernels.
  A separate BF523 external-state workflow uses two `0x18`-byte controller records
  at `0xFF803CE0`/`0xFF803CF8`; the active record is published at `0xFF900014` and
  advances through a seven-state handler table at `0x01F02B68`. Its observed flow
  gates and clears bounded external regions before finalizing state; the exact
  product/resource service remains unresolved. The first controller callback also
  consumes one of two bounded external effect-control blocks and forwards their
  low-halfword values through the effect-slot parameter-state path; the external
  block producer and protocol meaning remain unresolved.
The command-`0x33` ARM producer emits
either a single-record or even/odd paired form from `Voice_ApplyOscillatorSlotToDsp`.
The linked-update commands are asymmetric but share a stable packet direction: the ARM
state-linked token is first and the paired `0x118` voice-record token is second. BF523
commands `0x33` and `0x39` read their variant from state `+0x28` and source from state
`+0x2C`; command `0x35` uses the same selector and source offsets, additionally copying
state `+0x20` to `+0x24` before applying the update to the second voice record. Command
`0x33` instead addresses state `+0x28`, passes state `+0x30` to its helper, and that
helper reads its source scalar at state `+0x20`. The individual variant-field meanings
remain intentionally unresolved.
The individual variant-field meanings remain intentionally unresolved.

The BF523 audio initializer also constructs a pointer lattice at `0xFF902B7C`.
Its sixteen output positions advance by `0x50` bytes while drawing from the `0x1B4`-byte
voice-state array, the `0x118`-byte voice-record array, and a companion region rooted at
`0x0001A2C0`; additional derived pointer columns extend through root `+0x4D4`.
This is a separate DSP-side indirection layer used by later control/audio paths, not a
replacement for the direct Host-DMA token mapping used by commands `0x31`/`0x33`/`0x35`/`0x39`.
Its exact column semantics remain unresolved.

For oscillator slots, VoiceTask prepares an ARM `0x48`-byte slot, optionally copies
one of the BF523 template records with command `0x09`, then applies the slot through
the command sequence that updates descriptor parameters, callback linkage, and the
paired workspace. Commands `0x1F` and `0x32` pair descriptor `+0x0C` with workspace
  `+0x08`; BF523 dispatches on descriptor `callback_index` at `+0x0C`, passes the
  descriptor block beginning at `+0x10` as the source parameters, and updates the
  workspace through its 44-entry callback-index table. The slot allocator, retrigger,
  and refresh paths share `Voice_PrepareOscillatorSlotState`; BF523 performs the
  real-time rendering from the resulting descriptor/workspace state.
  Template preset loading supplies that contract: command `0x31` writes a static
  block whose first dword is `callback_index` and whose remaining dwords are the
  callback's parameter block beginning at `+0x10`.

### Audio processing

The BF523 audio thread services SPORT0 through DMA, processes oscillator and effect state,
and walks the live voice workspaces for each audio slice. During the PCM-load path,
command `0x3B` changes the workspace selected through the audio-root pointer cell before
the slice path consumes the transfer state. The ARM does not render audio samples itself.

## Hardware interface map

| Interface | ARM peripheral | Role |
| --- | --- | --- |
| Panel MCU | UART0 | Buttons, knobs, pads, identity, battery/power reports, panel commands |
| TRS MIDI | UART1 | MIDI receive/transmit |
| USB | USB0 device controller | USB MIDI and control requests |
| LCD | SPI0 + GPIO | Output-only framebuffer/page transfer and reset/control |
| Serial flash | SPI1 + GPIO | Boot/system/user/PCM/slice persistent storage |
| BF523 boot | SPI1 + reset GPIO | Blackfin loader stream |
| BF523 runtime | EMIFA CS2 Host DMA | High-speed commands, data, and state |
| SD card | SD/MMC | Resource, update, import/export, and user files |
| Audio codec/I/O | BF523 SPORT0 + DMA | Real-time audio input/output |

Detailed register, GPIO, endpoint-state, timer, and packet evidence:
[hardware I/O](docs/architecture/evidence/hardware-io.md).

## Persistence and formats

The application uses several independent persistent representations:

- 2 MiB ARM system image.
- PCM/sample image and separate slice metadata.
- Voice-assignment mode image (`0x3E8000` bytes).
- Serialized VoiceTask/shared-control images.
- Pattern/resource records.
- Wave/ELSI metadata.
- VSB update bundles.
- Ableton project export data.

Do not infer that two selectors or records share a format merely because they use the same
flash or SD-card helper. Format identity requires matching validation, size, and consumer
data flow.

## Confirmed uncertainty

The principal architecture-level open questions are:

- Product/electrical meanings for several GPIO and panel command lines.
- Battery measurement units and DC-jack polarity.
- Vendor meanings for several USB endpoint state bits and control variants.
- Product meanings for some VoiceTask selectors, mapped-state values, and DSP commands.
- Callsite ownership, if any, for RTOS mutex IDs 3 through 5.
- Exact expansion of the firmware acronym `VSB`.

Uncertainty belongs in [open questions](docs/architecture/evidence/open-questions.md) or in
the relevant Ghidra comment. It should not be hidden inside a confident symbol name.

## Detailed evidence index

| Topic | Evidence |
| --- | --- |
| Boot, startup, board setup, interrupts | [boot-and-interrupts.md](docs/architecture/evidence/boot-and-interrupts.md) |
| Task descriptors and CommandTask handlers | [rtos-tasks-and-command-dispatch.md](docs/architecture/evidence/rtos-tasks-and-command-dispatch.md) |
| Sequencer, mapped state, slots, timing | [sequencer-and-mapped-state.md](docs/architecture/evidence/sequencer-and-mapped-state.md) |
| VoiceTask services and common messages | [voice-control-and-services.md](docs/architecture/evidence/voice-control-and-services.md) |
| MIDI, USB transport, central routing | [midi-usb-and-common-messages.md](docs/architecture/evidence/midi-usb-and-common-messages.md) |
| RTOS implementation | [rtos-kernel.md](docs/architecture/evidence/rtos-kernel.md) |
| BF523 boot, VDK, and audio | [dsp-boot-and-audio.md](docs/architecture/evidence/dsp-boot-and-audio.md) |
| PCM resources, analysis, and playback | [pcm-sample-engine.md](docs/architecture/evidence/pcm-sample-engine.md) |
| Voice assignment and DSP control | [voice-dsp-control.md](docs/architecture/evidence/voice-dsp-control.md) |
| BF523 Host DMA and UART paths | [dsp-hostdma-and-uart.md](docs/architecture/evidence/dsp-hostdma-and-uart.md) |
| Serial flash, SD resources, updates | [storage-and-updates.md](docs/architecture/evidence/storage-and-updates.md) |
| Host DMA, USB, panel, LCD, timers, SD/MMC | [hardware-io.md](docs/architecture/evidence/hardware-io.md) |
| Ableton project export | [ableton-export.md](docs/architecture/evidence/ableton-export.md) |
| Explicit unresolved items | [open-questions.md](docs/architecture/evidence/open-questions.md) |

## Maintenance rules

When reverse engineering produces a confirmed finding:

1. **Update Ghidra first.** Apply the name, prototype, type, namespace/class, and useful
   comments at the actual program locations.
2. **Update one evidence file.** Record proof, addresses, layouts, constants, and
   uncertainty in the narrowest relevant subsystem document.
3. **Update this file only for architecture.** Change it when ownership, lifecycle,
   subsystem boundaries, record contracts, or an end-to-end flow changes.
4. Keep routine xref inventories, decompiler narration, and long lists of values out of
   this root document.
5. Retain constants here only when they define a protocol, persistent layout, state
   machine, safety boundary, or cross-subsystem contract.
6. Never promote an inference to a fact merely to make the document look complete.
