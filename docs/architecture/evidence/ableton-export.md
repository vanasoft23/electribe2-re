# Ableton project export

> Detailed evidence extracted from the original monolithic ARCHITECTURE.md.
> Ghidra is authoritative for current symbols, types, comments, and cross-references.

## CPU project/Ableton export path

- `BuildAbletonExportSceneRecords` (`0xC00325F8-0xC0032917`) builds the per-scene records
  consumed by the export serializer. It walks the export object's source vectors, maintains
  `0x28`-byte scene records, derives timing-related values through the CPU software floating-point
  helpers, and appends the records to the export arrays. The exact meanings of the remaining scene
  fields are unresolved.
- `SerializeAbletonProjectXml` (`0xC0032934-0xC0032F07`) emits an XML-like payload using the embedded
  `Project/Ableton Project Info` resource and scene fields corresponding to identifiers, `lengthInSec`,
  `beatTime`, `name`, `filename`, `speakerManualValue`, and `patternInfo.bpm`. Its timing conversion
  uses the software single-precision helpers and the `1000.0` constants at `0xC0032430` and
  `0xC0032F5C`; the external trigger and resource ownership remain unresolved.
- `SerializeAbletonProjectAuxiliaryData` (`0xC0031E1C-0xC00323DB`) is reached from the main serializer
  only when the export object's state byte at `+0x28` is set. It uses the same project-format
  resources and scene data, including the integer/fractional timing conversion, but its distinct
  output-container role remains unresolved.
- `CopyAbletonExportSceneRecord` (`0xC0032444-0xC0032497`) confirms the scene-record shape as
  `0x28` bytes: a scalar at `+0x00`, managed fields at `+0x04` and `+0x08`, copied data words at
  `+0x0C..+0x1C`, and a flag byte at `+0x20`. `AppendAbletonExportSceneRecord`
  (`0xC0032498-0xC00325E7`) grows the begin/end/capacity vector, transfers existing records while
  preserving those managed fields, destroys the old managed fields, and frees the old allocation.
  `GrowAndZeroAbletonExportWordVector` (`0xC0031D18-0xC0031E17`) provides the analogous word-vector
  growth/zeroing path, while `AssertAbletonExportWordVectorIndex` (`0xC0031CF8-0xC0031D13`)
  guards indexed access. Field meanings and the export container's ownership contract remain
  unresolved.
- The managed scene-record fields are reference-counted text objects. `AssignCpuRefcountedTextFromCString`
  (`0xC00A26C0`) computes `strlen` and delegates to `AssignCpuRefcountedTextFromBytes`
  (`0xC00A25D0-0xC00A26B7`), which stores the length and terminator while handling copy-on-write
  storage. `RetainCpuRefcountedTextObject` (`0xC00A2D54-0xC00A2DAB`) increments the observed
  reference count or clones a shared object; `ReleaseCpuRefcountedTextObject`
  (`0xC00A21D4-0xC00A220F`) releases it. `AssignCpuRefcountedTextObject`
  (`0xC00A2DB0-0xC00A2E3F`) combines replacement, retain/clone, and release behavior. This confirms
  why scene-record copy/append operations treat offsets `+0x04` and `+0x08` as managed text fields.
- `SerializeAbletonProjectFull` (`0xC0033EF8-0xC0034527`) is the shared full-project writer reached by
  both confirmed PatternSet handlers. It emits sixteen scene slots by walking the outer vector of
  `0x0C`-byte sub-vector headers and each nested `0x20`-byte record vector, writes the observed `.als`
  resource/XML-like payload, and then calls `SerializeAbletonProjectLite` (`0xC003386C-0xC0033E87`).
  The Lite writer emits the corresponding eight-slot resource using the observed `_Lite.als` suffix.
  Both paths use the software floating-point timing conversion; the individual resource-field meanings
  remain only partially resolved.
- `PrepareAbletonExportFullSceneVectors` (`0xC0033320-0xC003359B`) initializes sixteen `0x20`-byte
  records per source and appends their nested vector headers to the container's outer `+0x38/+0x3C`
  vector. `PrepareAbletonExportLiteSceneVectors` (`0xC00335B0-0xC0033857`) first releases the prior
  nested vectors, rebuilds up to eight records per source, pads each source to eight slots, and appends
  the resulting headers. Both helpers populate managed text fields and two computed timing fields from
  the shared voice-assignment table; the exact source-field semantics remain unresolved.
- The nested export slot record is confirmed as `0x20` bytes by `InitializeAbletonExportSlotRecord`
  (`0xC0031A3C-0xC0031A87`), `CopyAbletonExportSlotRecord` (`0xC0032F70-0xC0032FAB`), and the two
  serializers: flag at `+0x00`, reference-counted text at `+0x04/+0x08`, and two observed 64-bit
  timing/value fields at `+0x10` and `+0x18`. `ClearAbletonExportSlotRecordVector` releases the managed
  text fields without freeing the vector. `AppendAbletonExportSlotRecord` and its fast path grow/append
  these records, while `CloneAbletonExportSlotRecordVector` creates a retained copy.
- `AppendAbletonExportSubvectorHeader` (`0xC0033198-0xC00332DB`) and its fast path manage the outer
  vector of `0x0C`-byte nested sub-vector headers, transferring inner record-vector ownership during
  growth. This explains the two-level cleanup performed by `DestroyAbletonExportContainer`.
- `DestroyAbletonExportState` (`0xC00319C4-0xC0031A1B`) restores the export object's destructor
  vtable, releases both managed fields in each scene record, frees the scene-record vector, and
  releases the object's own text field at `+0x04`. `ReleaseAbletonExportSceneRecordText`
  (`0xC0031B24-0xC0031B43`) is the shared two-field cleanup helper. This confirms the export state
  owns the scene-record vector and its embedded text objects.
- The enclosing `DestroyAbletonExportContainer` (`0xC0031C54-0xC0031CA7`) installs a second vtable,
  releases a standalone `0x20`-byte-record vector at `+0x44/+0x48`, then walks an outer vector of
  `0x0C`-byte sub-vector headers at `+0x38/+0x3C`; each sub-vector header references another
  `0x20`-byte-record vector with managed text fields at `+0x04` and `+0x08`. It frees the outer
  allocation and delegates to the main export state destructor. `ReleaseAbletonExportAuxiliaryRecordVector`
  (`0xC0031C18-0xC0031C53`) is the shared cleanup helper for each `0x20`-byte record vector. The observed
  vtables are `g_vtAbletonExportState` at `0xC00A76E0` and `g_vtAbletonExportContainer` at `0xC00A7700`.
- `InitializeAbletonExportState` (`0xC0031A8C-0xC0031ABB`) initializes the embedded state and clears
  its scene-record vector at `+0x14/+0x18/+0x1C`. `InitializeAbletonExportContainer`
  (`0xC0031AC4-0xC0031B1B`) clears the embedded state, stores three constructor values at
  `+0x2C/+0x30/+0x34`, and clears both the outer sub-vector header at `+0x38/+0x3C/+0x40` and the
  standalone record-vector header at `+0x44/+0x48/+0x4C`; its two confirmed callers are the
  handler-0x19 and handler-0x1A PatternSet paths at `0xC0037F18` and `0xC00305D0`. The serializer's
  `MoveCpuRefcountedTextObject` (`0xC0031B44-0xC0031B6F`) transfers temporary text into destination
  storage and resets the source to the observed sentinel representation.

