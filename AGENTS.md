# AGENTS.md

## Purpose

This project uses LLM-assisted reverse engineering with Ghidra and Ghidra MCP to analyze the KORG Electribe 2 firmware, an ARMv5 binary running on the E2's AM1802 CPU.

### KORG E2 Specs
CPU is a Texas Instruments AM1802 which has ARM926EJ-S core.
CPU has 64 MiB of DDR2 RAM available accessible through cached range 0xC0000000 – 0xC3FFFFFF. 0xC4000000 – 0xC7FFFFFF is an uncached alias mirror to the cached DDR range.

DSP is an Analog Devices Blackfin BF523.
Most DSP communication is facilitated through CPU SPI1.
For high-speed CPU-DSP communication, AM1802 EMIFA peripheral is connected with BF523 HostDMA peripheral.
DSP has 32 MiB external DRAM available.

CPU SPI1 is also used for the 16 MiB flash.
CPU also has an SDMMC peripheral for SDCard.
LCD control happens over SPI0, and is output-only.
The MCU panel communicates over CPU UART0, and it's where Button/Knob/Pad etc inputs come from.
The MIDI TRS peripheral is implemented over CPU UART1.

### Factory Firmware Information
First 128 KiB of flash contains the bootloader, which consists of an AIS script, that loads the SBL as a payload into 0x80000000. The SBL sets up PSC, PLL, DDR, some GPIO and other stuff and loads the 2 MiB firmware image from flash into DDR at 0xC0000000.

###

In the `docs` folder, you can find the AM1802 and BF523 documentation PDFs, these are especially important because they provide understanding of the MMR layouts.

The `imhex` folder contains reverse engineered file formats.

The goal is to progressively recover meaningful program structure by tracing execution from the application entry point, identifying functions, variables, globals, data structures, and subsystem boundaries, and renaming only when there is high confidence.
Accuracy matters more than speed. Never guess.

## Primary Objectives

    Start analysis at the application entry point.
    Follow control flow outward to identify:
        functions
        global variables
        local variables
        data structures
        tables
        buffers
        dispatch logic
        subsystem boundaries
    Rename symbols only when their purpose is supported by strong evidence.
    Names should be shorter, yet descriptive, rather than long e.g Initialize -> Init.
    Treat the HACKTRIBE.bin Ghidra program database as the authoritative store for symbols, prototypes, data types, classes, comments, and cross-references.
    Keep ARCHITECTURE.md focused on stable ownership, lifecycle, subsystem boundaries, major data contracts, and end-to-end execution/data flow.
    Record detailed function/address/layout evidence in the narrowest matching file under docs/architecture/evidence/.
    Update ARCHITECTURE.md only when a finding changes the program-level model or an important cross-subsystem flow.
    Use strings, string cross-references, interrupts, calling patterns, and data flow as primary sources of evidence.
    Preserve uncertainty explicitly. If confidence is low, do not rename and do not document as fact.
    Derive your evidence from deep analysis of what it accesses/calls, what it's called/accessed by.

## Documentation Workflow

For each confirmed finding:

1. Update the Ghidra program database first.
2. Add detailed proof to one relevant `docs/architecture/evidence/*.md` file.
3. Update `ARCHITECTURE.md` only if ownership, lifecycle, subsystem boundaries, a major record contract, or an end-to-end flow changed.
4. Keep routine xref inventories, decompiler narration, and local implementation detail in Ghidra rather than Markdown.
5. Keep exact constants in `ARCHITECTURE.md` only when they define a protocol, persistent layout, safety rule, state machine, or cross-subsystem contract.
6. Preserve uncertainty explicitly. Do not create a confident symbol or architecture claim from a plausible product interpretation alone.
