# AI-Assisted Framework Authoring

AI assistance can propose tests for an existing PLC block and turn agreed test intent into a concrete TC3 UnitTest implementation. It can help select supplied Assertions, implement the required overrides, compose children and review the resulting code. The author remains responsible for the intended production behavior and acceptance criteria.

This companion explains how to request and review that work. Use it with the six authoring chapters and the actual framework version used by your application. The optional `tc3unittest-framework-authoring` skill supports the workflow; this guide remains usable without it and does not describe skill installation. Neither replaces engineering review, compilation or test execution.

## Scope of an authoring request

Ask for one clearly bounded change, such as:

- Analyze an existing block and propose meaningful behavioral tests and open decisions.
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

## Derive a useful test set

Start with what the block is responsible for, not with the number of methods or
the available Assertion types. For a small function this can be a few sentences;
for a resource controller it includes retained state, call history, dependencies
and externally visible effects. The following examples define illustrative
application behavior; LimitValue and IsRequestAllowed are not library APIs.

### Understand the boundary before choosing scenarios

Read the public declarations and the relevant implementation, callers and
dependencies. Describe:

- The transformation, decision or stateful operation the block provides.
- Valid inputs, configuration limits, output meaning and defined error behavior.
- Retained history, clocks, referenced storage and command/resource ownership.
- What the test can control, call and observe through the available boundary.

A caller can explain how an input is used, but cannot automatically establish
that undocumented behavior is correct. For example, a nonempty array at every
existing call does not define what an empty array should do. Keep that as an open
question unless the interface or requirement already excludes it. If analysis
reveals only a suspected guarantee, propose it for agreement before turning it
into a pass/fail condition.

State the boundary of the proposed test as well. A software unit test can prove
the chosen command/feedback relationship under controlled inputs; a test double
cannot establish that a physical device or actual ADS exchange will behave the
same way. Separate those integration questions from the block behavior.

### Review a source-backed block analysis

Before discussing scenarios, ask the assistant to explain the block in terms you
can check against the supplied sources. For a small function, a short paragraph
and a few references may be enough. A cyclic resource controller usually needs
more explanation of history, dependencies, timing and recovery. Use the result
in the ordinary answer or test plan; no separate document or fixed form is
required.

| Part of the analysis | What to check |
| --- | --- |
| Subject and source boundary | Which block/member and source revision were inspected? Which bodies, callers or requirements are missing? |
| Behavior and usable boundary | What do inputs/configuration mean, which domains are valid, and what can be controlled or observed? How do state, priorities, call order, time and recovery affect the response? |
| Relevant dependencies | Which calls, base implementations, overrides, accessors, shared data and external services explain that behavior? Which concrete interface bindings are known? |
| Critical areas | Which reachable paths, competing conditions, arithmetic/storage limits or lifetime assumptions could change an observable result? Why would they justify a test? |
| Open questions and evidence limits | What remains uncertain, what consequence does it have, and what source, decision or check would settle it? |

Keep the basis of each important claim visible:

- **Specified:** an identified requirement or accepted contract supports the
  expected behavior.
- **Observed:** a source body, caller or existing test shows the behavior.
  A deduction should identify the operations and ordering that support it.
- **Proposed characterization:** observed behavior is proposed for intentional
  preservation, pending acceptance as a test basis.
- **Unresolved:** intent or implementation evidence is missing or conflicting.
  An unconfirmed hypothesis belongs here, with an explanation of how to check it.

One behavior may have both specified and observed support. Compare them rather
than treating the implementation as its own correctness oracle. An inline
comment is useful documentation evidence; it does not automatically settle
conflicting intent. Accepting a characterization is a conscious decision to
preserve behavior, not a way to label an unconfirmed hypothesis as correct.

References should identify the supporting file or native object, member/section
and line or bounded range, tied to the inspected revision or snapshot. File XML
lines and editor/MCP body lines are different coordinates. A shared source list
is sufficient. Report a live/saved-source mismatch instead of combining both
versions as one implementation.

For inheritance, a derived body containing only `SUPER^()` does not explain the
whole call. The analysis must follow the relevant base body and the concrete
hooks it invokes. Similarly, a read-only Property can execute a getter with
effects; inspect that body before treating the value as a passive snapshot.
For an interface call, the declared method is only the boundary: assignments,
configuration, registration or lookup establish which implementation is used.
Without that evidence, the concrete target remains unresolved.

Classify each relevant dependency as reviewed, unresolved or deliberately outside
the chosen boundary, with its reason and consequence. A library reference alone
does not provide the implementation, resolved version or exact timer behavior.
Follow only the depth needed to explain the requested behavior and risks; do not
inventory an entire library without a reason. Missing sources can limit one
conclusion while leaving other useful analysis possible.

Files, engineering tools, source inventories and searches can expose code and
help navigate it. The assistant still reasons about its meaning. A completed
search or declaration inventory is not a complete semantic call/data-flow graph.
Unknown conditional build choices, unavailable bodies, graphical/IL code and
uncertain pointer/alias targets need explicit limits or additional review.
Structural/link checks validate the material they inspect, not the correctness
of an analysis. Distinguish source reasoning, compiler checks, runtime evidence
and any independent evaluation actually performed.

The next step is to select meaningful scenarios from this understanding. An
unresolved expectation needs agreement; an unresolved binding or observation
may need fixture work. Neither automatically requires a new production
interface, and neither prevents explaining the behavior already supported by
the available sources.

### Make expectation provenance explicit

For each selected scenario, identify the accepted requirement, owner decision or
explicitly accepted characterization that supports the expected observation.
The existing Specified/Observed/Proposed characterization/Unresolved distinction
also applies here: a passing old test, source comment or alternate implementation
alone does not settle intended correctness.

Literal accepted examples, independently justified mathematical relationships
and suitable reference models can provide an oracle. State relevant assumptions,
scope and tolerances. Running the subject to obtain Expected or copying its
algorithm risks preserving the same defect. An invariant that also permits a
meaningful wrong result needs additional distinguishing checks.

Keep candidates with missing intent visible and ask a focused consequential
question before encoding them as acceptance criteria. Missing source evidence
and missing control/observation are different gaps; continue unaffected work.
Ordinary representative values within an agreed domain need no new approval.

### Select techniques by the behavior and risk

Use the techniques that distinguish meaningful behaviors. They are not a
mandatory checklist for every block.

| Technique | Useful when | Purpose and limit |
| --- | --- | --- |
| Equivalence classes | Many inputs have the same required treatment | Choose representatives of each treatment; avoid arbitrary repeats |
| Boundary values | Ordered ranges have different behavior near a limit | Exercise the endpoint and meaningful representable neighbors |
| Decision tables | Conditions jointly permit or reject an operation | Cover feasible decisions; merge genuinely irrelevant conditions |
| State and sequence tests | History changes the response | Check meaningful paths, interruption and reuse; see [cyclic test design](#design-cyclic-and-temporal-tests) |
| Invariants and relationships | A requirement holds across many examples | Supplement specific expectations; a broad property alone can miss wrong outputs |
| Error and recovery tests | Invalid setup or a dependency failure has defined behavior | Check the diagnostic outcome, passive outputs and supported recovery |
| White-box review | Branches, conversions or dependencies reveal risks | Find candidate scenarios; implementation is not the correctness oracle |
| Regression and fault-based selection | A known defect or plausible mistake explains a risk | Preserve the relevant behavior; executed detection is a separate claim |

For a simple single-condition check, a decision table may add little. A pure
calculation needs no state-transition path; a block without a defined ordered
limit needs no invented boundary. Do not invent invariants or error cases when
the requirements provide none. Without source access, behavioral test planning
can still proceed while white-box risks remain unreviewed. A historical defect
only justifies a regression check while its behavior remains relevant.

The established black-box, white-box and experience-based techniques are
described in the [ISTQB Foundation syllabus, sections 4.1–4.4](https://istqb.org/wp-content/uploads/2024/11/ISTQB_CTFL_Syllabus_v4.0.1.pdf).
The examples below apply them to PLC behavior; they do not prescribe a coverage
quota or an implementation-specific branch test.

### Work from partitions to concrete boundary checks

Suppose LimitValue accepts any DINT and clamps its result to [-100,100], retaining
every in-range input. Below, inside and above the interval are three different
required treatments. The endpoints are important because the treatment changes
there; the data type's extrema also matter when implementation arithmetic could
overflow.

| Input | Expected result | Behavioral reason |
| --- | --- | --- |
| -101 | -100 | Lower clamping |
| -100 | -100 | Lower endpoint |
| -99 | -99 | Neighbor inside the valid interval |
| 0 | 0 | Interior value remains unchanged |
| 99 | 99 | Neighbor inside the upper endpoint |
| 100 | 100 | Upper endpoint |
| 101 | 100 | Upper clamping |
| Minimum representable DINT | -100 | Extreme lower input remains valid |
| Maximum representable DINT | 100 | Extreme upper input remains valid |

Expected results here come directly from the stated interval and examples, not
from executing a second copy of the clamping algorithm. The selected values are
concrete examples, not a universal minimum number of tests. Additional arbitrary
interior values add little unless another requirement or risk distinguishes them.
There is no invalid-input case merely because an input lies outside the output
interval: every DINT is valid in this example.

Use representable neighbors in the relevant unit. DINT neighbors differ by one;
string limits concern the declared capacity/encoding, array limits concern the
selected region, and floating-point neighbors cannot be chosen by blindly adding
one. Select meaningful numeric tolerances from the requirement rather than to
accommodate the current output. The
[numeric Assertion guidance](assertions.md#scalar-values-limits-and-tolerances)
and [array-region guidance](assertions.md#array-regions-and-pattern-checks)
explain the corresponding checks.

An invariant such as -100 <= result <= 100 is useful but insufficient: a function
always returning zero would satisfy it. Idempotence of clamping likewise does
not prove that in-range values are preserved. Keep these relationships as
supplements to the explicit expected examples, without requiring a new
property-testing engine.

### Work from decisions to condition combinations

Suppose IsRequestAllowed returns TRUE only when Request and Permissive are TRUE
and Fault is FALSE. Start with the decisions that change the required outcome:

| Decision | Request | Permissive | Fault | Expected |
| --- | --- | --- | --- | --- |
| No request | FALSE | Irrelevant | Irrelevant | FALSE |
| Missing permissive | TRUE | FALSE | Irrelevant | FALSE |
| Allowed | TRUE | TRUE | FALSE | TRUE |
| Fault blocks an otherwise valid request | TRUE | TRUE | TRUE | FALSE |

These rules summarize eight concrete combinations. For this small stateless
three-input function, checking all eight is inexpensive. Group the four
no-request combinations, the two missing-permissive combinations and the two
otherwise-permitted combinations, while retaining each row's failure identity.
The expected values are literals from the table, not the same Boolean expression
as the subject placed in the Expected argument.

For a larger block, first remove combinations that the input model genuinely
makes impossible and merge conditions irrelevant to a decision. Do not use
unseen inputs in current callers as proof that a combination is impossible.
An omitted feasible interaction is a stated coverage gap; its priority depends
on the consequence and likelihood of the defect. Pairwise or exhaustive
combinations are not universal requirements.

One successful permitted request does not test Fault handling. Comparing that
case with the otherwise identical Fault=TRUE case makes the missing interlock
observable. The implementation uses the appropriate
[Boolean Assertions](assertions.md#boolean-conditions-and-edges);
it needs no Preparation, timer or duplicated Test Case state machine.

### Use white-box findings without copying the implementation

Inspect the source to identify arithmetic overflow, conversions, array bounds,
reference lifetimes, retained flags, early exits, branch priorities and
dependency side effects that could violate an agreed guarantee. Connect each
material risk to an observable scenario. A branch with no external behavioral
difference does not automatically deserve a separate test.

For the limiter, swapped clamp outputs or modification of an interior value are
plausible faults with observable differences. Changing a strict comparison to an
inclusive comparison at a clamping endpoint may be equivalent when both branches
return that endpoint. Do not promise that the selected tests detect such an
equivalent change. For the permission decision, ignoring Fault is a meaningful
candidate; for a cyclic sequence, retained edge history can explain a repeat-run
regression. These are analytical reasons to select checks, not evidence that a
fault challenge was executed.

Prefer tests through the supported behavioral interface that remain meaningful
when internal decomposition changes. Google's
[behavior-focused testing discussion](https://testing.googleblog.com/2013/08/testing-on-toilet-test-behavior-not.html)
explains that maintenance advantage. A dependency interaction can itself be a
requirement, but checking a private helper call solely because it exists couples
the test to today's implementation.

Prefer real dependency implementations. A small local double is a narrowly
justified exception when the real dependency cannot practicably supply a needed
controlled response. The subject whose behavior is claimed remains real. State
the substitute's modeled behavior, accepted specification/version and the real
integration claims it cannot establish.

Where feasible, apply the same relevant behavioral checks with independent
expectations to the real dependency and the double, and retain focused
real-dependency integration checks. Review or repeat those checks after relevant
implementation/contract changes. Compilation checks interface compatibility,
not behavioral equivalence. Compare only behavior the double claims to model;
a deliberately injected fault need not reproduce ordinary real behavior.

These measures reduce divergence risk rather than guarantee equivalence. If
real comparison is unavailable, report that limitation. Do not reproduce the
subject algorithm inside a double, build a whole mirror solely for compatibility,
or add production access to private state just to exercise a branch. Propose a
material testability seam separately; blocked observation does not justify a
silently weaker test.

### Select failure, recovery and repeatability checks

Exercise invalid input only where the interface admits it and its expected
handling is defined. Do not assume every zero, empty value or null reference has
the same meaning. Likewise, a subject's specified Error response can be a
successful test observation; a wrong ordinary output is normally a failed check.

For a stateful subject, select relevant failures from the resources it actually
uses: missing feedback, a rejected request or an invalid configuration can have
different cleanup and recovery paths. Check the required status and resulting
commands, then the supported way to become usable again. Do not invent errors
for a stateless function that accepts its entire input range.

Keep related steps together when history is the point of the test. Split
independent failures when each needs a different baseline or diagnosis. Configure
and lifecycle Reset remain distinct; use the
[Test Case failure/cleanup guidance](test-case.md#reset-abort-and-failure-behavior),
the [Preparation target model](preparation.md#define-one-target-condition) and the
[temporal recovery discussion](#distinguish-cleanup-another-run-and-plc-reinitialization).
No hardware reset is implied for a pure calculation.

### Prioritize a proportional plan and explain omissions

Start with the small set of essential observable questions: what must the block
do, which defined boundaries change its treatment, and which credible failures
or state/history paths could invalidate a real use? Consider both the consequence
of a defect and how likely the implementation or its dependencies are to introduce
it. Methods, branches, Assertion types and test counts do not define that set.

Select representatives for distinct treatments, meaningful boundaries and relevant
histories. Before adding another group, ask: which relevant wrong behavior could
it distinguish that the selected groups do not already address? A distinct
boundary, failure/recovery path or credible independent implementation/regression
risk can justify it. Another ordinary value with the same treatment usually
cannot. This is a reasoned selection, not a requirement to execute a mutation
for every test.

Consolidate candidates before presenting the recommended plan. Also compare
implementation variants rather than automatically repeat a full matrix for every
type. Compare the required behavior, execution/history and relevant failure
mechanisms. Where a shared pattern is supported, use a deeper representative
matrix and targeted checks for actual differences. Similar source or a renamed
type alone does not establish equivalence: precision, representable neighbors,
range, storage, conversions and separately maintained implementations can expose
different defects. Keep the relevant distinguishing checks and state the limits
of the representative coverage. Do not demand exhaustive equivalence proof merely
to avoid arbitrary repetition.

Data variation and scenario identity are different decisions. Several values
that answer one behavioral question can share table-driven checks if the failing
row, stimulus and expectation remain identifiable. Keep independently meaningful
starting conditions, state/history, ownership, recovery or expected behavior
separate. Ordered steps belong together when their interaction is the subject.
Reducing the number of Test Case FBs by hiding unrelated behaviors behind modes
does not improve the test plan.

Present the recommended core first. For each selected group, explain the basis,
starting condition, stimulus/call sequence, independent expected observation,
completion condition and additional distinction proportionally. A small plan
can stay compact:

| Scenario | Basis and setup | Stimulus and observation | Completion and omission |
| --- | --- | --- | --- |
| Lower clamp | Any DINT accepted; no mutable fixture | -101/-100/-99 produce -100/-100/-99 | Finish after all three checks; upper boundary remains a separate group |
| Fault rejects a request | Defined permission table | Otherwise valid request with Fault TRUE produces FALSE | Finish after evaluation; no resource cleanup |
| Missing feedback | Defined cyclic deadline; subject baseline restored | Request, observe Command, keep Feedback FALSE, inspect the bounded final outcome | Finish at the observation endpoint even if Error never appears; exact deadline needs separate timing evidence |

Stop adding cases when the essential behavioral questions and selected material
risks are addressed and further reasonable candidates add no material distinction.
Do not use a fixed quota, percentage, all-combinations mandate or the mere
existence of another method as a reason to continue. A known relevant regression
can still justify a specific check even when the ordinary outcome class is
already represented.

Explain grouped redundancy and meaningful omissions briefly, rather than require
a worksheet for every Assertion or data row. Mark material gaps as unresolved,
blocked, outside the supported model or deferred with their consequence; they
do not become covered because the plan is small. Add further tests only with
their own contribution, not as an automatic optional-test catalogue.

This consolidation applies when selecting or reviewing test scope. For an
implementation-only request, preserve the already agreed scenarios. Propose a
material scope reduction for owner agreement rather than silently remove tests
or expected observations.

Tests need clear failure context, isolation and repeatability. Those quality
concerns also appear in
[Microsoft's unit-testing guidance](https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-best-practices).
Apply them to cyclic PLC execution as described here rather than impose a fixed
wall-clock test budget or exactly one Act call on every scenario.

### Turn the plan into framework composition

Choose Assertions only after the expected relationship, data type and observation
window are known. Implement each coherent scenario through the
[Test Case hooks](test-case.md#required-overrides), adding
[Preparation](preparation.md#choose-a-useful-reuse-scope) only when establishing a
real starting condition requires it. Group independent value samples only while
their names or row context still identify a mismatch.

Compose Test Cases into [Suites](test-suite.md) using the required order and
resource compatibility, then connect [Run Control](run-control.md) and the event
consumer. Reuse the bases' lifecycle, aggregation, reservations and event
publication. Scenario design does not require a new lifecycle or a structural
reorganization; follow the consuming project's existing layout and the
[development organization guidance](framework-model.md#develop-tests-alongside-the-subject).

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

The Preparation resource examples call the resource separately from the Preparation. A changed request may therefore affect feedback on a later call. Disabling first-call observation can represent that known ordering; it cannot stand in for an unknown settling time. Follow [tested-object call ownership](test-case.md#calling-the-tested-logic-internally-or-externally) and [Assertion observation](assertions.md#observation-and-evaluation-are-different-operations). Repeated calls are not proof that a runtime clock advanced. The [cyclic test-design section](#design-cyclic-and-temporal-tests) develops call traces, signal history, observation windows and timing evidence.

### Finish after the observation, including failure

Define an observation endpoint independently of whether the expected value occurred. After the intended evaluation, complete or advance the phase even when the Assertion reports Failed. Do not wait only for Passed and convert a useful mismatch into a framework timeout. Preserve Error for the contractually defined configuration/resource/framework failure paths.

The guide's single-state and positive/zero boundary examples record that evaluation happened before completing or advancing. Their result does not control progression. See [the complete Test Case example](test-case.md#create-the-concrete-fb). A scenario whose requirement is itself a bounded wait still needs a defined unsuccessful endpoint and an explicit interpretation of that outcome.

### Restore the real baseline and prove another run

Reset the owned subject, progress, command history, snapshots and checking components needed by the scenario. Clearing a local step variable does not restore a nested resource. Use the resource's supported reset/setup operation and wait for its actual baseline where required; do not write another owner's internal state or rebuild framework configuration as an ordinary lifecycle Reset.

`TestSuite_AssertionLifecycle/Test_AssertionResetReuse.TcPOU` demonstrates that Assertion Reset is queued and processed on a regular bound call. `TestSuite_Orchestrator/Test_OrchestratorRepeatAfterReset.TcPOU` provides repeated-run experience. Exercise another run with the same bindings, and interruption recovery where relevant, before claiming repeatability. Follow [initialization versus Reset](test-case.md#initialization-is-not-reset) and the [Assertion publisher isolation guidance](assertions.md#select-a-publisher-when-needed); this does not require hardware reset for every stateless test.

### Keep the expectation independent and the failure actionable

Derive expected values from the requirement or an explicitly accepted characterization. Use implementation details to locate boundaries, not to calculate the oracle with a copy of the same algorithm. For names, for example, supply separate valid/invalid examples for owner segments and Assertion-local suffixes instead of applying one character rule to both.

Give independent conditions distinct Assertion identities when that improves diagnosis. Group repeated checks only while their row/state and observed versus expected values remain clear. The [positive/zero example](test-case.md#extending-the-example-to-two-test-states) preserves both checks as independent Assertions; [snapshot Assertions](assertions.md#retained-snapshot-for-array-no-change) illustrate why observation storage and its lifetime also belong in the test design. No example alone proves complete behavioral coverage.

### Establish the conditions for a meaningful observation

Before implementing a selected scenario, establish what makes its observation
valid. Use the relevant patterns below, not a compulsory checklist or additional
tests. A direct stateless comparison needs no clock, resource readiness or
settling phase merely because those matters appear in other patterns.

Separate conditions supplied by requirements or inspected integration facts from
conditions the test will establish and assumptions still unresolved. Preserve
the [expectation evidence distinction](#make-expectation-provenance-explicit):
choosing a fixture does not create a new requirement for the subject. Establish
only the relevant initial state/history, stimulus ownership, execution/sample
order, dependency configuration and data lifetime. Preparation `Ready` means
startability; `Completed` establishes its target. Do not use successful execution
of the behavior being tested as an untested prerequisite for checking it.

A missing expected response can be the subject mismatch the test must detect.
Conversely, an unbound resource or an unusable sample does not establish that
mismatch. Define how a missing prerequisite or observation is diagnosed through
the existing framework behavior; never silently pass an unevaluated claim or
invent a Skip/Inconclusive result. Ask when this interpretation or an acceptance
boundary genuinely needs an owner decision, not for ordinary values chosen
within an established valid domain.

#### Check a computed value before completing

For a configured direct comparison, use this ordering:

`ProcessTests: compute/capture -> ProcessAssertions: check -> a later ProcessTests: complete`.

Keep the captured value valid until the check and record that the intended
comparison actually ran, independently of Passed or Failed. Do not call
`CompleteTests()` immediately after computing: its same-call phase change
disables the following `ProcessAssertions` hook's Enable. `NextTestState()` also
changes the State seen by subsequent hooks, so preserve the intended sample and
phase before advancing. The [complete Test Case example](test-case.md#create-the-concrete-fb)
shows the direct-check completion flag; do not treat `EvaluationActive` as proof
of a new result for every family.

#### Hand a command to an externally executed subject

First trace one actual cycle: who writes the command, when the subject
processes it, and when the test can read the resulting feedback. Observe whether
the API consumes a one-shot command or expects a held signal; do not recreate a
consumed bit on every call unless that is the intended stimulus.

Use `ObserveFirstCycle := FALSE` only when skipping that first enabled sample
matches the known ordering. It skips a sample after every disabled interval too;
a single-call observation window would then contain no observation. Keep TRUE
for a deliberately valid first sample. If acceptance takes several cycles,
start the appropriate check from a defined acceptance/feedback condition rather
than invent a delay or execute the subject twice. Retain an independent endpoint
if that required response never arrives. See
[external subject calls](test-case.md#calling-the-tested-logic-internally-or-externally).

#### Collect an interval and then evaluate it

For an edge count or sequence, define collection start, last included sample and
evaluation endpoint. Call the selected family with observation enabled over the
chosen interval and issue its required `Evaluate` at the endpoint before
`CompleteTests()` or a phase change can suppress that call. Do not keep Evaluate
TRUE throughout an unfinished collection, or stop early merely because the
current count/result happens to be correct.

Check the family's last-sample rule: edge-count observation occurs before
evaluation when both are enabled; sequence evaluation also checks the current
IN even with observation disabled. Supply meaningful inputs in either case.
`ObserveFirstCycle` does not postpone explicit evaluation. Follow
[explicit Evaluate](assertions.md#explicit-evaluate), including any required
baseline, instead of applying a universal end-of-window call recipe.

#### Sample inside a justified time range

Relate the measurement origin to the relevant event, such as the subject's
acceptance of the stimulus; a test phase starting is not automatically the same
instant. Use the actual clock resolution and call/sample order to choose an
achievable observation point within the required domain.

For example, if the agreed claim only needs a sample before 100 ms and the test
chooses roughly 80 ms, that choice does not establish a new 90-ms maximum.
A sample at 92 ms can still support that claim if no tighter requirement applies.
Do not infer a general jitter allowance or acceptance tolerance from this example.
Retain bounds needed to distinguish the behavior: when checking that interrupted
intervals do not accumulate, the new interval must still be below the delay while
the combined prior and new intervals would already reach it. Removing an
unjustified scheduling limit must not weaken that distinguishing observation.
If the required early sample is missed, a later correct output cannot replace
it. Retain the missing-observation diagnostic and the scenario's defined handling;
do not report it as a proven subject defect or silently omit the check.

Use the typed value and actual elapsed measurement for the decision, not rounded
finding text. Units, representation, snapshot lifetime and resolution matter
where they change the distinction being checked. Detailed timing limits belong
in [elapsed time and supervision](#separate-elapsed-time-from-calls-and-test-supervision).

#### Process reset before beginning another observation

Restore the real subject baseline, scenario progress and captured observations
through their respective owners. For an owned Assertion, use:

`Reset request -> regular FB call with valid bindings and no check -> later observation/evaluation`.

Do not count the reset-consuming call as the first sample. Do not assume that
calling `Reset()` alone has cleared its Result. Respect the family's baseline
and retained-history rules when disabling/re-enabling; these are not equivalent
to resetting. Clear test-owned completion/evaluation flags as part of the same
scenario reset so an old flag cannot skip a new check. See
[Assertion reset processing](assertions.md#call-reset-and-aggregate-through-the-test-case)
and [real baseline restoration](#restore-the-real-baseline-and-prove-another-run).

#### Fit supervision to the planned work

First outline the finite successful and unsuccessful paths, then check the
owner-supplied [Test Case configuration](test-case.md#initialization-is-not-reset):

| Configuration field | What the arrangement must fit |
| --- | --- |
| `Timeout` | Active Test Case execution, including Starting, Preparation and all planned Test processing |
| `PreparationTimeout` | Work within each active Preparation state |
| `ResetTimeout` | Scenario cleanup from actual entry into Reset |
| `AbortTimeout` | Controlled abort cleanup |

Keep existing defaults where suitable. Include the defined unsuccessful endpoint,
necessary handovers and actual scheduling/resource effects; do not copy the
subject deadline into every field, invent a universal margin or add all child
limits regardless of serial/parallel execution. Normal mismatches should reach
the scenario's checking endpoint, not be detected solely by framework timeout.
Use [nested supervision reasoning](#separate-elapsed-time-from-calls-and-test-supervision)
rather than another timer that duplicates base-owned monitoring.

## Design cyclic and temporal tests

Ordinary unit-test techniques still apply, but a cyclic block's behavior depends
on the history and order of calls. A single Arrange/Act/Assert description can
contain several bounded stimulus/execute/observe steps. It does not require
exactly one subject call for the whole scenario, nor does it authorize extra body
calls within one PLC cycle. A stateless function with no clock or mutable
dependency needs no artificial temporal fixture.

### Describe the call trace and the observation point

Identify the execution owner and the actual order of input changes, subject
execution and observation. Distinguish a request method that records work from
the later FB call that processes it. Reading an output immediately after that
request can correctly return the preceding processing result.

For illustration, suppose an application FB named FeedbackSequence accepts a
rising Request in Idle, drives Command until Feedback, and holds Completed until
Reset. These are example subject requirements, not supplied framework APIs.
With the test owning the subject call, a normal trace could be:

| Subject call | Inputs established before the call | Required observation after the call |
| --- | --- | --- |
| Baseline | Request FALSE, Reset TRUE | Idle; Command FALSE |
| Accept | Request TRUE, Reset FALSE, Feedback FALSE | Running; Command TRUE |
| Wait | Request held TRUE, Feedback still FALSE | Still Running before the deadline |
| Finish | Feedback TRUE | Completed; Command FALSE |
| Hold | Request still TRUE after completion | Completed remains held; no second job |

A different application call order can introduce a cycle of latency. Describe
that order rather than adding an unexplained delay or calling the subject again.
For an externally executed subject, the Test Case observes the point actually
available to it. Keep that resource's execution independent when it must continue
after the Test Case's active hooks stop. See
[tested-object call ownership](test-case.md#calling-the-tested-logic-internally-or-externally).

Specify whether a sample is needed before a transition, after it, or throughout
an interval. An output that is FALSE at the end does not prove it was FALSE
throughout. Sampled PLC checks establish behavior at their observation points;
they cannot exclude an unobserved pulse between samples.

### Include the relevant signal history

For an edge-sensitive input, test the sequence that makes the edge meaningful:
a sampled low, a sampled high, held high where relevant, and a new edge after
the required recovery. Writing TRUE repeatedly is not a sequence of new rising
edges. A low/high change between two subject calls may never be observed.

Distinguish these starting conditions when they affect the subject:

- A newly initialized instance with its specified previous-input history.
- The first call after a lifecycle Reset of an existing instance.
- The first enabled observation after disabled calls.
- A request or feedback already active when observation begins.

They are not interchangeable with TwinCAT's first task cycle. Derive the expected
behavior from the subject's startup, Enable and Reset semantics; do not impose
one universal edge-detector convention. In the example, Reset samples Request.
Holding it through Reset therefore requires a later sampled low/high before a
new job. A subject that intentionally clears edge history would need different
expectations.

### Choose a sample, a window or a sequence

Select the temporal question before selecting the Assertion:

| Required relationship | Useful observation model |
| --- | --- |
| A value is correct at a defined point | Capture and evaluate that sample |
| A condition remains valid while an operation runs | Observe the required condition throughout the defined sampled interval |
| A response occurs within a limit | Observe the response and an independent unsuccessful endpoint |
| Values or edges occur in a defined order/count | Collect the history, then perform the family's required evaluation |

Keep subject execution, Assertion observation and Assertion evaluation separate.
ObserveFirstCycle controls the first enabled observation; it is not a settling
timer and does not postpone an explicit Evaluate request. Some families need a
baseline before a comparison is possible. A held Passed result does not establish
that a collection window ended, and EvaluationActive alone does not prove input
validity or successful evaluation.

Finish after the intended evaluation, including a failed comparison. In the
normal hook order, CompleteTests from ProcessTests changes the phase before
ProcessAssertions executes. Record the completed check and finish on the next
appropriate call, or use another explicitly ordered path that preserves the last
evaluation. Use the detailed
[observation and evaluation rules](assertions.md#observation-and-evaluation-are-different-operations)
and [same-cycle transition guidance](test-case.md#cyclic-order-and-same-cycle-transitions).

### Separate elapsed time from calls and test supervision

Identify the subject clock, its units and resolution, the task/call period, the
sampling points and the test's completion condition. A loop making many
immediate calls is not elapsed-time evidence. Real-clock scenarios progress over
normal task cycles; a deterministic clock substitution is suitable only when a
supported seam and its meaning are already established.

TwinCAT [TIME](https://infosys.beckhoff.com/content/1033/tc3_plc_intro/12189021579.html)
has millisecond resolution, and the standard
[TON](https://infosys.beckhoff.com/content/1033/tcplclib_tc2_standard/74406539.html)
expresses its interval through TIME. Timer resolution and cyclic observation
both constrain what a check can distinguish. Do not assume that an arbitrary
sub-millisecond neighbor of a TIME threshold is a representable test input, or
that a sampled transition occurs at an exact wall-clock instant.

Keep three durations distinct: the subject's required deadline, the scenario's
observation endpoint, and the framework timeout that prevents the scenario from
hanging. Choose and justify them from their different responsibilities. When a
subject must time out after 50 ms, checking its final state at 150 ms can detect
an absent timeout but does not prove the exact 50 ms threshold or exclude an
early timeout. Those claims require suitable observations on the relevant sides
of the boundary. Do not silently widen acceptance to accommodate scheduling or
make the framework timeout serve as the expected subject outcome.

Reason from nested work upward when selecting supervision: the subject's
deadline, the scenario's observation and cleanup endpoints, its Test Case bounds
and relevant parent scheduling/resource waits. Serial and parallel arrangements
have different duration bounds. Do not blindly add every child limit or increase
a timeout merely to conceal an unexplained delay.

An expected subject Error can be the correct observation of a successful test.
Compare it through Assertions rather than report a framework Error merely
because the subject entered its specified error state. Apply the
[observation-condition patterns](#establish-the-conditions-for-a-meaningful-observation)
to distinguish a justified sampling constraint from an invented acceptance bound
and to define the interpretation of a missing observation.

### Test priorities with reachable competing conditions

Use state and input combinations the subject can actually encounter. In the
illustrative sequence, Reset with Request, Reset with invalid Timeout, and
Feedback on a call where the deadline is also due distinguish defined priorities.
Expected winners come from the subject requirements; framework request priority
does not define an unrelated subject's priority.

A test of coincident conditions must establish both conditions at the relevant
decision point. An uncontrolled delay followed by Feedback TRUE does not by
itself prove that the timeout was due. A deliberately suspended-call fixture can
probe that priority for a passive software subject when its timer behavior across
the gap is established. Label that call-model exception and its verification
limits; do not transfer it to equipment that needs continuous calls. If the
required timing cannot be controlled or observed, state the coverage gap rather
than write private state or invent an expected winner.

### Distinguish cleanup, another run and PLC reinitialization

Specify what is restored after success, failure and interruption: actual subject
commands, edge/timer history, scenario progress, captured samples and checking
components. Reset of an owned fixture uses its supported operations; clearing a
test's phase field does not reset a nested FB. Ordinary lifecycle Reset preserves
the framework's identity and composition. Assertion reset is deferred to a
regular call with valid bindings, as described in
[Assertion reset](assertions.md#call-reset-and-aggregate-through-the-test-case).

A framework Abort is not automatically a command on the subject. Define the
owned resource cleanup even when the subject has no Abort input. For the passive
example, its supported Reset provides cleanup; this does not establish a safe
cancellation procedure for a real actuator. Serial normal execution alone does
not prove that shared Reset or Abort actions cannot overlap.

Another run of the same initialized instances checks whether execution history
was restored. A PLC restart that reconstructs memory can hide that defect.
Conversely, lifecycle Reset does not validate PLC reinitialization after a setup
change. Follow the application's documented
[startup trigger and initialization order](run-control.md#plc-program-startup-and-cyclic-wiring);
normal PLC Stop/Start is not a substitute for this framework's reinitialization
path.

### Qualify the evidence and omissions

A source-reviewed call trace is a design argument. Compilation establishes
interface integration; it does not show that a timer advanced, an interruption
was cleaned up, or a second run succeeded. State which traces and outcomes
actually ran. Select additional temporal paths for meaningful risks, rather than
multiply every state/input/history combination solely for a coverage count.

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

When the behavior still needs analysis, request a proposal before code:

```text
Analyze [block and source revision] and propose a useful behavioral test set.
Read the supplied declarations, implementation and relevant callers/dependencies.
Known requirements and accepted behavior: [provide what is known].
Scope and resource restrictions: [identify the relevant boundary].

Explain responsibilities, retained history, dependencies and observable effects.
Separate specified behavior, observed implementation and unresolved intent.
Select meaningful partitions, boundaries, decisions and state/recovery sequences;
explain omissions and the faults each proposed scenario should distinguish.
For each scenario, state its basis, setup, stimulus/call order, independent
expected observation, unsuccessful endpoint and relevant cleanup.
Identify missing control/observation and open decisions before proposing a fixture.
Do not generate tests, change production code or adopt undocumented behavior
as the correctness criterion. Use the matching Tc3UnitTest guide for feasibility.
```

A missing testable abstraction does not prevent understanding the block or
proposing scenarios. Explain which observations can be implemented directly and
which require an agreed binding, dependency double or interface change.

For already-agreed intent, the following implementation brief can be used with
an assistant that can read the relevant documents and declarations:

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

For an analysis request, expect a concise behavior inventory, evidence-backed
scenario selection, independently justified observations, meaningful omissions
and the material decisions still needed. Identifying a useful test does not
claim that its fixture is already implementable or that the test ran.

When assessing AI-assisted test quality, distinguish the supplied intent and scenarios, the assistant's initial proposal and later changes after owner feedback. Preserve the initial proposal when evaluating test derivation. A collaboratively refined solution may be useful and correct without proving independent initial test selection. Record prior knowledge of reference solutions; do not describe such a walkthrough as blind evaluation.

For agreed implementation work, expect a coherent implementation of the requested
scope, not detached method fragments with missing ownership:

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

Verify that the chosen Assertion expresses the actual question. Observation Enable, explicit Evaluate and ObserveFirstCycle are not interchangeable. The scenario must not complete before the intended check, wait only for a successful result or hide an Error by replacing it with Failed/Passed. Use the [observation-condition patterns](#establish-the-conditions-for-a-meaningful-observation) to check relevant prerequisites, same-call phase changes, reset processing and justified sample boundaries; do not add irrelevant fixture machinery.

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
