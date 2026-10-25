# Run Control and PLC Integration

Run Control is the root of one PLC-side test hierarchy. It binds the concrete Test Suites, selects their execution order and concurrency, and connects the hierarchy to external commands and reporting. It does not implement Test Case stimuli, Preparation or Assertions.

Use one concrete `Tc3UnitTest.RunControlBase` derivation in one PLC program and one cyclic task, with the single Event Buffer service. The program owns the Run Control and command adapter; Run Control owns its Suites; each Suite owns its Test Cases. Do not instantiate another root to run a second group of tests in the same framework communication context. Compose that group as another Suite instead.

This chapter completes the hierarchy from [Test Case authoring](test-case.md) and [Test Suite authoring](test-suite.md), including the program startup and cyclic wiring. The [framework model](framework-model.md) explains the overall responsibilities.

## What you implement

| Application part | Your responsibility | Supplied behavior |
| --- | --- | --- |
| Concrete Run Control | Declare, initialize, register and call Suites; choose root timing and mode | Lifecycle, Suite orchestration, capacity admission, result aggregation, status and events |
| PLC program | First-cycle initialization and one ordered cyclic call chain | Command qualification through `RunControlCommandAdapter` |
| Communication wiring | Pass the actual library-owned communication variables | Root Name/Status projection and Event Buffer publication |
| Concrete test hierarchy | Safe resource bindings, defined tests and cleanup | Common lifecycle and reporting behavior of the owner bases |

The root has no parent object. The PLC program calls its inherited `Initialize(Name, EventBuffer)`. This supplies the root identity and administrative Event Buffer interface. Suite composition, root timing and optional resource context belong in the concrete Run Control's `Configure`, not extra external initialization arguments.

Do not instantiate a separate Sequencer, call an Orchestrator yourself or reproduce the base's result/event processing. Its processing already delegates scheduling to its owned helper and calls the concrete Suite hook at the appropriate point.

## Complete Run Control example

The following `ApplicationRunControl` uses `TestSuite_PositiveValues` from the [Suite chapter](test-suite.md). That Suite uses the two Test Case examples from the preceding chapter. These are application FBs you create, not additional library types.

Create the derived FB and its three required overrides: protected `Configure`, public `GetTestSuite` and protected `ProcessTestSuites`. As in the other chapters, code blocks show declarations followed by their implementations; use the corresponding XAE editors.

### FB declaration and body

```iecst
{region 'Documentation'}
(*!
<summary>Compose the application Suites and execute the inherited Run-Control lifecycle.</summary>
*)
{endregion}
FUNCTION_BLOCK ApplicationRunControl EXTENDS Tc3UnitTest.RunControlBase
VAR
    FPositiveValues : TestSuite_PositiveValues;
    FTestSuites : ARRAY[1..SuiteCapacity] OF Tc3UnitTest.I_TestSuite;
END_VAR
VAR CONSTANT
    SuiteCapacity : UINT := 4;
END_VAR

SUPER^(ControlData := ControlData);
```

`ControlData` is the inherited `VAR_IN_OUT` parameter. Forward it to the base once; do not redeclare or copy the complete structure into a private command/status object. The array has four available slots but will contain one registered Suite.

### Configure

```iecst
{region 'Documentation'}
(*!
<summary>Configure root timing and initialize and register the concrete Suites.</summary>
*)
{endregion}
METHOD PROTECTED Configure
VAR_IN_OUT
    Builder : Tc3UnitTest.RunControlConfigurationBuilder; //! Borrowed owner configuration builder used only during this Configure call.
END_VAR
VAR
    SuiteConfig : Tc3UnitTest.ST_TestSuiteConfig;
END_VAR

FConfig.Timeout := T#30s;
FConfig.ResetTimeout := T#3s;
FConfig.AbortTimeout := T#3s;
FConfig.CompletionDelay := T#100ms;
FResourceName := 'IntegerLogic';

SuiteConfig.Timeout := T#15s;
SuiteConfig.ResetTimeout := T#2s;
SuiteConfig.AbortTimeout := T#2s;

Builder.Initialize(Mode := Tc3UnitTest.E_OrchestrationMode.Serial,
    TestSuites := FTestSuites);

FPositiveValues.Initialize(Parent := THIS^,
    SuiteName := 'PositiveValues',
    ResourceName := 'IntegerLogic',
    Config := SuiteConfig);
Builder.Register(TestSuite := FPositiveValues);
```

The base validates the root name before invoking this hook. Use `FConfig` for the run configuration and `FResourceName` for optional diagnostic context; do not replace the established `FName` inside Configure.

The program supplies one nonempty root name segment using ASCII letters, digits, underscores or hyphens, without dots or spaces. Descendants build their names from that root. The complete identity, including a descendant's suffix, must fit NameLength (80 characters), so reserve room for Suite, Test Case and Assertion names. ResourceName is separate optional context with capacity 32; it does not identify the hierarchy.

Initialize every intended Suite and register it exactly once. The base checks that registered Suites initialized successfully; a child failure must not be hidden by simply omitting that child. Rejected builder registrations latch an error and make finalization invalid. If your Configure has additional conditional setup, ensure a partial collection cannot silently become a successful configuration.

The base calls `Builder.Finalize()` after Configure returns. Do not retain the temporary builder or add another registration handoff. `Builder.IsValid` describes the finalized outcome, not progress inside Configure. The base then initializes its Orchestrator and runs `CheckInitialization()`.

An optional `CheckInitialization` override can validate additional application-owned setup, but must include `SUPER^.CheckInitialization()`. Ordinary registration, child initialization and timing checks are already supplied.

### GetTestSuite

```iecst
{region 'Documentation'}
(*!
<summary>Return a registered Suite by its original array index without executing it.</summary>
*)
{endregion}
METHOD PUBLIC GetTestSuite : Tc3UnitTest.I_TestSuite //! Registered Suite at Index; zero outside the occupied range.
VAR_INPUT
    Index : DINT; //! Original occupied child-array index; indices outside the populated range return zero.
END_VAR

GetTestSuite := 0;
IF (ChildCount = 0) OR (Index < ChildArrayLowerBound)
    OR (DINT_TO_LINT(Index) >= DINT_TO_LINT(ChildArrayLowerBound) + UINT_TO_LINT(ChildCount)) THEN
    RETURN;
END_IF;

GetTestSuite := FTestSuites[Index];
```

Return the entry from the same array used by the builder, using its actual index. `ChildArrayLowerBound` and `ChildArrayUpperBound` describe capacity; `ChildCount` describes the contiguous populated range starting at the lower bound. Return zero outside that populated range, including unused capacity.

Do not guard this method with `IsInitialized`: the base needs lookup during synchronous initialization validation before it sets that flag. Do not execute Suites or issue requests from a lookup. The base supplies the generic `GetChild` view without a second interface array.

### ProcessTestSuites

```iecst
{region 'Documentation'}
(*!
<summary>Call every owned concrete Suite once, including during cleanup and Completed.</summary>
*)
{endregion}
METHOD PROTECTED ProcessTestSuites

FPositiveValues();
```

Registration enables scheduling, not FB execution. Call every registered concrete Suite exactly once per initialized cycle, including while Run Control is Idle, Completing or Completed. Do not select child calls by slot or use an Enable guard around this hook. Each Suite's lifecycle determines its active work; continued calls also let outstanding cleanup and status updates finish.

Run Control's base invokes this hook after the Orchestrator and aggregates the updated Suite results afterwards. Do not call the same Suite again from the PLC program or another owner.

## More Suites and orchestration modes

To add a Suite, make all four changes together: declare the concrete instance, initialize it, register it and add its cyclic call. Increase the local array capacity if required. There must be at least one registered Suite; unused capacity remains empty. The array and instances must outlive all execution, so keep them as instance fields, not temporary method-local storage.

The root builder follows the same pattern as the Suite builder, but accepts `I_TestSuite` and uses `TestSuite`/`TestSuites` parameter names:

| Mode | Registration | Meaning at run level |
| --- | --- | --- |
| `Serial` | `Register(TestSuite := ...)` | Suites execute in registration order, one at a time. |
| `Parallel` | `Register(TestSuite := ...)` | Suites can overlap; the helper starts at most one new Suite per call, subject to capacity. |
| `ParallelSlots` | `RegisterWithSlot(TestSuite := ..., ExecutionSlot := ...)` | Suites in one slot can overlap; the next slot waits for all Suites in the current slot to complete. |

For example, if `FPumpA`, `FPumpB` and `FSharedSupply` are your declared and initialized Suite instances:

```iecst
Builder.Initialize(Mode := Tc3UnitTest.E_OrchestrationMode.ParallelSlots,
    TestSuites := FTestSuites);

Builder.RegisterWithSlot(TestSuite := FPumpA,
    ExecutionSlot := 1);
Builder.RegisterWithSlot(TestSuite := FPumpB,
    ExecutionSlot := 1);
Builder.RegisterWithSlot(TestSuite := FSharedSupply,
    ExecutionSlot := 2);
```

This is a focused configuration example, not a declaration of library-provided pump Suites. It is appropriate only if the two pump scenarios can safely overlap and the shared-supply scenarios need a later, separate group. All three concrete calls remain unconditional in ProcessTestSuites.

For Parallel, select that mode and use ordinary Register for every Suite. For Serial, the ordinary registration order defines the effective slots. Explicit slots are allowed only in ParallelSlots; they must be positive and form consecutive groups beginning at one. The builder orders the array by slot, preserving registration order within each slot. Lookup must read that array rather than reconstruct a different order from instance names.

Choose the mode from dependencies and resource ownership, not current free buffer space. Parallel scheduling is first-fitting within the active slot, not a promise of simultaneous starts. A Failed Suite does not by itself prevent later Suites from running; an Error follows controlled error handling. A scenario must not assume that a preceding Suite passed merely because its slot has completed.

Resource safety crosses Suite boundaries. Independent Test Cases within each Suite are not enough if two Suites write the same physical equipment. Reset scheduling is capacity-bounded but independent of execution slots: at most one new Suite Reset is requested per helper call, and admitted resets can overlap. Shared Reset/Abort behavior must therefore be compatible even when normal execution is Serial.

## Root timing configuration

`Initialize` restores `ST_RunConfig` defaults before Configure customizes them:

| Field | Default | What to account for |
| --- | --- | --- |
| `Timeout` | `T#30s` | The whole active run, including scheduling and event-capacity waits. |
| `ResetTimeout` | `T#1s` | Complete hierarchical Reset, including admission waits and child cleanup. |
| `AbortTimeout` | `T#1s` | Controlled termination of active Suites and their descendants. |
| `CompletionDelay` | `T#100ms` | Temporal separation between final Result/Aggregation and Completed. |

All three timeouts must be positive. CompletionDelay may be zero, but completion still occurs in a later PLC cycle than finalization publication.

Size root timeouts for the complete composition. Serial execution can require the sum of Suite durations; slotted execution can require the sum of slot durations. Leave room for child cleanup and scheduling. Increasing a timeout does not repair a missing child call, a permanently impossible reservation or a Test Case that never confirms completion.

The owner bases supervise timeouts; the Orchestrator schedules children. Do not add duplicate timers or manually manufacture timeout results in ProcessTestSuites. `HasTimeout`, `HasResetTimeout` and `HasAbortTimeout` expose retained timeout findings until initialization or entry into a new Reset.

## Communication storage and service binding

Use the library's communication variables for the normal application path. The following names are relative to the `Tc3UnitTest` library namespace:

| Object | Purpose and writer |
| --- | --- |
| `GVL_UnitTest.RunControl.ContractInfo` | Library-initialized direct-access contract and framework versions. |
| `GVL_UnitTest.RunControl.ControlData.Cmd` | External Start/Abort/Reset bits, qualified and cleared by the command adapter. |
| `GVL_UnitTest.RunControl.ControlData.BufferCmd` | External buffer reset/delete commands, consumed through Run Control. |
| `GVL_UnitTest.RunControl.ControlData.Name` and `.Status` | Run Control's post-processing projection. |
| `GVL_UnitTest.EventStream` | Actual event storage, FIFO/status projection and Event Stream contract information. |
| `GVL_EventBuffer.Instance` | The method-driven service operating on that event storage. |
| `GVL_EventBuffer.Publisher` | Default publication interface of that same service. |

Do not create another communication GVL with the same role or expose the root's instance fields as the external contract. Contract information is initialized by the library; the program does not rewrite it each cycle. FrameworkVersion is the effective library version's Major.Minor.Build, without revision. Direct-access and Event Stream contract versions are separate from that library version.

The global publisher defaults to the supplied Event Buffer instance. Framework objects obtain and retain their local publisher view on first use. Initialize the service before any hierarchy initialization that could publish diagnostics. The administrative `I_EventBuffer` passed to Run Control must refer to that same service. Do not switch the global publisher around individual calls or during execution; already-bound instances do not automatically rebind.

Pass the actual communication fields, not copied command snapshots. `VAR_IN_OUT` gives direct access but is not a lock or an atomic snapshot against asynchronous ADS writes. The adapter's command qualification remains necessary. Never copy an entire locally modified ControlData back over the shared structure: that could overwrite commands written while the PLC was processing.

## PLC program: startup and cyclic wiring

Reference the framework library using its normal `Tc3UnitTest` namespace. The program also uses `Tc2_System.GETCURTASKINDEXEX`, so make `Tc2_System` available. Assign the program to the single cyclic task used for the test hierarchy and keep all framework calls on that task.

TwinCAT provides the current task index through [GETCURTASKINDEXEX](https://infosys.beckhoff.com/content/1033/tcplclib_tc2_system/31018507.html). Positive values identify cyclic PLC tasks; zero or negative values are not valid indices for this use. [PlcTaskSystemInfo.FirstCycle](https://infosys.beckhoff.com/content/1033/tc3_plc_intro/714821259.html) indicates the first PLC task cycle. Use that indication for the startup sequence. Reinitialization requires configuration reactivation or a PLC Cold Reset (XAE: Reset kalt), followed by PLC execution. A normal PLC Stop/Start does not trigger this FirstCycle path and is not a substitute.

### Program declaration

```iecst
{region 'Documentation'}
(*!
<summary>Initialize the event service and hierarchy at startup, then call the adapter before Run Control.</summary>
*)
{endregion}
PROGRAM MAIN
VAR
    RunControl : ApplicationRunControl;
    CommandAdapter : Tc3UnitTest.RunControlCommandAdapter;
    TaskIndex : DINT;
    EventBufferInitialized : BOOL;
    FrameworkInitialized : BOOL;
END_VAR
```

### Program implementation

```iecst
TaskIndex := Tc2_System.GETCURTASKINDEXEX();
IF TaskIndex <= 0 THEN
    RETURN;
END_IF;

IF TwinCAT_SystemInfoVarList._TaskInfo[TaskIndex].FirstCycle THEN
    CommandAdapter.Initialize(ControlData := Tc3UnitTest.GVL_UnitTest.RunControl.ControlData);

    EventBufferInitialized := Tc3UnitTest.GVL_EventBuffer.Instance.Initialize(Buffer := Tc3UnitTest.GVL_UnitTest.EventStream.Buffer,
        FifoControl := Tc3UnitTest.GVL_UnitTest.EventStream.FifoControl,
        Status := Tc3UnitTest.GVL_UnitTest.EventStream.Status);

    FrameworkInitialized := RunControl.Initialize(Name := 'LogicTests',
        EventBuffer := Tc3UnitTest.GVL_EventBuffer.Instance);
END_IF;

CommandAdapter(RunControl := RunControl,
    Commands := Tc3UnitTest.GVL_UnitTest.RunControl.ControlData.Cmd);
RunControl(ControlData := Tc3UnitTest.GVL_UnitTest.RunControl.ControlData);
```

Use the same ControlData for adapter initialization, cyclic command access and the Run Control call. The two initialization results are diagnostic observations, not substitutes for `RunControl.IsReady`. Keep the regular adapter and Run Control calls even if initialization fails: the base suppresses invalid hierarchy execution while continuing Name/Status projection. A failed buffer initialization cannot provide a usable event stream, so inspect those Boolean results and the buffer's error status as well as run status.

There is no cyclic Event Buffer FB call. Its methods update storage and its bound FifoControl/Status projections when operations occur. Run Control delegates Buffer commands; it does not periodically copy the Event Stream status itself.

### Why this order matters

The first-cycle block performs three distinct operations before any normal hierarchy processing:

1. **Discard old external commands.** Adapter Initialize clears Cmd.Start/Abort/Reset, BufferCmd.Reset and BufferCmd.DeleteSequenceId, plus its sampling history. It leaves Name/Status untouched and does not execute buffer or owner requests.
2. **Start an empty event context.** Event Buffer Initialize binds the real event array and status fields, clears old entries and resets global reservation accounting.
3. **Rebuild the hierarchy synchronously.** Run Control Initialize clears its transient state, validates identity and calls Configure. Configure initializes each Suite; Suite Configure initializes each Test Case; Test Case Configure initializes its Assertions and scenario-specific components. The bases validate the resulting setup before permitting execution.

The following regular Run Control call processes its one queued startup Reset. Only a successful root Initialize queues that Reset. The PLC program initiates all of this; the PC runner is not responsible for sending an initial reset just to make the application usable. Startup does not automatically Start tests.

There is no intermediate PLC cycle between these initialization calls. Invalid identity or configuration can stop traversal of a subtree; the invalid owner must not then execute that old subtree. Keep children accessible only through their owner's regular processing hook instead of calling them independently from the program.

### Initialization is not readiness

| Condition | Meaning for application code |
| --- | --- |
| `IsInitialized = FALSE` | Setup is invalid or incomplete. A Start cannot repair it. |
| Initialized, still `Uninitialized` | Setup is valid; the initial lifecycle Reset has not yet been admitted/processed. |
| `Reset` | Child Reset is progressing, potentially over multiple cycles and capacity waits. |
| `Idle` and `IsReady = TRUE` | The hierarchy is ready for a Start request. |
| `Completed` | A run or failed cleanup has reached a final root state; inspect Result, not just completion. |

Suites and Test Cases do not autonomously reset on initialization. Their parents reserve capacity and submit their Reset requests. Thus the hierarchy can be fully initialized in one task cycle while readiness takes longer. Do not insert polling loops or block the PLC task waiting for readiness; keep executing normal cycles.

### Application-owned state before the first Reset

Base initialization clears framework-owned requests, lifecycle/result/status, timers, aggregation and local reservation contributions. The Event Buffer's global accounting has already been cleared; startup does not attempt to release the previous run's reservations against the newly initialized buffer.

Your Configure implementations must also establish safe values for their own transient commands, counters, flags and bindings. Do not assume that a base initializer clears fields added in a derivation or that Stop/Start recreates all memory. Lifecycle Reset remains responsible for actively establishing the scenario's start condition.

An initialized Test Case can receive inactive processing-hook calls before its first admitted Reset. Keep resource commands passive during that interval. In particular, a stale explicit Assertion Evaluate input is not made safe just by setting observation Enable to FALSE. Assertion Initialize requests a family reset; its next regular call processes that reset with valid bound inputs before evaluation. See [Assertion authoring](assertions.md) for that distinction.

## Commands: external signals and PLC requests

### External lifecycle commands

The external application sets `ControlData.Cmd.Start`, `.Abort` or `.Reset` to TRUE. The adapter must see the bit in two consecutive samples before it forwards the matching request and clears that bit. This accommodates writes arriving during PLC execution; do not shorten the scheme to an unconditional copy-and-clear of all command fields.

There is no additional acknowledgement handshake or consumer-side reset. Each field is qualified independently. Repeated writes of TRUE to an already TRUE Boolean are not distinguishable additional requests.

The adapter does not select command priority or publish trigger events. Run Control processes accepted requests with Reset before Abort before Start and owns their event reporting. Sending conflicting commands together does not queue the lower-priority operation for later. A Start received before readiness is likewise not a deferred promise to start later.

Adapter Initialize runs as part of the coordinated first-cycle initialization sequence, not on normal PLC Stop/Start or for each lifecycle Reset. Commands present before startup initialization are discarded. Commands arriving afterwards use the normal sampling protocol; those qualified before successful Run Control initialization are cleared and discarded, not retained for a future successful initialization.

### PLC-side requests

Code on the same task can call `RunControl.RequestStart()`, `RequestAbort()` or `RequestReset()` directly. These methods record a request; the regular FB call performs the lifecycle work. Issue a Start only when IsReady, and issue each intended request once instead of repeating it every cycle while a state remains true.

Call a PLC-side request before the root FB call when it should be consumed in that cycle. Do not set an external command bit merely to communicate between PLC objects: the two-sample adapter is for the asynchronous external signal boundary. Conversely, do not bypass Run Control and command Suites separately during a run managed by its Orchestrator.

## Event Buffer commands and capacity

Run Control processes BufferCmd before its current-cycle lifecycle work. These commands do not use the lifecycle adapter's two-sample rule.

### Delete processed events

`BufferCmd.DeleteSequenceId` is a release watermark: the consumer has processed every outstanding event through that sequence number. It is not a physical array index or a request to delete one arbitrary event. Zero means no request.

The Event Buffer captures the requested value, processes the readable FIFO prefix and clears the external field only if it still matches the captured value. A distinguishably newer request is preserved. The program must not add another unconditional clear or directly edit the event array/FIFO indices. Consumer access is single-consumer; a second independent reader must not compete over release commands.

### Hard Buffer Reset versus lifecycle Reset

| Operation | Purpose | What it does not do |
| --- | --- | --- |
| First-cycle initialization | Rebuild setup and transient state, establish an empty event context, queue initial lifecycle Reset | Automatically Start tests. |
| `Cmd.Reset` / `RequestReset()` | Bring the existing hierarchy back to its startable state | Rebuild registration or erase the event log. |
| `BufferCmd.Reset` | Destructively discard the buffered event epoch and its accounting | Safely restart test execution or preserve the current run's evidence. |

Buffer Reset takes priority over Delete. Run Control first attempts hierarchical reservation release through every registered Suite, then performs the hard buffer reset even if a release attempt failed. Both Buffer command fields are cleared. The service clears stored events, FIFO state, sequence/deletion counters, loss count and aggregate reservations. No event is produced just to announce that buffer reset.

Do not call `GVL_EventBuffer.Instance.Reset()` directly during normal operation; doing so bypasses Run Control's coordinated release of local reservations. For a PLC-originated hard reset, use the same BufferCmd path with deliberately chosen timing.

A hard reset is allowed even while tests are active, but discards their event-log completeness. Active children that have lost their required reservations follow the existing framework-error path. This operation neither silently rebuilds those reservations nor submits a separate hierarchy Reset/Abort. Do not expect the affected run to continue successfully. It is useful when old evidence must intentionally be discarded, not as routine test cleanup.

### Capacity planning

`Param_EventBuffer.EventBufferLength` is the compile-time physical ring size, default 256; one position remains unused, so the maximum readable occupancy is 255 at that default. `EventBufferResetHeadroom` defaults to 20 and `EventBufferExecutionHeadroom` to 10. These are library parameters, not runtime commands or per-Suite reservations.

The framework reserves owner event budgets before admitting work. Temporary shortage waits; a permanently impossible budget is an error. Capacity waiting counts towards owner timeouts. The same program calls must keep running while a consumer drains events; do not repeatedly send Start to force progress.

For short standalone runs, a sufficiently sized buffer can retain the log without concurrent consumption. Longer or repeated runs need timely consumer deletion or an intentional decision to discard old evidence. Lifecycle Reset alone does not free old stored events. A nonzero `EventStream.Status.LostEventCount` means evidence was lost even if the final run state or later events are available. Do not treat a Passed status snapshot as proof of a complete event log.

## Optional PLC-only diagnostic consumption

Use `EventBufferDiagConsumer` only when you deliberately want to observe PLC lifecycle
progress without evaluating its events on the PC, for example during startup Reset.
It discards event evidence, including failure diagnostics. A Passed status observed
during such a session is not an evaluated test result.

Declare the consumer in the application program; it is not integrated automatically:

```iecst
VAR
    DiagConsumer : Tc3UnitTest.EventBufferDiagConsumer;
    EnableDiagnosticConsumption : BOOL := FALSE;
END_VAR
```

In the existing first-cycle initialization block, configure it if the defaults are
not suitable and start a fresh diagnostic observation period:

```iecst
DiagConsumer.MaxEventsPerCall := 32;
DiagConsumer.ConsumeInterval := T#10ms;
DiagConsumer.ResetDiagnostics();
```

Keep the startup initialization and command-adapter order from the program example.
Call the consumer **after** Run Control on the same task, on every cycle including
Reset, Idle and Completed:

```iecst
RunControl(ControlData := Tc3UnitTest.GVL_UnitTest.RunControl.ControlData);
DiagConsumer(Enable := EnableDiagnosticConsumption,
    Buffer := Tc3UnitTest.GVL_EventBuffer.Instance,
    Events := Tc3UnitTest.GVL_UnitTest.EventStream.Buffer);
```

Pass the actual event array belonging to the supplied buffer service.
`Events` is a call-scoped `VAR_IN_OUT CONSTANT` array: no array copy or retained
pointer is created, and the consumer cannot write through this parameter.
Events are removed only through the service's regular sequence-based deletion.
The consumer does not reset the buffer, manipulate FIFO indices, or release owner
reservations. Freed capacity becomes available to the hierarchy on its next cycle.

`Enable` defaults to FALSE. Activation consumes immediately; subsequent batches
follow `ConsumeInterval` (default T#10ms). T#0ms consumes every call. The batch is
limited to `MaxEventsPerCall` (default 32), even after missed intervals; there are no
catch-up batches. Zero is an invalid batch limit and prevents deletion.
Choose interval and batch size together so diagnostic draining can keep up with
event production and capacity waits do not cause lifecycle timeouts.

The read-only observations are:

| Property | Meaning |
| --- | --- |
| `DiscardedEventCount` | Confirmed deletions since ResetDiagnostics; saturates at the ULINT maximum. Sequence-number gaps are not counted as deleted events. |
| `LastBatchEventCount` | Actual deletions in the last attempted batch, including a partially completed batch. Held between batches and while disabled. |
| `PeakPendingEventCount` | Highest valid occupancy sampled before consumption on every enabled call, including calls between batch intervals. It is an observed peak, not a guarantee of detecting transients between calls. |
| `HasError` | Invalid buffer observation, batch failure or invalid time basis. Held until a batch succeeds or ResetDiagnostics clears it. |

`ResetDiagnostics()` clears these three statistics and HasError immediately,
without clearing events or changing the consumption schedule. Deactivation,
UnitTest Reset and Event Buffer Reset preserve the statistics. The current occupancy
and loss count remain available in the existing Event Stream status; the consumer
does not duplicate them. Disabled calls do not access or modify the buffer.

Use exactly one consumer for an event-buffer epoch. Do not run the diagnostic
consumer alongside the PC runner or another event consumer, and do not simply
hand a partially discarded epoch to the PC. For a subsequent evaluated session,
disable the diagnostic consumer and establish a new, complete event context through
the coordinated startup sequence before the PC consumer takes ownership.

## Completion, failure and another run

Normal completion publishes the root Result, then its Aggregation, once on entry to Completing. Run Control holds the finalized result and those event payloads unchanged, waits for CompletionDelay and emits its transition to Completed in a later cycle. That root transition is the lifecycle completion anchor, not an Orchestrator diagnostic or the first completed Suite.

CompletionDelay provides temporal separation; sequence IDs provide event ordering. The delay is neither a consumer acknowledgement nor a guarantee that the PC has read the preceding events. If its time measurement becomes invalid after publication, the base emits one Framework diagnostic and transitions to Completed without changing the published result. The minimum delay cannot then be guaranteed.

Status and child observation remain live during Completing and Completed. Keep calling Run Control and all owned Suites. The final owner result remains held, while current counts may still reflect late exceptional cleanup; those later snapshots do not rewrite the already published aggregation event.

| Situation | Root behavior and author action |
| --- | --- |
| Assertion/Test Case/Suite Failed | Ordinary test failure; remaining scheduled work can continue. Inspect finding events to diagnose the scenario. |
| Execution Error or execution timeout | Controlled error termination through AbortingFromError, then Completing/Completed with Error. |
| Explicit Abort during execution | Stop further starts, let active descendants perform abort cleanup, complete with Abort unless Error takes precedence. |
| Abort timeout | Diagnose and complete with Error; keep cyclic calls so subordinate cleanup can progress. |
| Child Reset failure | Continue attempting remaining resets while prerequisites/time allow; complete with Error if Reset cannot succeed. |
| Reset timeout | Stop root reset dispatch and finalize through Completing/Completed with Error, without dispatching execution Abort. |
| Initialization failure | Stay Uninitialized with configuration diagnostics; no automatic startup Reset or normal child execution. |

In failed Reset cleanup, a parent's completion does not prove that every descendant reached Idle. Already active descendants continue their own cleanup or timeouts. Hierarchical reservation release can precede the last late child diagnostic in this failure path; it is not an unlimited capacity guarantee for faulty tests. Fix the underlying scenario/configuration error rather than interpreting Completed as physical resource recovery.

For another normal run:

1. Keep the cyclic call chain running and preserve/read the preceding evidence as required.
2. Submit one lifecycle Reset.
3. Wait across PLC cycles for Idle and IsReady; inspect errors if that does not happen.
4. Submit one Start.
5. Observe completion and evaluate the event evidence. Do not use Initialize as the repeat-run command.

A Run Control result/status view supports control and diagnosis. The event stream supplies the detailed test evidence. Suite and Test Case instance data are not an alternative external result protocol.

For PLC-side observation, read `RunControl.Name`, `RunControl.Result` and its read-only `Status : ST_RunControlStatus`. The same current status is projected into ControlData after processing. It contains nested Execution flags/state/result, Runtime as TIME and Suite counts for Total, Inactive, Idle, Running, Completed, Passed, Failed and Error. Execution and result counts are different views, not one partition to add together. No application-written status-refresh method is required.

## Restart and Online Change

Startup initialization, lifecycle Reset and Buffer Reset remain separate even during development. When reinitialization is required, reactivate the configuration or perform a PLC Cold Reset (XAE: Reset kalt), then start PLC execution. The application program must execute the full first-cycle startup sequence before regular processing of the rebuilt hierarchy. Normal PLC Stop/Start does not trigger it. Do not individually reinitialize a live Suite to repair a partially changed setup.

After initialization, child registration, capacity, slot assignments and service bindings are fixed. Changes invalidating that setup require configuration reactivation or a PLC Cold Reset and renewed hierarchical initialization. This includes changed registered children, array layout/capacity, orchestration settings or configuration captured during Initialize; Online Change alone is not sufficient. In particular, the Event Buffer binding requires reinitialization after Online Change; do not assume that an automatically updated interface reference repairs every stored memory binding. Use the coordinated startup path, not a partial buffer-only reinitialization against old local reservations.

UnitTest lifecycle Reset prepares another test run with the existing setup; it does not perform reinitialization. Event Buffer Reset likewise does not rebuild the hierarchy. Do not infer reinitialization from a download or Stop/Start alone: use the required configuration reactivation or PLC Cold Reset path.

## Diagnose the integration

| Observation | Check first |
| --- | --- |
| No startup activity | MAIN is assigned to the intended cyclic task, TaskIndex is positive and the first-cycle path executes before regular calls. |
| Buffer initialization fails or no event diagnostics appear | The actual one-based EventStream array and its FifoControl/Status bindings, buffer capacity and EventBufferInitialized. Initialization diagnostics also need a usable publisher. |
| Root remains Uninitialized | FrameworkInitialized, Name validity, buffer readiness, builder errors and each registered Suite's initialization. Do not retry Start to fix configuration. |
| Initialized but not ready | Initial Reset progress, child calls, capacity waits and child readiness. Successful initialization does not skip Reset. |
| External commands have no effect | Same ControlData storage throughout, one adapter call before the root, two-sample qualification, root initialization/readiness and conflicting commands. |
| Commands are lost after a code change | Accidental whole-structure copy-back, unconditional clearing or multiple adapters/owners writing the same fields. |
| Root/Suite timeouts although no tests seem busy | Capacity waits, missing concrete calls, a child that never confirms cleanup/completion or too-small whole-composition deadlines. |
| Event buffer fills on repeated runs | Old events were not deleted; lifecycle Reset intentionally leaves the event log intact. |
| Current run errors after Buffer Reset | Its reservations and evidence were deliberately discarded; do not treat hard reset as transparent continuation. |
| Completed but descendants still show cleanup | Exceptional timeout completion; maintain cyclic calls and diagnose the affected child. |
| Stale behavior after Stop/Start or Online Change | Reinitialization requires configuration reactivation or PLC Cold Reset; Stop/Start alone does not trigger it. Check Configure fields and invalidated bindings. |

## Integration checklist

- One program/task owns one concrete root, one command adapter and the single Event Buffer context.
- The root calls its base once with the actual ControlData and implements all three required hooks.
- Every Suite is initialized, registered, looked up from the correct occupied range and cyclically called exactly once.
- Names identify the hierarchy uniquely, with enough length left for Test Cases and Assertions.
- Root and child modes respect resource ownership across execution, Reset and Abort.
- First-cycle processing clears old commands, initializes the Event Buffer, then synchronously initializes the complete hierarchy before normal calls.
- Concrete Configure implementations establish passive transient state before the first lifecycle Reset is admitted.
- Normal processing calls the adapter before Run Control and continues after Completed or configuration failure.
- Communication fields have one responsible writer; no whole-structure copy-back or direct instance-symbol publication is introduced.
- Timeouts and capacity account for the whole composition and expected consumer progress.
- Another run uses lifecycle Reset, readiness and Start; destructive Buffer Reset is a separate, intentional loss of buffered evidence.
- Setup-invalidating changes require configuration reactivation or PLC Cold Reset and full hierarchical initialization, not Stop/Start or live collection/service rebinding.

Return to [Test Suite authoring](test-suite.md) for child composition or the [framework model](framework-model.md) for the complete hierarchy.
