# Test Case Authoring

A Test Case implements one concrete scenario: establish a starting condition, apply stimuli, observe the response and finish with one result. It owns the tested behavior, not the Suite's scheduling.

Use `Tc3UnitTest.TestCaseBase` for the normal framework lifecycle. Your derived FB supplies configuration and scenario hooks. The base handles requests, lifecycle transitions, timing, result interpretation, status and standard events. The [framework model](framework-model.md) explains how this fits into the complete hierarchy.

## Define the scenario before the block

Describe the observable behavior before selecting an Assertion or writing a state sequence:

- Which resource or logic is being tested?
- Which starting condition is needed?
- Which stimulus does the test own?
- Which feedback and expected values establish correctness?
- When is the observation complete, even if the check fails?
- What must Reset and Abort do to leave the resource under defined control?

Completion is not the same as success. For example, an observation interval ends after its intended duration whether the response was correct or not. Waiting for an Assertion to become Passed can turn a legitimate Failed result into a timeout and hide the actual problem.

A Test Case should not depend on a previous test leaving the resource in a particular state. Use Preparation for a required starting condition and explicit Reset handling for scenario-local state.

## Reuse and resource interfaces

Prefer one stable behavior-oriented scenario over a configurable collection of unrelated tests.

A generally reusable Test Case depends on a small common interface. A resource-family Test Case uses a typed interface shared by related resources. A dedicated Test Case intentionally targets one block type or project resource. All three are useful; extracting dependencies is worthwhile only while the scenario and interface remain understandable.

Values that vary between uses belong on an explicit application interface: resource bindings, stimulus values, expected values, tolerances, limits or observation durations. Invariant facts of the scenario can remain local constants. Do not add mode switches that change the tested behavior, Assertion family and state sequence merely to share an FB type.

For resource bindings:

1. Prefer direct typed inputs and in-out parameters for small interfaces.
2. Reuse existing production resource DUTs or interfaces when they already express the required behavior.
3. Use an established resource accessor when the application already owns that abstraction.
4. Introduce a test-specific interface only when it makes a coherent dependency materially clearer.

Read-only feedback, limits and expected values are inputs. Writable resource data normally uses `VAR_IN_OUT` so the write ownership is visible at the call. An output can be appropriate when the test exclusively owns it and the surrounding application performs the final wiring.

Do not add test-only fields to production resource types. Generally reusable tests should not silently bind concrete global resources. A dedicated test may use a deliberate global binding, but that dependency and its write ownership must remain visible.

Each concurrent use needs its own Test Case, Preparation and Assertion instances and its own identity. Reusing an FB type is not sharing the state of one instance.

### Calling the tested logic internally or externally

An internal call lets the Test Case own the tested FB instance or call the tested function directly. This is straightforward when the scenario intentionally tests that concrete type.

An external call leaves the tested block in the PLC program or another application owner. The Test Case then controls stimulus and observes feedback through its interface. This can support the same behavior test against different implementations.

Call order matters in both arrangements. If the test writes a command after the tested block has run, the resulting feedback cannot appear until a later cycle. Disabling first-cycle observation can accommodate that known one-cycle relationship; it is not a substitute for the actual settling or observation time required by the test.

A continuously operating resource needs a call path independent of the test: TestCaseBase stops invoking scenario hooks once Completed is reached. Do not stop a production simulation merely because its test has ended unless that is the intended ownership model.

### Stimulus and feedback

The Test Case owns its resource actions during active work. Preparation owns the actions that establish the starting condition; test states own the actions that exercise the behavior. Make the handover explicit when a command must remain applied across those phases.

Disabled hooks are not permission to drive old stimuli. Reset and Abort may perform their explicitly owned resource actions, but idle and completed tests must not interfere with later tests.

Feedback represents the response of the tested logic or simulation. Do not write a feedback value locally just to satisfy an Assertion. The Suite's execution mode must prevent conflicting resource writes by concurrent Test Cases.

## Create the concrete FB

Use a behavior-oriented name such as `Test_AcceptsPositiveValue`. Derive from TestCaseBase and call `SUPER^();` once in the FB body.

Create overridden methods as separate XAE objects with their inherited signatures. In the examples, declarations end at the last `END_VAR`; the following statements belong in the implementation editor. For a method without variables, only the method signature and declaration comment belong in its declaration editor.

The snippets describe application code, not additional supplied library types. They are source-reviewed examples, not runtime-verified test fixtures.

### Required overrides

| Override | When it runs | What your implementation does |
| --- | --- | --- |
| `Configure()` | Inside Initialize, after identity validation | Set scenario state counts, initialize owned components and clear application-specific transient state |
| `ProcessReset()` | While the initialized owner is in Reset | Reset resources and Assertions; call CompleteReset when the owned reset work is finished |
| `ProcessAbort(Enable)` | Before Preparation/test processing, except Completed | Perform controlled cleanup when enabled; call CompleteAbort when finished |
| `ProcessPreparations(Enable)` | After Abort processing, except Completed | Call concrete Preparations, publish their combined observations and finish Preparation when its target is reached |
| `ProcessTests(Enable)` | After Preparation processing, except Completed | Apply stimuli, call the tested logic as appropriate and advance or complete test phases |
| `ProcessAssertions(Enable)` | After test processing, except Completed | Call Assertions with valid inputs, current State and scenario-specific activation |
| `AggregateResults(Aggregator)` | Every initialized call, including Reset and Completed | Add each owned Assertion once; read existing results only |

Implement all seven abstract hooks. An unused Preparation hook may have an empty implementation when the configured Preparation state count is zero. An empty Reset or Abort hook is not sufficient: those phases need explicit completion even when no resource cleanup is necessary.

Do not call the abstract base versions of these hooks. The FB body calls the base body; only an extension of an existing concrete method, such as CheckInitialization, includes its corresponding `SUPER^` method call.

### Useful optional overrides

`CheckInitialization() : BOOL` validates your configured children and scenario prerequisites after Configure. Include `SUPER^.CheckInitialization()`, then check your additions. A FALSE result leaves the owner uninitialized. Child initialization may already have emitted its own diagnostic; additional invalid setup needs its own meaningful initialization diagnostic.

The public GET-only `IsReady : BOOL` property can add resource-specific start prerequisites. Combine them with `SUPER^.IsReady`, rather than replacing initialization, Idle and error checks. The inherited implementation is sufficient when there are no additional prerequisites.

## Initialization is not Reset

The Suite calls the concrete instance's Initialize during its own Configure. For an instance named `FPositiveValue`, the call has this shape:

```iecst
FPositiveValue.Initialize(Parent := THIS^,
    TestName := 'PositiveValue',
    ResourceName := '',
    Config := TestConfig);
```

Here `THIS^` is the composing Suite, and `TestConfig` is an `ST_TestCaseConfig`. The Suite must inspect initialization success through the returned BOOL or the child's IsInitialized; the normal Suite base checks registered child initialization.

The base establishes identity, calls Configure and validates the resulting setup. Do not override Initialize, call Configure directly or write FInitialized yourself.

Configure runs on every explicit initialization. Clear your own old progress, pending resource commands and evaluation flags there; declaration defaults do not reliably clear reused instance memory after PLC Stop/Start. Initialize owned Assertions here, not on each cyclic call.

Successful initialization leaves the lifecycle Uninitialized until the parent reserves capacity and requests Reset. The initialized Test Case can receive disabled hook calls before that Reset. Those calls must already be passive; a later ProcessReset is not protection against an old stimulus being written first.

Reset preserves identity, configuration and composition. It restores scenario execution state for another run. Do not reinitialize Assertions or rebuild resource bindings on every Reset. Setup-changing Online Change requires configuration reactivation or a PLC Cold Reset followed by the normal hierarchical initialization; normal PLC Stop/Start is insufficient. Use that coordinated path, not hot reconstruction inside a running Test Case.

### State counts and timing configuration

Configure must explicitly set:

- `FPreparationStateCount := 0` for no Preparation, or the finite configured number of Preparation-state entries.
- `FTestStateCount` to at least one for the test phase.

These counts describe the longest finite execution path, not the number of helper instances. Multiple Preparations can serve one state. Finite repeated paths count repeated entries; an unbounded scenario cannot provide the event-capacity budget required by orchestration.

The base validates the counts against the available state ranges. The Assertion total comes from complete aggregation of all owned Assertions, not a separately maintained counter. Counts must be established by Idle/Ready and remain stable during execution.

`ST_TestCaseConfig` supplies four positive TIME values:

| Field | Default | Purpose |
| --- | --- | --- |
| Timeout | T#5s | Bound active Test Case execution |
| PreparationTimeout | T#2s | Bound the current Preparation state |
| ResetTimeout | T#1s | Bound scenario reset work |
| AbortTimeout | T#1s | Bound controlled abort cleanup |

Zero does not disable monitoring. The base measures elapsed time itself; no CycleTime input or parent-side duplicate timeout check is needed. A scenario's intended observation duration is separate from the timeout that prevents it hanging.

## Cyclic order and same-cycle transitions

Before the hooks, the base consumes requests, updates its timers and runs its Sequencer. Requests are processed with Reset before Abort before Start. The Sequencer uses observations retained from preceding processing.

In Reset, the base clears the combined Preparation snapshot and invokes ProcessReset. It then calls ProcessAbort, ProcessPreparations, ProcessTests and ProcessAssertions in that order, unless Completed has been reached. Each Enable is derived immediately before its hook call.

Finally, the base starts a fresh aggregation, invokes AggregateResults, updates the owner result/status and publishes finalization events when applicable.

Phase methods act immediately:

| Method | Effect |
| --- | --- |
| NextPreparationState | Advance one configured Preparation state |
| CompletePreparations | Finish the entire Preparation phase and enter the first Test state |
| NextTestState | Advance one configured Test state |
| CompleteTests | Finish the entire test phase and enter Completing |
| CompleteReset | Finish Reset in Idle, or finalize with Error if an error is held |
| CompleteAbort | Finish controlled abort processing and enter Completing |

A Next operation cannot advance beyond the configured interval. A Complete operation ends the phase; it is not a synonym for Next. The base checks allowed transitions.

Do not cache an Enable value and reuse it after a phase-changing call. In particular, calling CompleteTests from ProcessTests disables the subsequent ProcessAssertions call. Finish the last required evaluation first, then complete the phase on a subsequent call or through another deliberately ordered scenario path.

## A complete single-state example

This small application function is the tested logic:

```iecst
{region 'Documentation'}
(*!
<summary>Returns whether Value is strictly positive.</summary>
*)
{endregion}
FUNCTION IsPositive : BOOL //! TRUE when Value is greater than zero.
VAR_INPUT
    Value : DINT; //! Input value to classify as strictly positive.
END_VAR

IsPositive := Value > 0;
```

The Test Case checks that 1 is accepted. It has one Assertion, one Test state and no Preparation. In a real project, replace the tested logic and scenario data with the actual requirement; do not infer requirements from the implementation under test.

### Declaration and FB body

```iecst
{region 'Documentation'}
(*!
<summary>Checks that a positive input is accepted.</summary>
*)
{endregion}
FUNCTION_BLOCK Test_AcceptsPositiveValue EXTENDS Tc3UnitTest.TestCaseBase
VAR
    FPositive : Tc3UnitTest.AssertTrue;
    FActual : BOOL;
    FCheckPerformed : BOOL;
END_VAR

SUPER^();
```

### Configure and validate

```iecst
{region 'Documentation'}
(*!
<summary>Initializes the fixed scenario and its Assertion.</summary>
*)
{endregion}
METHOD PROTECTED Configure

FPreparationStateCount := 0;
FTestStateCount := 1;
FActual := FALSE;
FCheckPerformed := FALSE;
FPositive.Initialize(Parent := THIS^,
    AssertionName := 'PositiveAccepted');
```

```iecst
{region 'Documentation'}
(*!
<summary>Includes the owned Assertion in initialization validation.</summary>
*)
{endregion}
METHOD PROTECTED CheckInitialization : BOOL //! TRUE when inherited setup and the owned Assertions are initialized.

CheckInitialization := FALSE;
IF NOT SUPER^.CheckInitialization() THEN
    RETURN;
END_IF;
IF NOT FPositive.IsInitialized THEN
    RETURN;
END_IF;

CheckInitialization := TRUE;
```

The Assertion reports its own rejected initialization. The additional check prevents the Test Case becoming usable with an unusable child.

### Execute and observe

```iecst
{region 'Documentation'}
(*!
<summary>Computes the sample and completes after its Assertion has evaluated.</summary>
*)
{endregion}
METHOD PROTECTED ProcessTests
VAR_INPUT
    Enable : BOOL; //! TRUE permits active scenario work in this call.
END_VAR

IF NOT Enable THEN
    RETURN;
END_IF;
IF FCheckPerformed THEN
    CompleteTests();
    RETURN;
END_IF;

FActual := IsPositive(Value := 1);
```

```iecst
{region 'Documentation'}
(*!
<summary>Evaluates the computed sample and records that the check took place.</summary>
*)
{endregion}
METHOD PROTECTED ProcessAssertions
VAR_INPUT
    Enable : BOOL; //! Phase permission used to select this call's Assertion activation.
END_VAR

FPositive(Enable := Enable,
    State := State,
    IN := FActual);
IF Enable AND FPositive.EvaluationActive THEN
    FCheckPerformed := TRUE;
END_IF;
```

The first active call computes and checks the sample. The next active ProcessTests call completes the scenario. The flag means that this direct Boolean check was evaluated, not that it passed. Therefore an incorrect result still completes normally as Failed.

EvaluationActive is not a universal completion signal for all Assertion families. Sequence and edge-count checks need their own observation window and, where applicable, explicit Evaluate before the test phase ends. [Assertion authoring](assertions.md) explains family selection, concrete calls and their observation, evaluation and storage requirements.

### Aggregate without re-executing checks

```iecst
{region 'Documentation'}
(*!
<summary>Contributes the one owned Assertion.</summary>
*)
{endregion}
METHOD PROTECTED AggregateResults
VAR_INPUT
    Aggregator : Tc3UnitTest.I_ResultAggregator; //! Borrowed owner-held result sink; contribute each owned Assertion once without resetting or retaining the sink.
END_VAR

Aggregator.AddProvider(Provider := FPositive);
```

Add each owned Assertion exactly once, including inactive Assertions and calls in Completed. Do not reset the supplied aggregator, execute checks here, publish events or write status counters. The base owns those responsibilities.

A direct AddResult contribution also counts as one contribution. Do not combine several Assertion results into one value if you still expect the framework to report the original number of Assertions.

### Reset and Abort

```iecst
{region 'Documentation'}
(*!
<summary>Clears local progress and requests Assertion reset.</summary>
*)
{endregion}
METHOD PROTECTED ProcessReset

FActual := FALSE;
FCheckPerformed := FALSE;
FPositive.Reset();
CompleteReset();
```

The following ProcessAssertions call supplies the Assertion's inputs and consumes its pending reset with evaluation disabled. Calling Reset alone does not immediately clear an Assertion's Result.

```iecst
{region 'Documentation'}
(*!
<summary>Completes abort because this scenario owns no persistent resource action.</summary>
*)
{endregion}
METHOD PROTECTED ProcessAbort
VAR_INPUT
    Enable : BOOL; //! TRUE permits active Abort cleanup in this call.
END_VAR

IF Enable THEN
    CompleteAbort();
END_IF;
```

Create the unused Preparation override with an empty implementation:

```iecst
{region 'Documentation'}
(*!
<summary>No Preparation is required for the stateless function.</summary>
*)
{endregion}
METHOD PROTECTED ProcessPreparations
VAR_INPUT
    Enable : BOOL; //! TRUE permits Preparation work; disabled calls still supply current observations.
END_VAR
```

These methods complete the example FB. The Suite still has to initialize, register and cyclically call it; no direct Start or reservation bookkeeping is added to the Test Case. [Test Suite authoring](test-suite.md) shows the complete composition.

## Extending the example to two Test states

A second scenario checks the positive/zero boundary: 1 is accepted, then 0 is rejected. It uses the same application function but two independent Assertions so both outcomes remain visible.

Create `Test_ClassifiesPositiveBoundary` directly from TestCaseBase. Use the same ProcessAbort and empty ProcessPreparations implementations shown above. The following declarations and methods replace the corresponding single-state example parts; no inheritance from that example is needed.

```iecst
{region 'Documentation'}
(*!
<summary>Checks acceptance on the positive side and rejection at zero.</summary>
*)
{endregion}
FUNCTION_BLOCK Test_ClassifiesPositiveBoundary EXTENDS Tc3UnitTest.TestCaseBase
VAR
    FPositive : Tc3UnitTest.AssertTrue;
    FZero : Tc3UnitTest.AssertFalse;
    FActual : BOOL;
    FCheckPerformed : BOOL;
END_VAR
VAR CONSTANT
    StatePositive : Tc3UnitTest.E_State := Tc3UnitTest.E_State.Running;
    StateZero : Tc3UnitTest.E_State := Tc3UnitTest.E_State.Running + 1;
END_VAR

SUPER^();
```

The open E_State test interval permits these named scenario states. Keep them contiguous from Running; do not choose unrelated numeric values.

```iecst
{region 'Documentation'}
(*!
<summary>Initializes the two-state scenario and both independent findings.</summary>
*)
{endregion}
METHOD PROTECTED Configure

FPreparationStateCount := 0;
FTestStateCount := 2;
FActual := FALSE;
FCheckPerformed := FALSE;
FPositive.Initialize(Parent := THIS^,
    AssertionName := 'PositiveAccepted');
FZero.Initialize(Parent := THIS^,
    AssertionName := 'ZeroRejected');
```

```iecst
{region 'Documentation'}
(*!
<summary>Validates both configured Assertions.</summary>
*)
{endregion}
METHOD PROTECTED CheckInitialization : BOOL //! TRUE when inherited setup and the owned Assertions are initialized.

CheckInitialization := FALSE;
IF NOT SUPER^.CheckInitialization() THEN
    RETURN;
END_IF;
IF NOT FPositive.IsInitialized OR NOT FZero.IsInitialized THEN
    RETURN;
END_IF;

CheckInitialization := TRUE;
```

```iecst
{region 'Documentation'}
(*!
<summary>Advances after an evaluated sample, then computes the current phase sample.</summary>
*)
{endregion}
METHOD PROTECTED ProcessTests
VAR_INPUT
    Enable : BOOL; //! TRUE permits active scenario work in this call.
END_VAR

IF NOT Enable THEN
    RETURN;
END_IF;

IF FCheckPerformed THEN
    IF State = StateZero THEN
        CompleteTests();
        RETURN;
    END_IF;
    FCheckPerformed := FALSE;
    NextTestState();
END_IF;

CASE State OF
    StatePositive:
        FActual := IsPositive(Value := 1);
    StateZero:
        FActual := IsPositive(Value := 0);
ELSE
    Error(Message := 'Unexpected positive-boundary test phase.');
END_CASE;
```

On the transition call, NextTestState changes State immediately. The CASE therefore computes the zero sample before the zero Assertion is enabled later in that same cycle. Reusing the preceding positive sample would produce a false failure.

```iecst
{region 'Documentation'}
(*!
<summary>Calls both Assertions and enables only the current phase check.</summary>
*)
{endregion}
METHOD PROTECTED ProcessAssertions
VAR_INPUT
    Enable : BOOL; //! Phase permission used to select this call's Assertion activation.
END_VAR

FPositive(Enable := Enable AND (State = StatePositive),
    State := State,
    IN := FActual);
FZero(Enable := Enable AND (State = StateZero),
    State := State,
    IN := FActual);

IF Enable AND (FPositive.EvaluationActive OR FZero.EvaluationActive) THEN
    FCheckPerformed := TRUE;
END_IF;
```

Both FBs are still called when disabled. Their results remain independent, and both pending resets can be consumed without waiting for their active phase.

```iecst
{region 'Documentation'}
(*!
<summary>Contributes both findings, independent of the current phase.</summary>
*)
{endregion}
METHOD PROTECTED AggregateResults
VAR_INPUT
    Aggregator : Tc3UnitTest.I_ResultAggregator; //! Borrowed owner-held result sink; contribute each owned Assertion once without resetting or retaining the sink.
END_VAR

Aggregator.AddProvider(Provider := FPositive);
Aggregator.AddProvider(Provider := FZero);
```

```iecst
{region 'Documentation'}
(*!
<summary>Clears phase progress and requests both Assertion resets.</summary>
*)
{endregion}
METHOD PROTECTED ProcessReset

FActual := FALSE;
FCheckPerformed := FALSE;
FPositive.Reset();
FZero.Reset();
CompleteReset();
```

A Failed first check does not disappear when the second check passes. Both are collected, and the final Test Case result reflects the more severe outcome. The state counts and two Assertion contributions also give the framework the structural information needed before Start.

## Integrating Preparation in a resource test

The stateless examples need no Preparation. A resource scenario may instead need a starting condition such as a closed valve or an empty buffer. Reuse an existing suitable Preparation or author one for that target. [Preparation authoring](preparation.md) explains active target-state establishment, resource handover and combination of helpers.

The concrete Preparation belongs to the Test Case. Call it from ProcessPreparations even when Enable is false, so it can publish the current target/readiness observations without writing stimuli. Feed its observations to UpdatePreparationStatus.

For example, assume an application-owned `FPreparation` has cyclic inputs Enable and Feedback and an in-out Command, plus the standard Status property. In the containing Test Case, Command is writable resource data and Feedback is observed input. The integration hook is:

```iecst
{region 'Documentation'}
(*!
<summary>Publishes the resource Preparation observation to the owner lifecycle.</summary>
*)
{endregion}
METHOD PROTECTED ProcessPreparations
VAR_INPUT
    Enable : BOOL; //! TRUE permits Preparation work; disabled calls still supply current observations.
END_VAR
VAR
    Observed : Tc3UnitTest.ST_PreparationStatus;
END_VAR

FPreparation(Enable := Enable,
    Feedback := Feedback,
    Command := Command);
Observed := FPreparation.Status;
UpdatePreparationStatus(Ready := Observed.Ready,
    Running := Observed.Running,
    Completed := Observed.Completed,
    HasError := Observed.Error,
    State := Observed.State);

IF Enable AND Observed.Completed AND NOT Observed.Error THEN
    CompletePreparations();
END_IF;
```

This is an integration pattern for a resource-specific Preparation, not another library type or an addition required by the stateless examples. Configure sets FPreparationStateCount to one for this single Preparation phase and establishes any setup required by that particular helper.

Ready is startability, not target completion. Ready without Completed is a legitimate waiting condition, bounded by PreparationTimeout. Completed describes the current target condition, including while disabled; the base can skip active Preparation when it is already reached. Preparation errors prevent testing and enter the Test Case error path.

UpdatePreparationStatus stores the combined observation; it does not call Preparations or change the Test Case phase. Its State argument is optional and defaults to E_State.Uninitialized. Supply a meaningful Preparation-local state when it helps diagnose a stalled resource.

### Several helpers or Preparation states

Multiple helpers can serve one Preparation state. Their combined status must represent the actual dependency: two prerequisites needed together differ from two alternative ways to establish one target. Do not apply a blanket AND/OR rule to every field.

Multiple Preparation states use consecutive values from E_State.Preparing and an appropriate FPreparationStateCount. Advance an intermediate stage with NextPreparationState; use CompletePreparations only when the entire Preparation phase is finished.

The combined Completed signal also means the entire phase is finished. Do not expose an intermediate helper's Completed as the whole PreparationStatus.Completed: the Sequencer could then enter Running on the next call before later stages execute.

Keep combined error and target observations current, and stop the outgoing stage's resource actions before moving to the next. Completing Preparation can enable ProcessTests later in the same FB call, so its handover must be valid immediately.

## Readiness and application-specific validation

If a concrete Test Case has an input ResourceAvailable, it can add that prerequisite through a public read-only property:

```iecst
{region 'Documentation'}
(*!
<summary>Requires the base start permission and an available resource.</summary>
*)
{endregion}
PROPERTY PUBLIC IsReady : BOOL //! TRUE when inherited start prerequisites and ResourceAvailable both hold.
```

Its public Get implementation is:

```iecst
IsReady := SUPER^.IsReady AND ResourceAvailable;
```

This permits Start only when both conditions hold. It does not continuously supervise the resource once the test is active. Detect a loss that makes active execution impossible in the relevant processing hook, report Error and leave that processing branch.

Do not require the Preparation target to be reached merely to make the Test Case Ready when reaching that target is precisely the Preparation's job.

CheckInitialization is for configuration validity, not current execution completion. If your configuration is invalid, return FALSE and report the rejected setting once during initialization. The protected Error method is for lifecycle errors and ignores Uninitialized; it is not an initialization diagnostic API. An explicit initialization diagnostic can use the public EventPublisher view with CreateFrameworkEvent, while preserving the base's initialization checks and result.

Names are validated by the base. Pass only the local TestName to the Suite-owned Initialize call and initialize Assertions with Parent := THIS^ plus their local AssertionName. Choose unique sibling names and keep the complete hierarchy within 80 characters. ResourceName supplies optional diagnostic context; it is not the test identity.

## Reset, Abort and failure behavior

Reset clears scenario progress and restores owned resources for another run. If that work takes several cycles, return from ProcessReset and let the next cyclic call continue it. Call CompleteReset only when your work is complete. Issue a resource's one-shot reset command once if its interface requires that; do not retrigger it every cycle.

Assertion Reset requests belong on this path. Keep their normal FB calls present so the requests are consumed with valid checked-value bindings. Do not use disabling as a substitute for Reset.

Abort ends active execution under controlled resource ownership. Withdraw or complete scenario-owned actions in ProcessAbort when enabled. CompleteAbort means the cleanup is finished, not merely that an abort request was seen. A scenario with no resource cleanup can complete Abort immediately, as in the examples.

Handle higher-priority errors before successful completion. If a resource cannot continue meaningfully, call Error with specific context and stop that branch. The base owns controlled error termination and invokes Abort cleanup where applicable. Do not also assign the owner's result, force its state or publish duplicate failure events.

| Situation | Expected handling |
| --- | --- |
| A valid check finds incorrect behavior | Assertion Failed; finish the scenario at its intended endpoint |
| Invalid configuration | Failed initialization and a meaningful diagnostic; no normal execution |
| Preparation fails or times out | Base-owned Error termination; no active test phase |
| Execution cannot continue or its timeout expires | Error and controlled termination |
| Explicit Abort | Finish resource cleanup; final Abort unless Error takes precedence |
| Reset cannot finish within its deadline | Finalize with Error instead of claiming Idle/Ready; no execution-Abort detour |
| Abort cannot finish within its deadline | Finalize with Error rather than wait indefinitely |

Timeout finalization bounds the framework lifecycle; it does not physically repair a resource or guarantee successful cleanup. Investigate the diagnostic and fix the test/resource implementation. Do not keep issuing commands from an inactive hook to conceal the failure.

## Aggregation, status and events

The base interprets Assertion aggregation in the context of its lifecycle. A currently Passed Assertion does not require a currently Passed Test Case during active execution. CompleteTests does not itself assign Passed; finalization interprets the collected outcomes while preserving Error or Abort.

A check that was never evaluated can remain NotEvaluated. The author must ensure the intended checks actually run; successful phase completion alone is not proof of coverage. Add every owned Assertion during every aggregation call, not just those enabled in the current phase.

The base updates Status after scenario processing and aggregation. It supplies lifecycle state, readiness, result, runtime, state-count metadata and Assertion counters. Completed retains the final owner result but does not suspend current status projection or collection of existing Assertion results.

The bases emit the Test Case's request/transition events and final Result and Aggregation events. Assertions emit their own failed/error findings with the supplied owning State. The final Result and Aggregation precede the transition into Completed in a later cycle. Do not duplicate that publication in Configure, processing hooks or AggregateResults.

Use the existing observations for diagnosis:

- IsInitialized and Status.Execution.ConfigError for rejected setup.
- State, IsReady and resource feedback for start prerequisites or phase progression.
- PreparationStatus for the target condition and Preparation-local progress.
- Individual Assertion Result, ObservationActive and EvaluationActive for checks.
- HasTimeout, HasPreparationTimeout, HasResetTimeout and HasAbortTimeout for detected deadline failures.

Status snapshots are PLC-side observations. If an HMI needs them, publish a separate explicit wrapper with Name and Status; do not expose the Test Case instance. The external test log is based on events, not reconstructed from polled snapshots.

## Refactoring a dedicated Test Case for reuse

Preserve the scenario while extracting its bindings:

1. Record its stimuli, checked behavior, phase sequence, timing, Preparation, Reset/Abort effects and result meaning.
2. Identify concrete resources and instance-specific values.
3. Choose general, resource-family or deliberately dedicated scope.
4. Move varying dependencies to clear interfaces; retain invariant scenario facts locally.
5. Preserve internal versus external call ownership unless deliberately changing it, including any cycle delay.
6. Reuse existing Preparations and Assertions where their semantics fit.
7. Check the original binding and another independent instance, including failed checks, reset and abort.

Generalization must not silently change acceptance criteria, shorten observation or introduce mode-selected unrelated scenarios. Each independent use retains separate instances and identity.

## Test Case authoring checklist

- The scenario states its starting condition, stimulus, expected response and endpoint independently of success.
- Resource and tested-block call ownership are explicit; feedback is observed rather than manufactured.
- Configure sets both state counts, initializes owned Assertions and clears application-specific transient state.
- CheckInitialization includes the base checks and rejects unusable children or configuration.
- Every abstract hook is implemented and the FB body calls SUPER^ once.
- Disabled hooks are passive toward resources while still providing required component calls.
- Phase changes do not skip the final observation or feed stale values to the next phase.
- Reset requests are consumed through bound Assertion FB calls.
- Preparation Completed represents the whole target, not just readiness or an intermediate stage.
- Every owned Assertion contributes exactly once to aggregation regardless of the current phase.
- Reset and Abort complete explicitly, with timeouts and diagnostics for abnormal paths.
- Framework state, result, counters, reservation accounting and standard events are not reimplemented in the concrete Test Case.

Return to the [framework model](framework-model.md) for the complete hierarchy and the roles of the remaining authoring chapters.
