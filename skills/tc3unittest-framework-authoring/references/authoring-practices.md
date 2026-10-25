# Apply authoring practices

Use this reference when choosing scenario boundaries, extracting reuse, designing a fixture or reviewing generated tests. It is an AI authoring aid for applying existing guidance, not another framework specification.

Locate the matching guide's `docs/authoring/ai-assisted-framework-authoring.md#applied-authoring-practices` from the framework checkout root or its equivalent offline help chapter. That section owns the explanatory practices, applicability and examples. Read the relevant concrete chapter before implementing its pattern; resolve current declarations rather than treating an example name as a supplied API.

Use these questions to make the design concrete:

| Decision | What to establish before choosing |
| --- | --- |
| One scenario or several | Is the sequence itself the requirement, or are independent behaviors being combined? Show the initial/reset boundary and how a failure is identified. |
| General, resource-family or dedicated | What behavior stays fixed across a second real binding? Which values and references vary? What additional modes or dependencies would abstraction introduce? |
| Preparation or test action | Is the action establishing a prerequisite, or is its effect what the test must evaluate? Do not use the subject's successful behavior as an untested prerequisite for that same behavior. |
| Call and observation order | Who owns stimulus, DUT execution and sampling? Which call can first observe the changed input, and what actually advances time? |
| Completion on failure | What ends the observation if the expected response never occurs? Distinguish a mismatch from fixture/configuration error without weakening either. |
| Reset and another run | Which actual nested state, command history and stored observation must return to baseline? Is the checking Assertion's queued reset processed? |
| Independent oracle and diagnosis | What supports the expectation besides the current implementation? Can a reviewer identify the failing condition and its observed/expected values? |

Use the answers in the ordinary test plan or implementation explanation; do not create a separate mandatory questionnaire for an already-defined small scenario. Apply only relevant decisions. A stateless classification function needs no invented resource lifecycle, and an intentionally dedicated test needs no forced generalization.

Use the guide's examples as evidence for the selected shape. A repeated-Reset scenario can justify related temporal steps; a target-condition Preparation can justify binding reuse; an Assertion reset test can show the regular-call reset requirement. None authorizes copying S7 lifecycle templates, broadening an INTERNAL API, sharing mutable fixtures or assuming all resources have the same reset semantics.

Before calling a design reusable or repeatable, compare the claimed evidence with the actual second binding and repeated execution. Source analysis can justify suitability, but must not be presented as executed proof. If an example conflicts with the current contract, report that discrepancy rather than silently promoting the example into a rule.
