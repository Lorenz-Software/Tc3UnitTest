# Understand a block and its dependencies

Load this reference for source-based analysis before selecting tests, or for a requested white-box review. It implements the evidence distinction in [the skill entry](../SKILL.md#establish-what-is-known). It does not require a particular project layout, test fixture or source-analysis tool.

## Establish the inspected source

Identify the requested subject and public boundary, its revision and the available requirements. Keep the subject's source inputs separate from reference-test solutions or evaluation answers when evaluating the skill. An existing test is observed evidence, not an independent oracle merely because it passes.

Use saved native XML, supplied ST or available read-only engineering access. Record the actual source set:

- For a project, use its Compile entries and library references to distinguish compiled sources from loose files. Do not silently evaluate conditional/imported project items or conditional ST when the selected configuration is unknown.
- For individual files or snippets, identify the supplied members and missing context; do not imply whole-project coverage.
- For saved sources, retain the commit and relevant working-copy differences, or another reproducible snapshot identity. For live sources, identify the native object and reconcile with disk when both are available. Report disagreement instead of combining different versions as one implementation.
- An object GUID or TwinCAT XML format version is not the version of its behavior. Separately supplied library source must match the consumed library before it can establish that binary's implementation.

Missing engineering access does not prevent saved-source analysis. Missing bodies, callers or configuration narrow the conclusions; name the affected behavior rather than blocking unrelated analysis.

## Navigate from the public boundary

Read declarations and relevant bodies together. Include main execution, methods, property Get/Set bodies and actions that participate in the behavior. Separate persistent instance/history storage, temporary values, referenced storage and shared state; FC/FB classification alone does not establish retention or isolation.

Use the existing access path that exposes the needed evidence:

- Files: parse the native XML structure to distinguish declarations, main ST and nested members. Follow member nodes and FolderPath rather than treating editor folders as separate source files. For plain ST, preserve supplied unit/member boundaries.
- TE1000 MCP, when available: use find/tree for identity and nested members, then get_decl/get_impl or get_document for the relevant code. Recurse through method folders; a top-level outline may show only a folder. A namespaced base name identifies another type to inspect, not an inherited implementation already read.
- Search: locate callers, names, assignments and type uses, then inspect the surrounding code and receiver declaration. Search hits can come from comments, literals, unrelated scopes or declarations. Check caps/truncation and cache freshness before using the results to support coverage; refresh a live search when needed.
- Existing inventories/API models: reuse them for membership and declaration navigation when available. Check their supported syntax and omissions against the originals, especially qualified type names and private members. A public API model is not a complete implementation inventory or semantic call graph.

Do not require the documentation toolchain to read a supplied block. No additional parser/helper is needed solely to restate facts already available through these paths. A recurring evidence/navigation gap can justify a narrow helper; keep its output distinguishable from agent reasoning.

## Explain execution and relevant effects

Follow the actual order of guards, statements, branches and calls. Identify which conditions can hold together, which wins, what persists and what the caller observes after the call. Distinguish a request that stores intent from the later cyclic action. Explain critical paths, not every statement.

For a cyclic/stateful subject, trace the relevant phases: initial values or explicit initialization, ordinary execution, interruption/error handling, recovery and another use. Include changes made before a guard or RETURN, deferred work and the effect of disabling or skipping calls. Do not assume Reset, re-enable, PLC Stop/Start and a newly initialized instance have identical effects.

For timing, identify the called timer/clock, who calls it, the time unit, sampling points and known task/call order. Distinguish supplied requirements, source-visible ordering and unresolved clock/dependency behavior. A call count does not establish elapsed time; a timer name does not establish its resolution or behavior across call gaps.

Inspect relevant arithmetic/conversions, string/array bounds, pointer/reference/ANY operations and borrowed-storage lifetime. Explain the concrete possible effect and the evidence needed for it; do not invent out-of-contract races, malformed bindings or impossible input values merely to create failure scenarios.

Record visible reads/writes and effects, including GVLs, I/O, communication, event publication and delegated operations. State which values a test can control and which observations are available. A blocked observation can be an open fixture question; it does not authorize changing the production interface.

## Follow the dependencies that explain behavior

For each relevant edge, retain the source member/call site, receiver or storage identity, why it matters and one disposition:

| Disposition | Meaning |
| --- | --- |
| Reviewed | The needed body, binding or value was inspected; say which part was established. |
| Unresolved | The required implementation, target, version, configuration or other evidence is missing or ambiguous. |
| Outside the chosen boundary | Explain the exclusion and its consequence for the conclusions. |

Trace these cases where applicable:

| Dependency | Evidence to inspect |
| --- | --- |
| Direct call or owned FB | Resolve the declaration/type and relevant body. Include retained nested state and arguments/storage effects; a method call and an FB body call are different execution points. |
| Inheritance | Follow EXTENDS to the base and its relevant bodies, then the concrete overrides and SUPER calls. Show the base-to-hook call path. Reading only a derived SUPER^() body or only an abstract hook declaration is incomplete. |
| Property | Inspect the used accessor. A read can execute code and have dependencies or effects; do not assume a getter is a stored snapshot. |
| Interface dispatch | Follow the receiver's assignments, initialization/configuration, registration/lookup and relevant callers to identify supported concrete targets. An interface declaration or a list of implementers alone does not establish which one is bound. |
| DUT, constant or parameter | Resolve shape, bounds and applicable value/override where they change behavior. Do not evaluate an unresolved expression or library parameter as a fixed literal. |
| Shared or external state | Inspect writers and ownership where they affect the requested behavior. With missing writers/task context, report the uncertainty rather than claiming isolation. |
| External library/service | Record identity/version evidence and the behavior relied on. Declarations establish a boundary, matching documentation can specify it, and available matching source can explain implementation. None alone is runtime proof. |

Follow only the dependency depth needed to explain the requested behavior and risks. Stop an edge when the relevant fact is established, intentionally excluded with reason, or explicitly unresolved. Do not recursively inventory an entire library without a behavioral reason. Multiple possible interface/alias targets remain alternatives unless source evidence narrows them.

Textual ST is the demonstrated analysis path. A graphical/IL body, unavailable implementation, unknown conditional selection or pointer/alias-dependent target may require additional evidence and review. Do not silently treat it as an empty body or resolved dependency. Available portions can still be analyzed with that limit.

## Return a proportional understanding record

Use ordinary prose or a compact table in the requested answer/test plan; do not create a mandatory extra document or fixed schema. Combine these parts for a small function and expand where the behavior requires it:

| Part | What the reader needs |
| --- | --- |
| Subject and evidence boundary | Responsibility, interface/member, inspected revision/snapshot, actual source set and missing context. |
| Behavior and usable boundary | Input/configuration domains, observations/effects, retained state, priorities and sequences, time/call model, initialization/recovery and available control/observation. |
| Dependencies | Relevant edges and their reviewed/unresolved/excluded disposition, including base/override and binding evidence where applicable. |
| Critical areas and test implications | Reachable risks and meaningful observable distinctions, with requirement basis or open decision for candidate expectations. |
| Open questions and limits | Uncertainty/conflict, consequence and needed source/decision/check; what source, compiler and runtime evidence actually exists. |

Use the four evidence kinds from the entry. Explicitly label an unconfirmed hypothesis as Unresolved and say how it could be settled. Proposed characterization instead means an observed behavior proposed for intentional preservation; it still needs acceptance before becoming a correctness criterion. A claim can have separate specified and observed support; show conflict when they differ. Inline implementation comments do not automatically establish accepted intent.

Cite the supporting file/native object, member/section and line or bounded range, tied to the inspected source identity. Distinguish XML-file coordinates from declaration/body coordinates returned by a tool. A shared source list is enough; no repeated hash per sentence or numeric confidence score is needed.

For example, a short clamping function can be explained by its required range, typed boundary, complete comparison/return body, relevant constants and absence of state/time/effects in the inspected code. A feedback sequencer needs additional evidence for edge history, Reset/error priority, timers and held/recovery states. Neither example requires a test per branch or a preselected framework fixture.

End with what is understood and which unresolved items affect an expectation or feasible test arrangement. For the human review explanation and subsequent scenario selection, use [applied authoring practices](authoring-practices.md) to locate the matching guide sections. Do not claim complete transitive coverage from a successful search/inventory, treat current outputs as correctness requirements, or present source reasoning as executed verification.
