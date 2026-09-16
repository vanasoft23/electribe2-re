# RTOS kernel internals

> Detailed evidence extracted from the original monolithic ARCHITECTURE.md.
> Ghidra is authoritative for current symbols, types, comments, and cross-references.

- `InitializeRtosTaskState` at `0xC00002B4` resets scheduler globals,
  initializes 16 circular list heads, and builds runtime task-control state at
  `0xC06A24E4` from the ten static descriptors.
- `ResetRtosTaskControlBlock` at `0xC00003B0` clears a runtime task-control
  block, imports descriptor priority, and initializes its embedded list nodes.
- `StartRtosTask` at `0xC00003D8` builds the initial saved-register frame at
  the top of a descriptor's stack. It installs the descriptor argument in
  `r0`, the descriptor entry in the saved PC, and
  `rtos_task_entry_trampoline` (`0xC0001828`) as the task's first resume point.
- The trampoline restores the synthetic frame and branches to the task entry.
  If a task entry returns, control reaches `HandleRtosTaskReturn` at
  `0xC000066C`, which removes the task from runnable state and schedules a new
  task rather than returning into an invalid caller frame.
- `InitializeRtosKernelObjects` at `0xC00000F4` orchestrates initialization of
  the task state and other table-driven RTOS object pools, then installs
  configured interrupt callbacks.
- `EnqueueRtosTaskReady` at `0xC00018F0` inserts a task into the ready queue
  selected by its priority and updates scheduler selection state.
- `BlockCurrentTaskOnRtosWaitList` (`0xC0001D14`) marks the current task with
  state byte `+0x0C = 0x32`, removes it from the priority ready queue, stores
  its wait-link pointer in task field `+0x14`, and links that node to the
  supplied RTOS object's wait list. Objects with wait-list flag bit 0 set are
  priority ordered; other objects append in list order. Confirmed callers are
  event waits and mutex acquisition.
- `WakeRtosTaskFromWaitList` (`0xC0001C30`) removes an active timer record
  through task field `+0x14`, then normally restores the task to the
  priority-ordered ready queue and sets state byte `+0x0C = 1`. Event-set and
  mutex-release paths consume its return value as a possible context-switch
  request. If the task state already has bit 2 set, the routine preserves the
  alternate state instead of enqueueing it; that state’s higher-level meaning
  remains unresolved.
- `SwitchToSelectedTaskContext` at `0xC0001760` saves the current task's
  callee-saved registers, stack pointer, and resume PC. The runtime task-control
  fields used for the saved SP and PC are `+0x18` and `+0x1C`.
- The RTOS timer heap is a shared 1-based min-heap at the runtime array pointed
  to by `g_pRtosTimerHeapEntries` (`0xC06A2404`). Each 8-byte entry stores an
  absolute deadline at entry `+0x00` and a timer/callback-record pointer at
  entry `+0x04`; the pointed-to record stores its 1-based heap index at `+0x00`.
  `g_pRtosTimerHeapCount` points to the active-entry count at `0xC06A2934`,
  while the heap comparison reference word is at `0xC06A2930` and the current
  time word used for relative insertion is at `0xC06A292C`.
  `ReadRtosClockValue` at `0xC000132C` checks the clock-availability gate at
  `0xC06A2894` and, when available, writes a value formed from shared words
  `0xC06A2930` and `0xC06A2938` to the caller's output pointer; unavailable state
  returns `0xFFFFFFE7`. It is used by RTOS waits, timer paths, and the GPIO event
  handler. The clock-word split and unit remain unresolved.
- `InsertRtosTimerHeapEntry` (`0xC0001FA4`) inserts a deadline/record pair and
  uses `SiftUpRtosTimerHeap` (`0xC0002164`). `RemoveRtosTimerHeapEntry`
  (`0xC0001FEC`) removes the record named by its stored index, moves the final
  entry into the vacancy, and selects sift-up or `SiftDownRtosTimerHeap`
  (`0xC0001EF0`) to restore order. Moved records have their indices updated.
  `QueueRtosTimerRelative` (`0xC0001BC8`) associates a timer/callback record
  with the current task context and inserts it at current time plus a positive
  delay. The confirmed timer-record layout is `+0x00` = 1-based heap index,
  `+0x04` = direct callback function pointer, and `+0x08` = callback argument.
  `DelayCurrentRtosTask` (`0xC0000B78`) uses this layout to block the current
  task and wake it through `RtosTaskDelayWakeCallback` (`0xC0001CD4`).
  `WaitForEvent` (`0xC000085C`) uses `RtosEventWaitTimeoutCallback`
  (`0xC0001C7C`), which writes timeout result `-50` before requeueing the task.
  Static timer records are initialized by `InitializeRtosTimerRecord`
  (`0xC0001410`) and re-armed by `DispatchRtosStaticTimerCallback`
  (`0xC000143C`). The delay unit and static timer product meanings remain
  unresolved.
- The current task pointer is stored at `0xC06A289C`. The scheduler-selected
  task pointer is read from `0xC06A2924`. When it is null, the scheduler uses
  the idle stack at `0xC274EA3C` and executes ARM `WFI` before retrying.
- `InitializeRtosMutexes` at `0xC0000C4C` initializes seven mutex objects from
  `g_aRtosMutexDescriptors` at `0xC00A3728`; the count is stored at
  `g_dwRtosMutexDescriptorCount` (`0xC00A377C`). Each 12-byte descriptor has
  initial availability 1 and maximum availability 1, so all seven are binary
  mutexes. Mutex ID 1 serializes the complete BF523 Host DMA memory-transfer
  wrappers described below. Mutex ID 2 serializes the CPU SPI1 SerialFlash
  wrappers `ReadSerialFlashMutexed` (`0xC0029A74`) and
  `WriteSerialFlashMutexed` (`0xC0029AB8`). Mutex ID 6 protects the heap after
  `g_dwHeapLockEnabled` is set. Mutex ID 7 protects the shared VoiceTask
  event-buffer object initialized by `InitializeVoiceTaskEventBuffer`
  (`0xC003B904`): VoiceTask input/control producers append type-0/type-1
  records, the bulk producer appends type 2, and SeqTask timing paths append
  type 3 while holding that mutex. The higher-level meaning of the bulk
  payload remains unresolved.
  The only recovered dynamic mutex argument is `CircularBuffer::write`
  (`0xC0024BF4`), which reads the buffer object's mutex field at `+0x08`.
  `InitializeCircularBufferInstances` (`0xC0024EE4`) constructs five static
  8-byte/0x400-record buffers and passes mutex IDs `1, 2, 6, 2, 2` in order:
  `g_stVoiceTaskAuxiliaryQueue`, `g_stUsbMidiAuxiliaryQueue`,
  `g_stVoiceTaskInputQueue`, `g_stCentralServiceQueue1`, and
  `g_stCentralServiceQueue2`. No recovered circular-buffer instance uses IDs
  3 through 5.
- `AcquireRtosMutex` at `0xC0000D80` and `ReleaseRtosMutex` at `0xC0000CA8`
  are generic ID-based RTOS mutex operations, not SPI1-specific functions.
  Along with blocking/event operations such as `WaitForEvent`, they converge
  on `SwitchToSelectedTaskContext` after changing task readiness state.

