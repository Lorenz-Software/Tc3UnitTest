---
name: tc3unittest-framework-authoring
description: Derive and review behavioral unit-test plans for existing PLC blocks, then implement agreed scenarios with Tc3UnitTest. Use for test selection, reusable Test Cases and Preparations, or framework-conforming test composition. Does not build, deploy, control a PLC runtime or define production requirements.
license: MIT
metadata:
  version: "1.0.0"
  framework-library: "Tc3_UnitTest"
  framework-version: "1.0.0.0"
  framework-namespace: "Tc3UnitTest"
---

# Tc3UnitTest Framework Authoring

For matching framework resources and compatibility limits, use [framework resources](references/framework-resources.md). Load only the relevant guidance/API entries when implementing framework tests.

Support two entry points: derive a test plan from an existing block, or implement/revise already-defined test intent. Do not force rediscovery for an implementation-only request. Stop at a plan when only analysis was requested.

## Establish what is known

Identify the tested subject, version, public boundary and requested test scope. Inspect relevant declarations, callers and dependencies where they affect state, timing, ownership or observability. Do not equate FB with stateful or FC with stateless without checking relevant dependencies.

For source-based block understanding or white-box review, load [block and dependency analysis](references/block-analysis.md). It supplies the source-navigation procedure, proportional analysis record and explicit coverage limits. Use the available files or read-only engineering access; no particular MCP server, documentation generator or pre-existing test fixture is required.

Keep four kinds of evidence separate:

- **Specified:** expected behavior supported by a requirement or contract.
- **Observed:** behavior found in implementation, callers or an existing test.
- **Proposed characterization:** observed behavior that could be intentionally preserved, pending acceptance.
- **Unresolved:** missing or conflicting intent, bounds or integration facts, including explicitly labeled hypotheses that still need evidence.

Source inspection can reveal test candidates without a complete specification. It cannot establish that a current return value is correct. Existing tests provide useful experience and regression intent; check their expectations against the applicable specification. Report conflicts instead of silently choosing either source.

Ask a focused question when a missing fact changes expected behavior, resource effects or the meaning of a test. Explain the consequence and propose options. Continue independent analysis. Do not turn every ordinary test parameter or internal organization choice into a new approval gate; reuse intent already agreed for the task.

## Derive the useful tests

Start from the essential observable behavioral questions and material risks, then select scenarios before Assertions. Reuse defined intent directly; do not repeat discovery for settled questions. Consolidate candidates before presenting the recommended core. An additional group needs a relevant distinction, boundary, history/failure path or credible independent implementation risk not already addressed; another equivalent value alone is insufficient.

Compare implementation/type variants as well as input classes. Use a deeper representative matrix plus targeted checks for genuine differences where justified; similar source alone does not establish equivalence. Preserve meaningful precision/range, storage/conversion and separate implementation risks. Stop adding cases when essential behavior and selected material risks are addressed and further candidates add no material distinction. Explain grouped redundancy and material gaps briefly; do not produce a mandatory optional-test catalogue or per-row worksheet. For implementation-only requests, preserve agreed scenarios and propose any material reduction rather than silently change scope.

Map observable behaviors to scenarios before selecting Assertions. Consider applicable input partitions and boundaries, configuration errors, modes, state transitions, call sequences, edges, timing, initialization and recovery. For a pure function, omit irrelevant lifecycle machinery. For a cyclic block, a single input/output sample rarely expresses the whole scenario.

For each meaningful behavior, identify:

- a traceable requirement, accepted characterization or open decision;
- starting condition and owned stimulus;
- call/sample sequence and independently justified expected observation;
- an explicit completion condition, including when the check fails;
- isolation, Reset/Abort and repeated-run needs where relevant;
- its test or a visible gap, with reason and consequence.

Use compact prose or a matrix proportional to the task. Use no fixed test quota, one-test-per-branch rule or all-combinations mandate. Group data variations within a coherent scenario when the failing observation remains identifiable; keep independently meaningful state/history, ownership and recovery scenarios separate unless their interaction is the behavior being checked. Fewer Test Case FBs alone is not evidence of a better plan.

Trace each expected observation to an accepted requirement, owner decision or explicitly accepted characterization. A source comment, passing existing test or alternate implementation alone does not settle intended correctness. Keep an unresolved candidate visible until the consequential decision is made; continue independent work.

Derive expectations from the required relationship, accepted examples or another justified independent oracle. Reimplementing the tested algorithm inside the test risks reproducing its defect. An implementation branch may suggest a boundary worth testing; it does not authorize a new acceptance criterion. Distinguish unit, dependency-integration and actual environment/hardware checks.

Make the claimed observation feasible: identify relevant given conditions, what the test must establish and unresolved assumptions without turning fixture choices into subject requirements. For framework-specific actions, use the [observation-condition patterns](references/authoring-practices.md#establish-a-valid-observation) covering check-before-completion order, command handover/ObserveFirstCycle, collection/Evaluate, sampling bounds, deferred Reset and the separate supervision values. Apply only relevant patterns. A missed sample must not silently pass, and an absent expected response must not be dismissed as invalid setup.

For time-dependent behavior, identify the actual time source, resolution, task/call order and relevant bounds. Repeated calls do not necessarily advance time. Justify added observation-window limits separately from a chosen sample point; do not invent tolerances or extend deadlines to make a failing test pass.

Use real dependency implementations by default. A double is a narrowly justified exception for a dependency, never a substitute for the subject whose behavior is claimed. Explain the unavailable control/observation, scope the substitute and propose applicable independent safeguards against behavioral drift as described in [applied authoring practices](references/authoring-practices.md#choose-dependencies-and-check-doubles).

For concrete technique selection, worked examples, cyclic test design or reuse/fixture decisions, use [applied authoring practices](references/authoring-practices.md) to locate the matching guide sections. Select the relevant decisions; do not require every technique or practice for every test.

## Design for reuse with clear ownership

Search the available tests, Preparations and helpers before creating another type. Record the stable scenario or target condition separately from varying resource bindings, stimuli, expectations, limits and durations.

Choose the narrowest useful scope:

- **Generally reusable:** a coherent behavior expressed through a small common interface.
- **Resource-family:** a stable typed dependency shared by related resources.
- **Dedicated:** a deliberate concrete binding when generalization would add complexity without useful reuse.

Do not prefer generality at the expense of understandable behavior. A Preparation establishes a starting condition; it must not hide the behavior being tested. No Preparation is needed when the scenario already has a simple, controlled starting condition.

Expose varying bindings and scenario parameters without adding mode switches for unrelated behaviors. Reuse existing production interfaces where appropriate; do not add test-only fields or expose mutable internals to make a generic test work. Propose any material production seam or abstraction separately.

Reuse types, not mutable execution state. Each concurrent use needs its own scenario progress, Preparation/Assertion instances, identity and cleanup ownership. Shared resources require an explicit access and reset strategy; serial scheduling alone does not establish isolation between runs.

Where reuse is claimed, review a second suitable binding: unchanged scenario meaning, required interface, distinct state, command ownership and repeat/reset behavior. State whether that evidence is source review, compilation or actual execution. A hypothetical second binding is a design argument, not executed proof.

## Hand off accepted intent to implementation

Present unresolved expectations and consequential design choices before encoding them as acceptance tests. Do not silently change tested production behavior or expand the requested scope. If intent is already defined, proceed within it.

For Tc3UnitTest implementation or review, load [framework integration](references/tc3unittest.md). Use the matching Authoring Guide, contracts and actual declarations. Keep the behavioral reasoning independent of editor, MCP, build or runtime access. Missing framework sources/help is a specific information gap, not permission to invent an API.

Review the complete arrangement: fixture/setup, stimulus, tested-object execution, observation, completion, result and cleanup. A failed expectation must produce a diagnosable failed test rather than a scenario that waits for success until timeout. Preserve base-owned lifecycle and event handling.

## Review and report

Reconcile implemented tests with the behavior inventory. Report meaningful omissions, blocked control/observability, reuse choices and practical maintenance cost. Keep bounded cyclic work and visible ownership; avoid fixture frameworks or copied lifecycle state for a small scenario.

Use existing selftests and corrections as experience, not automatic templates or proof for newly generated code. When evaluating a test, explain which representative behavioral fault it should detect. Label an analytical prediction as such; claim fault detection only when the challenge was actually executed.

When assessing assisted test quality, distinguish supplied scenarios from those derived by the assistant and from changes made after owner feedback. Preserve the initial proposal when generation itself is being evaluated. A collaboratively refined, passing solution does not establish independent initial test-selection quality; prior knowledge of reference solutions also limits that claim.

Distinguish saved-source review, completed compiler/static checks and runtime observations. Record relevant failure, reset and repeated-run paths actually exercised. Authoring does not itself authorize deployment, installation, online control or resource writes. If a test fails, investigate the requirement, wiring and tested implementation before changing expectations.
