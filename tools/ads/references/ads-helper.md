# ADS helper

Use `scripts/ads.ps1` from 64-bit Windows PowerShell 5.1. Importing its modules
does not connect; the entry point rejects calls without `-AllowRuntimeAccess`
before loading dependencies or creating a client. Permission switches are not
authorization: first obey the owner's current runtime restrictions.

Do not run these examples during a runtime-access hold. No example is a request
to execute it. Paths shown below are relative to the repository root.

## Entry points

```powershell
# Set $xaeTargetNetId to the target Net ID shown in XAE
# for the agreed solution. This is a per-invocation check, not stored configuration.

# Read the published framework state and ordered event buffer; do not delete.
powershell.exe -NoProfile -NonInteractive -File tools/ads/scripts/ads.ps1 `
    -Operation Inspect -ExpectedName SelfTests -ExpectedTargetNetId $xaeTargetNetId -AllowRuntimeAccess

# Inspect only the local system state; use PlcState for the selected PLC port.
powershell.exe -NoProfile -NonInteractive -File tools/ads/scripts/ads.ps1 `
    -Operation Inspect -Scope SystemState -ExpectedTargetNetId $xaeTargetNetId -AllowRuntimeAccess

# Request one UnitTest Start and observe a NEW root completion transition.
powershell.exe -NoProfile -NonInteractive -File tools/ads/scripts/ads.ps1 `
    -Operation Command -Command Start -ExpectedName SelfTests `
    -ExpectedTargetNetId $xaeTargetNetId -AllowRuntimeAccess -ConfirmMutation
```

`ExpectedName` is the intended application's Run Control name, not an assumption
that the currently loaded application belongs to this repository. `PlcPort`
defaults to 851. System operations use port 10000 on the same resolved instance.

The helper reads `System/AmsNetId` from
`%ProgramData%\Beckhoff\TwinCAT\3.1\Runtimes\UmRT_Default\3.1\TcRegistry.xml`
and decodes its six hexadecimal bytes. `DefaultTransportAmsNetId` is not used as
the target. No workstation address is stored in the tool, and no alternative
Net ID can be selected by the entry point. Missing or malformed configuration
fails without falling back to the local router, another instance or another port.

`ExpectedTargetNetId` optionally compares that result with an independently
obtained target; it cannot override it. This engineering workflow requires the
comparison with the agreed XAE solution before connecting. The transport uses
`Connect(resolvedNetId, port)`, not `Connect(port)`. Configuration and matching XAE
selection are not proof of live process identity: coordinate any startup `-i`
override or Net ID collision before use. Do not guess a replacement address if
the selected instance is unavailable. Never restart shared services/router to
recover a connection while other instances are in use.
Beckhoff documents the instance registry and possible collision-related Net ID
changes in the [Usermode Runtime FAQ](https://infosys.beckhoff.com/content/1033/tc170x_tc3_usermode_runtime/16309329035.html).

| Operation | Inputs and behavior |
| --- | --- |
| `Inspect`, scope `Framework` | Requires `ExpectedName`. Reads both contract versions, root status, FIFO metadata and events; checks repeated event bytes and stable FIFO/status. |
| `Inspect`, scope `PlcState` / `SystemState` | Reads only the selected ADS server state. Does not imply initialized application data. |
| `Inspect`, scope `Symbols` | `Symbol` is an explicit list of scalar paths. Supports primitive scalars and the known contract enums; not arbitrary structs, pointers or interface instances. No writes. |
| `Command` | Requires `ExpectedName`, `ConfirmMutation` and `Command`: `Start`, `Abort`, `Reset` or `BufferReset`. Writes just one BOOL field once. `WaitFor=Accepted` observes field clearing only; default `Completed` also requires lifecycle evidence, or reset buffer metadata for `BufferReset`. |
| `Acknowledge` | Requires `ExpectedName`, `CapturePath`, positive `Watermark`, `ConfirmMutation`, `ExclusiveConsumer` and `EpochUnchanged`. Writes only the `UDINT` DeleteSequenceId field after archive verification. |
| `Runtime` | `RuntimeCommand=SystemRun` or `SystemConfig`, plus `ConfirmMutation`. One system-service WriteControl request and bounded observation. No PLC command, download or boot-project operation. |

Command field clearing indicates adapter consumption, not necessarily a permitted
lifecycle transition. `Completed` observation also does not mean `Passed`.
For Start/Abort, the helper looks for a new root Completed transition and current
Completed status. Reset looks for a new Idle/Ready transition or error completion.
These are command-observation criteria, not a full lifecycle log validator.
The one-shot helper does not perform streaming deletion while waiting. Insufficient
capacity can therefore cause a timeout. For an explicitly approved continuous
archive/acknowledgement session, use the repository
[event consumer](../../event-consumer/README.md). It reuses these modules
without adding test control or result interpretation. Do not silently acknowledge
or reset the buffer to make a command finish. Buffer Reset during active event
production may never yield an observable empty buffer; field-clearing-only observation remains
available and must not be reported as a verified complete reset snapshot.

## Acknowledgement procedure

1. Inspect and archive the current event range; examine the actual evidence file.
2. Select a contiguous watermark actually present in that capture. Every earlier
   unread event must have been processed. Gaps in the deletion prefix are rejected.
3. Coordinate single-consumer ownership. Exclude PC-runner consumption and any
   intervening PLC reinitialization, activation, download or Buffer Reset.
4. Invoke `Acknowledge` with that capture file and watermark. For example, append
   `-Operation Acknowledge -ExpectedName <root> -CapturePath <before.json>
   -Watermark <processed-sequence> -ExclusiveConsumer -EpochUnchanged
   -ExpectedTargetNetId $xaeTargetNetId -AllowRuntimeAccess -ConfirmMutation`
   to the script invocation.
5. Inspect the after evidence: command cleared, DeletedSequenceId equals the
   requested watermark, and the readable FIFO no longer contains that prefix.

`EpochUnchanged` is an operator assertion, not an inferred PLC epoch identifier.
The helper compares target, name, symbol generation, counters and exact archived
prefix bytes. None of those can conclusively distinguish a full reset followed
by identical data. If the assertion cannot be made, do not acknowledge. A
connection/symbol change or competing deletion ends the operation without retry.

## Dependencies and evidence

The default resolver searches the installed TwinCAT PLC ADS 4.x assembly directory
and selects the highest installed 4.x version there, not an unrelated product's
copy or a compatibility-build subtree. Use `TwinCatRoot` and `AssemblyPath` for
nonstandard installations. The matching Common64 native ADS dependency must be
present. Other SDK major versions require adaptation, not silent substitution.
No installation or download is performed. Native DLL lookup changes PATH only
inside the helper process and restores it on cleanup.

Invoke in an existing terminal/tool process with pipes; do not launch a visible
console or use `Start-Process` without `-WindowStyle Hidden`. Do not import an
incompatible ADS assembly into PowerShell 7. The transport's DLL selection can
be tested offline without instantiating an ADS client.

The helper does not consume a local TMC. It resolves supported contract members
from live symbols, validates names/types/sizes/member ranges and array stride,
and reads only those verified byte ranges. Contract 1.0.0 is the supported
consumer schema. Missing or incompatible symbols/contracts fail closed. The
one-byte ADS symbol version detects observed symbol-table changes; it is not a
permanent generation UUID or an Event Buffer epoch. Avoid Online Change during
an operation. Published root status is a separate diagnostic read, not an atomic
snapshot synchronized with events.

ADS 4.x may return symbol objects with both `DataType` and `Datatype` members.
The transport projects their metadata through exact-case .NET reflection; do
not replace that projection with direct PowerShell member access, whose
case-insensitive adapter rejects these objects.

Evidence is created in a fresh directory under
`artifacts/validation/tc3-engineering/`. Files are never overwritten. A capture
contains FIFO order, exact base64 event bytes, decoded events, contract identity,
sequence gaps and lost-event indication. `LINT`, `ULINT`, `LWORD` and `LTIME`
values use decimal JSON strings; this changes only the tooling evidence format,
not the PLC contract. Before a mutation, the helper flushes the before capture
and intent to disk. Acknowledgement also retains a copy/hash of the supplied
capture. After completion or failure, `operation.json` separates attempted
command, returned submission, observed condition and error. An ADS write failure
can leave acceptance unknown; it does not authorize resending.

`IoTimeoutMs` bounds one ADS call; `TimeoutMs` bounds the connected operation,
including layout resolution and polling. A deadline is applied before each I/O.
Cleanup disposes clients and command handles without changing PLC/IDE state.
Exit code 0 means the requested observation was obtained, not that the UnitTest
passed. Nonzero means refusal, failure or insufficient evidence. Report the
framework Result and event evidence separately.

## Offline checks

```powershell
powershell.exe -NoProfile -NonInteractive -File tools/ads/scripts/test-offline.ps1

# Additionally load the installed assembly and inspect API metadata; no client.
powershell.exe -NoProfile -NonInteractive -File tools/ads/scripts/test-offline.ps1 `
    -CheckInstalledDependencies

# Additionally read this machine's UmRT_Default configuration; still no ADS client.
powershell.exe -NoProfile -NonInteractive -File tools/ads/scripts/test-offline.ps1 `
    -CheckLocalInstance

# Replay a previously archived nonempty, contiguous capture without connecting.
powershell.exe -NoProfile -NonInteractive -File tools/ads/scripts/test-offline.ps1 `
    -CapturePath <saved-capture.json>
```

These checks exercise only the access helper: byte decoding, capture ordering,
acknowledgement safeguards, module wiring and the entry point's access gate.
They do not test FIFO behavior or lifecycle logic in PLC code. The optional DLL
check inspects API metadata without constructing an ADS client. A passing offline
check is not proof that the helper has been exercised against a runtime.

## API references

The transport uses Beckhoff's [ReadSymbolInfo](https://infosys.beckhoff.com/content/1033/tcadsnetref/7313479819.html)
and [symbol metadata](https://infosys.beckhoff.com/content/1033/tcadsnetref/7313547403.html)
for live layouts. Symbol-table generation follows the one-byte
[ADSIGRP_SYM_VERSION example](https://infosys.beckhoff.com/content/1031/tc3_adsdll2/124830987.html).
System-service commands use the documented
[port/state distinction](https://infosys.beckhoff.com/content/1033/tf3710_tc3_interface_for_labview/9988164363.html).
