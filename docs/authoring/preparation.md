# Preparation Authoring

A Preparation establishes the resource condition required before a Test Case starts testing. It owns the actions needed to reach that condition and reports current readiness, progress, completion and errors. It does not evaluate the functional test result.

The Test Case owns the Preparation instance, its cyclic calls, activation and timeout supervision. Start with the [framework model](framework-model.md) for the hierarchy and [Test Case authoring](test-case.md) for the surrounding lifecycle.

## Define one target condition

Describe what must be true before testing begins: a simulated actuator is at its starting position, a resource is idle, or a buffer contains the required starting data. Then identify the actions needed to reach that target from each normal resource state.

The Preparation should not depend on a previous test leaving one particular state behind. Handle ordinary starting states deterministically; reserve Error for conditions from which this Preparation cannot continue meaningfully.

If the target is already reached, report Completed without unnecessary stimulus. If the target needs several PLC cycles, perform a bounded amount of work per call and report Running while actively working. Never wait synchronously for feedback.

Preparation must not:

- perform the functional Assertions of the scenario,
- own the tested block's cyclic call,
- calculate the Test Case result or publish its Result/Aggregation events,
- duplicate the Test Case's Preparation timeout,
- continue writing merely because it was enabled earlier.

Some prerequisites need observation only. Others require active commands. Both are Preparations when they express the required starting condition; neither should conceal the test behavior itself.

## Choose a useful reuse scope

A generally reusable Preparation depends on a small common interface. A resource-family Preparation uses a typed interface shared by related resources. A dedicated Preparation intentionally targets one resource or scenario where further abstraction adds little value.

Before creating another FB, check whether an existing Preparation already expresses the same target-condition behavior. Reuse its type with different bindings where possible. Each concurrent use still needs its own instance and any retained progress.

Expose values that vary by resource or scenario through the application interface: target values, limits, resource references and observations. Keep invariant details local. Avoid mode switches that combine unrelated target conditions in one block.

### Resource interface and write ownership

Use inputs for feedback and other read-only information. Writable commands or resource data normally use VAR_IN_OUT so the affected storage is explicit at the call. Use outputs only when their exclusive ownership and the surrounding signal wiring are deliberate.

Prefer direct typed parameters for a small interface, or existing production resource DUTs/interfaces for a coherent larger dependency. Do not add UnitTest-only fields to production types. A dedicated test interface is useful only when it makes the resource boundary clearer.

Generally reusable Preparations should not silently select a concrete global resource. A dedicated global binding is possible, but its dependency and resource ownership must be visible.

The Test Case or application still calls the tested block. Preparation writes the resource interface; it does not assume ownership of that block's execution. Call order determines when a changed command can appear in feedback.

## Implementing the framework view

There are two supported approaches:

| Approach | What you implement |
| --- | --- |
| Derive from PreparationBase | FB body calling SUPER^ once and the protected Prepare method; use the inherited status support |
| Implement I_Preparation directly | The concrete FB's Enable processing and a read-only Status property, preserving the same behavioral rules |

I_Preparation exposes only Status of type ST_PreparationStatus. It does not execute the FB, provide a generic Initialize operation or carry an Enable request. The owner still calls the concrete Preparation FB with its resource-specific parameters.

PreparationBase supplies:

- the cyclic Enable input and read-only Enabled observation,
- a call to protected abstract Prepare on every FB call, including disabled calls,
- a stored FStatus snapshot and read-only Status property,
- protected UpdateStatus(State, ExecutionStatus, Ready).

It does not supply a target-state algorithm, a generic state machine, a timeout, retained completion or an initialization/reset protocol for your resource. These are not hidden in the getter.

UpdateStatus stores State and ExecutionStatus, derives Running/Completed/Error from ExecutionStatus, and suppresses Ready while Running. It does not infer the execution status from State or validate your resource. Supply the correct interpretation of the observations.

Use State for the Preparation's diagnostic progress. It is not the owning Test Case's lifecycle state. Reading Status returns the last stored observation; it neither calls Prepare nor changes the resource.

## Enable and current status

Enable grants temporary permission to act. It is level-based, not a Start pulse.

When disabled, make no resource writes. Clear or return any internal progress to an executable base state without issuing cleanup commands. Continue observing the target and conditions that determine readiness or error.

| Current condition | ExecutionStatus | Important flags |
| --- | --- | --- |
| No work active, target not reached, able to accept work | Idle | Ready TRUE, Running FALSE, Completed FALSE |
| No work active, target not reached, unable to accept work | NotReady | Ready FALSE, Running FALSE, Completed FALSE |
| Actively establishing the target | Running | Ready FALSE, Running TRUE, Completed FALSE |
| Target currently reached | Completed | Running FALSE, Completed TRUE; Ready may also be TRUE |
| Cannot continue meaningfully | Error | Running FALSE, Error TRUE |

Unknown is the initial unobserved snapshot, not a substitute for reporting a known NotReady condition. Update the applicable fields on every call rather than retaining stale flags accidentally.

Ready and Completed answer different questions. Ready means that the current resource condition allows this Preparation to establish the required pre-test target; the status mapping suppresses it while preparation work is active. It does not mean the target is reached, and Enable FALSE does not force it to TRUE. Completed is not a latched success from a previous activation: if the resource leaves the target while disabled, the next observation must reflect that.

A disabled Preparation may therefore report Completed, Error or an idle readiness condition. Enable FALSE does not force every status flag to FALSE.

### Removing Enable is not a resource cancellation protocol

Stopping writes does not undo a command already accepted by the resource. If cancellation needs an explicit command, the Test Case must provide it through its Reset/Abort handling or another clearly owned application path. Do not hide a cancellation write in disabled Preparation processing.

After the target is reached, the active test phase owns any stimulus needed to maintain or change it. Preparation must not compete with that phase. The behavior test may deliberately move the resource into a condition where the disabled Preparation reports neither Ready nor Completed. This is not a reason to restart Preparation, block the test or change its result; the Test Case's Assertions evaluate the behavior under test. The Suite must prevent other Test Cases from commanding the same resource concurrently.

## An active multi-cycle example

Assume a simulated resource has:

- RequestedValue: a retained target requested by its owner,
- ActualValue: feedback that approaches the requested value over successive resource calls,
- ResourceError: an indication that the resource cannot continue.

The Preparation's target is reached when both the request and feedback equal TargetValue. Checking the request as well as the feedback avoids reporting a stable starting condition while an old request still points elsewhere.

The resource itself is called outside the Preparation. Its call and model are application responsibilities; this helper never changes ActualValue or simulates successful feedback.

### FB declaration and body

Create this application FB, not a library object with an assumed existing implementation:

```iecst
{region 'Documentation'}
(*!
<summary>Establishes the requested and observed value of a simulated resource.</summary>
*)
{endregion}
FUNCTION_BLOCK Prepare_ValueAtTarget EXTENDS Tc3UnitTest.PreparationBase
VAR_INPUT
    ActualValue : DINT; //! Current resource feedback; this Preparation does not write it.
    TargetValue : DINT; //! Requested pre-test target, held stable during the Preparation phase.
    ResourceError : BOOL; //! TRUE reports that the resource cannot continue meaningfully.
END_VAR
VAR_IN_OUT
    RequestedValue : DINT; //! Resource command written only while enabled; a write does not establish feedback.
END_VAR

SUPER^();
```

Provide the actual feedback, target and error indication at every call. The owner keeps the target stable for the intended Preparation phase. This example uses direct scalar bindings; no additional resource DUT is needed.

### Prepare method

```iecst
{region 'Documentation'}
(*!
<summary>Drives only while enabled and publishes the current target observation.</summary>
*)
{endregion}
METHOD PROTECTED Prepare
VAR
    ObservedState : Tc3UnitTest.E_State;
    ObservedExecutionStatus : Tc3UnitTest.E_ExecutionStatus;
END_VAR

// C0371: validate the FB binding before accessing it from this hook.
{warning disable C0371}
IF NOT __ISVALIDREF(RequestedValue) THEN
    UpdateStatus(State := Tc3UnitTest.E_State.Error,
        ExecutionStatus := Tc3UnitTest.E_ExecutionStatus.Error,
        Ready := FALSE);
    RETURN;
END_IF;

IF ResourceError THEN
    UpdateStatus(State := Tc3UnitTest.E_State.Error,
        ExecutionStatus := Tc3UnitTest.E_ExecutionStatus.Error,
        Ready := FALSE);
    RETURN;
END_IF;

IF Enabled AND (RequestedValue <> TargetValue) THEN
    RequestedValue := TargetValue;
END_IF;

IF (ActualValue = TargetValue) AND (RequestedValue = TargetValue) THEN
    ObservedState := Tc3UnitTest.E_State.Completed;
    ObservedExecutionStatus := Tc3UnitTest.E_ExecutionStatus.Completed;
ELSIF Enabled THEN
    ObservedState := Tc3UnitTest.E_State.Running;
    ObservedExecutionStatus := Tc3UnitTest.E_ExecutionStatus.Running;
ELSE
    ObservedState := Tc3UnitTest.E_State.Idle;
    ObservedExecutionStatus := Tc3UnitTest.E_ExecutionStatus.Idle;
END_IF;

{warning restore C0371}

UpdateStatus(State := ObservedState,
    ExecutionStatus := ObservedExecutionStatus,
    Ready := ObservedExecutionStatus <> Tc3UnitTest.E_ExecutionStatus.Running);
```

The hook validates the RequestedValue binding with __ISVALIDREF before reading or writing it. An invalid binding reports Error and not Ready. C0371 also occurs for the validity check itself in the checked compiler; the local warning disable/restore brackets only the checked access region, following the [Beckhoff method guidance](https://infosys.beckhoff.com/content/1031/tc3_plc_intro/2530307467.html). No additional reference variable is needed.

The error path precedes resource writes. On the normal path, only a changed requested value is written, and only while enabled. Completion always uses actual feedback as well as the request; it does not follow merely from issuing the command.

There is no internal sequence to retain here. Multi-cycle behavior comes from the resource taking time to reach its target; adding a state machine solely to remember that it is waiting would not improve this helper.

For a target of zero, an illustrative call sequence is:

| Enable | Feedback at call | Request before call | Action | Published condition |
| --- | --- | --- | --- | --- |
| FALSE | 5 | 5 | No write | Ready, not Completed |
| TRUE | 5 | 5 | Request zero | Running |
| TRUE | 3 | 0 | No new request value | Running |
| TRUE | 0 | 0 | No write | Completed and Ready |
| FALSE | 2 | 2 | No write | Ready, not Completed |

The exact number of calls depends on the resource and call order.

## Connect the Preparation to a Test Case

The resource Test Case declares one instance:

```iecst
VAR
    FPreparation : Prepare_ValueAtTarget;
END_VAR
```

Its own interface provides ActualValue and ResourceError as observations and RequestedValue as writable resource data. In Configure, set FPreparationStateCount to one and configure the intended test states and Assertions as described in [Test Case authoring](test-case.md). This reactive helper needs no separate initialization method.

Implement the Test Case hook:

```iecst
{region 'Documentation'}
(*!
<summary>Establishes and reports the zero starting condition.</summary>
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
    ActualValue := ActualValue,
    TargetValue := 0,
    ResourceError := ResourceError,
    RequestedValue := RequestedValue);
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

Call the helper even when Enable is FALSE. The base uses current Preparation observations while starting, and may skip active Preparation if the whole target is already reached. Ready without Completed is not a preparation error: the base waits under its Preparation timeout.

UpdatePreparationStatus belongs to TestCaseBase and receives individual observations. It stores the combined snapshot without executing a helper or completing a phase. Its optional State parameter defaults to E_State.Uninitialized; supplying the helper's actual diagnostic state makes timeout/error evidence more useful.

CompletePreparations ends the whole phase immediately. The subsequent ProcessTests hook can be enabled in the same FB call, so the resource handover must already be valid. Preparation does not need to stay enabled to preserve the Test Case's permission to test.

If the tested resource is called from ProcessTests, keep its required cyclic call outside that hook's active-test guard so it can react during Preparation too. If it must continue after the Test Case reaches Completed, put its ongoing call under an independent application owner. Avoid calling the same stateful resource twice to compensate for a misunderstood order.

### Resource errors and timeout ownership

Report ResourceError through the Preparation status; do not emit another Test Case result or set the Test Case state directly. The base interprets the observed error during its relevant lifecycle processing.

PreparationTimeout belongs to the Test Case. A valid resource that simply has not reached its target is not automatically a local Error. Continue reporting its real progress and let the owner supervise the deadline. An impossible configuration or known unrecoverable resource condition should instead be recognized explicitly rather than disguised as waiting.

The Preparation-local State helps identify where it stopped. For more detailed resource diagnosis, retain meaningful observations in the named helper instance instead of creating another PC-facing result owner.

## Several Preparations in one Test Case

The number of helper instances does not determine FPreparationStateCount. Two independently prepared resources can share one Preparation state, while a single resource may require several ordered stages.

### Independent prerequisites required together

Suppose the Test Case owns two independent simulated resources, and both must be at their targets. Use two Prepare_ValueAtTarget instances with separate resource bindings and call both in ProcessPreparations.

For this specific dependency:

| Combined observation | Meaning |
| --- | --- |
| Ready | Both helpers are ready and neither reports Error |
| Running | At least one helper is actively preparing |
| Completed | Both targets are currently reached and neither reports Error |
| HasError | Either required helper reports Error |
| State | A meaningful combined stage, or the relevant failing helper's diagnostic state |

For an error-free pair, the core combination is:

```iecst
UpdatePreparationStatus(Ready := LeftStatus.Ready AND RightStatus.Ready,
    Running := LeftStatus.Running OR RightStatus.Running,
    Completed := LeftStatus.Completed AND RightStatus.Completed,
    HasError := FALSE);
```

LeftStatus and RightStatus are current snapshots read after their respective concrete FB calls. This fragment is only the error-free branch: inspect required-helper errors first and publish an error observation instead of completing the phase. Decide whether an error should prevent further helper actions in the same call, based on the resource dependencies and call order. Do not suppress an observed error merely because the other helper completed.

CompletePreparations is called only when the combined target is reached without error. Do not call it independently for each helper. Since this is one joint Preparation stage, FPreparationStateCount remains one.

The AND for Completed is justified by both prerequisites being required. It is not a framework-wide combination rule.

### Ordered stages

If resource B may only be prepared after A reaches a prerequisite, make that ordering explicit in the scenario. Options include one Preparation that encapsulates the whole coherent target behavior, or separate configured Preparation states in the Test Case.

For separate Test Case stages, use consecutive named states from E_State.Preparing, set FPreparationStateCount accordingly and advance intermediate stages through NextPreparationState. CompletePreparations ends all Preparation stages.

An intermediate helper's Completed is not the combined phase Completed. Publishing it as such can make the Test Case enter testing before later stages run. Keep the whole-target observation correct on disabled calls as well as during active staging.

Observe whether earlier prerequisites must remain true during later stages. A sequence of latched historical completions is not a substitute for a currently valid starting condition.

### Alternative ways to reach one target

When either of two techniques can establish the same target, select the technique and control its resource ownership explicitly. Do not enable competing writers and OR their Completed bits.

An error of the selected required path cannot be ignored just because an unused alternative has a convenient status. Define which observations actually describe the chosen path and which target condition ultimately permits testing.

## Internal progress and initialization

Use internal state only when the target-establishment algorithm needs it, for example an ordered resource handshake. Keep the active state processing recognizable and bounded; expose useful local progress through Status.State.

On disabled calls, return that internal progress to an executable base state without resource writes, while still reporting current target/error observations. Do not retain an old Completed latch.

PreparationBase does not define a universal Initialize or Reset method. If your concrete helper needs configuration or has additional transient state, provide the appropriate concrete setup and invoke it from the Test Case's Configure. Rebuild that state during PLC-start initialization rather than assuming declaration defaults ran again.

The Test Case still owns lifecycle Reset and Abort resource actions. A helper-specific setup/reset operation must not secretly replace those responsibilities or perform disabled cleanup. After restart, initialized but not yet reset Test Cases may call Preparations with Enable FALSE; those first observations must already be safe.

## Refactor bindings without changing behavior

To reuse an existing dedicated Preparation:

1. Record its target, normal starting states, exceptional conditions, active writes and Ready/Running/Completed/Error behavior.
2. Identify concrete resources and values that vary between instances.
3. Choose a scope that keeps one clear target-condition behavior.
4. Extract those dependencies into typed parameters or existing resource interfaces; leave production data types unchanged.
5. Preserve call ownership, disabled observation, enabled writes and any cycle-order assumptions.
6. Verify the original binding and another independent binding, including disable/re-enable and an already-reached target.

Do not generalize by introducing unrelated target modes, hidden cancellation commands or ownership of the tested block's call.

## Mocks are not resource Preparations

The library's PreparationMock is a controllable double for testing the owning Test Case behavior. It accepts Ready, Completed and Error inputs, with defaults TRUE, TRUE and FALSE. It performs no resource actions and has no automatic timed progression.

Those defaults report a reached target after a call; they do not establish a real starting condition. Use the mock when intentionally simulating a prerequisite, not as a production Preparation whose Completed happens to be convenient.

## Authoring checklist

- One understandable target condition is defined independently of the tested behavior.
- Expected normal starting states are supported; exceptional failures are explicit.
- The already-reached target requires no unnecessary stimulus.
- The resource's cyclic call remains with the Test Case or application owner.
- Enable FALSE causes no resource writes, including hidden cleanup.
- Status is refreshed while disabled, and Completed reflects the current target.
- Ready and Completed are not treated as synonyms.
- State and ExecutionStatus describe compatible local progress and observations.
- Required stimulus ownership is transferred explicitly when testing begins.
- Preparation errors and timeouts are interpreted by the owning Test Case.
- Multiple helpers are combined according to their actual dependency.
- Initialization and deactivation cannot reuse stale progress or commands.
- Mocks are used deliberately as doubles, not mistaken for resource implementations.

Continue with [Test Case authoring](test-case.md) for the scenario hooks around the Preparation, or return to the [framework model](framework-model.md).
