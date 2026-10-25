# Framework Architecture

This document describes the stable high-level architecture of the TC3 UnitTest framework.

It is permanent library documentation. Exact PLC/PC interface semantics are defined in `contracts/`. The [authoring manual](authoring/framework-model.md) explains practical framework usage.

## Execution Hierarchy

The framework is organized as a PLC-side execution hierarchy:

| Level | Main responsibility |
| --- | --- |
| Run Control | Owns one complete UnitTest run and binds the concrete Test Suites. |
| Test Suite | Groups related Test Cases and produces one Suite result. |
| Test Case | Executes one concrete test scenario and produces one Test Case result. |
| Preparation | Brings a tested resource into a required start condition for a Test Case. |
| Assertion | Evaluates one concrete condition and contributes to the owning Test Case result. |

Each level owns the level below it. Ownership includes start, abort, reset, readiness checks, monitoring where applicable, and result aggregation. Orchestrators are technical helpers and do not form additional reportable owner levels.

## TwinCAT Object Model

The implementation uses statically allocated function blocks, shallow inheritance, responsibility-focused interfaces, methods, properties, and stateless functions where they improve reuse or encapsulation.

- Owner base function blocks implement invariant lifecycle, result, timeout, aggregation, and event behavior.
- Concrete Suites and Test Cases derive from at most one framework base function block and provide project-specific behavior through protected hooks.
- Orchestrators depend on the smallest useful owner interface rather than concrete child types.
- Pure enum, value, and arithmetic operations remain stateless functions. Incremental result combination uses the method-driven `ResultAggregator`.
- Interfaces, references, pointers, function-block layouts, and internal state are never part of the PLC/PC contract.
- Runtime allocation, reflection-based discovery, and nondeterministic dispatch are not used.

Concrete Suite, Test Case, Preparation, and Assertion instances remain statically declared and are called once per required PLC cycle in deterministic order.

### Framework type names

Framework types use the `Tc3UnitTest` namespace. The selected base and interface names are:

| Role | Base FB | Interface |
| --- | --- | --- |
| Run Control | `RunControlBase` | `I_RunControl` |
| Test Suite | `TestSuiteBase` | `I_TestSuite` |
| Test Case | `TestCaseBase` | `I_TestCase` |
| Preparation | optional `PreparationBase` | `I_Preparation` |
| Assertion | `AssertionBase` | `I_Assertion` |

The concrete Orchestrator under Framework/Common/POU supports Test Cases and Test Suites through the common child/collection interfaces. Suite and Run Control bases provide the normal default composition and access their selected helper through protected FOrchestrator : I_Orchestrator. The common implementation supports E_OrchestrationMode.Serial, Parallel and ParallelSlots without strategy subclasses. Configuration builders define child composition and mode; a controlled test adapter may replace the helper before owner initialization.

### Suite binding

The concrete Run Control owns statically allocated Suite instances and a local `ARRAY OF I_TestSuite`. Its locally defined array capacity is distinct from the number of registered Suites. No library-wide `SuiteArrayLength` parameter or global Suite array is required.

During initialization, the base passes a method-local `RunControlConfigurationBuilder` to the concrete `Configure` implementation. Configure initializes and registers Suites. The base calls `Finalize()` after Configure returns and retains validated collection metadata. Registration belongs to synchronous initialization, not regular execution.

The concrete `GetTestSuite(Index)` supplies typed access to the local array; the base exposes the common `GetChild(Index)` view to its owned Orchestrator. `ProcessTestSuites()` calls the concrete Suite instances. The shared Orchestrator is reused without a parallel generic interface array or another scheduler.

RunControlBase implements I_OrchestratableCollection over its finalized owner-held metadata. ChildCount reads the registered Suite population; GetChild checks the occupied range before calling GetTestSuite. After builder finalization, the base exposes metadata during synchronous initialization validation and initializes its owned Orchestrator with Collection := THIS^ and the owner diagnostic identity before CheckInitialization. Failure hides the collection again. Orchestrator initialization caches the occupied bounds without executing Suites. The protected abstract ProcessTestSuites hook belongs to regular lifecycle execution, never to configuration or indexed lookup.

`RunControlConfigurationBuilder` applies the Test Suite builder rules below to `I_TestSuite` entries. Initialize binds and clears the local TestSuites array; Register and RegisterWithSlot assign the effective child slots. Finalize returns `ST_TestSuiteCollectionConfig` with FirstIndex, LastIndex, Count, IsValid and Mode. Bounds, registration rejection, stable slot ordering, contiguous-slot validation, idempotent finalization and setup-only pointer lifetime follow the same rules; the builder neither initializes nor cyclically calls Suites.

No Suite or Test Case interface array is published through ADS.

### Run Control initialization

RunControlBase.Initialize(Name, EventBuffer) rebuilds its initialization state, retains the length-limited name for diagnostics and validates the supplied name at hierarchy depth 1 before Configure. It requires a non-null administrative Event Buffer view and a valid publisher selected through its instance-local binding, supplied by the same initialized service. Run Control does not initialize or reset event storage during this handover.

Protected abstract Configure(Builder) sets FConfig and optional FResourceName, initializes owned Suites with Parent := THIS^ and registers them. FConfig starts with the ST_RunConfig defaults on each initialization. The base finalizes the builder before protected CheckInitialization validates positive timeouts and the registered, initialized Suites. Overrides include SUPER^.CheckInitialization(). CompletionDelay may be zero. Typed GetTestSuite and collection bounds/count are available for synchronous setup validation; failed initialization hides usable collection metadata again. Success establishes IsInitialized, not Idle or Ready, and queues one RequestReset through the existing mailbox. Cyclic processing consumes it once; failed initialization queues no Reset. The common collection and composed Orchestrator integration use this same configuration, without another registration step.

### Run Control cyclic integration

RunControlBase first processes the supplied external BufferCmd through ProcessBufferCommands, before lifecycle work can publish new events. It then follows the established Suite processing order: consume requests with Reset > Abort > Start priority, update elapsed-time helpers, execute the Sequencer using retained child observations, call the shared Orchestrator with the mapped task, call concrete Suites, aggregate their observations and results, update owner result/status, then publish finalization events. Sequencer owns transition decisions; pure transition validation and ChangeState retain their existing responsibility boundaries. External command qualification and BufferCmd intake remain separate from this PLC-internal lifecycle.

The normal path is Reset -> Idle -> Starting -> Running -> Completing -> Completed. Successful initialization queues the initial Reset; it does not directly establish readiness. There is no automatic Uninitialized-to-Reset transition in the Sequencer. Run Control owns its execution, Reset and Abort deadlines. Reset includes capacity waiting and continues remaining Suite reset attempts after child errors until completion or its deadline. A successful Reset reaches Idle; failed Reset or Reset timeout reaches Completing with Error. Execution errors select AbortingFromError; Abort timeout terminates through Completing with Error. Escalation from Aborting to AbortingFromError preserves the original abort deadline. Suite reservations and their release remain child-owned and coordinated by the existing Orchestrator; Run Control introduces neither a second ledger nor helper-owned timeout monitoring.

Suite aggregation uses ResultAggregator and the established owner rules: normal execution remains NotEvaluated until finalization, Failed children do not stop execution, Error escalates, and an unexpected child Abort is an error. Runtime measures root active execution, not summed child runtime. Finalization derives the final outcome and counters before publication; the finalized owner result and emitted event payloads remain unchanged until Reset, including error finalization after Reset or Abort timeout. Child aggregation and current status counters continue to refresh. Cyclic status projection does not reopen a published result.

### Run Control reset processing

The Run Control Reset deadline starts on actual entry into Reset and includes reservation-capacity waiting and all subordinate reset work. Repeated Reset requests retain the deadline, dispatch progress and held errors, and must not bypass Reset monitoring. Reset observations are consumed only once the composed Orchestrator is processing its Reset task; previous-task completion or errors must not decide the new Reset outcome.

Run Control uses the existing capacity-bounded Suite Reset dispatch, including the shared Test Case allowance. During Reset, previous-run child results are not aggregated into a new owner failure; the Orchestrator reports errors for children already processed by its reset dispatch. Such errors are held while later Suite reset attempts continue. Idle requires successful reset completion, ready children, valid collection/configuration and no owner/helper error. A reset deadline or invalid task clock ends through Completing with Error; a detected reset timeout remains visible through HasResetTimeout until Initialize or actual entry into another Reset. Invalid task-clock measurements are not timeout detections.

Reset preserves initialized composition and configured timings. It clears the root execution result, runtime and finalization latch, not the Event Buffer or its reservation count. Suite and Test Case contributions are reconciled by their hierarchical owner release methods; root code does not clear or duplicate them. A Reset failure or timeout maps Completing to the helper's Idle task without Abort or unconditional task-exit cleanup. Children continue their own lifecycle and timeout processing through regular calls, even after parent completion. A subsequent Start still requires root IsReady.

Execution timeout or an invalid execution clock selects AbortingFromError. Explicit Abort selects Aborting unless an Error already has priority. Abort completion waits for child/helper completion, bounded by the root AbortTimeout; an invalid Abort clock or Abort timeout ends through Completing with Error. HasTimeout and HasAbortTimeout retain detected timeouts until Initialize or actual entry into Reset; clock errors do not assert timeout flags.

### Run Control completion delay

Run Control publishes its final Result followed by Aggregation once in the entry cycle of Completing, after result/status projection. Its Sequencer retains Completing for the configured CompletionDelay before transitioning to Completed in a later cycle. The finalized owner result and emitted event payloads remain unchanged throughout this delay, while child aggregation and status counters continue to refresh cyclically, including in Completed. Explicit Reset remains available. Unlike the Suite's single-cycle Completing path, Run Control needs one-shot finalization handling across multiple cycles. If the delay clock becomes invalid after finalization publication, Run Control emits one Framework diagnostic and transitions to Completed without modifying published values. This defensive exception cannot guarantee the minimum delay and does not require a separate diagnostic latch: the terminal transition ends the check. The shared Orchestrator does not implement this delay or acquire another lifecycle state. Event sequence IDs define stream order; CompletionDelay adds temporal separation, not a consumer acknowledgement.

RunControlBase exposes protected read-only IsCompletionTimeValid for the completion-delay validity decision. Its default getter returns the state Stopwatch's IsValid value; both the Sequencer and the Completed transition check use it. A controlled selftest adapter may override this observation to exercise the invalid-time fallback without changing the system clock, timer internals, elapsed-time calculation, or other lifecycle phases. The getter has no processing side effects.

## Owner Lifecycles And Orchestration

The respective Run Control, Test Suite, and Test Case bases integrate their generic lifecycle processing. Separate Sequencer instances are not required by this model. The Test Case base supports the agreed Preparation and Test state ranges; a single-state test is a special case of the same processing.

Concrete Suites and Test Cases execute the base body once through `SUPER^()`. The base coordinates cyclic processing and invokes overridden `PROTECTED` extension methods at defined phases. Each extension point defines its own signature, results where needed, permitted side effects, and base-call requirements. There is no universal hook result or signature.

Protected methods and data are selected for practical test authoring. Lifecycle state may be protected where needed for an intentional extension; it is not required to be private. The concrete base design defines when derived code may change state and how timing, status, and events account for the change. Contractual lifecycle and result semantics remain binding.

Each hierarchy level retains its own orchestration responsibility while normally reusing the same concrete Orchestrator. Bases own helper initialization and cyclic ordering through I_Orchestrator. Concrete production owners configure mode and children through their builders; controlled selftest substitution does not require ordinary users to provide a helper. Serial, Parallel and ParallelSlots map to one slot-based processing model.

Project-specific owners should use the bases when their execution model fits. A direct implementation against the required framework interfaces remains permitted but must provide equivalent lifecycle, command, result, monitoring, capacity, and event behavior.

Serial, Parallel and ParallelSlots use the same slot-based execution implementation; their differences are established during registration.

### Internal interfaces, requests, and status

Suite and Test Case interfaces expose cohesive orchestration views with lifecycle request operations and the state information required by their consumers. They do not duplicate a complete owner API or require a universal owner interface.

A Suite or Test Case receives Start, Abort, and Reset through its request operations. A request records only the corresponding owner request; the regular owner FB call performs lifecycle processing. Repeated positive requests coalesce and do not count requests. Suite and Test Case owners have no `Control` DUT and no externally writable command storage.

Each Suite and Test Case exposes its mandatory typed status snapshot through a read-only `Status` property. Its stable `Name` is a separate property. If an application needs HMI or PC visibility for an owner, it creates an explicit data-oriented wrapper containing identity and the copied status snapshot. No owner instance data is published.

`ST_RunControl` is the sole external command structure. RunControlBase receives the complete structure as `VAR_IN_OUT ControlData` at its cyclic FB call, normally bound to `GVL_UnitTest.RunControl.ControlData`. Isolated selftests supply local storage instead. After internal processing, Run Control writes only its Name and current Status to their individual ControlData fields. ContractInfo is outside ST_RunControl and requires no cyclic handover.

RunControlCommandAdapter is the signal-transport boundary. It receives the selected I_RunControl and Commands : ST_Command through VAR_IN_OUT, bound to the actual ControlData.Cmd field. The PLC application calls it exactly once per task cycle before the corresponding Run Control FB. It qualifies Reset, Abort and Start independently across two consecutive samples, invokes the corresponding Request method and clears only that accepted field. After clearing, it retains the live command values for the following call. Unqualified fields and requests made through the OOP API remain untouched. Run Control's ProcessRequests retains priority and trigger-event publication; the adapter introduces neither a second owner request store nor duplicate trigger events.

VAR_IN_OUT accesses the supplied storage directly but does not synchronize external writers. Never copy the entire ControlData structure back; write only the owned fields and explicitly accepted command bits. The existing sampling protocol remains responsible for asynchronous command intake. Multiple identical writes while a BOOL is already set cannot represent distinct queued requests. BufferCmd remains part of the supplied structure, with processing defined separately by the Event Stream contract. Instance-local event-service binding is independent of communication-storage selection.

The PLC application calls RunControlCommandAdapter.Initialize(ControlData := ...) in the FirstCycle-triggered initialization sequence described under [Initialization And Remanence](#initialization-and-remanence), before Event Buffer and hierarchy initialization and before cyclic command intake. This method receives the selected ST_RunControl by VAR_IN_OUT and clears only its Cmd and BufferCmd fields plus the adapter's qualification history. It retains no reference, does not use the cyclic FB inputs, and leaves Name and Status unchanged. Clearing BufferCmd discards its Reset flag and DeleteSequenceId watermark; it does not reset or delete buffer contents. No owner request or event is generated. The normal cyclic interface and two-sample qualification are unchanged. Run Control Initialize clears its own request storage and, on success only, queues the initial Reset. A lifecycle Reset does not reset the adapter's sampling history. Before successful Run Control initialization, the adapter clears qualified commands and the existing passive owner request path discards them; they are not queued for later execution. Name and status projection continues on every Run Control FB call, including Uninitialized and Completed.

The adapter requires a valid, stable Run Control interface and matching command storage. The application owns this wiring; the adapter does not initialize or execute Run Control. A future RPC transport can invoke the same Request methods without signal qualification or changes to the owner request path; RPC is not implemented here. The concrete Run Control forwards its inherited ControlData argument to SUPER^(ControlData := ControlData) once per task cycle. Typical cyclic application wiring is:

```iecst
CommandAdapter(RunControl := Run,
    Commands := GVL_UnitTest.RunControl.ControlData.Cmd);
Run(ControlData := GVL_UnitTest.RunControl.ControlData);
```

Typed Suite and Test Case configuration DUTs are internal implementation data. Configuration is established through `Initialize(...)` and remains unchanged during regular execution. Test Case initialization is explicitly repeatable as described below; rejected input may remain available for diagnosis without permitting execution. Parent initialization follows static composition: Run Control initializes its Suites and each Suite initializes its Test Cases.

Framework collaborators use the appropriate behavioral interfaces. References to static test resources or larger shared data require defined lifetime, initialization, and mutation ownership. Bindings are established during composition or initialization; they do not introduce runtime registration or cyclic rebinding. References do not expose private owner internals or enter published contract data.

### Shared orchestration interfaces

The shared interfaces separate one child from its collection. I_Orchestratable extends I_ResultProvider. I_TestCase and I_TestSuite extend I_Orchestratable and retain their distinct typed Status properties. The shared child view contains read-only State, IsInitialized, IsReady, IsComplete, HasError and ReservedEntryCount, configuration-time writable ExecutionSlot, RequestStart/RequestReset/RequestAbort, and the existing reservation/release methods. Name and Result come from I_ResultProvider. Initialize remains an instance operation.

The Orchestrator observes these properties directly, without requiring a new common execution-status DUT or copying complete owner snapshots. HasError includes configuration and runtime errors; Result remains available separately for Abort and result handling. Typed status snapshots remain responsible for owner-specific aggregation and optional external status projection.

I_OrchestratableCollection provides indexed access for shared scheduling. It exposes collection bounds/count and GetChild(Index) : I_Orchestratable. The Orchestrator receives the collection and obtains each child through it; it does not receive a second separately registered set of children. A Suite provides this collection for its Test Cases while being an I_Orchestratable child of Run Control itself. Concrete owners retain their typed local arrays and indexed access; no parallel generic array, cyclic array pointer or per-child adapter is introduced. Only the owner invokes concrete child FBs, aggregates results and supervises its lifecycle timeouts. The helper retains contextual technical diagnostics, not owner lifecycle evidence.

The builder binds the typed array, determines its actual bounds, registers children, assigns slots and validates the completed configuration. The owner retains that finalized configuration alongside its array and exposes ChildArrayLowerBound, ChildArrayUpperBound and ChildCount through I_OrchestratableCollection. ChildCount describes the contiguous occupied range starting at ChildArrayLowerBound; ChildArrayUpperBound describes capacity, not the last registered child. GetChild(Index) uses the actual array index and returns zero outside the occupied range without executing a child. No separate Collection FB is required.

During initialization, the Orchestrator reads ChildArrayLowerBound and ChildCount once and caches the first and last occupied indices (ChildArrayLowerBound + ChildCount - 1). These immutable processing bounds are an intentional cache, not an independently maintained configuration. Registration/capacity validation remains with the builder and collection initialization; the Orchestrator does not need ChildArrayUpperBound or repeat that capacity check. It retains the collection interface for child lookup, not a pointer into the owner's array. Changes to composition require configuration reactivation or a PLC Cold Reset and renewed hierarchical initialization; lifecycle Reset preserves the configured collection and cached bounds.

Diagnostic initialization retains the owner Name and ResourceName. Technical Framework errors use <OwnerName>.Orchestrator and State = E_State.Error, without publishing owner lifecycle, Result or Aggregation evidence. Concrete child calls and result aggregation remain with the owner.

The helper receives I_OrchestratableCollection and observes I_Orchestratable children directly, without a typed status snapshot or level-specific configuration input. It caches only the first and last occupied indices; full collection metadata remain on the owner.

### Test Suite cyclic integration

The Suite base owns cyclic ordering: consume requests, update timers, process Sequencer using retained child observations, invoke the selected Orchestrator through I_Orchestrator, call concrete Test Cases through protected abstract ProcessTestCases(), aggregate child observations/results once, then update result/status and emit finalization events. ProcessTestCases invokes child FB instances without duplicating Suite sequencing or dispatch selection. The base retains task mapping and invokes helper processing once; initialization, execution and observations all use the same selected interface. A separate overridable ProcessOrchestrator hook is not the substitution mechanism. Run Control uses the same invocation pattern.

The concrete Orchestrator receives Task : E_OrchestratorTask at its FB call. The Suite supplies this value through its side-effect-free MapOrchestratorTask(State, CurrentTask) method, which reads only its explicit parameters; no Orchestrator request methods or request mailbox remain. Result is NotEvaluated or a held technical Error, never a child aggregate or separate Passed/Abort lifecycle. Read-only IsResetFinished, IsAbortFinished and IsExecutionFinished report task completion; IsComplete selects the current task completion and is FALSE in Idle. IsResetActive, IsExecutionActive and IsAbortActive identify the assigned task even after completion. IsReady requires initialized, error-free Idle, ready children and successful reservation cleanup. ActiveSlot exposes the selected unfinished Execution slot, otherwise zero. Task is the explicit cyclic input and remains observable; normal Suite consumers use dedicated signals. Completion does not select the next task.

Suite transition decisions belong to Sequencer. IsStateTransitionAllowed is a pure predicate; ChangeState applies only the requested permitted transition and its entry actions, never a replacement target. In both bases, a rejected transition from Uninitialized returns without an event or result change. From Completed it emits a contextual diagnostic without changing the finalized result. In other states it emits the diagnostic unless Error is already held, then latches Error. Rejection leaves the state and timers unchanged; no additional diagnostic marker is used. On its next execution, Sequencer sends active execution through AbortingFromError; Idle errors enter Completing. During Reset, a held child or Orchestrator error does not stop remaining child-reset attempts. The Suite enters Completing after the Orchestrator finishes or ResetTimeout expires; an invalid collection or task clock terminates Reset immediately with Error. Escalation during Abort retains its original deadline. Uninitialized remains non-executable, and Completed diagnostics do not change the finalized result. Reset-to-Idle requires valid configuration and collection, ready children, a neutral Orchestrator result and no held owner Error; Start requires IsReady. TestCaseBase uses the same pure transition-validation boundary while retaining its own MultiState and Reset/Idle behavior.

TestSuiteBase uses FStateTimer for state timing and both ResetTimeout and AbortTimeout. It restarts on actual permitted state transitions and explicit initialization, except Aborting-to-AbortingFromError: that transition retains the running timer and original abort deadline. Rejected transitions and repeated requests for the current state do not restart it. FExecutionTimer measures active execution across Starting and Running. No separate abort timer is retained. State-time observation and cyclic status projection continue in terminal states without modifying the finalized owner result; child aggregation continues to refresh status counters.

Child start readiness is summarized only by the Orchestrator. Suite and Run Control IsReady combine their own initialized, valid, error-free Idle state and collection validity with the helper IsReady and neutral Result. Their child-aggregation scans do not maintain a second readiness aggregate. Reset completion uses the helper IsResetFinished and Result rather than IsReady, which requires the Idle task. Existing invocation order is retained: helper observations come from its most recent execution, while typed result/status aggregation follows concrete child calls.

### Test Suite events and extension hooks

The Suite base publishes request triggers from the consumed request mailbox before applying lifecycle transitions. Each recorded request is reported once, including requests suppressed by Reset/Abort/Start priority; uninitialized cyclic processing remains passive. The initial Suite Reset is a capacity-admitted parent request and follows the same trigger and transition publication as later Reset requests. ChangeState publishes one Suite-scoped transition event for each actual permitted change; same-state and rejected transitions produce no transition event. Reset interrupting active execution emits the existing reset-warning diagnostic.

After the concrete Orchestrator and Test Case calls, AggregateResults, UpdateResult and UpdateStatus establish the final values. EmitFinalizationEvents publishes Result followed by TestSuite Aggregation only when the Suite has entered Completing. The next Sequencer call changes Completing to Completed without reinterpreting children or helper results, while aggregation, concrete child calls, Orchestrator administration and status projection continue. The single-cycle Completing path supplies one-shot publication without another flag. Completed retains the final owner result, not a frozen set of child counters; explicit Reset remains processable. Event-buffer insertion failures remain accounted for by the publisher, without cyclic retries or recursive diagnostics.

Configure(Builder) initializes and registers concrete children. The base finalizes their configuration and initializes its owned Orchestrator. The base calls that Orchestrator once per initialized cycle, including Completed, so reservation administration can finish without starting new tests. ProcessTestCases then invokes every owned Test Case once in every initialized cycle, including unselected children, Completing and Completed. ProcessTestSuites follows the same rule in Run Control. Neither hook takes an Enable input or gates child FB calls by the parent state. The Orchestrator's requests and each child's own lifecycle govern its work. Initialization remains the prerequisite for calling the hook. GetTestCase only supplies indexed access; CheckInitialization extensions include the base checks. Derived code calls SUPER^() once and does not duplicate lifecycle events or finalization.

### Test Suite child aggregation

TestSuiteBase calls its children exclusively through its own single-task execution path. After the Orchestrator and concrete child calls, AggregateResults scans the registered collection once, collecting lifecycle observations, results and execution counters from temporary child Status snapshots. Sequencer uses those retained observations on the following call; no separate pre-sequencing observation scan is required. External request methods record intent without processing child lifecycle state. Initialization clears observations; initialized Suites remain in Uninitialized until the parent submits a capacity-admitted Reset request. ObserveTestCase validates and reads an individual child within the aggregation scan. No persistent child-status array is introduced. Completed continues aggregation and child FB calls; only the final owner result remains held. AggregateResults never writes FStatus. UpdateStatus continues on every FB call, including Uninitialized and Completed; Passed/Failed come directly from ResultAggregator and Total from the configured collection.

TestCaseCountTotal is the registered count. Inactive, Idle, Running and Completed counters classify the child ExecutionStatus; Passed and Failed counters classify child results. A child contributes at most once to TestCaseCountError when its execution classification or result is Error. Invalid child bindings invalidate readiness/completion and contribute one Error each without dereferencing the missing interface. Execution.Error and ConfigError also prevent normal owner completion. Reset may observe stale child results while bounded reset dispatch is still pending; these do not replace reset timeout and Orchestrator failure handling.

Normal Starting/Running keeps the Suite result NotEvaluated. A child or technical helper Error escalates the owner; unexpected child Abort is an error unless confirming the selected owner abort path. A Failed child does not stop the Suite. Completing maps the established child aggregate to Passed/Failed while preserving owner Error/Abort priority. Completed retains the owner result until Reset or explicit initialization; child counters continue to reflect current observations. UpdateStatus still runs on every Suite FB call, including Uninitialized and Completed; retaining internal results does not suspend status projection. Runtime remains the owner's measured active execution time, not a sum of child runtimes.

### Independent Test Suite double

TestSuiteMock implements I_TestSuite directly without TestSuiteBase inheritance, child instances, a child collection or an Orchestrator. It is a reusable childless double, not a production Suite with an empty registered collection.

Ready and Completed default to TRUE; ResultValue defaults to E_Result.Passed. MinimumTestDuration is a writable TIME property defaulting to T#100ms. Requests only record intent; the regular FB call processes the simulated lifecycle. Reset and Abort need no additional completion acknowledgement. Normal completion requires Completed and the minimum test duration; Error ends early and Failed does not shorten the duration.

Initialize clears the mock's own old reservation contribution after Event Buffer startup initialization without attempting release. The initialized mock waits in Uninitialized for its parent's reserved Reset request, just like an ordinary Suite.

The mock publishes real Suite request, state-transition, Result and Aggregation events and performs real local/global Event Buffer reservation updates. It emits no child events. All Test Case counters remain zero; the simulated Suite result comes from ResultValue independently of those counters. Finalization preserves the established event order and retains the completed result. Executable integration and full verification remain separate from this double.

### Test Suite initialization and local collection

The concrete Suite owns its static Test Case instances and local ARRAY OF I_TestCase. TestSuiteBase establishes identity through Parent : I_RunControl and SuiteName, creates a method-local TestSuiteConfigurationBuilder and passes it by VAR_IN_OUT to protected abstract Configure(Builder), without a return value. Configure initializes children and builds their configuration. After its return the base calls Finalize, rejects an invalid returned configuration, initializes its owned Orchestrator with the finalized values, validates setup through extensible CheckInitialization, and only then reports initialization success. The Suite holds finalized collection metadata before helper initialization. Its initialization-validation phase exposes those values for child checks; helper initialization does not execute scheduling. The Suite exposes collection metadata only during that validation or after successful initialization. Failed initialization leaves the Suite Uninitialized with ConfigError and no usable published collection count. Cyclic Orchestrator execution requires successful Suite initialization; no additional Enable is used. The final check includes I_TestCase.IsInitialized. There is no separate registration handover, RegisterOrchestrator or application-owned Orchestrator initialization.

Builder.Initialize(TestCases, Mode) clears and binds the array once and fixes E_OrchestrationMode for this build. Register(TestCase) appends only in Serial or Parallel: effective slots are registration positions starting at 1 or always 1, respectively. RegisterWithSlot(TestCase, ExecutionSlot) is valid only in ParallelSlots. It inserts before the first larger slot, preserving equal-slot order, and shifts the occupied tail backwards. The builder sets the child's writable ExecutionSlot property; no parallel slot array or entry DUT exists.

Registration validates mode, reference, uniqueness, slot and capacity before mutating the array, Count or child slot. Rejection leaves the composition unchanged and latches an error until Initialize. Temporary gaps in assigned slots are allowed while building.

FirstIndex and LastIndex are the actual array bounds; Count is the contiguous occupied population from FirstIndex. Capacity is LastIndex - FirstIndex + 1, and the occupied end is FirstIndex + Count - 1. Arithmetic is checked before access. ST_TestCaseCollectionConfig carries FirstIndex, LastIndex, Count, IsValid and Mode as the finalized configuration values. Finalize returns this structure directly, including on repeated calls. The caller checks the returned IsValid; no separate configuration-snapshot property is required.

Finalize validates initialized, nonempty, error-free registration and contiguous populated slots beginning at 1. It discards the setup-only typed array pointer on both success and failure. IsFinalized records that the build has ended; IsValid records its outcome. Repeated Finalize calls return that outcome without touching the array. Further registration is rejected without changing finalized data; only Initialize starts another build. A premature return from Configure does not skip base-owned finalization. The concrete Suite need not call Finalize or maintain a validity flag.

The typed pointer is confined to synchronous setup with stable array storage and no concurrent mutation. The base retains the finalized configuration in FCollectionConfiguration; neither a builder reference nor an array pointer survives for cyclic use. ChildArrayLowerBound, ChildArrayUpperBound and ChildCount read this owner-held configuration and implement I_OrchestratableCollection directly. Public abstract GetTestCase(Index) supplies the typed entry, while concrete GetChild(Index) checks the occupied range and returns its common interface view. Invalid/unavailable access returns zero without invoking a child. After successful finalization, the base exposes this configuration during synchronous helper initialization and CheckInitialization. Failed initialization hides the metadata again. The helper receives only the common collection view and diagnostic identity; no owner property delegates metadata back to it.

Changing layout, registration or mode requires configuration reactivation or a PLC Cold Reset and explicit hierarchical initialization; lifecycle Reset retains setup. No global maximum child capacity, generic constant or Registry inheritance hierarchy is required. Orchestrator substitution is a pre-initialization dependency seam, not dynamic strategy switching. Direct I_TestSuite implementations remain permitted with equivalent contract behavior.

### Reset failure continuation

During Reset, CheckChildErrors interprets child errors only below the existing dispatch cursor. Old results above that cursor are ignored. Reset dispatch continues despite a held Orchestrator Error or rejected reservation while the collection remains valid. Readiness or terminal completion ends an individual processed child's Reset; terminal completion is a Reset failure. The helper defensively skips unusable entries, but this is not an end-to-end recovery guarantee: Suite-side detection of an invalid collection may terminate Reset immediately. Unfinished Reset processing remains bounded by the Suite deadline. No per-child history array is introduced. Repeated in-phase Reset requests preserve the cursor and held error.

The Suite latches an Orchestrator failure but remains in Reset while the Orchestrator finishes remaining attempts on a valid collection. Successful Reset reaches Idle; failed Reset finalizes through Completing to Completed after the Orchestrator completes, the Suite ResetTimeout expires, or a processing prerequisite becomes invalid. Reset completion and successful readiness are distinct. Reservation ownership remains local. Changing the helper task from Reset to Idle does not itself release unfinished reservations.

### Unified slot orchestration

One Orchestrator handles all modes through the slot-sorted child array. Serial produces one child per slot, Parallel one slot containing all children, and ParallelSlots explicit contiguous slot groups. Within a group, stable registration order determines first-fitting selection. The next slot starts only after every child in the current slot reaches Completed.

Current-slot boundaries restrict cyclic scans; encountering a higher slot ends the scan. No permanent slot lookup table or per-child control array is introduced. At most one child Start is dispatched per cycle. A pending Start index supports next-call confirmation. The Orchestrator coordinates reservations and requests, while concrete Suite code still calls child FB instances. SelectNextSlot() derives the first or next group from internal progress without caller-supplied index or slot arguments. Its caller decides when the completed current slot permits advancement. IsLastSlot(Slot) is a side-effect-free method comparing the supplied slot number with the last registered child's ExecutionSlot, irrespective of unused array capacity. ProcessSlot passes FCurrentSlot. The public collection bounds are named ChildArrayLowerBound and ChildArrayUpperBound to distinguish storage capacity from ChildCount and the occupied range.

The Orchestrator FB body first checks initialization. When Task differs from FPreviousTask, InitializeTask performs once-only entry initialization, then FPreviousTask records the supplied value. CASE Task dispatches ProcessIdle, ProcessReset, ProcessExecution or ProcessAbort in the same call. Neither entry initialization nor processing selects a different task. The Suite alone authorizes Start through its lifecycle and IsReady checks. InitializeTask only initializes task-specific progress; it does not recheck Idle/readiness. The Orchestrator retains processing-time child-state, reservation and Start-response checks, and a held helper Error still prevents further Starts. Reset entry clears progress and held helper errors; continued Reset calls do neither. Abort entry retains any pending Start confirmation. Idle entry stops dispatch without inventing child Abort requests. InitializeTask does not release reservations merely because the previous task was Reset; cyclic completion-based reconciliation remains separate. Task completion never changes Task. The Suite maps Reset to Reset, Starting/Running to Execution, Aborting/AbortingFromError to Abort, and Idle/Completed/Uninitialized to Idle. Completing preserves a previously assigned Execution or Abort task; a previous Reset or Idle task maps to Idle. The mapping consumes the Orchestrator's current task, not the owner result, so Reset failures never become Abort requests. This keeps normal completion and Aborting-to-AbortingFromError within the same task and preserves their progress. No helper execution timer, autonomous owner lifecycle, normal transition events, persistent child-status array or duplicate reservation ledger is introduced. Read-only completion properties expose prepared observations. Contextual Framework errors retain the .Orchestrator name; State is E_State.Error rather than a task identifier.

Child observation is separated by responsibility. CheckChildErrors checks bindings, task-specific errors and current-slot invariants without dispatch or reservation changes. FreeCompletedReservations performs eligible releases before completion or new admission. UpdateReadiness, UpdateResetCompletion and UpdateAbortCompletion prepare their respective observations in bounded scans; failed access or release prevents usable completion. The public completion/readiness queries remain side-effect-free. IsSlotCompleted inspects only the current slot; ProcessSlot advances its boundary or dispatches one candidate and is called only from the execution task after error checks and reservation reconciliation. InitializeTask selects the first slot once on entry to Execution, after clearing slot progress and only without a held helper Error. ProcessExecution owns pending-Start confirmation and ongoing processing; ProcessSlot selects subsequent slots. Abort still confirms an already pending Start before abort dispatch. The additional scans trade repeated interface-property reads for explicit responsibilities without retaining child-status copies or adding a reservation ledger.

### Test Case base execution

`I_TestCase` extends `I_Orchestratable`, which extends `I_ResultProvider` and exposes read-only Status and
RequestStart, RequestReset and RequestAbort. Initialization belongs to the
statically composing owner, not the orchestration interface.

One abstract TestCaseBase supports single and multiple Preparation and Test
states without owning a Preparation array. PreparationStateCount and
TestStateCount are finite-path capacity metadata, not automatic progression
controls; concrete initialization establishes them before Ready.

The cyclic processing order is:

1. ProcessRequests consumes pending same-task requests and emits request events.
2. The execution and phase Stopwatch helpers update their measurements.
3. Sequencer runs unconditionally and selects transitions from requests,
   existing child observations, prior aggregation and timeout conditions.
4. When initialized and in Reset, the base clears the Preparation snapshot,
   updates status and calls ProcessReset until CompleteReset or the base-owned Reset timeout.
5. In Completed, the base skips test-processing hooks, but continues aggregation,
   request processing and cyclic status projection without a base-body early return.
6. Otherwise, the initialized base calls ProcessAbort, ProcessPreparations,
   ProcessTests and ProcessAssertions in that order. Each Enable argument is
   evaluated from the current state immediately before its call.
7. On every initialized cycle, including Reset and Completed, the base starts a fresh collection and calls
   AggregateResults with the I_ResultAggregator view of its owned ResultAggregator.
8. UpdateResult applies owner result rules; UpdateStatus projects the snapshot;
   EmitFinalizationEvents emits Result and Aggregation while in Completing.
   On the next Sequencer call, the Completing branch changes to Completed;
   the common base-body tail projects that state on this and every later call.

The concrete Process methods own deterministic child calls, including necessary
disabled calls in Reset, abort handling and Completing. They are not invoked in
Completed. Required deactivation and cleanup must finish before terminal
completion; continuously operating application resources need an independent
call path. ProcessPreparations supplies combined observations through
UpdatePreparationStatus. PreparationStatus only returns the stored snapshot.

TestCaseBase deliberately deviates from the preference for one location of
state-transition decisions: internal scenario hooks can complete or advance a
phase immediately within the base-owned cyclic call. This lets scenario code
express completion directly and makes subsequent hook permissions reflect the
new phase. ChangeState centralizes validation and transition actions, not every
transition decision. This exception does not extend to the external request
interface or authorize asynchronous lifecycle execution. The existing Sequencer
name is retained for this component rather than the general StateMachine naming
preference.

NextPreparationState, CompletePreparations, NextTestState, CompleteTests,
CompleteAbort and CompleteReset perform checked transitions immediately. CompleteReset enters Idle without a held Error; otherwise it enters Completing and then Completed, never an abort state.
Subsequent hooks in the same call observe the new phase. External RequestStart,
RequestReset and RequestAbort instead record requests for regular FB processing.
ProcessRequests applies Reset-before-Abort-before-Start priority; Sequencer
evaluates phase-specific errors, timeouts and requests before scenario hooks.

CompleteTests does not assign Passed. UpdateResult derives the final outcome in
Completing from held termination results and existing evaluation results.
Completed retains that outcome until Reset or explicit reinitialization.

ChangeState owns transition checks, entry actions, measurement boundaries and
transition events. Initialize and actual entry into Reset clear the owner result.
IsStateTransitionAllowed is a pure predicate over the requested NewState; it
never selects a replacement target. Rejected transitions leave state and timers
unchanged and latch Error outside Uninitialized and Completed. Sequencer routes
held active-phase Error into AbortingFromError on its next execution; phase
completion and advancement helpers also preserve Error priority. MultiState
entry, configured upper bounds, one-step advancement and completed-Preparation
prerequisites remain enforced. UpdateResult does not erase a latched Error.
UpdateResult preserves the result during Reset and Idle. Error ignores
Uninitialized and Completed; elsewhere it publishes only when the held result
is not already Error, then holds Error. Reset and Idle retain their state;
active execution enters controlled error termination. A held Error prevents
the base IsReady release in Idle.

The internal method-driven Stopwatch helper owns timestamp acquisition,
start/reset/stop and elapsed-duration calculation. Measurements retain unsigned
64-bit 100 ns units; status uses the saturated TIME projection. No CycleTime
input or global clock update is required.

The Uninitialized CASE branch remains passive after successful Initialize until
the parent submits a capacity-admitted Reset request. Before successful
initialization, requests are consumed without execution or request events.
Request handoff uses call-local values, not a second persistent mailbox.
Cross-task or asynchronous request synchronization is not provided.

## Capacity-Aware Orchestration

Normal Test Case execution and hierarchical reset can create event bursts. Orchestrators use producer-side event-buffer capacity to bound subordinate dispatch without coupling PLC execution to consumer polling or batch sizes.

Each Test Case publishes `PreparationStateCount`, `TestStateCount`, and `AssertionCountTotal`. These values describe the longest finite executable lifecycle path and are valid while the Test Case is `Idle AND Ready`.

Before starting a candidate, the Orchestrator calls its ReserveExecutionEvents(). The Test Case computes the budget and adjusts its own reservation together with the Event Buffer aggregate. Capacity must cover all reservations and shared execution headroom. Each Test Case and Test Suite owns its own contribution; the Orchestrator has no duplicate ledger and starts at most one child per PLC cycle.

I_TestCase and I_TestSuite expose writable ExecutionSlot, read-only IsInitialized and ReservedEntryCount, and immediate ReserveExecutionEvents() : E_EventReservationResult, ReserveResetEvents() : E_EventReservationResult and FreeReservedEvents() : BOOL. These methods do not change lifecycle state. Budget and headroom calculation remain internal to the respective owner; callers pass no quantities. Reservation aligns the own contribution to the required total, so repeating the same request does not add another budget. FreeReservedEvents synchronously releases the complete registered subtree: a Test Case releases its own contribution; a Suite visits every registered Test Case and releases its own contribution as well. A zero own contribution does not skip children. All releases are attempted even after failures; FALSE reports partial failure, while successful local/global releases remain applied and unresolved contributions remain available for retry. Repeated release is idempotent. Each individual publisher operation changes its local and global counts together or leaves both unchanged on rejection.

Execution budgeting uses AssertionCountTotal from ResultAggregator through the Test Case status, available at Idle AND Ready. No MaxAssertionCount parameter, instance bound or additional count-limit guard is introduced.

The Orchestrator calls ReserveResetEvents before dispatching Reset and FreeReservedEvents after observing Idle AND Ready, Completed or a failed Start reaction as applicable. Lifecycle Reset does not zero the child contribution independently. Full PLC-start initialization is different: the Event Buffer is initialized first, then each Test Case and Suite Initialize sets its own FReservedEntryCount to zero while rebuilding transient setup. It does not release contributions from the preceding run, traverse old registration for cleanup, or abort because old contributions cannot be released against the new buffer accounting. Configure rebuilds the hierarchy and registration; regular execution begins only after successful initialization.

A reservation is created before the child Start request. On the next Orchestrator call, the child must have left `Idle` or reached `Completed`; otherwise the reservation is released and the missing Start reaction is handled as a framework error.

An accepted reservation is retained through execution, Abort, and finalization until the child reaches `Completed`. Parent Reset replaces execution reservations with Reset reservations and releases them when children reach `Idle AND Ready`. A successful hierarchical Run Control Reset leaves no reservations. Changing from Reset to Idle stops that helper's dispatch, without unconditional reservation cleanup. On Suite completion after a Reset failure, recursive FreeReservedEvents intentionally releases the whole subtree even if a Test Case is still resetting. That Suite no longer dispatches child requests, while cyclic calls continue so children reach their own normal or timeout completion. The temporary gap between reservation accounting and late event production, including possible overbooking by other active subtrees, is accepted for this failure path. This is not an unlimited event-capacity guarantee. No second cancellation protocol, additional child-call guard or reservation ledger is introduced. The PLC program must keep calling Run Control cyclically; its final owner result remains held while child aggregation and status counters continue to refresh. CompletionDelay and final Result/Aggregation publication remain unchanged; integration/selftests verify late child diagnostics, terminal cleanup and consumer interpretation.

The event-buffer command `BufferCmd.Reset` is the authoritative destructive reset of buffered events, event-buffer status, and reservation accounting. It remains available with active execution or outstanding reservations and does not require a PC consumer to drain the buffer first. Run Control calls `FreeReservedEvents()` on every registered Suite before resetting the Event Buffer; Suite release includes its Test Cases. All attempts precede the reset, but their return values do not gate it or the clearing of both Buffer commands. Successful releases synchronize local and aggregate contributions. Failed releases do not add a wait/retry protocol, force local fields to zero, or establish a guarantee of repaired accounting; full PLC-start initialization rebuilds those fields separately.

Buffer reset is separate from hierarchical lifecycle Reset. Existing Orchestrator checks for an active child without a reservation remain unchanged: affected execution follows its normal framework-error path. The integration does not suppress this check, rebuild active reservations, force lifecycle states, or add a separate Abort/Reset protocol. A destructive reset during execution invalidates the affected run's event-log completeness; preserving a successful uninterrupted run is not its purpose.

`Serial` preserves strict configured order. `Parallel` selects the first currently fitting candidate in configured order. `ParallelSlots` applies the same selection within the active slot and preserves slot order.

The producer-owned global count combines the separately owned Test Suite and Test Case contributions. Sequential calls within the owning PLC task prevent separate Orchestrators from allocating the same capacity.

Suite execution reserves ten own-event entries; Suite Reset reserves four. Child reservations are not included in those contributions. Both levels use Accepted, WaitingForCapacity and Error to distinguish successful admission, temporary pressure and invalid/permanently impossible requests. Case admission includes the fixed parent Suite allowance in the permanent capacity check. Suite Reset includes room for one child Reset allowance. The publisher exposes read-only Capacity as the actual usable event count (physical ring length minus its unused position), or zero for an invalid buffer. Capacity is independent of current occupancy and reservations.

Suite Reset admission checks current physical free entries against the global reservation after replacing its own contribution, plus reset headroom and one Test Case Reset allowance. Only the Suite contribution is reserved; the child allowance remains shared admission margin. The private Suite helper names this allowance ChildEntryCount to distinguish it from the Test Case helper's ConcurrentEntryCount, which belongs only to the permanent minimum-capacity check. The Test Case free-capacity check does not add the parent's allowance again. This permits overlapping Suite resets with at most one new dispatch per helper call, without reserving all child budgets in advance. Equal and reduced nonzero reservations pass the same admission check; full release remains ungated. Single-task reservation accounting preserves the margin at each Suite admission, but later event production may require consumer draining before a child fits. Reset timeout supervision and failure behavior remain unchanged.

The shared execution and reset headroom values preserve producer capacity for Run Control, Orchestrator, and additional exceptional framework events. They do not reserve capacity per owner or define consumer timing.

`EventBufferResetHeadroom : UINT := 20` is a consumer-overridable compile-time library parameter for the shared producer headroom during hierarchical reset. It is distinct from `EventBufferExecutionHeadroom : UINT := 10`, which applies to normal execution capacity gating. Neither parameter defines consumer timing or the destructive Event Buffer Reset command.

The reusable FIFO storage and its minimum external projection are defined by the FIFO prerequisite. UnitTest components depend on semantic event-capacity operations and do not access FIFO implementation state directly. The prerequisite may adapt internal FIFO handling and the minimum projected FIFO metadata to TwinCAT capabilities, but it must preserve the approved external event provision and `DeleteSequenceId`-based contiguous release behavior.

### Timeout ownership and diagnostic retention

Each TestCaseBase and TestSuiteBase detects and handles its own execution, Reset and Abort timeouts. TestCaseBase additionally owns Preparation timeout handling. Parents consume normal child state/result; Orchestrators do not re-evaluate child timeout thresholds. Suite-wide deadlines remain independent and include child handling and capacity waiting. The shared Orchestrator has no separate execution timer or Runtime property. TestSuiteBase measures active runtime, including capacity waiting, and owns execution timeout monitoring.

Reset and Abort timeout detection publishes a Framework diagnostic, holds Error and enters Completing, followed by Completed, without waiting indefinitely for child or hook completion. It does not imply that unfinished resources were physically reset or stopped. The Test Case uses FStateTimer for Reset and Abort as well as individual Preparation/Test states. Aborting-to-AbortingFromError preserves the original deadline; same-state requests do not restart timing.

Public read-only HasTimeout, HasResetTimeout and HasAbortTimeout expose latched owner-local diagnostic fields; TestCaseBase also exposes HasPreparationTimeout. HasTimeout denotes execution timeout, not the OR of all timeout flags. Flags clear only on explicit Initialize or actual entry into a new Reset, and otherwise survive phase changes and Completed. A Reset timeout in the new phase latches again. Getters only read stored values. These properties neither extend orchestration interfaces/status DUTs nor replace timer checks. Invalid clocks report errors without asserting timeout flags. Status.Runtime and event runtime publication remain unchanged.

## Duration Types

Owner configuration timeouts and delays and status `Runtime` fields use `TIME`. Internal start timestamps and elapsed durations retain the native time-source resolution. Stopwatch retains the 100 ns task-clock resolution and exposes ElapsedLTime for comparisons. Test Case and Suite bases compare it with TIME_TO_LTIME(ConfiguredTimeout), converting at comparison time instead of retaining duplicate configuration values. One-time conversion remains an option when its performance benefit justifies that additional state. Only status projection discards fractional milliseconds and saturates at the TIME maximum. Aggregation events publish numeric milliseconds preserving the unsigned TIME range. Absolute event timestamps remain LINT UTC Unix nanoseconds.

`ST_TestCaseConfig` contains `Timeout : TIME := T#5s`, `PreparationTimeout : TIME := T#2s`, `ResetTimeout : TIME := T#1s`, and `AbortTimeout : TIME := T#1s`. Identity is supplied separately through `Initialize(Parent : I_TestSuite, TestName, ResourceName, Config) : BOOL`. The base clears transient state and resets both INT count fields to the named sentinel StateCountNotConfigured = -1, accepts owner configuration, validates Parent before dereferencing it, and validates the hierarchical name before invoking protected abstract Configure() without a return value. The hook sets FPreparationStateCount and FTestStateCount and initializes owned components. Public concrete read-only INT PreparationStateCount and TestStateCount properties expose those fields, including the sentinel. Configure must explicitly assign both counts. Protected virtual CheckInitialization() : BOOL then distinguishes unset counts from range errors, checks Preparation count in 0..(E_State.Running - E_State.Preparing), Test count in 1..(E_State.Completing - E_State.Running), and positive timeouts; derived overrides include SUPER^.CheckInitialization() and may validate their own setup. Initialization failures publish framework diagnostics without executing the runtime Error lifecycle path. The owner remains uninitialized on failure and publishes a consistent status before returning. Initialize rebuilds transient setup during hierarchical PLC-start initialization; no separate Uninitialize call is required. Reinitialization during an active run is not a supported recovery path. The Parent interface is used only during initialization and is not retained. Declaration defaults also use the sentinel. UINT status fields receive only validated in-range counts by explicit conversion; invalid counts project as zero.

`ST_TestSuiteConfig` contains `Timeout : TIME := T#10s`, `ResetTimeout : TIME := T#1s`, and `AbortTimeout : TIME := T#1s`, in that order. Identity is supplied separately through the Suite initialization parameters `Parent : I_RunControl` and `SuiteName`; it is not part of the configuration DUT. The owning Initialize method validates all three timeouts as greater than `T#0ms`. Owner-specific extensions are aligned with the Test Suite base design.

The initial `ST_RunConfig` contains `Timeout : TIME := T#30s`, `ResetTimeout : TIME := T#1s`, `AbortTimeout : TIME := T#1s`, and `CompletionDelay : TIME := T#100ms`, in that order. Initialize validates all three timeouts as greater than `T#0ms`; `CompletionDelay` may be `T#0ms`. The concrete Run Control sets timing configuration in Configure; Suite binding follows the local collection and builder model defined above.

## Lifecycle And Result Model

Run Control, Test Suite, and Test Case are Full Owners. They use shared PLC enums for lifecycle state, execution status, and result while preserving the established numeric values.

`E_State.Completed` is the stable final lifecycle state. Normal completion, explicit abort, and controlled error termination all end in `Completed`; `Result` communicates the final outcome.

Finalization follows one order:

1. Final owner Result event.
2. Final owner Aggregation event.
3. State-transition event into `E_State.Completed` in a later PLC cycle.

Preparation may use a configured contiguous Preparation-state interval. Test Cases may use a configured contiguous Test-state interval. These ranges support MultiPrepareState and MultiTestState without changing the shared coarse execution status.

## Preparations

Preparations may implement `I_Preparation` directly or derive from the optional abstract `PreparationBase`. The interface exposes only the read-only `Status : ST_PreparationStatus` snapshot; it provides no execution method. Normal concrete FB calls receive level-based `Enable` and perform the actual work.

Preparation readiness describes whether its target-establishment behavior can operate from the current resource condition, not merely whether Enable is FALSE. Disabled calls perform no resource actions and report current observations. After handover to the Test Case's test phase, changes to the resource may make both Preparation Ready and Completed FALSE; neither is a continuing execution permission for that phase. The Test Case Sequencer interprets Preparation completion/error during Starting and Preparing, while the test phase evaluates the tested behavior through its Assertions.

`PreparationBase` accepts `Enable`, exposes read-only `Enabled`, and calls protected abstract `Prepare()` once on every FB call, including when disabled. Derived FB bodies call `SUPER^()` once. Derived implementations own the protected `FStatus` snapshot, target observation, resource actions, deactivation behavior, configuration, and any internal state machine. They maintain contract-consistent flags and observe whether the target remains reached; the base does not latch Completed. Its Status getter copies existing status without processing. The initial status retains the DUT defaults until preparation-specific processing updates it. Protected `UpdateStatus(State, ExecutionStatus, Ready)` immediately updates only `FStatus`: State and ExecutionStatus are copied, Running/Completed/Error are derived by equality with the respective execution status, and Ready is accepted except while Running. It neither derives execution status from State nor executes resource actions, emits events, or latches completion. No generic initialization, request mailbox, timeout, or reset API is imposed. Preparation timeout remains Test Case-owned.

`PreparationMock` is a public concrete library test double derived from `PreparationBase`. Inputs `Ready := TRUE`, `Completed := TRUE`, and `Error := FALSE` accompany inherited Enable. Each FB call derives execution status with priority Error, Completed, Enabled AND Ready (Running), then Idle when Ready, otherwise NotReady. Corresponding E_State values are Error, Completed, Running and Idle; both inactive execution statuses use E_State.Idle. It calls UpdateStatus with the selected execution status and the supplied Ready. Completed is independent of Enable, suppressed by Error, and never latched. Defaults report a reached target after the first call, allowing a Test Case to skip active preparation. Before the first call the inherited status retains its uninitialized defaults. The mock performs no resource actions and introduces no timer or automatic progression.

A concrete Test Case may own multiple local Preparation instances and defines their activation, call order, and combination in ProcessPreparations. The number of Preparation instances is independent of the number of Preparation states. The concrete implementation supplies individual combined observations through protected UpdatePreparationStatus; it does not pass an ST_PreparationStatus as input. The method updates the stored ST_PreparationStatus snapshot without calling or advancing Preparations. Its optional State input defaults to E_State.Uninitialized and represents the reported Preparation state, not the Test Case lifecycle state. The public read-only PreparationStatus property returns the stored snapshot; it is not an overridden aggregation hook. The concrete scenario defines the combination; no universal AND/OR combination is imposed.

Test Case ownership of Preparation timeout and status interpretation remains unchanged. Preparation error and timeout diagnostics use the reported PreparationStatus.State. UpdatePreparationStatus accepts Ready, Running, Completed and HasError as explicit BOOL observations, plus optional State := E_State.Uninitialized. It replaces the stored flags without latching; Ready is suppressed while Running. ExecutionStatus follows Error, Completed, Running, then Idle when Ready, otherwise NotReady. Reset does not call this observation method: the base directly restores State = Uninitialized, ExecutionStatus = Unknown and all flags FALSE before ProcessReset. The subsequent ProcessPreparations call may replace that reset snapshot with fresh observations in the same cycle, including while disabled.

## Assertions

Assertions retain typed checked-value inputs and run through their FB calls. A common abstract `AssertionBase` implements `I_Assertion`, shared result holding, reset priority, and one-shot finding behavior. It does not impose one evaluation strategy on every Assertion.

### Configuration and call interface

The owning Test Case calls AssertionBase.Initialize(Parent : I_TestCase, AssertionName, ResourceName := '', ObserveFirstCycle := TRUE) : BOOL before use and checks success. Name is read-only and receives the length-limited concatenation of Parent.Name and the local name for diagnostics before validation. The shared internal IsNameValid(Name, Depth) checks the unshortened full name for structure, ASCII character rules and GVL_Constants.NameLength. Depth 1, 2 and 3 identify Run Control, Suite and Test Case; Depth 4 validates three Owner segments followed by a nonempty ASCII Assertion-local suffix, which may contain further dots. Invalid names never enable execution, even though their diagnostic projection is retained. Parent is not retained. The Test Case supplies ResourceName and ObserveFirstCycle through Initialize, with defaults '' and TRUE. Both properties are read-only; changing either requires another Initialize call. Initialize is repeatable, clears the base-owned result and accepted activity/history, and queues a reset, including on failure; family settings remain unchanged. The next regular FB call processes ResetAssertion with bound inputs and returns without calling Assert. Initialize never calls ResetAssertion directly. IsInitialized is read-only. An invalid Parent or name produces a Framework diagnostic when a publisher is bound and leaves the Assertion unusable. The common body suppresses Assert until initialized; ObservationActive and explicit EvaluationActive also enforce that prerequisite. Initialization marks activity inactive until the next FB call, preserving first-observation semantics. Stored family-specific observations are reset when the queued reset is processed; they must not be treated as newly evaluated observations between Initialize and that FB call. Normal Reset retains initialization validity and identity. There is no additional Configure or CheckInitialization hook for Assertions.

Regular calls receive `Enable`, optional `Evaluate`, the current owning Test Case `State`, and typed checked values and limits. Read-only `Enabled` mirrors the accepted Enable input. Public read-only `EvaluationActive` belongs to AssertionBase and exposes the effective evaluation gate for the current/last FB call, including reset and first-cycle handling. Read-only `Result : E_Result` exposes the held result.

Public `Reset()` records a reset request. The next FB call clears resettable Assertion state, invokes the specific reset extension, and skips observation, evaluation, and finding publication. Until that call the previous result remains available. Configuration is retained.

### Base responsibilities and extension points

The base body first accepts control inputs for its observation properties, then processes any pending reset with priority; otherwise it calls protected abstract `Assert()`.

| Member | Visibility | Responsibility |
| --- | --- | --- |
| `Reset()` | public | Record a reset request for the next FB call. |
| `ResetAssertion()` | protected, overridable | Reset specific state such as edge counters or previous-value storage. |
| `Assert()` | protected, abstract | Perform the concrete observation and evaluation. |
| `Pass()` | protected | Promote `NotEvaluated` to `Passed` without de-escalating a held result. |
| `Fail(Message)` | protected | Apply a failed finding without de-escalating `Error` and publish the Failed finding once. |
| `Error(Message)` | protected | Apply `Error` and publish the Error finding once. |

The protected finding methods act immediately within Assertion processing. They are not public result manipulation or request APIs. Finding publication follows result escalation without separate finding flags: `Fail()` acts only from `NotEvaluated` or `Passed`; `Error()` acts only while the result is not already `Error`. A Failed result can escalate to Error, but `Fail()` after Error neither changes the result nor publishes an event. Concrete Assertions supply the diagnostic data; the base owns common publication behavior.

AssertionBase accepts `ObserveFirstCycle` through Initialize with default TRUE and exposes the configured value through a read-only property; Reset retains it. Observation uses `Enable AND (ObserveFirstCycle OR EnablePrevious)`, suppressed during reset. Direct evaluation follows ObservationActive. FALSE skips the first enabled call after startup, reset, or a disabled call. The body captures the previous call's Enable before accepting new inputs; a reset call contributes FALSE. The captured history remains unchanged during and after Assert until the next FB call. Both gates are calculated by overridable public read-only getters, not by a preparation method or stored gate fields. ObservationActive owns the observation gate; EvaluationActive delegates to it in the common base. Getter evaluation is bounded and side-effect-free. Inputs, reset state and previous-call history remain stable until the next FB call, so Assert and subsequent online monitoring use the same context.

`AssertionWithEvaluationBase` overrides the EvaluationActive getter to use the accepted Evaluate input independently of Enable and ObserveFirstCycle. Both bases report FALSE for a reset call. Concrete Assertions use EvaluationActive at their evaluation stage; the inherited ObservationActive independently controls observation, including ObserveFirstCycle. The gate is not proof of valid checked data or a newly produced result. It must permit evaluation when `Enable = FALSE`. Edge-count families observe while enabled and evaluate on request; sequence families may detect a failed observation before the completeness evaluation. A universal disabled early exit in the common base would violate these semantics.

Scalar sequence assertions observe through `ObservationActive` and check completeness through `EvaluationActive`, using the typed expected array without modifying it. Evaluate also checks the current input and may advance the sequence even when Enable is FALSE. The first observation must match the first expected entry; subsequent value changes advance at most one entry per call. Repeated equal observations do not advance. Disabling observation retains progression; Reset restarts at the supplied array's lower bound. Only explicit evaluation can produce Passed; mismatches, progression beyond the last entry, or incomplete evaluation produce Failed. Bit-string variants apply Mask to both progression and value acceptance. An empty mask produces Error whenever observation or evaluation is active, including after Failed. Every expected-array access is bounds-checked; advancing past the upper bound is rejected before incrementing the index.

Further intermediate bases require shared domain processing, not just a common input or data type. Previous-value storage, counters, windows, and type-specific validation remain with their responsible families. Signed integer variants may share stateless `LINT` algorithms; unsigned variants may share `ULINT` algorithms while retaining typed public APIs and bounds.

`Fail(Message)` and `Error(Message)` each accept one `VAR_INPUT` parameter, `Message : STRING(GVL_Constants.MessageLength)`. The concrete Assertion supplies the complete finding text, including applicable expected/actual values, limits, indices, or invalid-configuration details. There are no separate generic expected/actual parameters or diagnostic DUTs. Rendered assertion values remain bounded by `GVL_Constants.AssertionValueLength`; the full message uses the existing event message capacity.

The base supplies its configured `Name` and `ResourceName` and the current owning Test Case `State` to `CreateAssertionFailedEvent` or `CreateAssertionErrorEvent`, then publishes the constructed event through its selected instance-local `I_EventPublisher` view. Scope, result, and severity follow the existing event constructors. Concrete Assertions do not pass this context again or construct a full event for the finding methods.

### Character assertions and diagnostics

Separate Char/WChar equality, inequality and no-value-change assertions use BYTE/WORD code values without introducing alias types or character classification. Comparisons are exact and case-sensitive. NoValueChange follows the existing consecutive-observation model. The dedicated internal `CreateAssertionTextValue_Char` and `CreateAssertionTextValue_WChar` functions format printable ASCII (16#20..16#7E) as a quoted character followed by its hexadecimal code, for example `'A' (16#41)` or `'A' (16#0041)`. Other values use only the fixed-width hexadecimal code; this is formatting, not input validation. No additional escaping or case conversion is performed.

As an owner-approved exception to explicit string-capacity declarations, these two formatters and the short local value texts in their character assertions use plain `STRING` (default capacity 80). Their fixed formats require at most 10/12 characters; no separate length constants or runtime length checks are needed. Full finding messages retain `GVL_Constants.MessageLength` and their maximum composed lengths are checked during implementation.

### String assertion capacities and comparison

STRING and WSTRING assertions use the independent consumer-configurable library parameters `Param_Assertions.AssertionStringLength` and `Param_Assertions.AssertionWStringLength`, both defaulting to 80. They declare their respective text capacities directly with these parameters; diagnostic preview and event capacities remain unchanged. Increasing a capacity increases bounded processing work and, for value-change assertions, instance storage.

Text inputs use `VAR_IN_OUT CONSTANT` so a longer actual value is not truncated during transfer. Active processing rejects content exceeding the configured capacity with Error before comparison or baseline storage, including after Failed. Empty text is valid for equality and value-change assertions. Equality and inequality compare the complete accepted content exactly and case-sensitively; no case conversion is performed. WSTRING comparison uses its native code units, not a STRING conversion. Diagnostic conversion and shortening affect only the message preview. String, WString and their ByteArray/WordArray bridge previews retain printable ASCII code units (16#20..16#7E) and replace every other byte or wide code unit with the single byte 16#D7. STRING/WSTRING zero terminates input; selected array zero is replaced like other nonprintable data. Quotes and backslashes are not escaped. The 40-byte output limit includes enclosing quotes and shortening ellipsis. These lossy diagnostic aids have no required consumer glyph rendering; see [Event Stream Contract](../contracts/event-stream-contract.md#table-b-st_event).

No-value-change assertions retain the consecutive-observation model: the first active observation establishes a baseline, interruption invalidates continuity, and Reset clears history. Length validation also applies to baseline capture. Inputs are read only during the owning FB call and must remain stable for that call. The stored previous value is instance-owned; no external reference is retained for later observation.

Contains, StartsWith and EndsWith use internal typed Boolean comparison functions with read-only STRING/WSTRING references and direct code-unit indexing. No temporary substring, character array, raw pointer or 255-character standard-function limit is introduced. The assertion validates references and configured content lengths before calling its predicate, with Error checks preceding a held Failed result. Comparisons remain exact and case-sensitive. Prefix/suffix comparisons are linear in text length; a straightforward fragment search can require a product of text and fragment lengths, so larger capacity settings require application task-budget review. An empty Fragment, Prefix or Suffix is a programming error and produces Error during active evaluation, including after a held Failed result. Empty IN remains valid and does not match a nonempty pattern. A nonempty pattern longer than the text does not match.

### Boolean value-change observation

`AssertNoValueChange_Bool` compares consecutive active observations. The first active observation captures the baseline without producing Passed; subsequent equal observations permit Passed, and a change produces Failed with previous/actual diagnostics. With `ObserveFirstCycle = TRUE`, capture occurs on the first enabled call and comparison starts on the second. With `FALSE`, the first enabled call is excluded, capture occurs on the second and comparison starts on the third. An observation interruption invalidates the baseline but retains the held result. Reset clears observation history and suppresses processing. `EvaluationActive` reports whether the current/last call has both an active observation and a preceding active baseline; capturing the first baseline must not retrospectively mark that call as evaluated.

The scalar `AssertNoValueChange_<Type>` variants for bit strings, integers, REAL and LREAL follow the same observation and reset model with native typed previous-value storage. Comparisons are exact; no tolerance is applied. REAL/LREAL reject NaN and either infinity with Error on any active observation, including baseline capture and after a held Failed result. Non-finite values are not compared or converted to numeric diagnostic text. Observation validation may therefore report Error while EvaluationActive is FALSE on the first observation.

### Duration assertions

TIME and LTIME assertions use native unsigned duration values, respectively in milliseconds and nanoseconds. Equality, strict ordering and inclusive timespan comparisons operate directly on these types without subtraction or signed narrowing. StartTime > EndTime reports Error during active evaluation before a held Failed result can suppress processing; equal bounds remain valid. No-value-change variants follow the consecutive-observation and reset model above with native typed history. Diagnostics use the corresponding native time-to-string conversion.

### Calendar and time-of-day assertions

DATE assertions compare calendar days, ignoring any hidden time-of-day remainder in the native seconds representation without modifying inputs. This applies to equality, ordering, timespan boundaries and no-value-change observations. TOD and DT assertions compare native values at millisecond and second resolution respectively, without timezone conversion. Timespans include both endpoints; reversed bounds report Error before a held Failed result. TOD timespans do not wrap across midnight. These variants retain the established observation and reset model.

LDT and LTOD assertions use their native nanosecond-resolution types on Build 4026. They retain the same strict ordering, inclusive timespan, reversed-bound Error and consecutive-observation rules. LTOD timespans do not wrap across midnight. No DTL type or DTL assertion family is introduced.

TOD and LTOD assertions reject values at or beyond 24 hours with Error, without modulo normalization. Validate every relevant operand before comparison or temporal text conversion and before the held Failed guard. No-value-change assertions validate IN during active observation, including initial baseline capture; invalid values are not stored as a baseline.

### Typed array equality

Array equality compares the entire Expected array with IN starting at StartIndex, irrespective of their lower bounds. Inputs are read-only references and must remain stable during the call. An invalid selected range reports Error before access or a held Failed guard. Bounds arithmetic uses widened integers to avoid overflow before validation. REAL/LREAL validate all Expected elements as finite before comparing; non-finite expectations report Error even after Failed. Non-finite actual elements produce Failed, not Error. Elements outside the selected IN range are not examined. Comparison stops at the first mismatch after expectation validation and reports both indices and values. No full-array copy is performed.

DWORD/LWORD array equality and no-value-change assertions apply Mask to both compared elements; the default mask includes all bits. REAL/LREAL variants apply a finite, non-negative absolute Tolerance (default zero), including the tolerance boundary. Invalid tolerance reports Error before snapshot writes or a held Failed guard. Finite comparisons reuse the overflow-safe typed tolerance helpers. Snapshot comparisons accept equal same-sign infinities without subtraction; unequal non-finite values produce Failed. Snapshot storage retains the original unmasked values.

### Typed array contains-value

Contains-value assertions search Length elements of IN starting at StartIndex through typed read-only array references. Length is USINT; zero or an out-of-bounds selection reports Error before access, including after a held Failed result. DWORD/LWORD apply Mask to both operands. REAL/LREAL accept either infinity in Expected and IN: identical infinities match, other infinite combinations do not. NaN in Expected reports Error; NaN in IN is a non-match and search continues. Tolerance must be finite and non-negative; finite operands use the overflow-safe typed tolerance helpers with an inclusive boundary. A match passes; exhausting the selected range fails. No array copying or evaluation outside the selected range is performed.

### Typed array contains-array

Contains-array assertions search for the complete contiguous Expected pattern within the selected IN range. Independent lower bounds are supported. Zero Length, an empty pattern, a pattern longer than Length, or invalid selected bounds reports Error before access. Each candidate ends within the selected range; overlapping candidates remain eligible. REAL/LREAL validate the complete Expected pattern for NaN before searching, including after a held Failed result. The per-element Mask, Tolerance, infinity and actual-NaN rules are the same as for contains-value. A mismatching element rejects only its candidate, not later candidates. Both arrays are read-only and stable during the call; no array copy is made. The bounded nested search may require (Length - ExpectedLength + 1) * ExpectedLength comparisons.

### Typed array all-equal

All-equal assertions require every element in the selected IN range to match the scalar Expected value. Range validation and per-element Mask, Tolerance, infinity and NaN semantics follow contains-value. Consequently an actual NaN is a mismatch and produces Failed, while NaN Expected produces Error. Comparison stops at the first mismatch and reports its index and actual value. Passing requires the complete nonempty range to match. The scan is linear, read-only and performs no array copy.

### BYTE/WORD array operations

BYTE/WORD arrays follow the same typed equality, contains-value, contains-array, all-equal and snapshot rules as DWORD/LWORD, with native-width Mask and hexadecimal diagnostics. Snapshot data remains unmasked and is captured once until Reset. Starts-with-array and ends-with-array compare the complete Expected pattern at the beginning or end of the selected IN range. Independent array lower bounds are supported. Zero Length, an empty pattern, a pattern longer than Length, or invalid selected bounds reports Error before access or a held Failed guard. Prefix/suffix comparison stops at the first mismatch; it neither searches other positions nor copies array data.

### Character arrays

Character array assertions use BYTE elements for Char and WORD elements for WChar, matching the scalar character API. Equality and content checks compare exact character codes without masks, case folding or encoding conversion. Zero-valued elements are ordinary array data, not string terminators. Value diagnostics use the existing character-formatting functions with default STRING locals, retaining the code representation for non-printable values. Array bounds, selected-range handling and once-until-Reset snapshot ownership follow the corresponding typed array operations. STRING/WSTRING bridge behavior is defined separately.

### Array-to-text bridges

BYTE/Char arrays compare directly with STRING code units; WORD/WChar arrays compare with WSTRING code units. Expected is a read-only reference using the existing assertion text capacity parameters and length validators. Text ends at its first null code unit; array null codes remain ordinary data and do not terminate the selected range. No conversion, case folding, masking or temporary array-to-text copy is performed. Empty Expected, zero Length, invalid references, over-capacity text or invalid array bounds report Error. A nonempty Expected longer than the selected range reports Failed. Equality additionally requires equal lengths; prefix/suffix compare at the selected boundaries, and containment searches contiguous candidates. The redundant Byte-to-Char-array and Word-to-WChar-array equality entries map to AssertEqualArray_Char and AssertEqualArray_WChar because their underlying PLC representations already coincide.

### Length until token assertions

BYTE and WORD length-until-token assertions measure the number of elements before the first matching token in the selected range, excluding the token. Every relation requires a match; absence produces Failed, including NotEqual. Value tokens use a native-width mask on both operands. Array tokens match exact contiguous code units without a mask. Zero search length, invalid references or bounds, and empty or oversized array tokens produce Error before a held Failed result can suppress processing. Expected is a USINT comparison operand, not a range configuration limit. Typed read-only array references avoid copies; widened index arithmetic precedes validated narrowing. These direct checks use AssertionBase evaluation and reset behavior.

### Token counting and search helpers

Internal BYTE/WORD FindValueToken, FindArrayToken, CountValueTokens and CountArrayTokens functions provide stateless, typed read-only array operations. Callers validate stable references and complete search/token ranges before invoking them. Find functions return success and an absolute Index; Index is meaningful only on success. LengthUntil assertions derive the preceding length from that index. Count functions scan directly rather than repeatedly invoking Find.

Value-token and array-token assertions expose a public read-only TokenCount : UINT property backed by FTokenCount. Active evaluation counts all masked value matches or exact non-overlapping array matches; zero matches is a valid count. A held Failed freezes the measured count, while Reset or a detected configuration error clears it. Disabled calls retain it. Range bounds are inclusive; reversed bounds produce Error before the held Failed guard. Array-token counting uses exact, non-overlapping matches: advance by the token length after a match and by one element otherwise. No additional overlapping mode is provided.

### Array snapshot lifetime

Array no-value-change assertions capture their selected IN segment once into caller-owned Memory on the first active observation after Reset. The snapshot remains unchanged until Reset, including across Disable/Re-Enable before any comparison. Disable pauses processing, not snapshot ownership. Reset invalidates the snapshot without clearing external memory; the next active observation overwrites the selected snapshot elements. Capture does not report Passed. Subsequent consecutive active observations compare against the original snapshot without copying it again. ObserveFirstCycle controls observation as in AssertionBase.

IN is read-only; Memory is a separate writable array of the same element type with at least Length elements, used from its own lower bound. Length retains the reference API's USINT range; zero is invalid. The caller keeps array bindings, StartIndex, Length and Memory contents stable from capture until Reset and must not overlap snapshot storage with IN. Range validation precedes access, using widened arithmetic. No raw pointer, dynamic allocation or cyclic full-array copy is required.

REAL/LREAL snapshots reject NaN before writing any snapshot element; either infinity is permitted. Later NaN values produce Failed against the valid snapshot. NaN classification precedes numeric comparison to avoid floating-point exceptions; it does not turn an actual-value mismatch into Error. Snapshot validation runs only before initial capture, not cyclically after capture.

### Boolean edge assertions

`AssertionEdgeCountBase` extends `AssertionWithEvaluationBase` and owns signal history, a UINT edge count, overflow handling and Reset. Concrete count assertions supply the edge direction and count predicate. The read-only `EdgeCount` property exposes the count without permitting mutation. Observation captures a baseline on the first active call and detects edges from the second consecutive active observation. Thus ObserveFirstCycle TRUE starts detection on the second enabled call; FALSE starts it on the third. Observation interruptions invalidate the baseline but retain the count and result. Reset clears all history and the count.

Count observation precedes explicit evaluation, so a detected edge in the current call is included. Evaluate remains independent of Enable and observation history. An increment beyond UINT maximum produces Error during observation, even without Evaluate, and leaves the count saturated until Reset. Reversed count bounds produce Error during active evaluation before the held Failed guard; equal bounds are valid. Strict ordering uses Maximum/Minimum consistently with other comparison assertions.

`AssertNoRisingEdge` and `AssertNoFallingEdge` extend AssertionBase directly without a counter. They use the same baseline and first-observation rules and evaluate on each subsequent active observation. Their EvaluationActive reports the current/last call's actual comparison gate. Observation history is maintained independently of held results.

### Floating-point comparisons

REAL and LREAL retain distinct typed comparison variants. Exact equality and inequality do not use an implicit epsilon. Ordering inputs use Maximum for less-than/less-equal and Minimum for greater-than/greater-equal. Range membership includes both bounds; equal bounds are valid, while Minimum > Maximum reports Error during active evaluation.

Relevant non-finite operands (NaN or either infinity) report Error before comparisons, arithmetic or numeric text conversion, including when Failed is already held. Use Tc2_Utilities.RealIsFinite and LrealIsFinite on their native typed references. Do not change runtime floating-point exception settings. Dedicated classification assertions are separate from these comparisons.

Tolerance variants use absolute tolerance: zero is valid and a negative or non-finite tolerance reports Error. EqualTolerance accepts deviation <= tolerance; NotEqualTolerance accepts deviation > tolerance. Typed helpers must reject mathematical deviations beyond the largest finite type value as outside tolerance before subtraction, without scaling operands or tolerance. Otherwise retain the ordinary typed rounded difference. Held Error remains unchanged until Reset.

### Configuration failures and family processing

Configuration checks belong to the concrete Assertion or a justified family base, inside the processing path reached through `Assert()`. Input-dependent checks remain separate from the central identity initialization; no additional universal validation hook or Assertion initialization state machine is required. Any remaining family-specific writable configuration properties supply their settings without producing findings; ResourceName and ObserveFirstCycle are configured exclusively through Initialize.

Validate the prerequisites before the operation that needs them:

- Direct checks validate configured indices and ranges when their evaluation is active, before shifts, indexing, or comparisons.
- Observation checks validate the source and reference-storage ranges before an initial snapshot as well as before later evaluation.
- Explicit-evaluation families preserve their separate observation and evaluation gates. An `Evaluate` request is not blocked merely because `Enable = FALSE`; its operation-specific prerequisites must still hold.

A detected configuration error calls `Error(Message)` and skips the operation whose prerequisites failed. It is not a failed comparison. Correcting inputs does not clear the held Error; an explicit reset is required. Reset processing has priority and produces no configuration-error event in that call. Disabled direct checks do not publish configuration errors merely because they were called.

Input-dependent checks are not moved exclusively into Test Case initialization: indices, ranges, and bindings supplied at the FB call may differ later. Validation arithmetic and memory access must remain safe before any read, write, shift, or copy. Type-specific failure classification and observation-history updates stay with the responsible family; a common early exit must not silently alter them.

The common base owns only shared reset, result, and finding behavior. The explicit-evaluation base adds the agreed control surface; additional family bases are introduced with their concrete family implementations when shared domain behavior justifies them. This infrastructure design does not preselect a complete inheritance tree for the catalog.

### Result view and aggregation

`I_ResultProvider` exposes read-only `Name : STRING(GVL_Constants.NameLength)` and `Result : E_Result`. Assertions and the owner interfaces I_TestCase, I_TestSuite and I_RunControl provide this common identity/result view. Test Case initialization receives Parent : I_TestSuite; Suite initialization receives Parent : I_RunControl; Run Control has no Parent. A Parent establishes its identity before initializing its children. I_TestCase and I_TestSuite inherit their shared orchestration members through I_Orchestratable. They and I_RunControl each expose RequestStart(), RequestAbort(), RequestReset() and a read-only Status property of their respective ST_TestCaseStatus, ST_TestSuiteStatus or ST_RunControlStatus type. Request methods record requests; regular owner FB processing performs the lifecycle work. I_Assertion extends I_ResultProvider without adding members and distinguishes Assertions from other result providers. Initialize and Reset remain instance APIs, not interface members. I_TestCase additionally exposes read-only IsInitialized for final parent setup validation. Suite initialization registers its local Test Case collection as described below; no I_TestElement is introduced. ResultAggregator consumes Result only.

`ResultAggregator` is a local method-driven utility FB with no cyclic body requirement:

- `Reset()` explicitly starts an empty collection by clearing result and counters.
- There is no Enable gate. Add methods always contribute; retaining a collection means making no Reset/Add calls.
- `AddProvider(...)` reads the supplied provider result immediately and retains no provider reference. A null interface is a programming error and contributes `E_Result.Error`.
- `AddResult(...)` combines a directly supplied `E_Result`.
- Read-only `Result`, `TotalCount`, `PassedCount`, `FailedCount`, and `ErrorCount` expose the collection. Each accepted contribution counts once, including `NotEvaluated` in the total. Counting continues after Error.

The combination priority for defined results is `Error > Abort > Failed > Passed > NotEvaluated`. An empty collection remains `NotEvaluated`. All combination rules belong to this aggregator; no parallel Combine-result FCs are introduced. It produces no events. Counters use UINT; collections must remain within its representable contribution count.

The owner selects contributors and rebuilds the aggregate in its aggregation phase. Final lifecycle interpretation, including unexpected subordinate Abort handling and successful completion with a neutral evaluation result, remains owner-owned. TestCaseBase owns the aggregator and passes its I_ResultAggregator interface by VAR_INPUT to AggregateResults, without a return value. This contribution-only view exposes AddProvider and AddResult; Reset and result/counter access remain on the concrete owner-held ResultAggregator. The base always supplies its own valid instance; the hook does not perform a redundant null-interface check. The concrete hook adds each owned Assertion exactly once; it does not reset the aggregator. The base explicitly calls Reset() before starting a fresh collection on every initialized call, including Reset and Completed. Reset status counters therefore reflect current Assertion observations; UpdateResult retains responsibility for the owner result and does not turn those observations into a new Reset result. Collection only reads existing results and does not execute Assertions. Idle collection establishes the total before Ready is published. UpdateResult applies lifecycle rules; UpdateStatus projects counters. Finalization events use the final owner result and status. Direct AddResult contributions count individually, not as expanded child collections.

## Event Storage Capacity

`EventBufferLength : UINT := 256` is a consumer-overridable compile-time library parameter defining the physical number of event storage positions. The supported physical length is `3..32767`; one ring position remains unused, so usable capacity is `EventBufferLength - 1` (255 events with the default length). The Event Buffer validates the supplied storage against these FIFO limits. This is an implementation/configuration limit, not a transport limit. External consumers use the published `FifoControl.BufferLength` as defined by the Event Stream contract.

## Events And Diagnostics

The PLC framework emits structured UnitTest events. The Event Stream is the normative source for automated result and completeness evaluation.

Run Control owns processing of event-buffer Reset and release requests. Consumers never modify FIFO state, buffer status, or event entries directly. An event-buffer Reset starts a new event-buffer epoch and is independent of Run Control lifecycle Reset.

The Event Buffer encapsulates FIFO handling, initialization, reservation accounting, event insertion, contiguous release, and status access. Event entries reside in dedicated global communication storage, never in the Event Buffer instance. Lifecycle owners use semantic operations rather than accessing that storage or FIFO indices directly. External publication uses the contract-defined data projections, not function-block instances or interfaces.

### Event Buffer composition and execution

The initial framework uses one PLC program, one task, one Run Control, and one Event Buffer. The library declares a default global Event Buffer instance and a global `I_EventPublisher` interface variable bound to that instance. There is no global getter. The interface variable and concrete instance are PLC composition objects, not ADS or OPC UA communication data.

The PLC application may bind another supported implementation to the global publisher before the first consumer access. Consumers retain an instance-local binding as specified below; subsequent global changes do not retarget already bound consumers. The PLC program calls `RunControlBase.Initialize(Name, EventBuffer : I_EventBuffer)` and supplies the administrative view of the same service used by that Run Control's publisher. Run Control retains this view; it is not supplied again at the cyclic FB call. The base accepts and validates the supplied root name before calling Configure and before any Suite initialization. Timing configuration and Suite composition belong to the concrete Configure implementation, not additional external Initialize parameters. No separate ConfigureIdentity method is required.

### Instance-local publisher binding

Publishing components expose a public read-only EventPublisher property backed by protected FEventPublisher : I_EventPublisher. The property is not added to owner interfaces. When the field is zero, the getter copies GVL_EventBuffer.Publisher into it and returns the field. A successfully established binding remains unchanged across regular calls and lifecycle Reset. No declaration-time dependency on the global interface value, global_init_slot, public setter, additional Initialize parameter or automatic parent-to-child propagation is introduced.

All publication, initialization diagnostics, reservation/release and loss-count access use this property; an operation may obtain the interface once into a local variable. A missing publisher is a programming/setup error, not a recoverable framework condition. No additional per-access null guards, fallback service or recursive diagnostics are introduced; an invalid interface call may stop the PLC. Service readiness and capacity checks retain their separate responsibilities. Owner and Orchestrator bindings are not changed on the fly; the explicit Assertion binding method below is the scoped exception.

AssertionBase provides public BindPublisher(Publisher : I_EventPublisher) on the concrete instance API, not I_Assertion. It immediately selects a nonzero publisher; zero is ignored and leaves the existing binding unchanged. No initialization or lifecycle guard applies, including when explicitly replacing a previous binding. Binding neither resets the Assertion nor publishes or replays findings. Initialize and Reset retain the selected publisher. Without explicit binding, the existing lazy default remains in effect. The caller owns the publisher lifetime and the consequences of routing subsequent events to another service; no automatic propagation or reservation transfer is introduced.

Assertion selftests use the concrete production types and BindPublisher directly. An Assertion test subject is derived only where additional controlled behavior or observations are needed, not merely for publisher assignment. Other framework subjects may still use thin adapters that assign their protected field before first use. This does not construct a second automatically bound framework hierarchy. The test arrangement owns any child/helper bindings and coherent publisher/administrative views needed by its subject; it does not copy production algorithms.

Suite and Run Control bases use protected FOrchestrator : I_Orchestrator for helper initialization, cyclic execution and every helper observation. The normal composition supplies the framework Orchestrator without requiring an application-supplied instance. A controlled owner test adapter may bind an alternative before Initialize; initialization must preserve that selection. Lifecycle Reset retains it, and on-the-fly replacement is not supported. I_Orchestrator covers the operations and observations consumed by the bases, not publisher configuration. A thin adapter derived from Orchestrator can assign its own protected FEventPublisher before first use and is then supplied through I_Orchestrator. Thus the real helper algorithm remains under test without accessing protected members of a composed object from its owner. A fully isolated owner test may instead supply an interface double. No additional publisher parameter is added to Orchestrator.Initialize, and no automatic publisher propagation is introduced.

The bases bind their owned FDefaultOrchestrator only while FOrchestrator is unassigned. I_Orchestrator.Execute(Task) invokes the existing concrete FB body once; CurrentTask exposes its assigned task for owner mapping. This interface bridge neither duplicates scheduling logic nor introduces a second processing path.

The Event Buffer performs its work immediately through methods and exposes observations through read-only properties. It needs no cyclic FB call: it has no autonomous lifecycle processing or pending request mailbox. This is a deliberate exception to the normal owner FB processing model.

### Publisher interface

`I_EventPublisher` provides the following methods. Parameters are `VAR_INPUT` unless explicitly identified as `VAR_IN_OUT`.

| Method | Parameters | Return |
| --- | --- | --- |
| `PublishEvent` | `Event : ST_Event` | `INT` |
| `ReserveSpace` | `EntryCount : UINT`, `HeadroomEntryCount : UINT`, `OwnerReservedEntryCount : UINT` (`VAR_IN_OUT`) | `BOOL` |
| `FreeReservedSpace` | `EntryCount : UINT`, `OwnerReservedEntryCount : UINT` (`VAR_IN_OUT`) | `BOOL` |

`PublishEvent` receives its event by value and assigns SequenceId and Timestamp to its own copy. It does not modify the caller's event. Positive results indicate successful FIFO insertion, zero indicates no transfer, and negative results identify errors. The public, qualified-only `E_EventPublishResult` alias refers to the internal `E_FifoResult`; the method return remains `INT`. No second result enum is introduced.

Convenience functions construct and return standardized `ST_Event` values without publishing them. They preserve contextual event construction and readable call sites, including direct use of a factory result as the `PublishEvent` input. Callers may also construct an event themselves. Lifecycle owners retain responsibility for publication timing and one-shot behavior. Pure rendering helpers remain stateless functions.

Event Buffer reservation methods take a change amount, not a replacement total. Each Test Suite and Test Case retains its own contribution, while the Event Buffer owns the aggregate. ReserveSpace checks that physically free entries cover the increased aggregate plus headroom and updates both counts together. FreeReservedSpace decreases both counts without requiring free buffer capacity; it releases reservations, not events. A request exceeding the owner's contribution is rejected. Rejection leaves both counts unchanged. Owner reservation methods calculate the difference from the required total and delegate to these operations; Orchestrators do not retain a second ledger.

Replacing an existing budget must preserve its accounting if an increase fails. An owner must not release its current reservation first and then assume that a subsequent reservation will succeed.

The publisher exposes GET-only properties:

- `Capacity : UINT`: usable positions in the actual bound buffer, independent of occupancy and reservations; zero when invalid.

| Property | Type | Meaning |
| --- | --- | --- |
| `IsValid` | `BOOL` | FIFO configuration and indices are valid. |
| `FreeEntryCount` | `UINT` | Physically free entries, without subtracting reservations; zero when the FIFO is invalid. |
| `ReservedEntryCount` | `UINT` | Aggregate producer reservation. |
| `LostEventCount` | `UINT` | Lost-event count, including availability to Aggregation event producers. |

Observations do not replace the authoritative capacity check in `ReserveSpace` or insertion result from `PublishEvent`. No additional `IsFull` property is required. Publisher properties are PLC-side observations, not external communication symbols.

### Event construction functions

Event constructors return a fully initialized `ST_Event` by value. All inputs are `VAR_INPUT`; constructors neither publish nor access a publisher, clock, or mutable global state. SequenceId and Timestamp remain zero until publication. Classification and state inputs use the corresponding framework enums. Text inputs use the existing `GVL_Constants` capacities and the ASCII-based representation, including the reserved diagnostic preview replacement byte, defined in the Event Stream contract.

| Constructor | Inputs |
| --- | --- |
| `CreateStartEvent`, `CreateResetEvent`, `CreateAbortEvent` | `OwnerScope`, `Name`, `ResourceName`, `State` |
| `CreateStateTransitionEvent` | `OwnerScope`, `Name`, `ResourceName`, `StateOld`, `StateNew` |
| `CreateTestSuiteOrchestratorStateTransitionEvent`, `CreateTestCaseOrchestratorStateTransitionEvent` | `Name`, `StateOld`, `StateNew` |
| `CreateFrameworkEvent` | `Name`, `State`, `Severity`, `Message` |
| `CreateResultEvent` | `OwnerScope`, `Name`, `ResourceName`, `State`, `Result`, `Message` |
| `CreateAssertionFailedEvent`, `CreateAssertionErrorEvent` | `Name`, `ResourceName`, `State`, `Message` |
| `CreateRunAggregationEvent` | `Name`, `Status : ST_RunControlStatus`, `LostEventCount : UINT` |
| `CreateTestSuiteAggregationEvent` | `Name`, `Status : ST_TestSuiteStatus` |
| `CreateTestCaseAggregationEvent` | `Name`, `Status : ST_TestCaseStatus` |

Trigger constructors set Trigger, Info, NotEvaluated, and the respective text `Start trigger.`, `Reset trigger.`, or `Abort trigger.`. Transition constructors set StateTransition, Info, NotEvaluated, and the new state; their message describes the numeric old and new states. Orchestrator transitions select their dedicated scope, append `.Orchestrator` to the supplied parent name, and assign the result into the fixed-capacity event name. They use an empty resource name and introduce no additional parent-name validation. Full Owner identity validation remains the owner's responsibility under the contracts.

Framework diagnostics set Framework scope and event type, an empty resource name, and NotEvaluated. Result and Aggregation severity maps Passed/Failed to Info, NotEvaluated/Abort to Warning, and Error or unsupported values to Error. Assertion findings select Assertion scope and the respective Failed/Error result.

Aggregation constructors use the supplied status snapshot rather than a control DUT or owner instance. They format the contract-defined counters and unsigned millisecond runtime; the Run caller supplies LostEventCount. Constructors do not perform aggregation, change lifecycle state, or decide publication order. Fixed-capacity text assignment does not add a constructor-level error protocol.

### Administrative interface

`I_EventBuffer` provides the following methods:

| Method | Parameters | Return |
| --- | --- | --- |
| `Initialize` | `Buffer : ARRAY[*] OF ST_Event`, `FifoControl : ST_FifoStatus`, `Status : ST_EventBufferStatus` (all `VAR_IN_OUT`) | `BOOL` |
| `Reset` | None | None |
| `ProcessDeleteRequest` | `SequenceId : UDINT` (`VAR_IN_OUT`) | None |

`Initialize` binds the external event array and the two external status fields for the service lifetime and initializes the internal, `ST_Event`-specific FIFO. Array bounds determine physical length and are validated against the one-based contract storage and FIFO limits; no `ANY` descriptor or externally supplied element size is involved. The FIFO owns its default event constant for clearing removed entries; the Event Buffer separately clears the complete event array on Reset. Successful initialization establishes empty storage, clears sequence, deletion, loss and reservation state, and publishes the initial status. Failed initialization publishes invalid configuration to the supplied status fields and leaves the service unusable. `TRUE` means fully initialized. All supplied storage must remain alive and dedicated to that service. Initialization occurs before the first framework processing; an invalidated binding after Online Change requires configuration reactivation or a PLC Cold Reset and renewed initialization.

`Reset` requires successful initialization, retains the storage binding, and immediately clears event storage, FIFO state, sequence/deletion status, loss count, and reservations. Run Control handles the external Reset command, gives it priority over Delete, attempts registered Suite/Test Case reservation release hierarchically before invoking `Reset`, and clears both external Buffer command fields. Failed release return values, active execution, and an undrained buffer do not gate this destructive operation. The Event Buffer does not receive the external command DUT and does not traverse the owner hierarchy itself.

`ProcessDeleteRequest` captures the supplied sequence watermark and releases entries from the FIFO output side through that watermark. It updates `DeletedSequenceId` from actually removed events and rejects or stops invalid requests according to the Event Stream contract. It clears the supplied field only if it still equals the captured value, preserving a distinguishably newer request. Run Control passes the actual external `BufferCmd.DeleteSequenceId` field, not a copied request. Progress is available through status rather than a method return.

The administrative view exposes GET-only `Status : ST_EventBufferStatus` and `FifoStatus : ST_FifoStatus`. Both return value snapshots, not writable references to internal data. The Event Buffer itself projects these snapshots into its bound external status fields after event insertion, deletion and reset, including failed operations that affect diagnostics. There is no separate cyclic publication call and no publication side effect in observation getters. Run Control processes Buffer commands before its regular owner/child processing; on Buffer Reset it owns hierarchical reservation release before delegating the destructive reset. It neither publishes Event Stream status nor receives another EventStream parameter. Neither status snapshot includes reservation accounting. The PLC application binds the same selected service to `GVL_UnitTest.EventStream.Buffer`, `.FifoControl` and `.Status`; isolated subjects may bind test-local fields and a differently sized one-based array. There is no second event array or cyclic full-buffer copy.

Full Owner lifecycle, Result, and Aggregation evidence uses the Run Control, Test Suite, and Test Case owner scopes. Generic Orchestrators may emit technical diagnostics with dedicated Orchestrator scopes; these are not additional lifecycle-completion evidence.

Assertion failed/error events are Assertion-owned findings. They contribute to Test Case aggregation but are not final Test Case Result events.

### Optional PLC diagnostic consumer

`EventBufferDiagConsumer` is an explicitly instantiated, disabled-by-default utility,
not part of normal Run Control execution or evaluated test runs. The application
calls it after Run Control on the same task, including during initial Reset and
after completion. It borrows the actual event array through `VAR_IN_OUT CONSTANT`
and removes observed FIFO-head sequences through `I_EventBuffer.ProcessDeleteRequest`.
It neither resets the Event Buffer nor changes reservation accounting.

`MaxEventsPerCall` (default 32) bounds one batch; `ConsumeInterval` (default T#10ms)
controls batch spacing. Activation processes immediately; zero interval permits
every call and missed intervals do not accumulate catch-up work. Read-only
`DiscardedEventCount` counts confirmed removals, `LastBatchEventCount` retains the
last attempted batch count, and `PeakPendingEventCount` samples valid occupancy on
every enabled call before consumption. `ResetDiagnostics` clears these statistics
and `HasError` without changing buffer contents or scheduling. Disabling or buffer
epoch changes do not clear the diagnostic observation period.

Diagnostic consumption requires exclusive consumer ownership and deliberately
discards the evidence required by the PC runner. It does not establish a test
result. Application wiring and the transition back to evaluated operation are
described in the [Run Control authoring guide](authoring/run-control.md#optional-plc-only-diagnostic-consumption).

## PLC/PC Publication

The library owns `GVL_UnitTest` with the public `RunControl` and `EventStream` areas. Public structures are data-oriented DUTs. Internal object-oriented implementation details are excluded from the symbol surface.

`GVL_UnitTest.RunControl` uses `ST_RunControlCommunication` to group `ContractInfo : ST_ContractInfo` and `ControlData : ST_RunControl`. The GVL requires qualified access and is always linked so its communication storage is present independently of PLC-side references. Declaration initialization supplies the direct-access contract version from `GVL_Constants` and `FrameworkVersion` through `GetFrameworkVersion()` from generated library metadata, without a separately maintained version string or a cyclic formatting call. The generated version data is constant and initialized before the communication variable. ControlData uses its existing DUT defaults; all communication storage is non-remanent.

`GVL_UnitTest.EventStream` uses `ST_EventStream` for `ContractInfo`, `FifoControl`, `Status` and the parameter-sized event array. It is the sole default event storage; `GVL_EventBuffer` retains only the unpublished service instance and publisher interface. Event Stream contract metadata is initialized separately from Direct Access metadata. The EventStream variable and all its descendants are read-only in OPC UA; reusable DUTs do not enable publication on their own.

OPC UA publication is enabled on the global RunControl variable, not on the reusable DUT definitions. The container permits access to writable command descendants; ContractInfo, Name and Status retain their nested read-only attributes. Cmd and BufferCmd retain their declared command access. This does not publish a Run Control FB instance or change ADS access semantics.

The initial Run Control command transport uses the established Boolean command fields. The PLC qualifies externally written lifecycle commands across two consecutive calls to protect against writes during a PLC cycle, processes an accepted command, and resets its field in the acceptance/processing cycle. No request-ID handshake is added.

Only lifecycle command and buffer request fields are externally writable by contract. Producer data is read-only. OPC UA access attributes mirror this ownership; direct ADS access remains governed by the contract and the consuming access profile.

ADS RPC command methods are not part of the initial contract. They may be evaluated later as a separately versioned TwinCAT-native command transport.

## Initialization And Remanence

The root PLC application performs explicit one-shot framework initialization when the current task's FirstCycle flag is TRUE, before regular `RunControl()` processing in that cycle. Reinitialization requires configuration reactivation or a PLC Cold Reset (XAE: Reset kalt), followed by PLC execution. A normal PLC Stop/Start does not trigger this initialization path. Here, PLC-start initialization refers to this coordinated rebuild, not every transition from PLC Stop to Run. Setup changes that invalidate initialization after Online Change require configuration reactivation or a PLC Cold Reset and renewed hierarchical initialization; hot reinitialization and recovery of corrupted child bindings are not supported operating scenarios. Existing defensive checks remain, but they do not guarantee continued child processing after a collection becomes invalid. The Event Buffer is initialized and the publisher bound before Run Control initialization, so configuration diagnostics can be published. The program supplies the root name and Event Buffer interface to Run Control initialization. The base validates the root identity before Configure; the concrete Run Control establishes timing configuration and Suite composition; Run Control initializes its statically bound Suites, and each Suite initializes its statically bound Test Cases. The PC runner neither invokes nor configures this initialization. `FB_Init` is not the primary configuration path.

This is a complete startup rebuild, not cleanup of the previous run. Event Buffer initialization establishes empty storage and zero global reservations; each Suite and Test Case Initialize clears its own reservation contribution without calling FreeReservedEvents. The owner bases reset transient requests, result/status, timing and helper progress, and their Configure paths rebuild registration. They must not rely on declaration initialization having cleared reused instance memory. Arrays, registered children and service bindings remain fixed during subsequent regular execution. The PLC application first initializes the command adapter with the selected ControlData to discard pending external commands and sampling history before the new Event Buffer epoch. Its cyclic external-command sampling rules remain unchanged.

Successful hierarchy initialization leaves owner lifecycles in Uninitialized; IsInitialized reports valid setup independently of lifecycle readiness. At the successful end of RunControlBase.Initialize, the root queues exactly one RequestReset. Its next regular FB call processes that request. Suite and Test Case bases, including framework doubles, do not autonomously leave Uninitialized: each parent reserves Reset capacity before requesting its child Reset. Failed initialization queues no startup Reset. Successful Reset establishes Idle and readiness; failed or timed-out Reset ends through Completing in Completed with Error, without Aborting or AbortingFromError. Neither startup initialization nor the initial lifecycle Reset requires a PC-issued command. A later Reset remains explicit; there is no cyclic startup retry, new initialization API or on-the-fly rebinding mechanism.

Framework initialization explicitly considers declaration values, `FB_Init`, `TcInitOnReset`, normal storage, `RETAIN`, `PERSISTENT`, reset variants, download, restart, and Online Change.

Commands, lifecycle state, status, event storage, sequence and release state, reservation accounting, Orchestrator state, and Assertion state are execution-transient and must not survive unintentionally. Any remanent framework datum requires an explicit semantic reason and contract review.

TwinCAT runtime initialization, UnitTest lifecycle Reset, and event-buffer Reset are separate mechanisms.

### Base lifecycle observations

TestSuiteBase exposes public read-only BOOL IsAborted, IsAborting, IsComplete, IsResetting and IsTestSuiteActive. IsAborted matches TestCaseBase: Completed with Result = Abort, or the legacy Aborted state. IsAborting includes Aborting and AbortingFromError; IsComplete means Completed regardless of result. IsResetting means Reset. IsTestSuiteActive includes Starting, Running, Completing and both abort states, excluding Uninitialized, Reset, Idle and Completed.

Both bases expose public read-only IsIdle and HasError. IsIdle describes State = Idle, not start readiness. HasError computes the existing owner error condition from live owner fields, including configuration errors; status projection uses that same property. The Test Case retains its existing invalid-state error classification. These getters introduce no new state, do not process requests or publish events, and support online monitoring. IsIdle remains a concrete base API; HasError is also part of I_Orchestratable. Neither adds a field to the status DUTs.

## Status Views

Status views make current PLC execution observable in TwinCAT XAE and available to higher PLC levels, HMI, or diagnostic clients. The completed owner result remains stable until Reset. Status counters continue to reflect child observations; they are independent of the previously emitted aggregation event.

Status is not a replacement for the Event Stream when a completed UnitTest run is evaluated. The PLC/PC contract defines the exact publication and access semantics.

## Documentation Boundaries

- `docs/framework-architecture.md`: stable high-level architecture.
- `contracts/`: normative framework and PLC/PC behavior.
- [Authoring manual](authoring/framework-model.md): practical framework-user guidance.
