# Apply authoring practices

Use this reference when choosing scenario boundaries, extracting reuse, designing a fixture or reviewing generated tests. It is an AI authoring aid for applying existing guidance, not another framework specification.

Use [framework resources](framework-resources.md) to locate the matching `docs/authoring/ai-assisted-framework-authoring.md` in the packaged framework resource root, a matching checkout or equivalent offline help. Use its `#review-a-source-backed-block-analysis` section to review the source-backed understanding record and evidence limits; use `#derive-a-useful-test-set` for behavior boundaries, technique selection and independent expectations; use `#prioritize-a-proportional-plan-and-explain-omissions` for essential questions, representative selection, consolidation across variants and the stopping criterion; use `#design-cyclic-and-temporal-tests` for call traces, signal history, clocks and recovery. Its `#applied-authoring-practices` section owns the concrete reuse and fixture explanations. Read only the sections relevant to the request, then the responsible concrete chapter before implementing its pattern; resolve current declarations rather than treating an example name as a supplied API.

Use these questions to make the design concrete:

| Decision | What to establish before choosing |
| --- | --- |
| Another group or already represented | Which essential question or material risk does it add? Could an existing group or targeted variant check cover it without losing an identifiable observation? Stop at the justified core; explain meaningful gaps briefly. |
| One scenario or several | Is this data variation within one coherent behavior, an ordered interaction, or an independent state/history, ownership or recovery scenario? Preserve the initial/reset boundary and identifiable failures. |
| General, resource-family or dedicated | What behavior stays fixed across a second real binding? Which values and references vary? What additional modes or dependencies would abstraction introduce? |
| Preparation or test action | Is the action establishing a prerequisite, or is its effect what the test must evaluate? Do not use the subject's successful behavior as an untested prerequisite for that same behavior. |
| Call and observation order | Who owns stimulus, DUT execution and sampling? Which call can first observe the changed input, does ObserveFirstCycle preserve that observation, and what actually advances time? |
| Completion on failure | What ends the observation if the expected response never occurs? Does the intended Assertion evaluation finish before CompleteTests/NextTestState changes phase? Distinguish a mismatch from fixture/configuration error without weakening either. |
| Reset and another run | Which actual nested state, command history and stored observation must return to baseline? Is the checking Assertion's queued reset processed? |
| Independent oracle and diagnosis | What accepted behavior supports the expectation? Are literal examples, mathematical relationships or a reference model independent of the subject algorithm, with justified assumptions/tolerances? Which plausible observable fault would this scenario or coherent group distinguish? |

Use the answers in the ordinary test plan or implementation explanation; do not create a separate mandatory questionnaire for an already-defined small scenario. Apply only relevant decisions. A stateless classification function needs no invented resource lifecycle, and an intentionally dedicated test needs no forced generalization.

## Move from behavior to an executable scenario

For the selected behavior, connect the accepted expectation to representative partitions, meaningful representable neighbors or reachable decision/state/history sequences. Explain the distinguishing observation and a plausible behavioral fault; do not require one test per branch or an artificial test for an observationally equivalent source change. Hypothesized detection remains analytical until challenged in execution.

Distinguish missing intent from missing source or fixture evidence. Ask about a consequential priority, deadline, error response or resource effect before encoding it; ordinary representative values inside an agreed domain need no repeated approval. Neither current output nor an invariant that permits a meaningful wrong result is a sufficient oracle by itself.

Choose a point sample, sampled interval or ordered history from the actual question. State stimulus, owner call and observation order. In an external-call arrangement the application owns and services the real subject outside the test hierarchy; the Test Case only controls supported stimuli and observes feedback. Use the actual public communication model: a real-instance/interface binding, or Control/status structures consumed/produced by the subject. A reusable Test Case may expose its own binding method; select the concrete resource in its owning Suite configuration without forwarding that method through every ancestor. Do not put a per-field mirror around a different subject API. One-shot command receipt may clear the shared bit; held signals retain their specified semantics. Derive cycle latency and cleanup confirmation from that arrangement instead of adding another subject call or assuming same-call effects. Keep servicing when the resource requires it after active test hooks stop.

Define a finite unsuccessful endpoint for waiting scenarios, then complete or advance after the intended evaluation even on mismatch. Preparation establishes prerequisites rather than proving the tested effect. Single-state, multi-Teststate and short internal stepping are choices based on useful phase visibility and cohesion; none is universally required. Preserve inherited hooks, same-call phase changes and the regular valid calls that consume deferred Assertion resets.

Plan timeout supervision from the actual nested work upward: subject deadline, observation/cleanup endpoint, Test Case supervision and relevant parent scheduling. Account for the chosen serial/parallel behavior and resource waits. Do not add all child limits blindly, inflate a bound from observed slowness, or treat framework timeout as the expected subject response. An exact numeric bound that affects acceptance needs a justified basis.

## Establish a valid observation

Use the guide's `#establish-the-conditions-for-a-meaningful-observation` section
when arranging a selected scenario. It owns the worked patterns. Record relevant
given conditions, test-established conditions and unresolved assumptions in the
ordinary plan, preserving the entry's four evidence categories. Apply the
following actions only where the scenario needs them:

- Direct value: capture the actual sample, perform the intended direct check in
  ProcessAssertions, then complete/advance after that check even on mismatch.
  A phase change in ProcessTests can change the following hook's Enable/State.
- External command: trace receipt, subject execution and feedback before choosing
  ObserveFirstCycle. FALSE skips the first sample after each disabled interval;
  it is not a settling timer and can suppress a one-call check entirely.
- Collection: choose the last included sample and family-specific Evaluate
  before phase completion. Preserve valid inputs for explicit evaluation; neither
  held Passed nor EvaluationActive universally proves collection is finished.
- Time range: align clock origin, resolution and call order with the claim.
  A chosen sample point does not justify an extra upper bound. A missed required
  sample needs explicit diagnosis; a later correct value cannot establish it.
- Another run: restore the real baseline and reset completion flags. Process
  queued Assertion Reset on a regular valid call that does not also check, then
  follow the family's actual baseline/history rules.
- Supervision: fit the finite path to ST_TestCaseConfig.Timeout, each Preparation
  state's PreparationTimeout, and cleanup ResetTimeout/AbortTimeout. Reuse
  suitable defaults; do not invent fixed margins or substitute framework timeout
  for the subject's expected response.

Preparation Ready does not establish its Completed target. Check relevant
binding/configuration, data lifetime, units and comparison resolution without
requiring elaborate setup for a simple function. Compare actual typed data, not
rounded diagnostics. Ask about consequential missing acceptance/interpretation
facts, not routine choices inside an established valid domain.

Do not classify the absence of the subject response being tested as a fixture
precondition failure. Conversely, do not treat an unusable observation as proof
of a subject defect. Use existing documented framework outcomes and diagnostics;
do not silently pass, skip the intended check or invent a new result state.

## Choose dependencies and check doubles

Prefer the real dependency. Use a small local double only when a specific necessary rejection, failure, timing or other response cannot practicably be controlled through the real dependency. Keep the real subject under test. Identify the modeled behavior, its accepted specification and consumed version, and the real integration claims the substitute cannot establish.

Propose or implement safeguards within the authorized scope:

- Where feasible, run the same relevant boundary checks with independently justified expectations against both the real dependency and the double.
- Retain focused checks using the real dependency for the actual binding/interaction; a substitute-only test cannot establish them.
- Review and repeat the applicable comparisons when the dependency or relevant contract changes. Interface/compiler checks catch signature changes, not behavioral drift.

Apply comparison only to behavior the double claims to reproduce. A deliberately injected fault need not match ordinary real-device behavior. Never build expected values by copying either implementation, and do not construct a mirror of the whole dependency merely to claim compatibility. If real comparison is unavailable, report that evidence gap; these safeguards reduce divergence risk, not guarantee future equivalence.

## Apply existing framework patterns

Use the guide's examples as evidence for the selected shape. A repeated-Reset scenario can justify related temporal steps; a target-condition Preparation can justify binding reuse; an Assertion reset test can show the regular-call reset requirement. None authorizes replacing the supplied lifecycle with another platform's implementation, broadening an INTERNAL API, sharing mutable fixtures or assuming all resources have the same reset semantics.

Before calling a design reusable or repeatable, compare the claimed evidence with the actual second binding and repeated execution. Source analysis can justify suitability, but must not be presented as executed proof. If an example conflicts with the current contract, report that discrepancy rather than silently promoting the example into a rule.
