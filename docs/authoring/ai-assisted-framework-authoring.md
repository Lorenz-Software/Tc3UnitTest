# AI-Assisted Framework Authoring

AI assistance can propose tests for an existing PLC block and turn agreed test intent into a concrete TC3 UnitTest implementation. It can help select supplied Assertions, implement the required overrides, compose children and review the resulting code. The author remains responsible for the intended production behavior and acceptance criteria.

This companion explains how to request and review that work. Use it with the six authoring chapters and the actual framework version used by your application. The optional `tc3unittest-framework-authoring` skill supports the workflow; this guide remains usable without it and does not describe skill installation. Neither replaces engineering review, compilation or test execution.

## Scope of an authoring request

Ask for one clearly bounded change, such as:

- Implement or revise a Test Case for specified stimuli and expected behavior.
- Implement a Preparation that establishes a specified resource condition.
- Select and wire Assertions for defined observations and evaluation windows.
- Compose known Test Cases into a Suite with an agreed execution mode.
- Compose known Suites into Run Control and connect the PLC startup/cyclic path.
- Refactor resource bindings or review an existing implementation without changing its test intent.

The skill includes optional native source starting points for the guide's immediate Boolean Test Case and scalar target-condition Preparation. Their application names and the sample IsPositive function are illustrative application code, not additional library APIs. Adapt their stated assumptions and assign fresh native object identities when copying them; they are not required for other scenarios.

Static checks, single-state and multi-state scenarios, optional Preparation and Serial/Parallel/ParallelSlots composition are all supported by the supplied framework structure. Prefer the existing bases and helpers. A custom lifecycle, new Assertion algorithm or new resource abstraction is a separate design decision, not an automatic consequence of requesting a test.

Keep test proposals separate from implementing accepted intent. Supplying production source can establish the interface, call behavior and candidate tests, but is not permission to derive acceptance criteria from whatever that implementation currently happens to return. Do not change production code, write expected values into real feedback or weaken a check just to obtain a passing test.

## Request a test plan when intent is not yet complete

For an existing block, supply its version, relevant requirements, interface, callers and known dependencies. Ask for a behavior inventory and proposed scenarios before implementation. Separate requirement-backed expectations, observed implementation, proposed characterization of current behavior and unresolved questions. Existing tests and prior corrections are useful experience; they do not automatically make an observed behavior correct.

For each relevant behavior, connect the requirement or open decision to the starting condition, stimulus/call sequence, independently justified expected observation and completion condition. State relevant isolation, Reset and repeated-run needs and identify uncovered or blocked behavior. Use a compact matrix or prose proportional to the task; a stateless function does not need an invented lifecycle.

Ask the author to resolve missing intent when it changes correctness, timing or resource ownership. An incomplete specification need not block useful analysis, but proposed characterizations must be accepted before they become correctness criteria. Already-agreed intent can proceed directly to implementation without a new discovery stage. A test must be able to complete and report Failed when its expected response does not occur; completion must not depend only on success.

### Review reuse before adding components

Search existing Test Cases, Preparations and helpers first. Distinguish the stable behavior or target condition from varying resource bindings, stimuli, expectations, limits and durations. Select general, resource-family or dedicated scope using the [Test Case](test-case.md#reuse-and-resource-interfaces) and [Preparation](preparation.md#choose-a-useful-reuse-scope) guidance. Do not combine unrelated scenarios behind mode parameters merely to share one FB type.

Reuse types while keeping progress, Preparation/Assertion state and cleanup ownership independent for each use. Review a second suitable binding when claiming reuse, and distinguish source-reviewed suitability from compiled or executed evidence. A dedicated test remains appropriate when abstraction would obscure the behavior. Shared resource access requires explicit ownership and isolation, including Reset and Abort.

Once the intended scenarios and material open decisions are settled, use the implementation context and review below. No new production interface, test seam or framework behavior is implied by approving a test plan.

## Applied authoring practices

These practices apply the existing Test Case, Preparation and Assertion guidance to recurring authoring decisions. They do not override a contract or establish another lifecycle. The named SelfTests are development-source examples under `SelfTests/TestCases/`, not supplied consumer types or templates.

### Keep one coherent behavior per scenario

When a block has several independent behaviors, prefer separate Test Cases so each has a clear starting condition, failure identity and reset. Keep multiple steps together when their order or interaction is the behavior being checked. A sequence that requests Reset twice and then observes completion belongs together; a mode switch selecting unrelated reset, numeric and configuration tests usually does not.

For example, `TestSuite_TestSuiteLifecycle/Test_SuiteMockRepeatedReset.TcPOU` keeps repeated requests and progress in one scenario. A compact group of independent boundary values can instead share a table-driven check when the failing row, input and expectation remain identifiable. Follow [Test Case authoring](test-case.md#define-the-scenario-before-the-block); neither one Test Case per input nor one Test Case per production block is a universal rule.

### Reuse a stable scenario or target condition

Before extracting a reusable type, name what stays the same and show what changes between two real uses. Resource bindings, targets, limits and durations may vary while the tested relationship remains stable. If reuse requires changing the behavior, Assertion family or state sequence through mode parameters, reconsider the boundary.

The guide's `Prepare_ValueAtTarget` example uses scalar bindings; the SelfTest helper of the same name binds a concrete `PreparationResource`. Both are useful at their chosen scopes. Reuse the appropriate type with independent instances, not one mutable instance across unrelated owners. See [Test Case reuse](test-case.md#reuse-and-resource-interfaces) and [Preparation reuse](preparation.md#choose-a-useful-reuse-scope). A dedicated implementation is preferable when abstraction adds no practical second use.

### Separate establishing a condition from testing it

Use a Preparation to establish a required starting condition, and Assertions to evaluate the tested response. Do not let Preparation perform the stimulus whose effect the Test Case is meant to prove. If the Preparation itself is the subject, exercise it as the tested component rather than require its success before the test can begin.

`TestSuite_Preparation/Test_PreparationReachesTarget.TcPOU` observes request/feedback separation and actual resource progress. `Test_PreparationDisabledObservation.TcPOU` checks observation without writes. The resource supplies feedback; assigning expected feedback in the Preparation would bypass the behavior under test. Follow [Preparation target conditions](preparation.md#define-one-target-condition).

### Make call order part of temporal expectations

For a cyclic subject, state who prepares inputs, who calls it and when the test samples feedback. Preserve one execution owner and the normal policy of at most one body call per PLC cycle. A deliberately call-driven test double or immediate method probe is a scoped exception, not a reason to multiply calls to a running cyclic resource.

The Preparation resource examples call the resource separately from the Preparation. A changed request may therefore affect feedback on a later call. Disabling first-call observation can represent that known ordering; it cannot stand in for an unknown settling time. Follow [tested-object call ownership](test-case.md#calling-the-tested-logic-internally-or-externally) and [Assertion observation](assertions.md#observation-and-evaluation-are-different-operations). Repeated calls are not proof that a runtime clock advanced.

### Finish after the observation, including failure

Define an observation endpoint independently of whether the expected value occurred. After the intended evaluation, complete or advance the phase even when the Assertion reports Failed. Do not wait only for Passed and convert a useful mismatch into a framework timeout. Preserve Error for the contractually defined configuration/resource/framework failure paths.

The guide's single-state and positive/zero boundary examples record that evaluation happened before completing or advancing. Their result does not control progression. See [the complete Test Case example](test-case.md#create-the-concrete-fb). A scenario whose requirement is itself a bounded wait still needs a defined unsuccessful endpoint and an explicit interpretation of that outcome.

### Restore the real baseline and prove another run

Reset the owned subject, progress, command history, snapshots and checking components needed by the scenario. Clearing a local step variable does not restore a nested resource. Use the resource's supported reset/setup operation and wait for its actual baseline where required; do not write another owner's internal state or rebuild framework configuration as an ordinary lifecycle Reset.

`TestSuite_AssertionLifecycle/Test_AssertionResetReuse.TcPOU` demonstrates that Assertion Reset is queued and processed on a regular bound call. `TestSuite_Orchestrator/Test_OrchestratorRepeatAfterReset.TcPOU` provides repeated-run experience. Exercise another run with the same bindings, and interruption recovery where relevant, before claiming repeatability. Follow [initialization versus Reset](test-case.md#initialization-is-not-reset) and the [Assertion publisher isolation guidance](assertions.md#select-a-publisher-when-needed); this does not require hardware reset for every stateless test.

### Keep the expectation independent and the failure actionable

Derive expected values from the requirement or an explicitly accepted characterization. Use implementation details to locate boundaries, not to calculate the oracle with a copy of the same algorithm. For names, for example, supply separate valid/invalid examples for owner segments and Assertion-local suffixes instead of applying one character rule to both.

Give independent conditions distinct Assertion identities when that improves diagnosis. Group repeated checks only while their row/state and observed versus expected values remain clear. The [positive/zero example](test-case.md#extending-the-example-to-two-test-states) preserves both checks as independent Assertions; [snapshot Assertions](assertions.md#retained-snapshot-for-array-no-change) illustrate why observation storage and its lifetime also belong in the test design. No example alone proves complete behavioral coverage.

## Supply the authoring context

Provide the relevant information below. Mark items as not applicable when the scenario genuinely does not need them; do not leave missing decisions disguised as default values.

| Topic | Information the author supplies |
| --- | --- |
| Requested artifact | Test Case, Preparation, Suite, Run Control, integration or review; new implementation versus a change to existing code. |
| Framework and target | Framework version/source revision, namespace, TwinCAT build and relevant project restrictions. |
| Defined behavior | Requirement or scenario description, stimuli, expected values/conditions, tolerances and what constitutes failure. |
| Observable interface | Exact types, members, array bounds, units, strings/encoding and accessible feedback. Include the actual declarations when names alone are ambiguous. |
| Call ownership | Who owns and calls the tested FB/FC, and whether feedback reflects the same PLC cycle or a later cycle. |
| Resources | Which instance/equipment/data is used, who may write it, and which other tests or application logic can access it. |
| Starting conditions | Required Preparation targets, accepted initial conditions and resource readiness. |
| Timing and completion | Observation window, explicit evaluation point if needed, phase completion, timeouts and expected cleanup. |
| Identity and placement | Root/parent identity, local names, resource context, existing owners and intended project locations. |
| Composition | Concrete children, registration order, mode, slot groups and resource restrictions across those groups. |
| Existing work | Code and bindings to preserve, changes already made, known defects and the exact requested change boundary. |

An expectation must be precise enough to distinguish similar tests. For example, "the output becomes TRUE" leaves open whether the first TRUE is sufficient, whether it must remain TRUE for a window, and when the scenario ends. Likewise, "unchanged" needs a baseline and an observation interval. These choices affect Assertion selection and must come from the test intent.

For array and sequence checks, provide the selected region, expected sequence/pattern and any caller-owned snapshot storage. For numeric tolerances, provide the intended tolerance rather than asking the assistant to choose a convenient value. For a multi-cycle resource, define Reset and Abort behavior as well as the successful path.

### Level-specific inputs

For a **Test Case**, describe the actions and observations in each phase. State whether the scenario owns an internal tested instance or drives an externally called object. Specify any required transfer of stimulus ownership between Preparation and testing. A test phase needs an explicit completion condition; a Passing Assertion alone is not a universal completion policy.

For a **Preparation**, specify the target condition to establish, which normal initial states it must handle, permitted commands and exceptional failures. A Preparation should establish that condition, not merely report an invented Completed flag. Disabled behavior must still provide meaningful observation without continuing resource writes.

For a **Suite or Run Control**, supply the concrete child types/instances and the intended scheduling. If the mode is undecided, request a proposal and agree on it before generation. Parallel groups require explicit resource compatibility, including Reset and Abort; separate instances or serial execution within each child do not prove that sharing is safe.

For **program integration**, identify the single task, existing program call order and selected communication storage. Ask for the complete startup and cyclic path, not an isolated root call with unspecified initialization.

## Use the manual and actual interfaces

Start with the [framework model](framework-model.md), then use the chapters relevant to the requested change:

| Chapter | What assistance should take from it |
| --- | --- |
| [Test Case authoring](test-case.md) | Required hooks, Configure versus Reset, tested-object calls, phase completion, aggregation and normal/exceptional paths. |
| [Preparation authoring](preparation.md) | Target establishment, resource ownership, enabled actions, disabled observation and integration into Test Cases. |
| [Assertion authoring](assertions.md) | Family selection, initialization, concrete signatures, observation/evaluation, reset and storage requirements. |
| [Test Suite authoring](test-suite.md) | Builder usage, local arrays, lookup, concrete calls and mode/resource consequences. |
| [Run Control and PLC integration](run-control.md) | Root composition, first-cycle initialization, command adapter, communication and repeated runs. |

Normal application authoring should be possible from these chapters. Inspect the actual declarations when exact parameters, visibility or available types need confirmation. Do not invent framework FBs, method names, inputs, state values or events to make a sketch look complete. Do not combine examples from a different framework version with the current APIs without checking compatibility.

The supplied base owns the generic processing. Assistance should implement the application's required overrides, not copy the base lifecycle into every concrete FB. For example, `GetTestCase(Index)` and `GetTestSuite(Index)` are abstract bridges to an array held by the concrete owner: their implementations read the same array populated by the builder. They do not manually reconstruct the registration order or select children with a second independently maintained mapping.

If a manual statement and the available implementation appear inconsistent, identify the concrete discrepancy and ask for its resolution. Do not silently replace established behavior, alter the contract or introduce a workaround with different semantics. Existing application rules and framework rules must be reconciled rather than selectively ignored.

## Resolve uncertainty before generating behavior

Ask a focused question when missing information changes what the test means or whether its resource access is safe. Examples include:

- Is the observation required once, throughout a window or only at its end?
- Is the tested object called before or after the scenario, and who owns that call?
- Does Preparation need to drive the resource or only observe an already established condition?
- Can two scenarios write the same resource during execution or cleanup?
- Should a phase finish after a fixed stimulus sequence or after a defined feedback condition?
- Is the requested operation already represented by a supplied Assertion, or would it need a new algorithm?

Explain the consequence of the options. Do not bury a missing timing, concurrency or expected-value decision in generated constants, empty hooks or comments such as "adjust as needed" and then report the implementation as complete.

Routine code organization and naming can follow the existing conventions without reopening agreed test behavior. When revising code, list any proposed semantic change separately from mechanical restructuring. A binding refactor must not quietly change sampling order, timeout interpretation or acceptance criteria.

## A practical request format

The following brief can be used with an assistant that can read the relevant documents and declarations:

```text
Task:
Create/revise/review [artifact] for the defined scenario below.

Context:
Framework version or source revision:
TwinCAT build and namespace:
Existing parent and child instances:
Relevant declarations and code to preserve:

Defined test intent:
Requirement:
Initial/Preparation condition:
Stimuli and sequence:
Expected observations and tolerances:
Observation/evaluation timing:
Phase completion:
Reset and Abort behavior:
Timeouts:

Bindings and composition:
Resource instance/interface and write ownership:
Tested-object call owner and cyclic order:
Names and parent identity:
Registration order, execution mode and slots:

Deliverable:
Implement the required declarations, FB body and overrides using the supplied
bases and current interfaces. Preserve the stated test behavior and existing
work. Explain the application wiring and any unresolved decisions.
Do not invent stimuli, expectations or production behavior. Ask before filling
semantic gaps or introducing a framework/API change.
Report source review, compiler checks and runtime execution separately.
```

Supply actual project values, not a request for the assistant to fill every blank. For a pure stateless function, resource cleanup can explicitly be "none"; for a valve or drive that would require a real engineering decision.

### Example: a fully defined small scenario

The following request corresponds to the existing [single-state Test Case example](test-case.md#a-complete-single-state-example). Its criterion is supplied explicitly, not discovered by inspecting the function's implementation:

```text
Create Test_AcceptsPositiveValue derived from TestCaseBase.
The existing function is IsPositive(Value : DINT) : BOOL.
Requirement for this scenario: Value = 1 must produce TRUE.
Call the function inside the Test Case; there is no stateful tested instance,
shared mutable resource or Preparation.
Use one Test state and the supplied AssertTrue. Evaluate the computed sample,
then complete the phase after that evaluation, regardless of Passed or Failed.
Use the local Assertion name PositiveAccepted and the parent-provided identity.
Configure the Assertion during Test Case configuration. Reset clears the local
progress and requests Assertion reset. Abort needs no resource cleanup.
The owning Suite supplies the Test Case timing configuration.
Implement all required overrides, including the empty Preparation hook and
aggregation of this one Assertion. Do not modify IsPositive or add more cases.
Use the current Test Case authoring chapter and confirm actual signatures.
```

An incorrect FALSE result must lead to a failed, completed test, not a test that waits forever for TRUE. A good review therefore checks the generated completion condition as carefully as the comparison itself.

For a composition-only follow-up, supply the existing child types and names, requested order/mode and resource constraints. Ask for Configure, array lookup and concrete cyclic calls together. A builder registration without a matching child call is not a complete composition.

## What a useful response should contain

Expect a coherent implementation of the requested scope, not a pile of detached method fragments with missing ownership:

- The concrete declarations and FB body, required overrides and relevant configuration.
- Exact bindings to the tested object, resource interface and parent/children.
- A short explanation of call order, phase completion and responsibility boundaries where they affect correct use.
- Explicit unresolved decisions or unavailable interface information, without claiming those parts are finished.
- A description of what was changed and preserved when revising existing code.
- Verification results with their actual scope and limits.

Do not ask for or accept duplicated framework state machines, hand-written status aggregation or extra event publication where the bases already supply them. Do not introduce another communication protocol merely to simplify generated application code.

## Review before relying on generated code

### Behavior and ownership

Check stimuli, expected values, timing and completion against the supplied requirement. Check that feedback comes from the tested object rather than being assigned by the test. Ensure every stateful object has a clear owner and is called exactly once through the intended path. Parallel execution must not introduce conflicting writes, including during Reset and Abort.

Verify that the chosen Assertion expresses the actual question. Observation Enable, explicit Evaluate and ObserveFirstCycle are not interchangeable. The scenario must not complete before the intended check, wait only for a successful result or hide an Error by replacing it with Failed/Passed.

### Framework integration

Check that:

- Derived FB bodies invoke their base once, with required inherited parameters forwarded.
- Initialize/Configure establishes identity, child setup and passive application-owned transient values; lifecycle Reset is implemented separately.
- Required completion hooks are used at the intended point, without replacing the base lifecycle.
- Assertions have initialized names and valid input/storage bindings on every relevant call, including reset processing.
- Each owned result is contributed once; aggregation does not execute checks or publish duplicate finalization events.
- Registered children, actual array lookup and concrete cyclic calls describe the same composition.
- The program uses the documented first-cycle order and adapter-before-root calls; root and child call paths do not stop merely because an owner reached Completed.
- External publication uses the defined communication variables or explicit status wrappers, not instance internals.

Apply the detailed checklists from the relevant chapters rather than inventing a second set of lifecycle rules for assisted code.

### Clean code and practical diagnosis

Read the generated code as code you will maintain. Look for a clear functional scope, descriptive names, visible ownership, straightforward error paths and unnecessary layers or copied state. Avoid a generic configuration framework for one small scenario when explicit calls are clearer. Check bounded cyclic work and unnecessary copying as well as logical correctness.

Confirm that names and finding context identify the failing scenario, and that a developer can observe the relevant state without creating a new external instance-data contract. A successful compile does not establish readable design or a meaningful test.

### Verification evidence

Keep three different results separate:

1. **Source review:** interfaces, lifecycle responsibilities, test intent and saved files were checked. This does not establish compiler validity.
2. **Compiler/static checks:** the named target project and relevant objects were actually checked. A build that excludes unused blocks is not evidence for those blocks. Attribute diagnostics to the specific completed operation, not an old error list.
3. **Runtime verification:** the intended target actually executed the scenario, and observations/events were inspected. Record which normal, failure, reset/repeated-run and relevant abort/restart paths were exercised. Compilation alone is not runtime evidence.

Before runtime execution, agree on the target and resource effects. Do not treat permission to author code as permission to operate connected equipment. Missing tools, unavailable targets or unperformed checks should be reported directly, not replaced by an unsupported "verified" claim.

## Keep the boundary intact during iteration

When a test fails, compare the observed behavior with the requirement and inspect the generated wiring. Do not automatically change expected values, extend deadlines, remove Assertions or modify production code to make the run pass. Identify whether the issue is in the test implementation, the tested implementation or an unresolved requirement, then agree on the appropriate change.

Assistance remains responsible for implementing the supplied framework usage accurately. The author remains responsible for test intent, acceptance criteria, resource permissions and the decision that the resulting test is useful. Neither an assistant's confidence nor a generated checklist replaces those decisions.

Return to the [framework model](framework-model.md) for the manual's entry and the concrete chapters for implementation guidance.
