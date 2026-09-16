# Battery status, panel measurement, and DC diagnostics

> The panel MCU is the measurement endpoint. The recovered ARM application does not
> directly sample a battery ADC; it consumes fixed panel-UART packets and routes the
> resulting values through the common-message service.

## Normal battery/DC data path

- `ConsumePanelUartProtocolByte` (`0xC00282D8`) assembles normal panel packets as
  five bytes: packet type at `+0`, followed by four payload bytes at `+1..+4`.
  The parser stores only while its byte count is below five, then resets the count
  when a packet completes. The same parser has a separate fixed `0x100`-byte bulk
  mode.
- `ProcessPanelUartCentralMessage` (`0xC002814C`) maps packet type `6`'s byte at
  `+1` to common-message type `7`. The common-message payload is the unsigned
  one-byte panel measurement.
- The same dispatcher maps packet type `7`'s byte at `+1` to common-message type
  `6`, with payload `1` when the byte is nonzero and `0` otherwise. This is the
  panel-provided DC-jack/connection condition; its electrical polarity is not
  proven by the CPU code.
- `MainCommonMessageService::StoreCommonMessageType6Selector` (`0xC0070D14`)
  stores the DC condition at service offset `+0x1D4`. Type 7 is stored by
  `StoreCommonMessageType7Selector` (`0xC0070D20`) at `+0x1D8` and is dispatched
  through the common-service vtable slot `+0x44` to
  `HandleCommonMessageType7BatteryMeasurement` (`0xC00837D4`).

## Battery monitor client

`VoiceTaskBatteryMonitorClient` is a lazily allocated `0x330`-byte listener client,
constructed by `InitializeVoiceTaskBatteryMonitorClient` (`0xC0077B4C`). The relevant
fields are:

| Offset | Recovered role |
| ---: | --- |
| `+0x318` | pointer to four-byte chemistry threshold table |
| `+0x31C` | chemistry/validity gate |
| `+0x320` | most recently received measurement |
| `+0x328` | classified battery level, observed values `0..4` |
| `+0x32C` | low-battery notification latch |

`RefreshBatteryMonitorThresholdsFromChemistrySetting` (`0xC0077940`) selects the
table from Global `BATTERY TYPE`:

- Ni-MH (`0`): `{134, 129, 124, 97}`
- Alkali (`1`): `{127, 110, 104, 97}`

The setting has an important validity boundary. `AdjustVoiceTaskControlField24ByStep`
(`0xC007B2D0`), the normal two-choice edit path, clamps the value to `0..1`.
However, deferred parameter code `0x3B` in `ApplyVoiceTaskParameterCode`
(`0xC008EF20`) copies a raw byte into the same field through
`SetVoiceTaskControlField24` (`0xC00472F8`), which performs no range check.
`RefreshBatteryMonitorThresholdsFromChemistrySetting` assigns no new pointer for
values other than `0` or `1`; it leaves `+0x318` unchanged. Since the monitor
constructor enables the validity gate before the initial refresh, an invalid
initial value can leave a null threshold pointer, while a later invalid update
can preserve an old pointer. A subsequent measurement classification can then
dereference null or stale table state. This is a conditional null/stale-pointer
availability defect, not a demonstrated linear overflow; whether malformed
persisted or externally supplied state can reach deferred code `0x3B` remains
unresolved.

`ClassifyBatteryMeasurementByChemistry` (`0xC0077A14`) applies strict descending
threshold bands: above threshold 0 -> level 4, above threshold 1 -> level 3,
above threshold 2 -> level 2, above threshold 3 -> level 1, otherwise level 0.
The low-battery latch is cleared for levels 2..4. A guarded level-1 transition
emits common-message type 9 with payloads `0x1B` and `0x1A`; level 0 requests the
LCD/panel hardware-reset path. The exact measurement units remain unresolved.

## Diagnostic class and workflow

`VoiceServiceBatteryDcDiagnosticsState` is the selector-8 class allocated by
`SelectVoiceServiceStateObject` (`0xC0075E68`) at `0x18` bytes. Its recovered layout
is the `0x10`-byte `VoiceServiceStateBase` prefix followed by:

| Offset | Recovered role |
| ---: | --- |
| `+0x00` | diagnostic-class vtable |
| `+0x04` | owning `MainCommonMessageService *` |
| `+0x08` | shared `LcdTextContext *` |
| `+0x0C` | shared mapped-state context pointer |
| `+0x10` | workflow state |
| `+0x14` | workflow retry/scratch counter or flag |

The class vtable at `0xC00E43B0` supplies the destructor, workflow processor
`ProcessBatteryCheckWorkflowStep` (`0xC0075618`), event filter
`FilterBatteryDcDiagnosticsEvent` (`0xC007133C`), and step selector
`SelectVoiceServiceStepState` (`0xC0075990`).

`SelectVoiceServiceStepState` maps selections `1..5` to workflow states
`1, 3, 5, 7, 9`, displays the selected diagnostic step, and participates in the
panel command queue. The processor uses the following confirmed labels/actions:

- state 0: `Battery Check`;
- state 1: gates on the DC condition, showing `Not Connected Error !` for zero or
  `Dc Jack Pull` and sending panel SysEx command `0x6D`, parameter `1`;
- state 3: mode-dependent branch that either terminates or shows `Level High` and
  sends `0x6D`, parameter `2`;
- state 4: displays the numeric measurement and tests it against `0xB0`, setting
  or clearing mapped-state entry `0x12`;
- state 5: shows `Power Measurement` and sends `0x6D`, parameter `3`;
- state 7: shows `Led Half Measurement`, sends `0x6D`, parameter `4`, and queues
  panel command `0x02` with payload `1`;
- state 9: shows `Level Low` and sends `0x6D`, parameter `5`;
- state 10: displays the numeric measurement, retries while it is below `0x68`,
  and limits the retry counter to ten attempts.

The state/event meanings beyond these observed labels, the units of the measurement,
and the exact response semantics of panel command `0x02` remain unresolved. The
fixed five-byte packet assembly and one-byte measurement extraction show no new
linear buffer overflow in this path.
