# Event consumer

Capture the PLC event stream without a PC runner. The tool repeatedly reads,
archives and acknowledges events across multiple buffer fillings. It does not
interpret results, start tests, reset the buffer or control the PLC/runtime.

## Requirements and operation

- Run from a complete repository checkout using 64-bit Windows PowerShell 5.1.
- TwinCAT ADS .NET 4.x and its matching native dependency must be installed.
  The tool reuses the modules under
  `tools/ads/scripts/`; it has no separate ADS implementation.
- The local `UmRT_Default` instance must contain the running, initialized
  application. The expected Run Control name defaults to `SelfTests`.
- Confirm the intended local target in XAE. Its AMS Net ID must match the
  locally resolved `UmRT_Default` configuration; the argument is a comparison,
  not a target override. No workstation address is stored in the tool.
- Obtain runtime-read and acknowledgement approval before use. This must be the
  only consumer: do not consume the same stream with a PC runner or another tool.
- Do not reset the Event Buffer, reinitialize/restart the PLC, download, activate
  configuration or perform Online Change during capture. The protocol has no
  unique epoch identifier; identical data after a reset cannot always be detected.

See the shared [ADS helper guide](../../tools/ads/references/ads-helper.md)
for dependency resolution and target checks. Event semantics remain defined by
the [Event Stream contract](../../contracts/event-stream-contract.md).

From the repository root, after the approvals and target check:

```powershell
# Enter the target Net ID shown by the agreed XAE solution.
$xaeTargetNetId = Read-Host 'Verified local UmRT_Default target Net ID'
powershell.exe -NoProfile -NonInteractive -File tools/event-consumer/consume-events.ps1 `
    -ExpectedTargetNetId $xaeTargetNetId -ExpectedName SelfTests -PlcPort 851 `
    -DurationSeconds 600 -AllowRuntimeAccess -ConfirmMutation `
    -ExclusiveConsumer -EpochUnchanged
```

For a complete test-run capture, start the consumer first and leave it running
through final event delivery. Test execution is controlled separately. The tool
also captures unread events already present when it starts; events deleted before
its initial watermark cannot be recovered.

`DurationSeconds` defaults to 120 and accepts 1 through 3600 seconds.
`PollIntervalMs` defaults to 50 (10 through 1000); `IoTimeoutMs` defaults to 3000
(100 through 10000). Connection/layout setup and each capture/write operation use
a 30-second ADS budget. Waiting for a deletion acknowledgement uses a 3-second
budget. The run duration is independent of these budgets. Stop requests and budget
expiry are observed between operations; an in-flight read/write can finish later.

Stop by creating the printed `stop.request` file, by Ctrl+C, or by letting the
duration expire. Do not kill the process for a normal stop. A pending write might
already have been accepted; inspect `PendingWatermark` rather than resending it.
The consumer does not stop automatically when the root reports Completed.

## Evidence and failure behavior

Every invocation creates a fresh, ignored directory under
`artifacts/validation/event-consumer/`. There is no automatic resume or reconnect.

- `events.jsonl`: session context, initial deletion watermark, complete event
  batches, acknowledgement intentions and observed acknowledgements. Each `Events`
  record contains the helper capture with `Capture.Events` in FIFO/SequenceId order,
  decoded values and exact base64 event bytes. Repeated verification reads are not
  appended as duplicate event batches. 64-bit timestamps remain decimal strings.
- `operation.json`: termination reason, event/batch counts, persisted and observed
  acknowledgement watermarks, any pending watermark and an error if applicable.

Each batch is written and flushed to disk before its contiguous deletion watermark
is submitted. No unpersisted events are acknowledged. Read, persistence, sequence,
identity or acknowledgement errors stop the consumer. An ambiguous failed write
is not retried. Previously flushed batches remain available; after abnormal process
termination a final partial JSONL line or missing summary may require inspection.

Exit code 0 means a normal bounded/explicit stop, not Passed tests or an empty FIFO.
A pending watermark means deletion was not confirmed before stopping. Exit code 1
indicates failure; parameter/approval failures also terminate without connecting.
Throughput during a running test depends on event production and obtaining a stable
capture; the tool stops if bounded consistency checks cannot obtain one.

To load the captured event values offline, set `$capturePath` to `events.jsonl`:

```powershell
$events = @(Get-Content -LiteralPath $capturePath | ForEach-Object {
    $record = $_ | ConvertFrom-Json
    if ($record.Kind -eq 'Events') { $record.Capture.Events.Value }
})
```

## Offline tests

```powershell
powershell.exe -NoProfile -NonInteractive -File tools/event-consumer/test-offline.ps1
```

These tests exercise consumer sequencing, persistence-before-acknowledgement,
duplicate/gap rejection, cancellation and failures using simulated reads/writes.
They do not construct an ADS client or test PLC behavior. Test evidence is also
written beneath `artifacts/validation/event-consumer/`.
