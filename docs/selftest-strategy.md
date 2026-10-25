# Framework Selftest Strategy

Status: Active

This document defines the PLC-side selftest approach for TC3 UnitTest. It describes test ownership, structure, execution, and evidence without defining individual test intent.

## Purpose

Framework selftests validate TC3 UnitTest with the framework's own Test Cases, Assertions, Test Suites, Run Control, lifecycle handling, and Event Stream. They do not introduce a second PLC test protocol or an independent assertion framework.

Component-focused tests and end-to-end tests form one selftest system. Their distinction is a matter of test scope and organization, not separate infrastructure or result handling.

## Placement

Selftest logic is stored below the `SelfTests/` area of the authoritative development PLC project:

```text
SelfTests/
├── RunControl/
├── TestSuites/
├── TestCases/
└── TestDoubles/       optional and created only when justified
```

Executable composition remains below `Runtime/`. It binds the Selftest Run Control, performs the required initialization and configuration, and calls the test application cyclically. It must not own framework test intent or duplicate Selftest logic.

Selected selftests also serve as executable usage examples alongside the framework bases and their interface documentation. No separate example objects or copy templates are required.

## One Selftest Hierarchy

The initial selftest application has exactly one top-level Selftest Run Control. It binds both component-focused and integrated suites.

Component-focused coverage includes:

- Assertions and result utilities;
- public status projections;
- integrated Test Case and Test Suite base lifecycles, including single-state and multi-state cases;
- Test Case and Test Suite Orchestrators;
- Run Control behavior;
- Event creation, buffering, reservation, release, reset, and loss handling.

Integrated coverage includes complete Test Case, Test Suite, and Run Control lifecycles and verifies their result, aggregation, command, timeout, abort, reset, and event interaction.

The top-level Suite execution is initially serial and deterministic. Tests of parallel and parallel-slot Orchestrators create concurrency only inside their controlled test arrangement. They do not require the complete Selftest run to execute Suites concurrently.

## Framework-Native Evaluation

Selftests use production UnitTest mechanisms. They do not publish an additional bootstrap GVL, result DUT, or PLC/PC contract.

The normal framework contracts govern commands, lifecycle state, results, aggregation, and Event Stream evidence. The Event Stream is the authoritative evidence for automated completeness and result evaluation.

The fact that the framework tests itself is intentional. Confidence is established through contract-derived expectations, focused boundary tests, deterministic execution, implementation review, and integrated lifecycle and event verification rather than through a second PLC-side testing framework.

## Test Isolation

Each Test Case owns its DUT instances, test state, and test data locally by default. Setup and reset use the normal Test Case lifecycle and Preparation concept.

Selftests must not depend on residual state from a preceding Test Case or on incidental Suite execution order. Shared mutable test state requires an explicit justification and deterministic ownership and reset behavior.

TwinCAT interfaces, inheritance, methods, and local FB instances may improve controllability without exposing production internals as public mutable APIs. Deliberate protected dependency seams are permitted for thin derived test adapters; they do not justify exposing arbitrary internal state.

For isolated Assertions, use their concrete production types and public BindPublisher with a local capture publisher before initialization diagnostics or findings can occur. Zero assignment leaves the existing binding unchanged. Keep derived Assertion subjects only for genuine controlled behavior or additional observations; they inherit the same binding method. Other framework subjects still use adapters that assign protected FEventPublisher before first use. The surrounding selftest framework continues to use its normal result publisher. Production processing is used unchanged, not mirrored. Dependencies of composed children/helpers remain the responsibility of the controlled test arrangement; there is no automatic hierarchy-wide binding propagation or global publisher switching around calls. The public read-only EventPublisher property and the Assertion-specific binding API follow framework-architecture.md.

Suite and Run Control test adapters bind protected FOrchestrator : I_Orchestrator before owner initialization. The base initializes, invokes and observes that same selected helper. A thin adapter derived from the real Orchestrator binds its own protected FEventPublisher before first use; it inherits production processing unchanged. An interface double may instead isolate the owner from real scheduling. Overriding an owner call alone is not the substitution mechanism. The normal default composition remains available without application-supplied helpers. A Run Control subject's administrative Event Buffer and publisher must refer to the intended same service; the test arrangement supplies that consistency without additional production binding management. Individual Run Control/Event Buffer subjects are local test objects, not additional top-level selftest runners or published communication endpoints.

Run Control communication subjects use local `ST_RunControl` storage at the cyclic `ControlData` argument. Command-adapter tests initialize the adapter with that local storage and use its `Cmd` field for cyclic calls with a small `I_RunControl` double that records requests without reproducing the owner lifecycle. Verify startup clearing of all lifecycle commands, Buffer Reset and the Delete watermark, preservation of Name and Status, and cleared qualification history without owner requests or Event Buffer operations. Initialization must work before the first cyclic adapter call. Commands supplied afterwards still require two consecutive samples. Combined scenarios initialize the adapter before the Event Buffer and hierarchy, then call it before the concrete Run Control each cycle. They inspect the local projection and isolated event evidence without changing the surrounding selftest runner's global communication storage or publisher.

Communication verification covers qualification across consecutive calls, writes around sampling boundaries, simultaneous and mixed OOP/signal requests, PLC-owned command clearing, passive uninitialized processing, and status refresh through Completed and Reset. Source traces and offline compilation are preparation for these scenarios, not evidence that asynchronous transport or runtime integration has passed.

## Test Doubles

Test Doubles are optional. A small double used by one test remains local to that test area. A shared `TestDoubles/` folder is created only when multiple tests need the same controlled implementation.

Fakes, stubs, and mirror-like implementations all belong to the same Test Double concept. A mirror of production behavior is a last resort because it can diverge from the implementation it represents. Every shared or mirror-like Test Double must state:

- the production boundary it substitutes;
- the behavior it controls;
- why a local instance or normal interface implementation is insufficient;
- how divergence from the represented production behavior is detected or avoided.

## Selftest Development Rule

Before the first Selftest slice for a framework block or coherent block family:

1. analyze the current implementation and its public and internal boundaries;
2. compare expected behavior with the authoritative contracts and architecture;
3. identify nominal, boundary, invalid-configuration, timeout, abort, reset, and state-transition cases that apply;
4. identify required event and aggregation evidence;
5. align any uncovered contract, architecture, or testability decision with the project owner before encoding it as an expectation.

Implementation behavior alone is not the specification. Existing behavior that conflicts with an authoritative contract is reported rather than silently copied into the Selftest expectation.

Selftests are developed with behavior-complete vertical framework increments. A new component is not considered validated merely because it compiles; the relevant focused and integrated Selftest slices must accompany it when their dependencies exist.

Exhaustive combinations are added only when they represent distinct behavior, a boundary, or a concrete regression risk.

## Runtime And Automation

The Selftest PLC application starts in a defined reset state and is controlled through the normal Run Control contract. Configuration and cyclic execution remain logically separate.

The repository build can compile the Selftest application without changing a runtime. Runtime execution is an explicit additional step governed by the deployment and runtime safety rules in [Build And Validation Workflow](build-workflow.md).

A successful compile-only build must not be reported as a successful Selftest run. Automated Selftest execution must record the selected XAR build line and evaluate the complete framework result evidence.

## Version Coverage

Build 4026 is the Selftest development and runtime target.

Version-specific Selftest forks are not maintained. A version-specific harness adaptation is permitted only when required by verified engineering or runtime behavior and must not change the tested framework semantics.
