# BF523 Host DMA and UART control paths

> Detailed evidence extracted from the original monolithic ARCHITECTURE.md.
> Ghidra is authoritative for current symbols, types, comments, and cross-references.

### BF523 Host DMA and UART message paths

- `BF523_HostDPMTxThread_Run` begins by calling
  `BF523_InitializeHostDmaPort` at `0x00018F32`. That function installs Host
  DMA interrupt routing and writes `HOST_CONTROL=0x0344` before setting
  `HOSTDP_EN`, leaving `0x0345`. The documented bits select 16-bit host data,
  interrupt mode, host writes and reads enabled, burst DMA requests enabled,
  and the port enabled.
- On its VDK interrupt-driven path, HostDPMTx calls
  `BF523_ProcessHostDmaPortCommand` at `0xFFA04EC8`. This routine tests
  `HOST_STATUS.HSHK`, validates state in `g_HostDmaCommandBuffer`
  (`0xFF900A34`), and accepts a 16-bit command type below `0x3C`. It dispatches
  through the corresponding entry in the 60-element function-pointer table at
  `g_apHostDmaCommandDispatch` (`0x01F02B84`). The non-null entries target case
  labels within this routine, not independent functions. All 60 entries are
  populated. Blackfin loader fill records expand command IDs `0x03`-`0x08`,
  `0x0A`-`0x15`, and `0x17`-`0x1E` to the shared handler at `0xFFA04F50`;
  these entries appear as zeros only in flat artifacts that do not materialize
  fill records. The complete expanded table is typed and labeled in the BF523
  Ghidra program.
- The application command buffer begins with the confirmed six-byte
  `E2_HostDmaCommandHeader`: `state_flags` at `+0x00`, `command_id` at `+0x02`,
  and the command-specific `argument_04` at `+0x04`. Every identified ARM
  producer initializes `state_flags` to `0x0106`. The BF523 tests bits `0x0104`
  against the current processing mode and clears bit 1 when it accepts the
  command.
- Command payload addresses are 16-bit word-address tokens, not raw pointers.
  `BF523_TranslateHostWordAddress` at `0xFFA071CC` maps tokens below `0x4000`
  to `0xFF800000 + token*4` and all other tokens to
  `0xFF8F0000 + token*4`. For example, token `0x428D` maps exactly to the
  command buffer at `0xFF900A34`.
- The ARM-side DspIf builders at `0xC0011EB0` through `0xC00125F0` construct
  variable application commands and write them to `0xFF900A34` through
  `WritePaddedBufferToDspViaHostDma`. Their callers directly confirm use of
  command IDs `0x00`, `0x01`, `0x02`, `0x09`, `0x16`, `0x1F`, `0x21`,
  `0x26`, `0x2B`, `0x2E`, `0x32`-`0x39`, and others. Separate builders at
  `0xC0094BE0`, `0xC001310C`, `0xC00132C0`, `0xC00134F4`, `0xC00137A8`,
  and `0xC0013D98` embed fixed command IDs `0x2C`, `0x2D`, `0x2F`, `0x30`,
   `0x31`, and `0x3B`, respectively.
   The CPU builder at `0xC0013D98` is `DspIf_SendMdmaTransferCommand3B`: it emits
   `{header, 0x3B, phase, sampling-mode, sampling-source, storage-end-high,
   storage-end-low}` under DSP mutex 1. Phase 1 is used to begin a sample transfer;
   the load-state completion path sends phase 0 with zero payload fields.
   The extracted BF523 dispatch table resolves first-level command `0x3B` to the
   case at `0xFFA056F0`. Its fixed state base is `0xFF9031D8`, which is the
   audio-engine state at `g_DspAudioEngineState + 0x134`; the command-specific
   fields therefore land at root offsets `+0x154`, `+0x158`, `+0x15C`, `+0x160`,
   and `+0x168`. For phase 1, the case sets state `+0x20` to 1, selects configuration value 2 or 4 at `+0x24`
    from `sampling-mode`, selects a source pointer at `+0x28` from the fixed
    `0xFF802878` workspace using the `(sampling-source, sampling-mode)` pair
   (`+0x04` for source=0/mode=0, `+0x00` for source=0/mode!=0, `+0x14` for
   source!=0/mode=0, and `+0x10` for source!=0/mode!=0),
   copies the 32-bit storage-end value from packet `+0x0A/+0x0C` to state
   `+0x2C`, and sets state `+0x34` to 1. It also publishes pointer
   `0xFF80004C` through the shared pointer cell at `0xFF8029DC`. Phase 0 clears
   the MDMA state fields observed at `+0x20` and `+0x34`, restores the pointer
   cell to `0xFF803540`, and resets `0xFF802FAC` to `0x01C65EE4`. The audio-state
   initializer `BF523_InitializeAudioEngineState` (`0x01F0C55C`) seeds root
   `+0x13C` with `0xFF8029DC` and root `+0x140` with `0xFF802FAC`, confirming
   that these are persistent audio-engine pointer cells rather than packet data.
   The same initializer clears root `+0x154` and `+0x168` and initializes the
   storage-end field at root `+0x160` to `0x00365EC0`; command `0x3B` therefore
   overwrites a pre-existing audio-engine transfer-state record rather than
   creating a transient packet object. The audio slice later writes its updated
   storage-end result to root `+0x16C` (`0xFF903210`), the exact BF523 address
   read by ARM `Pcm_GetDspSampleStorageEnd` before the next runtime allocation;
   the packet's `+0x160` value and this maintained `+0x16C` value are distinct
   fields.
   The pointer side effect has a confirmed audio-processing consumer: the same
   initializer stores `0xFF8029DC` at audio-root `+0x13C`, and
   `BF523_ProcessAudioDmaSlice` (`0xFFA0141A`) loads that root field, dereferences
   the pointer cell, and reads/writes the selected workspace record. Thus command
   `0x3B` changes which workspace record the audio slice path operates on during
   phase 1 and restores the normal workspace during phase 0. This ties the CPU
   PCM-load command to the DSP audio state machine; it does not yet prove that
   the generic MDMA register helper below is its direct callee.
    The same audio-state initializer stores MMR pointers at root `+0x100`, `+0x104`,
    `+0x108`, `+0x114`, `+0x118`, `+0x11c`, and `+0x120`. They resolve respectively
    to `MDMA_D0_IRQ_STATUS` (`0xFFC00F28`), `MDMA_S0_NEXT_DESC_PTR` (`0xFFC00F40`),
    `MDMA_D0_NEXT_DESC_PTR` (`0xFFC00F00`), `MDMA_S0_X_MODIFY` (`0xFFC00F08`),
    `MDMA_D0_X_MODIFY` (`0xFFC00F14`), `MDMA_S0_CONFIG` (`0xFFC00F54`), and
    `MDMA_D0_CONFIG` (`0xFFC00F48`). At the start of the audio slice's MDMA setup,
    the slice polls bit 3 through the status pointer, accesses the S0/D0 descriptor
    pointer registers, and writes the S0/D0 X_MODIFY and CONFIG registers through
    the remaining slots. This proves that the `0x3B`-related audio path includes
    direct MDMA-register synchronization in the audio path sharing the `0x3B` state,
    although the descriptor formats and exact
    transfer-unit semantics remain unresolved.
    Within that slice path, the optional transfer branch is gated by audio-root
   `+0x154` and consumes the adjacent state at `+0x158`, `+0x15C`, `+0x160`,
   and `+0x164`. It reads a word from the workspace selected through `+0x15C`,
   byte-swaps that word into `0xFF80004C`, republishes the same workspace pointer
   through the `0xFF8029DC` cell, writes the pre-increment staged end through the
   reset-cell pointer at root `+0x140`, and computes `candidate = +0x160 + +0x158`.
   If `+0x164 <= candidate`, it replaces the candidate with `+0x164` and stores 2
   at `+0x168`; it then clears `+0x154` and writes the resulting endpoint to both
   `+0x160` and maintained field `+0x16C` (`0xFF903210`). The exact transfer units
   and field product meanings remain unresolved, but the endpoint arithmetic is
   confirmed by the instruction sequence.
   These are confirmed DSP-side effects; the hardware-register and sample-format meanings
   of the state fields are still unresolved.
   A separate BF523 helper, `FUN_01F0E15C` (`0x01F0E15C-0x01F0E28F`), directly
   programs MDMA D1/S1 in chunks of at most `0x40` units. It uses
   `FUN_01F0E0E8` as an external-SDRAM range-overlap check and starts/stops the
   channels through the shared MDMA wait helper. Its known owner,
   `FUN_00017EAC`, copies a bounded list of segments into the staging buffer at
   `0xFFA04612`; the accumulated size is rejected once it reaches 2000 units.
   Call sites at `0x00018BC4` and `0x00018BFE` reach that owner. This D1/S1
   staging route is separate from live command `0x3B`: the live path has no
   established call edge to `FUN_01F0E15C` and the audio slice directly programs
   MDMA D0/S0. The product-level service represented by `FUN_00017EAC` remains
   unresolved.
- One non-PCM scalar path is now tied across the boundary at an exact DSP address.
  CPU `SendDspScalarZeroOrMax` (`0xC009A808`) converts its input to either
  `0` or `0x7FFFFFFF`, then emits command `0x01` with token `0x4C4E` through
  `DspIf_SendHostCommand1WithTokenAndDword` (`0xC0012B4C`). The BF523 command-`0x01`
  case (`0xFFA05000`) translates tokens at or above `0x4000` as
  `0xFF8F0000 + token*4`; therefore `0x4C4E` targets `0xFF903338` (audio-root
  offset `+0x294`) and receives the assembled 32-bit payload. The target is
  confirmed, but its product-level control meaning and downstream consumers
  remain unresolved.
 - The generic CPU packet builders have now been bounded at the halfword level:
  `DspIf_SendHostCommand2Words` emits `{0x0106, command}`;
  `DspIf_SendHostCommand4Words` emits `{0x0106, command, argument, payload}`;
  `DspIf_SendHostCommand5Words` emits a command, zero argument, and two payload
  words; `DspIf_SendHostCommand6Words` emits a command, zero argument, one
  payload word, and one dword; `DspIf_SendHostCommand7Words` emits a command,
  selector value 1, and four payload words; and
  `DspIf_SendHostCommand9Words` emits the observed command/zero/dword/word/dword
  form. `DspIf_SendHostCommandWordArray` copies a leading word and variable
  array data after the header. These are packet-shape findings; their individual
  command-field meanings remain caller-specific.
 - The CPU-side transfer boundary is also explicit. `WaitForDspHostDmaAllowConfig`
   polls status bit 7 at `0x60000002`, while
   `WriteBufferToDspViaHostDma` emits the seven-halfword memory-write configuration
   beginning with `0x00AB` and streams at most 16 halfwords per FIFO block.
   `WriteAlignedBufferToDspViaHostDma` handles counts above 15 by writing a leading
   16-halfword block and then the remaining aligned block; `WritePaddedBufferToDspViaHostDma`
   rounds application packet counts to the 16-word boundary. The top-level
   `WriteDspMemoryViaHostDma` serializes these writes with RTOS mutex 1. Its four
   current callers are the PCM stream parser, the runtime PCM-catalog rebuild,
   a DSP event-buffer writer, and the voice-service DSP memory test; the known
   PCM and test destinations are derived from runtime state or fixed data, and
   the wrapper itself does not impose a BF523 address-range check. The corresponding
   read helper begins with `0x00A9`.
   A search of this call chain found no known CPU caller that supplies the literal
   BF523 backing addresses `0xFF800034` or `0xFF900CBC` used indirectly by the
   audio root's descriptor/configuration pointer chains. Their exact producer
   remains unresolved; static extracted backing words are zero, so they may be
   runtime-populated rather than firmware-initialized.
 - Fixed CPU builders are now documented at the packet boundary:
  `DspIf_SendHostCommand2D` emits command `0x2D` with one translated token
  and two halfwords; `DspIf_SendHostCommand2F` emits command `0x2F` with a
  boolean flag, token, dword payload fields, and the observed intervening zero;
   `DspIf_SendHostCommand30` emits command `0x30` with a flag, token, three
   dwords, one halfword, and a final dword; and the locked `0x31` builder emits
   a token followed by count-plus-one high/low dword pairs. The destination-token
   and payload product meanings remain unresolved.
   The generic `0x31` builder has no count guard: its unlocked local payload area
   holds six dwords, while the locked builder's area holds 63. The locked wrapper
   forwards its count unchanged. The recovered CPU call graph currently supplies
   only counts 1, 2, or 13 in the general wrapper, a fixed maximum of 18 in the
   oscillator-preset path, and 1/12/14/18 in the variant-table path, so no oversized
   CPU-side packet is established; the BF523 command-`0x31` handler also has no
   visible count/range check and relies on the producer contract.
- Several mutex-guarded consumers now anchor the generic packet shapes to CPU
  behavior: `DspIf_SendHostCommand21Locked` sends fixed command `0x21`;
  `DspIf_WriteDspUpperHalfwordByToken` uses command `0x00` to write a
  token-selected upper halfword; `DspIf_SendHostCommand2WordArrayLocked`
  wraps command `0x02`; `DspIf_SendHostCommand36DwordLocked` splits one
  dword for command `0x36`; and the command-`0x37` wrappers distinguish
  voice-record selection (`argument_04=1`) from the fixed-record selection
  path (`argument_04=0`). These observations constrain the CPU-side
  dispatch contract without assigning product names to the DSP fields.
- Command `0x21` has a more specific startup contract than its packet shape alone
  suggests. The BF523 case at `0xFFA050EE` accepts only dispatcher mode `4`. It
  waits for the shared workspace word at `0xFF802870` to become nonzero, using
  the initialization path through `0x01F0E7F4` and `0xFFA0B94C`. It then derives
  a count `N = (word[0xFF802870] << 8) + (word[0xFF802874] >> 9)`, fills `N`
  callback-workspace fields `+0x08/+0x0c` in the `0x28`-byte records rooted at
  `0xFF800748` (the first written address is `0xFF800750`) with fields `{x,
  5*x+1}` while advancing `x` as `25*x+6`, and seeds the first dword of sixteen `0x118`-byte
  records at `0xFF90186C` with the subsequent `5*x+1` sequence. CPU
  `InitializeVoiceTaskDspVoiceRuntime` (`0xC009B6B8`) sends the fixed packet once
  after preparing the ARM-side voice/control tables. The record topology is
  confirmed; the generated values' product-level meaning is not.
- Command `0x26` is the paired oscillator-slot deactivation/reset operation. The
  BF523 case at `0xFFA05172` accepts only dispatcher mode `0x0104` and walks
  `argument_04 + 1` token pairs. The first token translates to descriptor `+0x00`;
  the second translates to workspace `+0x04`. For each pair it clears the
  descriptor active word, copies descriptor `+0x64` (`template_index`) to
  workspace `+0x00`, and clears workspace `+0x04`. CPU
  `DspIf_DeactivateOscillatorVoiceSlotAndResetWorkspace` (`0xC00985CC`) is the
  corresponding producer after the ARM slot allocation bit is cleared. This
  preserves template identity while returning the callback workspace to its
  inactive state; the remaining workspace fields are unaffected by this command.
- The CPU oscillator update path is now bounded at
  `PrepareOscillatorMetadataParameterUpdate` (`0xC0099944`) and
  `ComputeAndSendOscillatorParameterPayload` (`0xC009559C`). The first resolves the
  metadata record selected by object field `+0x3A`, then supplies the object fields
  `+0x14`, `+0x3E`, and `+0x3F`, metadata selector `+0x12`, metadata flags `+0x19`
  and `+0x1D`, and conditional linked-object `+0x9C` values. The calculator handles
  selectors `0..0x31` plus the observed PCM cases, derives a per-voice oscillator
  token, and conditionally emits Host-DMA command `0x2D` (two payload halfwords) and
  command `0x2E` (one payload halfword). These names describe data flow; individual
  oscillator-parameter meanings remain unresolved.
- `Voice_ApplyOscillatorSlotToDsp` (`0xC0098604`) invokes this metadata update while
  applying one ARM `0x48`-byte oscillator-slot record. The two auxiliary paths are now
  named `RefreshOscillatorMetadataParameterUpdate` (`0xC0099A04`), which performs the
  observed metadata pre-step before re-emitting the payload, and
  `EmitOscillatorMetadataParameterUpdate` (`0xC0099A2C`), which directly resolves the
  `+0x3A` metadata record and re-emits its selector payload.
- The first descriptor writes in `Voice_ApplyOscillatorSlotToDsp` are now bounded.
  `DspIf_WriteOscillatorSlotDescriptorField04` (`0xC00985B4`) sends the slot
  halfword at `+0x2C` as command `0x2B` to descriptor token
  `0x43AC + slot*0x1A`, which is descriptor offset `+0x04`. The following
  `DspIf_SendHostCommand2C` sends the slot `+0x2E` value with adjacent tokens
   `0x43AC`/`0x43AD` (descriptor offsets `+0x04`/`+0x08`). These writes establish
   the descriptor's early linked-object state before the variant workspace path;
   their product-level meanings remain unresolved.
- The corresponding BF523 cases show the transformation stage behind those
  writes. Case `0xFFA051C0` (command `0x2B`) translates descriptor `+0x04`,
  stores the payload in that destination's upper halfword, adds the payload to
  the previous upper-halfword value, clamps the helper input to `0..0x7FFF`
  when descriptor `+0x08` is below `0x21`, and calls helper `0xFFA06970` with
  selector descriptor `+0x08` and destination descriptor `+0x0C`. Case
  `0xFFA05210` (command `0x2C`) translates descriptor `+0x04` and `+0x08`,
  stores the signed payload in `+0x08`, adds it to the old upper halfword at
  `+0x04`, clamps to `0..0x7FFF` when descriptor `+0x0C` is below `0x21`, and
  calls the same helper with selector `+0x0C` and destination `+0x08`. Thus the
  ARM slot fields `+0x2C`/`+0x2E` feed a DSP descriptor-update stage before
  command `0x32`; the resulting accumulator units remain unresolved.
- The shared DSP helper at `0xFFA06970` is a separate 44-way dispatcher used by
  both descriptor cases. Its observed argument contract is `R0=variant index`,
  `R1=bounded value`, and `R2=destination pointer`; indices below `44` select
  the table at `0x01F03068`, while out-of-range indices return without a table
   operation. This table must not be confused with the command-`0x32` table at
  `0x01F02CD8`: both have 44 entries, but the former is reached by descriptor
   commands `0x2B`/`0x2C` and the latter by oscillator workspace command `0x32`.
- The descriptor-parameter table at `0x01F03068` was enumerated as follows:
  `0`→`0xFFA069A0`, `1..2`→`0xFFA069AC`, `3`→`0xFFA069CA`, `4`→`0xFFA06A08`,
  `5`→`0xFFA06A3C`, `6`→`0xFFA06A48`, `7`→`0xFFA06A54`, `8`→`0xFFA06A60`,
  `9..10`→`0xFFA06A74`, `11`→`0xFFA06AC2`, `12`→`0xFFA06B08`,
  `13`→`0xFFA06B3E`, `14`→`0xFFA06BAC`, `15`→`0xFFA06C40`,
  `16`→`0xFFA06C7C`, `17..18`→`0xFFA06CB8`, `19`→`0xFFA06D02`,
  `20`→`0xFFA06D48`, `21`→`0xFFA06D86`, `22`→`0xFFA06DD4`,
  `23`→`0xFFA06E22`, `24`→`0xFFA06E68`, `25..26`→`0xFFA06E9E`,
  `27`→`0xFFA06EE0`, `28`→`0xFFA06F1E`, `29..30`→`0xFFA06F54`,
  `31`→`0xFFA06F8C`, `32`→`0xFFA06FC4`, `33`→`0xFFA06FF0`,
  `34`→`0xFFA07012`, `35`→`0xFFA07026`, `36`→`0xFFA07032`,
  `37`→`0xFFA0703E`, `38`→`0xFFA0708E`, `39`→`0xFFA070EA`,
  `40`→`0xFFA0712C`, `41`→`0xFFA07138`, `42`→`0xFFA07144`, and `43` aliases
  index `0`. This is implementation-reuse evidence, not product naming.
- The selector-dependent parameter commands have separate BF523 consumers.
  Command `0x2D` case `0xFFA05268` translates its object token, reads the
  object's low halfword as a selector, and calls `0xFFA05DD0` with the object
  `+0x04` address and the payload pointer; that helper dispatches selectors
  below `44` through the table at `0x01F02ED8`. Command `0x2E` case
  `0xFFA05290` passes the same object/payload shape to `0xFFA06474`; that
  helper routes selectors `25..32` through the eight-entry table at
  `0x01F02F88` and handles selectors `33..35` with dedicated cases. The CPU
  `ComputeAndSendOscillatorParameterPayload` path therefore supplies the
  per-voice token and selector payload to distinct DSP-side selector families;
  their field meanings remain unresolved. The `0x2D` helper packs the two
  payload halfwords into one 32-bit value and preserves the first halfword as
  a scalar; selectors `1/2` write the packed value at target `+0x10`, selector
  `3` at `+0x1C`, and selector `4` at `+0x20` while deriving a related value
  at `+0x14` (offsets relative to the passed object `+0x04`). The `0x2E`
  inline selectors `33`, `34`, and `35` write the payload halfword to target
  `+0x30` after a 16-bit shift, target `+0x24`, and the passed target `+0x04`
  address respectively; selectors `25..32` remain table-dispatched.
- The command-`0x2E` selector table at `0x01F02F88` has eight entries for
  selectors `25..32`: `25..26`→`0xFFA06508`, `27`→`0xFFA06548`,
  `28`→`0xFFA06582`, `29..30`→`0xFFA065B6`, `31`→`0xFFA065F0`, and
  `32`→`0xFFA06624`. The targets call shared fixed-point helpers and write
  selector-dependent record fields; their product meanings remain unresolved.
- Commands `0x2F` and `0x30` form the following parameter-application stage.
  Their BF523 cases read the target object's low halfword as the variant,
  pass `(variant, target +0x04, payload-at-command-+0x08)` to
  `0xFFA05CB2`, and, for command `0x30`, also pass the same tuple to
  `0xFFA05BF0`. The first helper dispatches variants below `21` through
  `0x01F02E84`; the second uses a distinct 21-entry table at `0x01F02E30`.
  The `0x2F` helper packs payload halfword pairs at offsets `0/2`, `4/6`,
  `8/0x0A`, and `0x0E/0x10` into four 32-bit intermediates before dispatch.
  The `0x30` helper instead consumes payload halfword `+0x0C` as a signed
  fixed-point input and derives the destination values from it. Relative to
  the command packet, this is payload base `+0x08`, therefore packet `+0x14`;
  on the ARM side it is the serialized `param_5`, `0x5785` for `packet_mode == 0`
  and `0x62` otherwise. Observed
  command-`0x2F` cases update groups around destination offsets `+0x34..+0x50`
  (relative to the passed `target +0x04`) and a marker at `-0x10`, while
  command `0x30` cases update groups around `+0x14..+0x40`; these are
  structural offsets, not assigned musical field names.
  The first shared dispatcher also preserves a stable output-word contract: the
  ARM builder's dwords 0..2 are reconstructed from packet halfword pairs at
  payload offsets `0/2`, `4/6`, and `8/0x0A`; dword 3 is reconstructed from
  `0x0E/0x10`. Its command-`0x2F` table writes those words as follows (offsets
  relative to the passed state `+0x2C` base): groups `{1,2,8,14,20}` map
  dwords 0..2 to `+0x2C/+0x30/+0x3C`; `{3,9,15}` map them to
  `+0x44/+0x48/+0x4C`; `{4,10,16}` map dwords 0..3 to
  `+0x48/+0x4C/+0x50/+0x44`; `{5,11,17}` map dwords 0..2 to
  `+0x44/+0x40/+0x3C`; selector `6` maps dwords 0,1,3 to
  `+0x4C/+0x50/+0x44`; and `{7,12,13,18,19}` map dwords 0..2 to
  `+0x34/+0x3C/+0x38`. The command-`0x30` case invokes this same first
  dispatcher before its separate halfword overlay, so both commands share
  this output-word-to-context mapping. Additional marker/derived stores remain
  intentionally unnamed.
  In particular, the `0xFFA05BF0` variant helpers write destination `+0x28`
  for variants `6` and `7/12/13/18/19`. The CPU producer
  `BuildAndSendDspVoiceVariantParameters` obtains token `0x02C2 + voice*0x6D`
  from `DspIf_GetVoiceStateRecordToken` and adds decimal `10` (`0x0A`) for
  both command `0x2F` (`packet_mode == 2`) and command `0x30`, so each
  translates directly to the voice-state record `+0x28`. The BF523 cases read
  the variant halfword there and pass the address of the following word
  (`record +0x2C`) as the destination base. Consequently command-`0x30`
  helper `+0x28` writes land at `record +0x54`, not at the selector; both
  commands consume the selector rather than producing it.
  The repeated table targets also establish shared variant families: command
  `0x2F` groups `{1,2,8,14,20}`, `{3,9,15}`, `{4,10,16}`, `{5,11,17}`,
  `{6}`, and `{7,12,13,18,19}` share target implementations; command `0x30`
  has corresponding groups `{1,2,8,14,20}`, `{3,9,15}`, `{4,10,16}`,
  `{5,11,17}`, `{6}`, and `{7,12,13,18,19}`, with variant `0` taking the
  no-op target. This is a confirmed implementation grouping, not a product
  naming assignment.
  The ARM normalized-class builders are now named by implementation class:
  `BuildDspVariantPayloadClass0` (`0xC0093EB4`) emits three dwords for classes
  `{0,1,7,13,19}`; `Class2` (`0xC00944F4`) emits four for `{2}`; `Class3`
  (`0xC00946B0`) emits four for `{3,14,15}`; `Class4` (`0xC0093F40`) emits
  three for `{4,10,16}`; `Class5` (`0xC009438C`) emits four for `{5,11,17}`;
  `Class6` (`0xC00940F8`) emits four for `{6,12,18}`; and `Class8`
  (`0xC0094860`) emits four for `{8,9}`. These are CPU packet-construction
  classes, not product/effect names.
  When the command's repeat/count field is nonzero, the cases repeat the
  application at the target offset `+0x1B8`. This ties the ARM variant-payload
  builders to two distinct DSP-side field-application families while leaving
  the field units unresolved.
- Several command operations are structurally confirmed even though their
  higher-level musical semantics remain unresolved. Commands `0x00`, `0x01`,
  and `0x02` write upper halfwords, full 32-bit values, or sequential upper
  halfwords to translated destinations. Command `0x09` copies 26 dwords between
  translated addresses; `0x16` writes pairs of upper halfwords; and `0x31`
  writes sequential dwords assembled from high/low payload halfwords. Commands
  `0x2D` through `0x35` update linked DSP object state through distinct helper
  routines, while `0x3B` configures an MDMA transfer. These labels deliberately
  describe observed memory effects rather than assigning unproven feature names.
- Command `0x37` has a second 25-entry table at
  `g_apHostDmaCommand37Subdispatch` (`0x01F02C74`). Its first entry targets
  `0xFFA05778`; loader fill records assign subcommands 1-16 to `0xFFA0577C`
  and subcommands 17-24 to `0xFFA05798`. Subcommand 0 selects the fixed pointer
  `0xFF802878`. Subcommands 1-16 select field `+0x110` from one of sixteen
  `0x118`-byte records rooted at `0xFF90186C`; subcommands 17-24 select field
 `+0x114` from odd-indexed records 1, 3, ..., 15. Each path stores its selected
 pointer at `0xFF9031DC`. The command's setup stage also uses the
 `0xFF9031D8` audio-engine state: nonzero `argument_04` installs `0x01C722A0`
 at that state field, while zero restores `0xFF803540` through `0xFF8029DC`
 and `0x01C65EE4` through `0xFF802FAC`. In `BF523_ProcessAudioDmaSlice`
 (`0xFFA0141A`), the selected pointer is loaded at `0xFFA017D6`, dereferenced,
  and its dword is written to `0xFF80004C`. This proves the command-`0x37`
  selection-to-audio handoff. During the same slice's 16-voice loop, the active
  dword read from each state record at `+0x00` is copied to six dwords in the
  corresponding `0x118`-byte voice record at `+0x100..+0x114`. Thus the
  command-`0x37` `+0x110`/`+0x114` targets are active-state mirrors, although the
  product meaning of the published word remains unresolved.
- The ARM-side sequencer producer is now bounded. `SelectDspVoiceRecordFieldForSequencer`
  (`0xC0034798`), called from `ProcessSequencerTick`, checks a pending record's
  active byte at `+0x04`, voice index at `+0x08`, and paired-mode flag at `+0x0C`.
  Ordinary records index `g_abDspVoiceRecordFieldSelectorByVoice`
  (`0xC00F92F0`) directly, yielding selectors `1..16`; paired records divide
  the voice index by two and index `g_abDspVoiceRecordFieldSelectorByPair`
  (`0xC00F9300`), yielding selectors `0x11..0x18`. The selected byte is sent
  through `DspIf_SelectDspVoiceRecordField` (`0xC0014368`) as command `0x37`
  with subcommand/record-mode `1`. The separate `DspIf_SelectFixedDspRecordField`
  (`0xC00143E4`) sends command `0x37` with mode `0` and selector `0`, selecting
  the fixed `0xFF802878` pointer. This establishes that command `0x37`'s
  selector is derived from sequencer voice identity.
- The selected pointer is now tied to a downstream DSP processing contract. The
  fixed-point kernels `BF523_ProcessAudioRecordTransformA` (`0xFFA00AD0`) and
  `BF523_ProcessAudioRecordTransformB` (`0xFFA00C80`) receive a context whose
  `+0x04` field is loaded as the selected record/buffer pointer. Both perform
  saturating multiply-accumulate transforms and write through that pointer;
  transform B additionally reads selected-record `+0x08/+0x0C` for the final
  linked-output update. This identifies command `0x37` as selecting an active
  audio-processing record/buffer. Both addresses are also present in static
  external-SDRAM effect descriptors whose display-name strings include
  `[I/Dbl] SR1 Comp`, `[I/Dbl] Limiter`, and `[I/Dbl] Ring Mod`; because the
   same kernels are reused, this does not assign either kernel to one specific
   effect. Exact caller dispatch and field-level signal semantics remain
   unresolved.
- The external effect-descriptor ABI is partly recovered from the DSP image. A
  descriptor-pointer table at external address `0x00004C30` is indexed by the
  seven-bit value read from `0xFF9007CC + slot`; the selected table entry is then
  treated as a descriptor pointer. Static records for `[I/Dbl] SR1 Comp` and
  `[I/Dbl] Limiter` contain the two selected-record transform addresses at
  descriptor offsets `+0x18` and `+0x1C`; the `[I/Dbl] Ring Mod` record visibly
  references `0xFFA00AD0` among a broader callback set. A separate runtime path
  around external address
   `0x00018ADA` loads descriptor `+0x20` and calls it indirectly at
   `0x00018B22`, with effect-state arguments and `0xFF900820` as live state;
   this is a distinct descriptor callback and must not be conflated with the
   `0xFFA00AD0/0xFFA00C80` transform pair. The exact path that invokes the pair
   during the audio slice is still unresolved. Two additional external control
   routines are now bounded: `0x00017C78` selects the descriptor from the masked
   per-slot effect byte, loads descriptor `+0x2C`, and calls it with pointer-lattice
   state `0xFF902B7C + slot*0x34`, voice-record state `0xFF900118 + slot*0x118`,
   and mode `1`; `0x00017DC4` writes a supplied halfword into per-slot parameter
  state and follows descriptor `+0x14` control entries when supported. These are
  descriptor/control paths, not direct calls to the selected-record audio kernels.
 - The seven-entry table at external address `0x01F02B68` is now tied to its owner,
   `BF523_ProcessExternalStateStep` at canonical callback entry `0x0001859C`; its
   table-dispatch setup begins at `0x000185A4`. The owner loads a state-object pointer
   from `0xFF900014`, reads the state dword at object offset `+0x0C`, and
   selects the corresponding entry for states `0..6`: `0x000185E4`, `0x00018600`,
   `0x000186AE`, `0x00018736`, `0x0001878A`, `0x000189C8`, and `0x00018A84`.
   The same setup prepares the descriptor-pointer table at `0x00004C30`, the
   voice-state base at `0xFF800B08`, and companion base `0x0001A2C0`. The handlers
   visibly initialize and gate state, select/clear bounded external regions in
   chunks, and finalize the state transition. The table entries are shared state
   labels under a callback/continuation ABI, not seven independently established
   product-level functions. The exact service and the producer of the `0xFF900014`
   pointer cell are now partly resolved: `BF523_AdvanceExternalStateController`
   at `0x01F0E3AA` publishes the currently active record, and
   `BF523_InitializeExternalStateControllers` at `0x01F0E5F8` initializes the two
   records at `0xFF803CE0` and `0xFF803CF8`. The controller promotes an enabled
   record through its early states and compares its timing fields against
   `0xFF800054`; `BF523_ReadExternalStateControllerValue` at `0x01F0E420` selects
   one of `0xFF900004`/`0xFF900006` using the active record's mode bit. These
   observations establish BF523-side ownership, but not the product/resource
   service represented by the workflow.
  - The initialized controller records resolve their callback fields: the first record
    at `0xFF803CE0 + 0x08` points to `BF523_ProcessExternalEffectControlBlock`
    (`0x00017FF8`), while the second record at `0xFF803CF8 + 0x08` points to
    `BF523_ProcessExternalStateStep` (`0x0001859C`). The first callback's state-one
    path chooses one of two `0x80`-byte candidate blocks at `0xFF900018` or
    `0xFF900098`, validates a marker/high-nibble sequence, scans at most 32 dwords,
    and passes each low halfword to `BF523_UpdateEffectSlotParameterState(0, 0,
    value)`; it clears the marker bit in processed entries. This ties controller 0
    specifically to the effect-slot parameter path, although the external producer
    and protocol meaning of those blocks remain unresolved.
  - `BF523_FxCtrlMRxThread_Run` (`0x01F0E660`) is the scheduler context for these
   controller records. At startup it calls `BF523_InitializeExternalStateControllers`
   with argument `1`; after the UART0 RX ring is drained, it calls
   `BF523_HasPendingExternalStateController` (`0x01F0E37C`) and, when nonzero,
   advances both records again with argument `0`. The same thread parses ordinary
   UART0 bytes through `BF523_ParseMidiByte`, but no direct static call from that
   parser to `BF523_ProcessExternalStateStep` is established; the remaining link is
   through the controller callback/continuation fields.
  - The audio slice's currently recovered indirect dispatch is a separate, smaller
   L1 kernel table. `BF523_InitializeAudioEngineState` installs `0xFFB000E0` at
   audio-root `+0x18`; initialization copies 20 pointers from `0xFF803B84` into
   that scratchpad table. `BF523_ProcessAudioDmaSlice` loads an index from the
   active state-record `+0x28` dispatch-selector field, scales it by four, adds
   `0xFFB000E0`, dereferences the resulting pointer, and calls it at
   `0xFFA01A72`. The static table uses seven
   kernels: `0xFFA03820`, `0xFFA0383C`, `0xFFA03A1C`, `0xFFA03C3C`,
   `0xFFA03EAC`, `0xFFA0411E`, and `0xFFA042DA`; repeated entries are deliberate
   table data. This proves the audio-slice callback layer, but not that it is the
   external descriptor `+0x18/+0x1C` transform pair. Those descriptor callbacks
   remain reachable only through a still-unresolved object/descriptor path. The loop
   passes state `+0x2C` as the kernel's state-context base; kernels then access later
    context offsets relative to that base. The CPU `SendDspVoiceVariantWordBlock`
    producer now closes the selector loop: command `0x31` writes its first assembled
    dword directly to this state `+0x28` field, and the low halfword is consumed by
    the four BF523 variant/update paths. Product/effect selector semantics remain
    unresolved.
   The two indices in this path are now separated precisely. The normalized ARM variant
   index directly indexes the 20-entry BF523 audio table: indices
   0 -> 0xFFA03820; 1,2,8,14 -> 0xFFA0383C; 3,9,15 -> 0xFFA03A1C;
   4,10,16 -> 0xFFA03C3C; 5,11,17 -> 0xFFA03EAC; 6 -> 0xFFA0411E; and
   7,12,13,18,19 -> 0xFFA042DA. The first dword of the matching command-0x31
   block supplies a separate low-halfword selector, in variant-index order
   1,2,6,7,3,5,4,8,0x0C,0x0D,9,0x0B,0x0A,0x0E,0x12,0x13,0x0F,0x11,0x10,0x14.
   Thus the selector chooses the command-0x2F/0x30/update overlay family, while the
   normalized variant index chooses the audio kernel; they must not be collapsed into
   one vocabulary. Variant index 20 has selector zero and a one-byte block, but no
   corresponding entry in the 20-entry audio table.
   Raw instruction tracing also bounds each kernel's P2 footprint. P2 enters at state
   +0x2C: kernel 0xFFA03820 performs no P2 dereference and advances P2 by +0x58;
   0xFFA0383C reads entry-relative +0x00..+0x18; 0xFFA03A1C and 0xFFA03C3C
   read +0x00..+0x30; 0xFFA03EAC reads +0x00..+0x20 and +0x34/+0x38;
   0xFFA0411E reads +0x00..+0x10, +0x20, and +0x34/+0x38; and 0xFFA042DA
   reads +0x00..+0x20. These are access footprints only, not recovered product
   field meanings.
   The `+0x28` offset follows the instruction-level pointer walk: after the active-state
   preamble, `P2` is at record `+0x10`; the loop reads the record's words at `+0x10`,
  `+0x14`, `+0x18`, `+0x1C`, `+0x20`, and `+0x24`, then loads the selector at `+0x28`.
  The post-increment leaves `P2` at `+0x2C` when the indirect kernel is called. This is why the selector is not the
  separate pointer-lattice column.
- A suspected external `+0x28` producer at `0x01F0F630` is ruled out for the
  voice-state array. Its only direct caller, `0x01F0FC02`, passes a temporary
  stack buffer (`FP-0x3C`) as the first argument; the callee stores that argument
  in `P3` and its `+0x28/+0x2C` writes therefore target the temporary object.
  Other fixed-address external routines inspected around `0x00017CE0`,
  `0x00017EAC`, `0x00018000`, and `0x0001859C` access different state/control
  fields and do not write the audio-record selector. The actual global voice-state
  `+0x28` producer is the CPU command-`0x31` path described above.
- Two additional L1 `+0x28` writers are bounded but are not promoted to selector
  producers. `0xFFA00728` receives an object, loads nested objects from its
  `+0x04` and `+0x08` fields, and writes the nested `+0x28` (alongside `+0x2C`,
  `+0x30`, and `+0x38`). `0xFFA01260` follows the same object shape and writes
  `+0x28` on both nested objects. Neither routine receives the confirmed
  `0xFF800B08 + voice*0x1B4` base directly, and their pointer-table references
  are indirect; object identity and call-site role therefore remain unresolved.
- The same table gives a stable effect-ID vocabulary. Entries `0x00..0x26` are
  the input/[I] and input-double/[I/Dbl] family (with `NoFx(Thru)` at
  `0x00..0x0E`, plus `0x17` and `0x19..0x26`); the named entries are `0x01`
  mKP2 Comp, `0x02` SR1 Comp, `0x03` Cheap Comp, `0x04` Punch, `0x05`
  Limiter, `0x06` 2 Band EQ, `0x07` 4 Band EQ, `0x08` Exciter, `0x09`
  Decimator, `0x0A` Filter, `0x0F` Distortion, `0x10` Acid Driver, `0x11`
  Chorus, `0x12` Flanger, `0x13` Phaser, `0x14` Tremolo, `0x15` Level Mod,
  and `0x16` Ring Mod; `0x18` is Short Delay. Entries `0x27..0x40` are the
  mute/[M] family: `0x27` NoFx(mute), `0x28` mKP2 Comp, `0x29` SR1 Comp,
  `0x2A` Limiter, `0x2B` 4 Band EQ, `0x2C` Wah, `0x2D` MultiModeFilter,
  `0x2E` Distortion, `0x2F` TubePre, `0x30` NoFx(mute), `0x31` Chorus,
  `0x32` Flanger, `0x33` Phaser, `0x34` Tremolo, `0x35` Level Mod, `0x36`
  Hall Reverb, `0x37` Smooth Hall, `0x38` Wet Plate Reverb, `0x39` Dry plate
  Reverb, `0x3A` Room Reverb, `0x3B` Mod.Delay, `0x3C` Tape Echo, `0x3D`
  Grain Shifter, `0x3E` Decimator, `0x3F` KPQ Looper, and `0x40` Vinyl Break.
  This is a table-index recovery, not a claim that every ID is currently
  reachable from every ARM voice/effect field.
- The record-selection purpose is narrowed by ARM-side `voice_t` data flow.
  `DspIf_InitializeVoiceDspRecords` (`0xC009345C`) sends command `0x34`,
  `DspIf_RefreshVoiceDspRecords` (`0xC0093784`) sends command `0x35`, and the
 command `0x39` producer `Voice_ApplyDspRecordVariantCommand39` (`0xC0097A1C`) receives a `voice_t *`. Their voice
 index is bounded by the sixteen-iteration loop at `0xC0097BAC` and addresses
 two parallel BF523 arrays: sixteen opaque `0x1B4`-byte
 `E2_DspVoiceStateRecord1B4` records at `g_aDspVoiceStateRecords`
 (`0xFF800B08`) and sixteen opaque `0x118`-byte `E2_DspVoiceRecord118`
 records at `g_aDspVoiceRecords` (`0xFF90186C`). Command `0x34` uses offset
 zero in the first array; commands `0x35` and `0x39` use offset `0x20`, and
 command `0x33` uses offset `0x28`. Commands `0x33`, `0x35`, and `0x39`
 address the paired voice record at offset `+0x04`.
 Command `0x37` selects fields `+0x110`/`+0x114` from the second array and
 writes the resulting pointer to `g_pDspSelectedVoiceRecordField`
 (`0xFF9031DC`). `BF523_ProcessAudioDmaSlice` dereferences that pointer and
 writes the selected dword to `0xFF80004C` before continuing its per-voice
 processing.
- The ARM producer for command `0x33` is now identified as
  `DspIf_UpdateVoiceRecordVariantState` (`0xC0097AC0`), called from
  `Voice_ApplyOscillatorSlotToDsp` (`0xC0098604`). It first checks the linked-
  operation gate and the voice's paired-resource mode. The single-record form
  sends state token `0x02CC + voice*0x6D` (state-record offset `+0x28`) and
  paired-record token `0x461C + voice*0x46` (paired-record offset `+0x04`) in
  a five-word packet. The paired form normalizes the voice index to an even
  base and sends both records in a seven-word packet. This is the ARM-side
  producer for the BF523 21-entry command-`0x33` variant dispatcher; the
  command's individual field meanings remain unresolved.
- `NormalizeDspVoiceVariantIndex` (`0xC0097744`) maps input variant indices below
  `0x11` through the 17-byte table at `0xC00E8F88`:
  `{0x14,1,5,2,3,4,6,7,0x0B,9,0x0A,0x0C,0x0D,0x11,0x0F,0x10,0x12}`.
  Inputs at or above `0x11` select fallback class `0x14`; the normalized class
  is then consumed by the variant payload builder. The table is currently read
  from an executable memory region and is not force-typed as data in Ghidra.
- The command-`0x39` producer's supporting ARM path is now named and typed:
  `SendDspVoiceVariantWordBlock` (`0xC0094A10`) selects a variant-specific
  table, builds a command-`0x31` word block, and sends it to the selected
  voice-state token; `ClearDspVoiceVariantBlocks` (`0xC00936CC`) writes a
  zeroed `0x38`-byte command-`0x31` block to one voice or an even/odd pair;
  `UpdateVoiceVariantParameterState` (`0xC00979C8`) updates the ARM-side
  variant scalar state; `SendVoiceVariantDspPayload` (`0xC00976F4`) packages
  the voice-derived values; and `BuildAndSendDspVoiceVariantParameters`
  (`0xC0094A6C`) selects one of the variant-specific payload builders before
  emitting command `0x2F` or `0x30`. These names describe the observed
  transport/data roles; the musical meanings of the variant fields remain
  unresolved.
 - The conditional packet-mode path is now reduced to a concrete predicate.
   IsVoiceTaskRateBaseInputZero computes the slot-0 base input, indexes the
   128-entry table at 0xC00E8370, and compares the result with the first value
   0x00B6DB6D. All 128 entries were checked and are strictly decreasing, so
   the predicate is true exactly for base input zero. FUN_c009791c inverts
   this bit when its control argument is zero: the resulting command-0x30
   overlay is 0x5785 for base input zero and 0x62 otherwise. The table's
   product role remains unresolved.
- `SendVoiceVariantDspPayload` (`0xC00976F4`) is the direct payload-emission
  stage called by `Voice_ApplyDspRecordVariantCommand39` (`0xC0097A1C`).
  `Voice_ApplyOscillatorSlotToDsp` (`0xC0098604`) reaches the same builder
  through the conditional wrapper at `0xC009791C`; that wrapper either uses
  packet mode `1` or derives an inverted mode bit from `0xC0096B2C`.
- The ARM source fields for this path are now explicit in `voice_t`: `+0x31`
  (`bDspVoiceIndex`) selects the 16-entry BF523 state record; `+0xB2`
  (`bDspVariantIndex`) is normalized through the 17-byte class map; and
  `+0xB4/+0xB6` (`wDspVariantInput0/1`) feed the selected fixed-point payload
  builder. `SendVoiceVariantDspPayload` supplies these four fields, plus the
  paired-resource-mode result, to `BuildAndSendDspVoiceVariantParameters`.
  That dispatcher uses seven confirmed CPU builder groups:
  `{0,1,7,13,19}`, `{2}`, `{3,14,15}`, `{4,10,16}`, `{5,11,17}`,
  `{6,12,18}`, and `{8,9}`. These CPU groups do not all match the BF523
  dispatch groups, so the normalized selector and DSP table remain the
  authoritative variant-class boundary.
  For command `0x2F`/`0x30`, the resulting token selects state `+0x28` and the
  BF523 destination base is state `+0x2C`; this establishes the complete
  CPU-source → packet-token → DSP-destination chain without assigning product
  names to the input words.
- The ARM producers of the two payload words are now bounded. `ComputeDspVariantInput0`
  (`0xC009775C`) writes `voice_t +0xB4` after combining fields `+0xA8`, `+0xC4`,
  `+0xA0`, and the value from `0xC0097334`, then clamps/saturates at `0x7F00`.
  `ComputeDspVariantInput1` (`0xC0097990`) writes `voice_t +0xB6` from nested
  timbre `+0x0E` plus voice `+0xA4`, clamps to `0..0x7F`, and shifts left by
  eight. `UpdateVoiceVariantParameterState` (`0xC00979C8`) is the central
  path: it conditionally copies nested timbre `+0x0C` into the variant byte,
  invokes the first calculator, and performs the same second-input derivation.
- The command-`0x31` transport itself is bounded on the BF523 side at
  `0xFFA05382`: it translates the packet token located at packet offset
  `+0x06`, then writes `argument_04 + 1` consecutive 32-bit values assembled
  from the packet's high/low halfword pairs beginning at packet offset `+0x08`.
  This is the DSP consumer of the ARM `SendDspVoiceVariantWordBlock` and
  `ClearDspVoiceVariantBlocks` producers. For `SendDspVoiceVariantWordBlock`,
  ARM passes `DspIf_GetVoiceStateRecordToken(voice) + 0x0A`; direct token
  translation therefore lands at state-record offset `+0x28` (the base token
  `0x02C2 + voice*0x6D` translates to `0xFF800B08 + voice*0x1B4`). The first
  assembled dword supplies the low-halfword selector consumed by the BF523
  command-`0x2F`/`0x30`/`0x33`/`0x39` paths; subsequent dwords begin at state
  `+0x2C`. The table at `0xC00E632C` has 21 normalized-class pointers and the
  byte table at `0xC00E6380` supplies the dword count directly: classes emit
  12, 14, or 18 dwords beginning at `+0x28`, while class `0x14` emits one zero
  dword. This is the confirmed selector-producer-to-consumer mapping; the
  individual fixed-point fields remain unresolved.
- The normalized-class lengths are, in class order `0..0x14`:
  `{12,12,18,14,18,14,18,12,14,14,18,14,18,12,14,14,18,14,18,12,1}`
  dwords. The first dword of each static block contains the class-specific
  low-halfword dispatch selector; the remaining bits and later payload words
  do not by themselves establish product field semantics.
  Reading the first dword of each selected ARM block gives the exact selector
  sequence `{1,2,6,7,3,5,4,8,0x0C,0x0D,9,0x0B,0x0A,0x0E,0x12,0x13,
  0x0F,0x11,0x10,0x14,0}` in class order. This is an implementation mapping,
  not a product-name assignment.
- The command-`0x31` block and command-`0x30` dynamic overlay are now tied at
  field granularity. The BF523 command-`0x30` selector table dispatches
  selectors `{1,2,8,14,20}` to `0xFFA05C0C` (state `+0x14/+0x18`),
  `{3,9,15}` to `0xFFA05C24` (state `+0x2C/+0x30`),
  `{4,10,16}` to `0xFFA05C3C` (also `+0x2C/+0x30`),
  `{5,11,17}` to `0xFFA05C54` (state `+0x34/+0x38`), selector `6` to
  `0xFFA05C6C` (state `+0x24/+0x28/+0x2C/+0x30/+0x34/+0x38/+0x3C/+0x40`),
  and `{7,12,13,18,19}` to `0xFFA05C92` (state
  `+0x1C/+0x20/+0x24/+0x28/+0x2C/+0x30`). Selector `0` is a no-op.
  These helpers read the selected halfword at payload-base `+0x0C` (the ARM
  command packet's `+0x14`; the payload base is packet `+0x08`), convert it into
  fixed-point values, and overwrite fields in the same state context populated
  by command `0x31`. The current ARM builder supplies `0x5785` when its
  `packet_mode` is zero and `0x62` otherwise. Command `0x31` therefore
  establishes the class baseline while command `0x30` overlays selected runtime
  values. The field units remain unresolved.
- The audio-slice loop consumes that same context after loading selector
  `+0x28`: it reads state dwords at `+0x2C`, `+0x30`, `+0x34`, `+0x38`,
  `+0x3C`, `+0x40`, and `+0x44`, then uses `+0x44` as an indirect pointer
  (loads it into a pointer register, dereferences it, and writes the computed
  result). Longer command-`0x31` classes extend through `+0x54`, `+0x5C`, or
  `+0x6C` respectively, so the class length controls how much of the later
  audio context is initialized. This identifies a shared CPU-produced/DSP-
  consumed record contract without assigning musical names to the fields.
- `ClearDspVoiceVariantBlocks` is a distinct command-`0x31` producer use. It
  passes token `0x461C + voice*0x46`; direct translation maps this to the
  `0x118`-byte voice-record array at offset `+0x04`, not to the `0x1B4`
  state-record array. Its count argument `0x0D` causes the BF523 handler to
  write 14 zero dwords (`0x38` bytes), and the paired form sends the same
  block to the even and odd records. Thus command `0x31` is reused for two
  destination layouts selected by the ARM token family.
- The BF523 consumer provides one bounded field-level correlation for this
  unresolved block family. In `BF523_ProcessAudioDmaSlice` (`0xFFA0141A`), an
  active state record is consumed from its base through its early pointer and
  control fields; the subsequent fixed-point path reads the state-record region
  beginning at `+0x40` and continues through later offsets including `+0x44`,
  `+0x48`, `+0x4C`, `+0x50`, `+0x54`, `+0x58`, `+0x5C`, and `+0x60`.
  The CPU `ComputeAndSendOscillatorSliceScalar` path (`0xC0094F10`) emits a
  command-`0x31` dword at oscillator-slot token offset `+0x10`; direct token
  translation makes this an exact write to the live oscillator descriptor
  `+0x40`. Separately, the larger voice-variant blocks begin at state `+0x28`
  and extend over the subsequent fields listed above, including the audio
  context beginning at `+0x2C`.
- Command `0x34` establishes more of the record linkage without yet resolving
  musical semantics. It stores the paired `0x118`-byte record address into
  state-record fields `+0x20` and `+0x24`, clears voice-record dwords
  `+0x04..+0x3C` and `+0x100..+0x114`, and initializes state-record fields
  `+0x1A8`, `+0x1AC`, and `+0x1B0` to `0x729`, `0x7FFF`, and zero.
- The BF523 command `0x35` case matches the CPU ordering directly. The first
  translated token is the state record at `+0x20`; the second is the paired
  `0x118`-byte voice record at `+0x04`. The handler copies state `+0x20` into
  state `+0x24`, reads the variant from first-object `+0x08` (state-record
  `+0x28`), passes first-object `+0x0C` (state-record `+0x2C`) as the source
  workspace, and passes the second translated pointer as the destination to
  `BF523_DispatchVoiceRecordVariantUpdate` (`0xFFA05AEC`). The helper therefore
  applies its source-derived groups into the paired voice record; the caller
  then recomputes additional fields in both linked objects. This corrects the
  earlier source/destination shorthand: command `0x35` does not make the
  second token a `0x1B4` state-record destination. The helper's 21-entry table
  is labeled `g_apVoiceRecordVariantUpdateDispatch` at `0x01F02DDC`; its shared
  targets in index order `0..20` are `0xFFA05B58`, `0xFFA05B0C`,
  `0xFFA05B0C`, `0xFFA05B5C`, `0xFFA05B74`, `0xFFA05B90`, `0xFFA05BA4`,
  `0xFFA05BE0`, `0xFFA05B0C`, `0xFFA05B5C`, `0xFFA05B74`, `0xFFA05B90`,
  `0xFFA05BE0`, `0xFFA05BE0`, `0xFFA05B0C`, `0xFFA05B5C`, `0xFFA05B74`,
  `0xFFA05B90`, `0xFFA05BE0`, `0xFFA05BE0`, and `0xFFA05B0C`.
  The repeated targets are the implementation families below; this is a
  table-index mapping, not a product-level variant naming.
  implementations copy source groups `+0x44..+0x50` to destination `0..+0x0C`,
  `+0x44..+0x4C` to `+0x14..+0x1C`, or `+0x34..+0x3C` to `+0x20..+0x28`; other
  variants use `+0x3C..+0x44` around destination `+0x28..+0x30` or derive a
  bounded value at destination `+0x10`. These are confirmed record-copy and
  derived-state families, not product-level field names.
- Command `0x39` uses the same ARM token ordering and translated record roles.
  Its BF523 case reads the variant from first-object `+0x08` (state-record
  `+0x28`) and uses first-object `+0x0C` (state-record `+0x2C`) as the source
  workspace. The second translated object remains the paired voice-record
  destination. Commands `0x35` and `0x39` therefore share both the selector
  offset and the update dispatcher; command `0x35` additionally copies state
  `+0x20` to `+0x24` and performs the post-dispatch recomputation.
- Command `0x33` is the related state-update path used by
  `DspIf_UpdateVoiceRecordVariantState` (`0xC0097AC0`). Its BF523 case takes
  the variant from the first translated object's low word (state-record
  `+0x28`), passes first-object `+0x08` (state-record `+0x30`) as the helper's
  source argument, and writes the second translated record through
  `BF523_DispatchHostDmaCommand33Variant` (`0xFFA059F8`). That helper reads its
  source scalar at `R1-0x10`, which is state-record `+0x20`. Relative to its
  destination pointer, the implementation groups are:
  `{1,2,8,14,20}` clear dwords `+0x14..+0x28`;
  `{3,9,15}` clear `+0x04..+0x10`, `+0x20..+0x28`, and `+0x2C`;
  `{4,10,16}` clear `+0x10..+0x28`;
  `{5,11,17}` compute `max(source-0x18000,0)`, scale it by `0x4000`
  below `0x1000` or use `0x04000000`, write that value to dwords `0..7`,
  and clear dwords `8..9`;
  `{6}` scales the source by `0x1000` below `0x4000` or uses `0x04000000`,
  writes dwords `0..6`, and clears `7..8`;
  `{7,12,13,18,19}` writes zero to dword `0`, then the scaled/sentinel value
  to dwords `1..7`. Variant `0` is a no-op. These effects establish the
  command relationship to `0x35`/`0x39`; product field meanings remain
  unresolved.
- Two other bounded variant dispatchers are now explicit in Ghidra:
  `BF523_DispatchHostDmaCommand32Variant` (`0xFFA057B8`) uses a 44-entry table
  at `0x01F02CD8`, while `BF523_DispatchHostDmaCommand33Variant`
  (`0xFFA059F8`) uses a 21-entry table at `0x01F02D88`. Repeated table targets
  deliberately share initialization/update behavior. Their higher-level
  variant meanings remain unresolved, so the case targets retain address-based
  names.
- The command-`0x32` table was enumerated from reconstructed external SDRAM:
  indices `0..2` and `40..42` return without writes; `3`→`0xFFA057E8`,
  `4`→`0xFFA057F2`, `5`→`0xFFA05808`, `6..8`→`0xFFA05828`,
  `9..10`→`0xFFA05852`, `11`→`0xFFA0585A`, `12`→`0xFFA05866`,
  `13`→`0xFFA05872`, `14`→`0xFFA05876`, `15`→`0xFFA05880`,
  `16`→`0xFFA058A0`, `17..18`→`0xFFA058C0`, `19`→`0xFFA058CA`,
  `20`→`0xFFA058DC`, `21..22`→`0xFFA058F0`, `23`→`0xFFA058FE`,
  `24`→`0xFFA0590A`, `25..26`→`0xFFA05916`, `27`→`0xFFA0592E`,
  `28`→`0xFFA05946`, `29..30`→`0xFFA0595E`, `31`→`0xFFA0592E`,
  `32`→`0xFFA05946`, `33`→`0xFFA0597A`, `34`→`0xFFA05990`,
  `35`→`0xFFA059A0`, `36`→`0xFFA059A4`, `37`→`0xFFA059B6`,
  `38`→`0xFFA059C2`, `39`→`0xFFA059D0`, and `43`→`0xFFA057DC`.
  This records implementation reuse without assigning product semantics.
- The command-`0x32` dispatcher contract is also bounded: `P0` receives the
  first object's `+0x04` source-block address and `P2` receives the second
  object. Direct table targets show that indices `3` and `4` write fixed-point sentinel
  `0xC0000000` to destination `+0x00`; index `4` additionally clears
  destination `+0x04`. Indices `6`-`8` clear destination `+0x04/+0x08` and
  conditionally write `0x1999FFFF` based on P0-relative source `+0x14`, while indices `9`/`10` copy
  destination `+0x00` to `+0x04`. These are structural write effects only;
  they do not establish the fields' musical meanings.
  The broader 44-entry table groups several additional implementation families:
  index `5` tests P0-relative source `+0x0C` against `0x70C3FFFF` before the
  `0x1999FFFF` write; indices `11`/`12` install `0xC0000000` in paired
  destination fields; indices `14`/`15` derive negated destination values;
  indices `17`/`18` install `0x80000000`; indices `22..25` derive values
  from P0-relative source offsets `+0x10`, `+0x18`, or `+0x1C`; and index `26` clears
  P0-relative source `+0x10/+0x14` along with destination fields
  `+0x00/+0x08/+0x0C/+0x10/+0x14`. These remain implementation families,
  not product-level names.
- For commands `0x1F` and `0x32`, the BF523 cases at `0xFFA050B0` and
  `0xFFA053B6` translate each pair of word-address tokens and pass the same
  three-part contract to their helpers: the first object's `+0x00` dword is the
  dispatch index, the first object's `+0x04` address is the source block, and
  the second translated object is the destination. The ARM oscillator producers
  supply descriptor `+0x0C` and workspace `+0x08`; therefore the dispatch index
  is descriptor `callback_index` at `+0x0C`, while the source block begins at
  descriptor `+0x10`. This corrects the earlier interpretation that treated
  descriptor `+0x10` as a standalone variant selector. The command-`0x32`
  implementation table still has 44 callback-index entries; its individual
  fixed-point/product meanings remain unresolved.
- Command `0x1F` is the corresponding callback-index-specific field-copy path.
  Its source pointer is descriptor `+0x10`, and the table at `0x01F02FB8`
  writes selected dwords into the callback workspace. Confirmed groups include:
  indices `1/2` copy source `+0x10` to destination `+0x04`; `3` copies
  source `+0x1C/+0x20` to destination `+0x04/+0x08`; `0x0B` copies
  source `+0x18/+0x1C` to destination `+0x04/+0x0C`; `0x11/0x12/0x13`
  copy source `+0x18` to destination `+0x08`; `0x17` copies source
  `+0x10/+0x14` to destination `+0x04/+0x0C`; `0x19/0x1A/0x1D/0x1E`
  copy source `+0x18` to destination `+0x0C`; `0x1B/0x1F/0x27`
  copy source `+0x10/+0x14` into destination `+0x0C/+0x10` (with the
  same observed target family); `0x1C/0x20` copy source `+0x1C` to
  destination `+0x0C`; `0x21` copies source `+0x30` to destination `+0x04`;
  `0x23` copies source `+0x0C` to destination `+0x00`; `0x25` copies
  source `+0x14` to destination `+0x04`; and `0x26` copies source
  `+0x08/+0x0C` to destination `+0x04/+0x08`. The remaining indices are
  no-ops in the recovered table. These offsets are relative to the descriptor
  `+0x10` source block and workspace destination; product meanings remain unresolved.
- `BF523_InitializeUart0AndDmaChannels` at `0x00018CC8`, called when the
  FxCtrlMRx `Run` method starts, configures UART0 for eight-bit operation with
  divisor `0x0102` and `GCTL=1`. It programs DMA peripheral maps exactly as
  follows: DMA8 = UART1 RX (`0xA000`), DMA9 = UART1 TX (`0xB000`), DMA10 =
  UART0 RX (`0x8000`), and DMA11 = UART0 TX (`0x9000`).
- DMA11 transmission uses the `0x8000`-byte ring at
  `g_aUart0TxByteRing` (`0x01C6A2A0`). Its confirmed read index, write index,
  and pending DMA byte count are at `0x01F0CE20`, `0x01F0CE24`, and
  `0x01F0CE28`; ring arithmetic is masked by `0x7FFF`.
- `BF523_Uart0RxAndDma11InterruptHandler` at `0xFFA09A20` distinguishes UART0
  receive-data-ready from DMA11 completion. On UART receive it reads
  `UART0_RBR`, inserts the byte into the `0x4000`-byte
  `g_aFxCtrlUart0RxByteRing` at `0x01C662A0`, advances its write index at
  `0x01F0CE18` modulo `0x4000`, and posts a VDK ISR signal. DMA11 completion
  is acknowledged separately.
- `BF523_FxCtrlMRxThread_Run` consumes that UART0 ring through the read index
  at `0x01F0CE14`. It filters byte `0xFE` and passes other bytes to
  `BF523_ParseMidiByte` (`0x00019384`). The caller passes the parser-state
  address `0x01F0CE2C` and the received byte; those arguments and the call edge
  are now represented in the separate `ghidra/E2_BF523_Parser` program because
  the main BF523 project is currently locked by the interactive Ghidra session.
- The parser's confirmed state layout is rooted at `0x01F0CE2C`: mode byte
  `+0x05`, current message count `+0x06`, expected count `+0x07`, and message
  storage beginning at `+0x08`. The storage is bounded by the comparison
  `count < 0x30`, so it provides a 0x30-byte message buffer including the
  status byte. A newly accepted status is stored at `+0x08` and starts the
  count at one. Data bytes are appended at `+0x08 + count` while the active
  parser mode permits it.
- `BF523_GetMidiParserExpectedCount` at `0x00019134` maps the status class
  through the eight bytes at `0x01F0C9F8` (`02 02 02 02 01 01 02 00`) and
  returns the selected byte plus one. For channel-status classes `0x80` through
  `0xEF`, this produces total message counts `3, 3, 3, 3, 2, 2, 3` for
  classes `0x8` through `0xE`. The same table is used for accepted system
  statuses through `0xF7`; their higher-level meanings are not assigned.
- `BF523_ParseMidiByte` ignores `0xF8` and values above `0xF8` (the caller
  separately filters `0xFE`). Status bytes other than
  `0xF7` are stored as the current status; `0xF0` selects a distinct mode,
  while the other accepted status path selects the ordinary bounded-count
  mode. The parser tests mode values `0`, `1`, `2`, `3`, and `7`; mode-one
  completion and the `0xF7` reset path are directly established, while the
  vendor-level meanings of the other modes remain unresolved. These functions,
  the state bytes, the 48-byte message buffer, and the count table are labeled
  and commented in the Ghidra parser program.
- On the parser's `0xF7` path, `BF523_ValidateFxCtrlPayloadMarker` at
  `0x000192BC` receives the message buffer at `0x01F0CE2C + 0x08` and the
  current count. It does not read the count. It tests buffer bytes `+0x05` and
  `+0x06`, and calls `BF523_ProcessFxCtrlByteSequence` at `0x0001A288` with
  buffer `+0x07` only when `+0x05 == 0x7F` and `+0x06 == 0x7F`.
- `BF523_ProcessFxCtrlByteSequence` consumes a zero-terminated byte sequence,
  calls `BF523_DispatchFxCtrlByteByState` at `0x0001A0F0` once for each
  nonzero byte, then reads the dword at `0x01F0CA14` and calls
  `BF523_FinalizeFxCtrlResponse` at `0x00019470`.
- `BF523_DispatchFxCtrlByteByState` selects through the four-entry table
  `g_apFxCtrlByteDispatch` at `0x01F03118`, indexed by
  `g_dwFxCtrlByteDispatchState` at `0x01F0CAEC`. The entries are
  `0xFFA07144`, `0xFFA069A0`, `0x0001A12C`, and `0x0001A140`. The first two
  are common L1 early-return targets. The latter two are local handlers that
  test for input byte `0x40` and write state `1` or `2`. The state-machine
  purpose remains unresolved.
- `BF523_FinalizeFxCtrlResponse` compares the dword at `0x01F0CA14`, checks
  the pending flag at `0x01F0CA10`, assembles response fields in
  `g_abFxCtrlUart0ResponseBuffer` at `0x01F0CB08`, and queues the resulting
  bytes through `BF523_QueueUart0TxBytes` at `0x0001902C`. That queue function
  directly updates the UART0 TX ring at `0x01C6A2A0` using the surrounding
  read/write/count state. The visible bytes near `0x01F0CA14` begin with
  `JobTime`, but only the observed dword-comparison role is confirmed.
- `BF523_HostDmaPortInterruptHandler` at `0xFFA09AE8` acknowledges the relevant
  Host-DMA/DMA status, examines `g_HostDmaCommandBuffer` and `HOST_STATUS`, and
  posts the VDK ISR signals consumed by `BF523_HostDPMTxThread_Run`.
