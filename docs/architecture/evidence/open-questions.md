# Open questions

> Detailed evidence extracted from the original monolithic ARCHITECTURE.md.
> Ghidra is authoritative for current symbols, types, comments, and cross-references.

## Unresolved

- Flag bits other than the confirmed initially-runnable bit (`0x2`) have not
  been observed; the two trailing descriptor slots (`+0x18/+0x1C`) are
  confirmed unused/reserved by the recovered task initialization and scheduler
  paths.
- The low-level USB device-controller worker has no recovered C++ task-class
  name, so its functional name records its confirmed role rather than claiming
  an original source identifier.
- No recovered acquire/release callsite supplies RTOS mutex IDs 3 through 5,
  either directly or through the five static CircularBuffer instances. Their
  intended roles, if any, remain unobserved in the CPU image.
