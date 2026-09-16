# Architecture evidence

These files retain detailed, evidence-backed reverse-engineering notes from the former
monolithic `ARCHITECTURE.md`.

Use them for:

- function and global addresses;
- caller/callee and producer/consumer evidence;
- structure offsets and record sizes;
- protocol constants and state transitions;
- explicit uncertainty local to a subsystem.

Do not treat them as a substitute for the Ghidra program database. Symbols, prototypes,
types, class namespaces, comments, and cross-references may evolve after a note was
written. Verify the current database before applying or changing a symbol.

The root [ARCHITECTURE.md](../../../ARCHITECTURE.md) is the maintained program map. It
describes stable ownership, lifecycle, subsystem boundaries, and end-to-end flow.

## Files

| File | Scope |
| --- | --- |
| [boot-and-interrupts.md](boot-and-interrupts.md) | DDR, ARM entry, startup, board setup, AINTC |
| [rtos-tasks-and-command-dispatch.md](rtos-tasks-and-command-dispatch.md) | Task descriptors and CommandTask handlers |
| [sequencer-and-mapped-state.md](sequencer-and-mapped-state.md) | Sequencer, mapped state, slot lifecycle, timing |
| [voice-control-and-services.md](voice-control-and-services.md) | VoiceTask controls, services, common messages |
| [midi-usb-and-common-messages.md](midi-usb-and-common-messages.md) | MIDI parsing, USB transport, central routing |
| [rtos-kernel.md](rtos-kernel.md) | Scheduler, waits, timers, mutexes |
| [dsp-boot-and-audio.md](dsp-boot-and-audio.md) | BF523 loader, VDK, SPORT0/audio |
| [pcm-sample-engine.md](pcm-sample-engine.md) | PCM catalog, ELSI, analysis, playback |
| [voice-dsp-control.md](voice-dsp-control.md) | Voice assignment and DSP control |
| [dsp-hostdma-and-uart.md](dsp-hostdma-and-uart.md) | BF523 Host DMA and UART control |
| [storage-and-updates.md](storage-and-updates.md) | Serial flash, SD resources, VSB bundles |
| [battery-and-panel.md](battery-and-panel.md) | Panel battery measurement and DC diagnostics |
| [hardware-io.md](hardware-io.md) | Host DMA, USB, panel, battery, LCD, timers, SD/MMC |
| [ableton-export.md](ableton-export.md) | Ableton project construction and serialization |
| [open-questions.md](open-questions.md) | Explicit architecture-level unknowns |

## Update policy

- Put a finding in one primary evidence file; link instead of duplicating it.
- Prefer ownership and data flow over a list of references.
- Keep routine xrefs and local-variable detail in Ghidra comments.
- Preserve exact values only when they define behavior or a format.
- Prefix inference with its confidence and the evidence that constrains it.
