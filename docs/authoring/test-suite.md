# Test Suite Authoring

A Test Suite groups related Test Cases and determines which may execute together. It does not implement their stimuli or checks. Derive from `Tc3UnitTest.TestSuiteBase`, declare the concrete Test Cases, configure their registration and call them cyclically. The base supplies the Suite lifecycle and its Orchestrator.

Read the [framework model](framework-model.md) for the hierarchy and [Test Case authoring](test-case.md) for implementing a child. This chapter explains how to turn those children into a working Suite.

## Decide what belongs together

Group scenarios by a meaningful resource, behavior or application responsibility, not merely by Assertion type. Prefer Test Cases that each establish their own starting conditions and can report their own result. Serial execution guarantees order, but does not make the previous Test Case's successful result a prerequisite for the next one.

Before selecting a mode, identify which scenarios write the same resource, share mutable test data or depend on exclusive external equipment. Two Test Cases can safely overlap only when their stimuli, Preparations, Reset and Abort behavior are compatible. Different FB instances do not necessarily mean different resources.

| Your implementation owns | The base and its Orchestrator own |
| --- | --- |
| Concrete Test Case instances and resource bindings | Suite lifecycle and request processing |
| A local array of Test Case interfaces | Generic lookup through the Suite's collection view |
| Child initialization and registration | Validation and finalization of that configuration |
| Mode and, when needed, slot assignment | Capacity-admitted child Start and Reset requests |
| One concrete call per child per initialized cycle | Scheduling, readiness observation and error escalation |
| Additional application-specific configuration checks | Suite timing, aggregation, status and events |

Do not add a second Sequencer or instantiate another Orchestrator for normal Suite authoring. In particular, do not send independent child Start/Reset requests alongside the supplied scheduling logic.

## Required implementation

The concrete FB body calls `SUPER^();` once. Implement these three methods:

| Method | Visibility | Responsibility |
| --- | --- | --- |
| `Configure(Builder)` | Protected | Initialize the owned Test Cases, bind the local interface array and register the children in the selected mode. |
| `GetTestCase(Index)` | Public | Return a registered interface at its actual array index, or zero outside the populated range. No child execution or other side effects. |
| `ProcessTestCases()` | Protected | Call each concrete registered child exactly once, including when it is not currently selected for execution. |

`CheckInitialization()` is an optional protected extension point. Its existing implementation checks the collection, initialized children and required positive timeout values. An override must retain `SUPER^.CheckInitialization()` and add only checks for additional setup owned by that concrete Suite. Do not repeat ordinary child or builder validation in every Suite.

The Suite does not need a custom `AggregateResults`, Reset implementation or finalization-event method. Those responsibilities are already implemented by the base.

## Complete composition example

This example combines `Test_AcceptsPositiveValue` and `Test_ClassifiesPositiveBoundary` from the [Test Case chapter](test-case.md). They are application FBs from that chapter, not library types. Both use the chapter's `IsPositive` function and have no shared mutable resource. Serial mode makes their ordering explicit; later sections show how to change that configuration.

Create the following Suite FB and its three method overrides. Code blocks containing a declaration and executable statements show the declaration followed by the implementation; place them in the corresponding XAE editors.

### FB declaration and body

```iecst
{region 'Documentation'}
(*!
<summary>Compose the two independent positive-value Test Cases in one Suite.</summary>
*)
{endregion}
FUNCTION_BLOCK TestSuite_PositiveValues EXTENDS Tc3UnitTest.TestSuiteBase
VAR
    FPositive : Test_AcceptsPositiveValue;
    FBoundary : Test_ClassifiesPositiveBoundary;
    FTestCases : ARRAY[1..TestCaseCapacity] OF Tc3UnitTest.I_TestCase;
END_VAR
VAR CONSTANT
    TestCaseCapacity : UINT := 4;
END_VAR

SUPER^();
```

The array has room for four references, but only two children will be registered. It does not contain additional Test Case instances, configurations or copied status records.

### Configure

```iecst
{region 'Documentation'}
(*!
<summary>Initialize and register the concrete Test Cases using the supplied temporary builder.</summary>
*)
{endregion}
METHOD PROTECTED Configure
VAR_IN_OUT
    Builder : Tc3UnitTest.TestSuiteConfigurationBuilder; //! Borrowed owner configuration builder used only during this Configure call.
END_VAR
VAR
    TestConfig : Tc3UnitTest.ST_TestCaseConfig;
END_VAR

TestConfig.Timeout := T#5s;
TestConfig.PreparationTimeout := T#2s;
TestConfig.ResetTimeout := T#1s;
TestConfig.AbortTimeout := T#1s;

Builder.Initialize(Mode := Tc3UnitTest.E_OrchestrationMode.Serial,
    TestCases := FTestCases);

FPositive.Initialize(Parent := THIS^,
    TestName := 'PositiveAccepted',
    Config := TestConfig);
FBoundary.Initialize(Parent := THIS^,
    TestName := 'PositiveBoundary',
    Config := TestConfig);

Builder.Register(TestCase := FPositive);
Builder.Register(TestCase := FBoundary);
```

Both `Initialize` calls return a Boolean success result. The example leaves the subsequent verification to the Suite base: every intended child is registered, and the base rejects a child whose initialization failed. Each child also diagnoses its own initialization failure. Do not silently omit a failed child and thereby turn an incomplete collection into a valid Suite.

`Register` also returns a Boolean. A rejected registration latches a builder configuration error, so the base's finalization rejects the configuration even if the caller does not branch on that return value. For application-specific early exits, take care not to leave an apparently valid but incomplete collection; use an explicit configuration check when completeness depends on additional conditions.

The base passes a temporary builder to `Configure` and calls its `Finalize()` after the hook returns. Do not store the builder, finalize it prematurely or test `Builder.IsValid` as if it already represented a finalized configuration inside `Configure`. A second explicit registration/finalization handoff to the base is not needed.

### GetTestCase

```iecst
{region 'Documentation'}
(*!
<summary>Return a registered Test Case by its original array index without executing it.</summary>
*)
{endregion}
METHOD PUBLIC GetTestCase : Tc3UnitTest.I_TestCase //! Registered Test Case at Index; zero outside the occupied range.
VAR_INPUT
    Index : DINT; //! Original occupied child-array index; indices outside the populated range return zero.
END_VAR

GetTestCase := 0;
IF (ChildCount = 0) OR (Index < ChildArrayLowerBound)
    OR (DINT_TO_LINT(Index) >= DINT_TO_LINT(ChildArrayLowerBound) + UINT_TO_LINT(ChildCount)) THEN
    RETURN;
END_IF;

GetTestCase := FTestCases[Index];
```

The lookup returns entries from exactly the array passed to the builder. It uses actual array indices, not positions rebased to one. The wider arithmetic avoids overflowing the upper occupied-range calculation.

Do not add an `IsInitialized` guard here: the base already uses the collection while validating initialization, before it sets its final initialized flag. At that point the registered range is available. The base supplies the corresponding generic `GetChild` view itself.

### ProcessTestCases

```iecst
{region 'Documentation'}
(*!
<summary>Call every owned concrete Test Case once, including during cleanup and Completed.</summary>
*)
{endregion}
METHOD PROTECTED ProcessTestCases

FPositive();
FBoundary();
```

Registration makes a child addressable to the Orchestrator; it does not execute the child's FB body. This hook provides that execution. Call all registered children, not just the current slot or the child whose status says Running. Their own lifecycle determines whether they perform Reset, Preparation, test work, Abort or only administrative/status work.

Do not gate these calls by Suite state. In particular, calls continue during Completing and Completed so children can finish exceptional cleanup and keep their status current. This does not start another test. Do not also call these same instances from the program or another owner.

These three methods and the FB body complete the example Suite. Run Control still has to initialize, register and cyclically call it. [Run Control and PLC integration](run-control.md) completes this example hierarchy.

## Owner initialization and identity

The concrete Run Control owns the Suite instance. During its own `Configure`, it initializes the Suite before completing the root configuration. For example, in that parent context:

```iecst
VAR
    SuiteConfig : Tc3UnitTest.ST_TestSuiteConfig;
END_VAR

SuiteConfig.Timeout := T#15s;
SuiteConfig.ResetTimeout := T#2s;
SuiteConfig.AbortTimeout := T#2s;

FPositiveValues.Initialize(Parent := THIS^,
    SuiteName := 'PositiveValues',
    ResourceName := 'IntegerLogic',
    Config := SuiteConfig);
```

Here `FPositiveValues` is the parent's `TestSuite_PositiveValues` instance and `THIS^` is the Run Control, not a PLC program. The [Run Control chapter](run-control.md) covers its registration and program integration.

Pass only the Suite's local name segment. `Initialize` builds the full identity from `Parent.Name` and `SuiteName`; each child then adds its own local segment. With a root named `LogicTests`, the example child names are `LogicTests.PositiveValues.PositiveAccepted` and `LogicTests.PositiveValues.PositiveBoundary`.

Use nonempty ASCII name segments containing letters, digits, underscores or hyphens, without embedded dots. Keep sibling names unique and the complete hierarchy within the configured `NameLength` of 80 characters. Leave room for child and Assertion names; a valid Suite name alone does not guarantee that its descendants fit. `ResourceName` is separate diagnostic context, up to 32 characters, and is optional. It does not replace identity or make a shared resource safe for parallel execution.

Successful initialization builds and checks the complete setup but leaves the Suite in `Uninitialized` until its parent requests a capacity-admitted Reset. `IsInitialized` therefore does not mean `IsReady`. A failed initialization remains Uninitialized with a configuration error and does not enter normal child processing.

Reinitialization requires configuration reactivation or a PLC Cold Reset (XAE: Reset kalt), followed by PLC execution; normal PLC Stop/Start is insufficient. In the resulting first-cycle initialization sequence, the program starts the root initialization chain again; the parent calls the Suite's `Initialize`, which synchronously invokes `Configure` and rebuilds the child setup. Initialize any additional transient fields introduced by your derivation there as well. Declaration initializers alone are not a replacement for this restart path.

Lifecycle Reset is different: it prepares a new run without rebuilding the registration. Keep the child collection, capacity, bindings and slot assignment fixed after initialization. A setup-invalidating change requires configuration reactivation or a PLC Cold Reset and renewed initialization; do not rewrite the interface array during cyclic processing or use initialization as an in-run reconfiguration command.

## Local array, capacity and populated range

Declare the array and concrete children as persistent instance fields of the Suite, not method-local temporary variables. Here "instance fields" means storage lasting as long as the FB instance, not TwinCAT `PERSISTENT` or `RETAIN` storage.

The builder clears the supplied array during `Initialize`, fills a contiguous prefix and reports the populated count. Unused capacity remains empty. There must be at least one registered child; a normal Suite is not an empty placeholder.

| Property on the Suite | Meaning |
| --- | --- |
| `ChildArrayLowerBound` | The actual lower bound of the supplied array. |
| `ChildArrayUpperBound` | The actual upper bound of the supplied array, including unused capacity. |
| `ChildCount` | The number of registered children, not the array capacity. |

For an array `[10..13]` with two registered children, lookup indices 10 and 11 are populated. Indices 12 and 13 are unused capacity and must return zero. The last occupied index is `ChildArrayLowerBound + ChildCount - 1`; it is not necessarily `ChildArrayUpperBound`.

Do not cache a second copy of these interfaces, counts or child statuses for scheduling. The Suite owns the array and supplies lookup; the Orchestrator accesses it through that collection. No additional global array or maximum-count library parameter is required.

Configuration fails for insufficient capacity, a null child, duplicate registration of the same instance, an invalid mode/registration combination or invalid slot layout. Name uniqueness remains an authoring responsibility; registering distinct FB instances does not make duplicated names acceptable.

## Choosing and configuring orchestration

All three modes use the same concrete child instances, array and cyclic-call hook. Select the mode from ordering and resource constraints, not from current Event Buffer occupancy. Buffer admission is handled in every mode.

| Mode | Registration | Execution guarantee | Typical reason to choose it |
| --- | --- | --- | --- |
| `Serial` | `Register(TestCase := ...)` | One executing Test Case at a time, in registration order. | Scenarios need exclusive execution access to the same resource. |
| `Parallel` | `Register(TestCase := ...)` | Children may overlap; capacity determines admission. | Independent resources or read-only checks with compatible timing. |
| `ParallelSlots` | `RegisterWithSlot(TestCase := ..., ExecutionSlot := ...)` | Children in one slot may overlap; all must complete before the next slot starts. | Grouped concurrency separated by resource or ordering barriers. |

Parallel means overlapping multi-cycle scenarios in the same PLC task, not simultaneous threads. The Orchestrator starts at most one new child per call. Even within one slot, do not assume a common start cycle. When capacity is temporarily limited, an admissible later child in the same slot can start before an earlier child that is still waiting.

### Parallel

For the independent logic examples above, change the builder initialization to:

```iecst
Builder.Initialize(Mode := Tc3UnitTest.E_OrchestrationMode.Parallel,
    TestCases := FTestCases);
```

Keep both ordinary `Register` calls. The builder assigns all children to slot one. Do not pass a slot through `RegisterWithSlot` in this mode.

### ParallelSlots

Use `RegisterWithSlot` for every child in this mode. For the same two example instances, after initializing them:

```iecst
Builder.Initialize(Mode := Tc3UnitTest.E_OrchestrationMode.ParallelSlots,
    TestCases := FTestCases);

Builder.RegisterWithSlot(TestCase := FBoundary,
    ExecutionSlot := 2);
Builder.RegisterWithSlot(TestCase := FPositive,
    ExecutionSlot := 1);
```

Although registered second, `FPositive` executes in the first slot. The builder inserts entries in ascending slot order, retaining registration order within the same slot. `GetTestCase` must therefore read the registered array, not reconstruct a different order with a CASE over concrete instances. Concrete cyclic calls remain unchanged.

Slots start at one and must be consecutive in the finalized configuration. Registering slot two before slot one is allowed, but leaving slot one absent is not. Slot zero is invalid. Calling ordinary `Register` in ParallelSlots is a configuration error, just as calling `RegisterWithSlot` in Serial or Parallel is an error.

A resource-oriented grouping could instead be:

| Test Case | Controlled resource | Slot |
| --- | --- | --- |
| OpenValveA | Valve A | 1 |
| OpenValveB | Valve B | 1 |
| CloseValveA | Valve A | 2 |

The two valves can be tested concurrently in slot one if their surrounding equipment is also independent. CloseValveA waits for both children of slot one. It must still establish its own required starting conditions rather than assume that OpenValveA passed. These names illustrate already-defined scenarios, not additional framework-provided FBs.

The Test Case's writable `ExecutionSlot` is assigned by registration. Do not change it cyclically. The Suite's own `ExecutionSlot` belongs to its parent Run Control's scheduling and is unrelated to the currently active slot among the Suite's children.

### Resource safety also includes Reset and Abort

Serial mode serializes test execution, not every child activity. Reset dispatch is capacity-admitted and may overlap across children: the Orchestrator can request another child's Reset on a later cycle while a previous Reset is still running. Reset does not use the execution-slot barriers.

Consequently, two serial Test Cases targeting the same resource must still have compatible Reset actions. For example, two cleanups that both command the same safe position may be compatible, whereas one enabling a drive while another disables it is not. Make that ownership explicit when implementing the Test Cases; changing the Suite mode alone cannot repair conflicting cleanup.

Likewise, concurrent Abort cleanup must be compatible, and resource sharing with another Suite must be considered at Run Control level. Only the responsible application author can decide whether a resource or test-data dependency permits overlap.

## What happens during a cycle

The Suite base processes requests and its lifecycle, executes its Orchestrator, calls `ProcessTestCases`, then aggregates child results and refreshes status and events. The concrete child calls consume requests that were issued earlier in that cycle. The Orchestrator observes their updated status on its next call; do not add extra calls to force immediate confirmation.

This division explains two common mistakes:

- A registered child that is never cyclically called cannot process Start or Reset. Registration and a readable interface are not proof of execution.
- A child called only while Running cannot consume the request that would move it out of Idle, and may not finish cleanup. Keep the hook unconditional and let child lifecycle logic control work.

Readiness is already summarized by the Orchestrator. Suite `IsReady` additionally requires valid initialization, Idle and absence of a held error. Do not maintain another user-defined readiness aggregate in parallel. If a Test Case needs an application-specific start permission, implement that in the child's readiness hook as described in its chapter.

## Lifecycle, capacity and failure consequences

### Reset and becoming ready

The parent requests Reset after reserving the Suite's own event budget. The Suite's Orchestrator separately reserves the necessary budget before requesting Reset from each child. It can skip an already Idle and ready child and waits when capacity is temporarily unavailable.

Successful Reset ends in Idle with `Result = NotEvaluated`; it is preparation for another run, not a test result. Children must explicitly finish their reset work and become ready. A child reset error does not mean the remaining children should be abandoned immediately: the orchestration continues attempting their reset within the available time.

A failed or timed-out Reset ends through Completing in Completed with Error, not through the execution Abort path. That is a stable failure state, not a usable Idle state. Inspect the diagnostics and fix the cleanup before expecting another successful run.

### Execution and waiting for capacity

Start admission requires the Suite to be ready. The Orchestrator reserves each child's execution budget before submitting its Start request. Normal application code neither reserves those entries nor maintains a separate reservation counter.

Temporary capacity shortage delays admission without manufacturing a Failed test result. If a child's required budget cannot fit at all, it is an error rather than an endless capacity wait. A child missing its cyclic call also fails start confirmation; repeatedly issuing Start is not the remedy.

Suite execution timeout includes scheduling and capacity waiting. Size it for the whole composition: serial execution can require the sum of child durations, and slotted execution can require the sum of slot durations. Do not simply copy the largest individual Test Case timeout. Ensure the event consumer drains the buffer when the complete run produces more events than it can retain.

A child's Failed result is an ordinary test outcome and does not by itself prevent the other registered tests from executing. A framework/child Error follows the execution-error cleanup path. Abort requests stop further execution starts and let active children perform their controlled abort work; an Error remains higher priority than Abort.

### Timeouts and late cleanup

`ST_TestSuiteConfig` contains `Timeout`, `ResetTimeout` and `AbortTimeout`, all positive `TIME` values. Their defaults are respectively `T#10s`, `T#1s` and `T#1s`. Choose them from the expected work and required failure-detection interval rather than increasing them to hide missing child calls or completion signals.

The base owns Suite timeout monitoring; Test Cases still own their own phase timeouts. Do not duplicate those timers in `ProcessTestCases`. `HasTimeout`, `HasResetTimeout` and `HasAbortTimeout` retain detected timeout information until initialization or a new lifecycle Reset.

On a Reset timeout, the Suite stops issuing reset work and reaches its error completion path. Hierarchical reservation cleanup is framework-owned. Already active children continue receiving FB calls and can reach their own timeout or cleanup completion. The Suite's stable completion is not a guarantee that a physical resource has recovered or every child became ready. This is another reason not to stop child calls in Completed.

Lifecycle Reset and Event Buffer Reset are different operations. Do not erase the Event Buffer to prepare an ordinary new Suite run. Buffer commands belong at the Run Control communication boundary, not in this composition hook.

## Results, status and events

The base aggregates child results after their calls. In a normal run, the Suite's Passed/Failed result is finalized when execution finishes, rather than treating one early Passed child as a completed Suite. Error handling can escalate before normal completion.

Read `Status` for the typed `ST_TestSuiteStatus` snapshot and `Name` for identity. The snapshot contains execution status, `Runtime` and Test Case counts: Total, Inactive, Idle, Running, Completed, Passed, Failed and Error. Execution counts and result counts describe different views; they are not one partition to add together. Transitional states also need not appear in an Idle/Running/Completed subtotal.

The base emits the Suite result and aggregation events during Completing, followed by the transition to Completed on a subsequent cycle. Do not emit another set from the concrete FB or request completion yourself. The Suite has no additional configurable CompletionDelay; root completion behavior belongs to Run Control.

Completed does not disable status refresh or child calls. The Suite retains its completed result while observation remains current, including during exceptional late cleanup. A snapshot can therefore provide more recent diagnostic information than the earlier finalization events; it does not retroactively replace them.

The Orchestrator is a scheduling helper, not another reportable test level. Its technical errors produce Framework diagnostics with an Orchestrator-qualified name. Do not generate extra normal task/slot transition events to simulate another lifecycle owner.

For HMI or external communication, deliberately copy the public `Name` and status snapshot into an explicit data wrapper in the application's chosen communication storage if needed. Do not publish the Suite's instance internals or introduce writable child-control arrays.

## Diagnose a composition

| Observation | Check first |
| --- | --- |
| Suite remains uninitialized with a configuration error | Parent/name validity, builder mode and registration calls, nonempty capacity, slot layout, initialized children and positive timeouts. Read the initialization Framework event. |
| Initialization succeeded, but the Suite is not ready | Has the parent submitted Reset? Are all child calls present? Does each child's reset complete and readiness permit starting? |
| A child never starts | Its registration and lookup, readiness, slot barrier, event capacity and the concrete cyclic call. Do not send a competing Start to bypass scheduling. |
| Parallel children start on different cycles | This is normal. Check capacity and scheduling constraints, not an assumed simultaneous-start guarantee. |
| Suite times out while individual cases appear healthy | Total serial/slotted duration, capacity waiting, consumer progress and a child that never reaches completion. |
| Failed tests run to completion rather than stopping the Suite | Expected: Failed is a test outcome, not a framework Error or a fail-fast scheduling command. |
| Reset ends in Completed/Error instead of Idle | Reset diagnostics and `HasResetTimeout`; then inspect each child's cleanup and readiness. Completed here does not mean successful reset. |
| Counts or events do not match the intended children | Missing/duplicate registration, a lookup based on the wrong array/order, missing/double calls or duplicated hierarchical names. |
| Reset or Abort affects another test unexpectedly | Shared stimulus ownership, cleanup compatibility and concurrency across both Test Cases and Suites. |

The supplied `TestSuiteMock` is a childless simulation of the Suite-facing behavior for isolated tests of a parent. It is not a replacement for this composition and does not demonstrate real child orchestration.

## Review checklist

- The Suite groups defined scenarios and declares every concrete child and the interface array as instance fields.
- Its FB body calls `SUPER^()` once; Configure, GetTestCase and ProcessTestCases provide the three required responsibilities.
- Configure initializes every intended child and registers it exactly once, with a valid name and suitable configuration.
- The base owns finalization; no temporary builder reference or writable cyclic registration remains.
- Lookup uses the same registered array, actual indices and occupied range, including during initialization checks.
- Every registered child is called exactly once per initialized cycle, without parent-state or slot guards and without another owner calling it too.
- Mode and slots reflect resource and ordering constraints; shared Reset/Abort effects are safe even when cleanup overlaps.
- Slot values and the collection remain fixed after setup; setup changes require configuration reactivation or a PLC Cold Reset and renewed hierarchical initialization.
- Timeouts cover whole-Suite execution and cleanup, including admission waits; event consumption is provided by the surrounding application.
- Generic lifecycle, reservations, readiness, aggregation, status and events are left to the supplied framework rather than reimplemented.

Return to the [framework model](framework-model.md) for the overall hierarchy or the [Test Case chapter](test-case.md) to refine a child scenario.
