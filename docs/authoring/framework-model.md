# Framework Model

TC3 UnitTest lets a PLC application execute tests in a TwinCAT runtime and report their outcomes to an external runner. You supply the test intent, resource bindings, stimuli and expected behavior. The framework supplies the common lifecycle, orchestration, result handling and event reporting.

This authoring manual is for PLC developers using the library in their own projects. It assumes familiarity with Structured Text, function blocks and method overrides. Start here to understand the responsibilities before implementing the concrete blocks. Normal usage relies on the supplied bases; it does not require writing another framework state machine.

## Using the packaged library

### Install and reference the library

Use TwinCAT 3.1 Build 4026. Native consumer builds and the bounded lifecycle smoke use the Windows Usermode Runtime and the `Release|TwinCAT OS (x64)` configuration. That evidence does not establish compatibility with other build lines, target architectures or runtime configurations.

1. Obtain the library and offline HTML help from the same release. The regular installation artifact is `Tc3_UnitTest-<version>.compiled-library`; `Tc3_UnitTest-<version>.library` is the source-visible/debug-capable alternative. Choose one format for that library identity/version.
2. In your consuming PLC project's Library Manager, open the Library Repository and install the chosen file into the intended repository. Installation changes the local repository; it does not download a PLC application.
3. Add a reference to `Tc3_UnitTest` from `Lorenz Software`, selecting the intended version. Its default namespace is `Tc3UnitTest`; the examples in this guide use that namespace. A file being present on disk is not the same as an effective resolved project reference.
4. Inspect effective dependencies in Library Manager. The producer uses `Tc2_Standard`, `Tc2_System`, `Tc2_Utilities`, `Tc3_Module` and automatic `Tc3_GlobalTypes`. Exact producer versions accompany the library's build/release provenance; verify resolutions rather than assuming that matching library title/version text proves the same dependency set.
5. Reference `Tc2_System` directly where the startup example uses `GETCURTASKINDEXEX`. A native Empty PLC Project also needs the `Tc3_Module` system reference for its generated task/module context; an existing project template may already provide it. Rebuild after reference changes.

Do not compile another copy of Framework into the application or add the library development project as a reference. SelfTests and the development Runtime composition are not library inputs for your application. You supply concrete test elements, `MAIN` and its cyclic task as described by the following chapters.

Both formats have the same library identity and namespace. Installing both under the same identity/version is not a way to select the format per reference; check the resolved repository/file when changing formats. TwinCAT may store the compiled file with an engineering-specific suffix such as `.compiled-library-ge33`; the original downloaded artifact remains the `.compiled-library` file.

### Configure compile-time parameters

Select the library reference in Library Manager, open its parameter view and edit the consumer values there. Save and rebuild the application. Parameters are compile-time configuration, not ADS commands or runtime-writable fields. Use XAE's parameter editor rather than hand-editing project XML.

| Parameter list | Setting | Declared default | Effect |
| --- | --- | --- | --- |
| `Param_Assertions` | `AssertionStringLength` | 80 | STRING assertion capacity in bytes |
| `Param_Assertions` | `AssertionWStringLength` | 80 | WSTRING assertion capacity in code units |
| `Param_EventBuffer` | `EventBufferLength` | 256 | Physical ring positions; usable occupancy is one less |
| `Param_EventBuffer` | `EventBufferResetHeadroom` | 20 | Shared reset headroom |
| `Param_EventBuffer` | `EventBufferExecutionHeadroom` | 10 | Shared execution headroom |

The API parameter-list pages show the saved library defaults. They do not reflect a consuming project's overrides. `GVL_Constants` contains fixed constants, including protocol capacities and contract versions; it is not another parameter list. Increasing an assertion string capacity does not enlarge its diagnostic value preview or the Event Stream message field.

For example, `EventBufferLength=384` and `AssertionStringLength=96` produce a 384-position ring (383 usable positions) and STRING(96) assertion bindings with either library format. Declare matching application data, for example:

```iecst
VAR
    ActualText : STRING(Tc3UnitTest.Param_Assertions.AssertionStringLength);
    ExpectedText : STRING(Tc3UnitTest.Param_Assertions.AssertionStringLength);
END_VAR
```

`EventBufferLength` supports 3..32767 physical positions; headroom and the complete owner event budgets must fit the chosen capacity. The integrating PLC uses its effective configuration, while an external reader uses the published `EventStream.FifoControl.BufferLength` and live symbol layout. Do not change capacities in a live hierarchy without rebuilding and following the reinitialization procedure in [Run Control authoring](run-control.md#restart-and-online-change).

### Read versions and API visibility correctly

| Observation | Meaning |
| --- | --- |
| Library Manager identity / help About page | Company, title, namespace and four-component library version |
| `GetFrameworkVersion()` and published `FrameworkVersion` | Major.Minor.Build library version without revision |
| Each published `ContractVersion` | Independently versioned Direct Access or Event Stream protocol |
| TwinCAT engineering version | Tool/build environment, not the library version |
| XML `TcPlcObject Version` | Source-file format, not a function block's semantic version |

Per-block semantic versions are not maintained. Match the help package to the library version and use the release provenance for the actual package/source association; matching version labels alone are insufficient.

Public types and protected extension hooks support the normal authoring path. Some internal types appear in the API reference because exported declarations require them. An internal page does not make that type an external extension point: for example, do not declare an application `Stopwatch`. The documented `GVL_EventBuffer.Instance.Initialize` call and passing that same instance as `I_EventBuffer` are supported without directly declaring the internal concrete `EventBuffer` type.

## Finding the right chapter

The manual follows the work from an individual scenario to a complete PLC application:

| Chapter | Authoring task |
| --- | --- |
| Framework model — this chapter | Understand the execution hierarchy, responsibilities, resources, results and reporting. |
| [Test Case authoring](test-case.md) | Implement a scenario, bind the tested logic and supply the required processing hooks. |
| [Preparation authoring](preparation.md) | Establish a resource's starting condition and report its current status. |
| [Assertion authoring](assertions.md) | Select and wire checks, including observation, evaluation, reset and family-specific requirements. |
| [Test Suite authoring](test-suite.md) | Compose Test Cases and select their execution order and concurrency. |
| [Run Control authoring](run-control.md) | Compose Suites and connect initialization, cyclic execution and commands to the PLC program. |
| [AI-assisted authoring](ai-assisted-framework-authoring.md) | Supply defined test intent and review assisted implementations. |

For a new test, define its observable behavior first. Then choose Assertions, add Preparation only if needed, compose the owning Suite and connect that Suite to Run Control. The detailed chapters explain the implementation work; this chapter explains how the pieces cooperate.

## The execution hierarchy

A normal application uses one program, one cyclic task, one Run Control and one Event Buffer. Below Run Control, each Suite owns its Test Cases. Each Test Case owns its scenario-specific Preparations and Assertions.

| Element | What you author or configure | What the framework provides |
| --- | --- | --- |
| Run Control | A `RunControlBase` derivation that configures the run and binds concrete Suites | Run lifecycle, Suite orchestration, aggregation, status and run events |
| Test Suite | A `TestSuiteBase` derivation that groups, initializes and calls concrete Test Cases | Suite lifecycle, Test Case orchestration, aggregation, status and Suite events |
| Test Case | A `TestCaseBase` derivation that applies stimuli, calls helpers and completes scenario phases | Common lifecycle, timing, result escalation, status and Test Case events |
| Preparation | Resource-specific target-state behavior, optionally using `PreparationBase` | A common status interface and interpretation by the Test Case |
| Assertion | Selection, initialization and wiring of the supplied concrete check | Typed checking, retained local results and finding diagnostics |
| PLC program | The concrete Run Control instance, command adapter and startup/cyclic wiring | Reusable command transport, Event Buffer service and communication structures |

Run Control, Suites and Test Cases are the lifecycle owners. Preparation is a prerequisite helper, not another test result. An Assertion supplies one local evaluation result, not another owner lifecycle. The Orchestrator is a technical scheduling helper, not an additional reportable test level.

For example, a valve-opening Test Case can first establish a closed valve, issue an open command and observe position feedback. Preparation establishes the starting condition; Assertions check the response. Related valve scenarios form a Suite. Run Control combines that Suite with the other tests of the PLC application.

## Base classes and concrete implementations

Framework types use the `Tc3UnitTest` namespace. Concrete owner FBs derive from the matching base, call its FB body once through `SUPER^()`, and implement its abstract methods. A hook is such an overridable method: the base decides when to call it, and your implementation supplies the application-specific work.

The responsibilities are deliberately different:

- `Initialize` is the base-owned setup sequence called by the owner.
- `Configure` is your implementation's hook for establishing its own setup and initializing owned components.
- Processing hooks contain concrete child calls, stimuli, observations and scenario completion.
- The base handles generic request processing, lifecycle progression, timing, status and events.

For Suites and Run Control, Configure uses a supplied builder to register children and choose an orchestration mode. You still declare and cyclically call the concrete child FB instances. Registration makes a child available to the scheduler; it neither instantiates nor executes that FB.

For a Test Case, the concrete hooks perform Reset/Abort cleanup, Preparation, test actions, Assertion calls and collection of Assertion results. Phase-completion methods tell the base when that concrete work is finished. One Test Case base supports both single and multiple Preparation/Test states; a multi-phase test does not require replacing the lifecycle.

Do not add competing lifecycle processing or duplicate event publication around these hooks. A direct implementation against the framework interfaces is possible for a deliberate special case, but then it must supply the equivalent lifecycle, monitoring, result, capacity and event behavior. That is not the normal authoring path.

### Interfaces and status snapshots

Interfaces expose selected PLC-side views of objects. For example, `I_TestCase` lets the Suite orchestrate a Test Case, while `I_ResultProvider` lets an aggregator read a result. They do not eliminate the concrete cyclic FB call.

A Suite or Test Case exposes its current typed snapshot through the read-only `Status` property; `Name` is a separate property. There is no externally writable Suite/Test Case command DUT. The parent submits lifecycle requests through methods.

Reading a property does not execute a test. Conversely, putting an interface in an array does not cause TwinCAT to call the instance automatically. Your concrete owner provides both the registered lookup and the explicit child calls.

## Test intent and reuse

A Test Case represents one understandable, behavior-oriented scenario. Reuse changes its bindings, not what counts as success. Expected values, tolerances, resource references and observation times may vary between instances; unrelated scenarios should not be selected through a growing set of mode switches.

Choose a useful reuse scope:

- A generally reusable scenario depends only on a small common interface.
- A resource-family scenario uses a stable typed interface for related resources.
- A dedicated scenario intentionally depends on one tested block or application structure.

A Test Suite is usually a project-specific grouping rather than a reusable behavior in its own right. Reuse the Test Case or Preparation type with separate instances where appropriate. Do not share stateful Assertion or Preparation instances between independently executing tests.

The tested FB or FC may be called inside the Test Case or elsewhere in the application. Internal calling keeps a test self-contained but couples it to that block type. External calling can let one scenario validate different implementations through common stimulus and feedback. In either case, call ownership and order must be explicit: whether feedback is available in the current or next PLC cycle affects the checks.

Test intent remains the author's responsibility. The framework cannot decide which production behavior is correct, infer expected values or determine whether two resources are safe to manipulate concurrently.

## Resources and stimulus ownership

While a Test Case is active, it owns the resource actions needed for its scenario. Its Suite must prevent another concurrent Test Case from writing conflicting stimuli. This includes Preparation work, not just the final test phase. Run Control must apply the same reasoning when allowing whole Suites to overlap.

Preparation controls the actions needed to establish the starting condition. Once testing begins, the Test Case owns the actions used to exercise the tested behavior. If a stimulus must continue after Preparation completes, make that handover explicit.

Inactive processing must not keep writing stale commands. Observe real feedback from the tested block or simulation; do not overwrite feedback merely to satisfy the expected result. Keep production resource types free of test-only fields when an explicit test interface or existing production interface can carry the required values.

For example, two independent arithmetic checks can run together. Two scenarios that both command the same valve cannot normally run together, even if they use separate Test Case instances. Selecting Parallel does not make shared resource access safe.

## Initialization and repeated runs

Initialization and lifecycle Reset solve different problems.

For reinitialization, reactivate the configuration or perform a PLC Cold Reset (XAE: Reset kalt), then start PLC execution. Normal PLC Stop/Start does not trigger the FirstCycle-based initialization path. In that initialization cycle, the program clears pending external commands through the command adapter, initializes the Event Buffer and initializes the concrete Run Control before regular hierarchy processing. Run Control configuration initializes Suites; Suite configuration initializes Test Cases; Test Case configuration initializes Assertions and other owned setup.

The base clears its transient state. Your Configure implementation must also clear application-specific progress or commands and rebuild its bindings. Do not assume PLC Stop/Start has recreated all instance memory.

Successful initialization means the setup is valid, not that the hierarchy is already ready to Start. Suite and Test Case lifecycles remain Uninitialized until their parent requests Reset. Successful Run Control initialization queues the initial Reset; regular cyclic processing then carries it through the hierarchy with capacity checks. No PC command is needed to establish this startup base state, and initialization does not start the tests.

Lifecycle Reset reuses the configured composition. It clears execution state and lets the concrete scenario restore its resources. Successful Reset reaches Idle and readiness; a failed Reset ends in controlled error finalization rather than claiming that the test can start.

Before another run, request Reset and wait for Run Control readiness, then request Start. Do not call Initialize for every run. Child arrays, registration, orchestration mode and service bindings stay fixed after initialization. An Online Change that invalidates that setup requires configuration reactivation or PLC Cold Reset and renewed hierarchical initialization, not hot rebinding during a run.

## Cyclic execution and requests

The PLC program calls the external command adapter before Run Control. Run Control's base invokes the Suite-call hook, each Suite invokes its Test-Case-call hook, and each Test Case executes the scenario hooks in the base-defined order.

Call every registered concrete Suite and Test Case once in its owner's regular initialized path, not only the selected slot. Each child's lifecycle decides whether it performs active work. This also lets pending Reset or Abort processing settle. The framework does not require a separate application-maintained CycleTime value.

`RequestStart()`, `RequestAbort()` and `RequestReset()` record intent; the regular owner FB call processes it. Reset takes priority over Abort, which takes priority over Start. Do not issue independent child requests around the parent's Orchestrator for the same execution path.

Scenario completion inside a Test Case is different from an external request. Methods such as `CompleteTests()` finish a phase immediately within cyclic processing. Later hooks in that call see the new phase. Therefore, finish the required observations before completing their phase; completion does not guarantee that a later Assertion hook still receives Enable.

Suite and Run Control child calls continue in Completed. A completed Test Case no longer executes its scenario or Assertion-processing hooks, but still refreshes its status and aggregates existing results. A production resource that must run continuously needs an independent call path rather than relying on a completed test.

## Execution order and concurrency

The bases own a common Orchestrator. The configuration builder selects one of three modes:

| Mode | Meaning | Typical reason to choose it |
| --- | --- | --- |
| Serial | Children execute one after another in registration order. | Shared resources or a required exclusive sequence |
| Parallel | Children may execute concurrently. | Independent resources and scenarios |
| ParallelSlots | Children in a slot may overlap; the next slot waits for the current slot to finish. | Concurrent groups with ordered boundaries |

Parallel permits concurrency; it does not promise simultaneous starts. Event capacity may delay admission. Choose the mode from resource ownership and intended order, not buffer size.

The builder manages the registered population and slot assignment. The concrete owner keeps the local typed child array and supplies indexed access. Array capacity is not the number of registered children. Registration order matters for Serial; slot grouping matters for ParallelSlots. Do not modify either during execution.

### Event capacity and waiting

Starting or resetting children can produce many events before the external consumer releases them. The framework reserves capacity before dispatching the corresponding child request and releases reservations through its owner/helper handling.

The Test Case supplies accurate finite Preparation/Test-state counts and complete Assertion aggregation so the framework can determine its execution budget. Suite and Run Control authors do not maintain a second reservation ledger or write FIFO indices.

Capacity waiting is part of the parent's timed operation. A run can therefore wait even though the next child is otherwise ready. Check the consumer's progress and the selected buffer capacity instead of bypassing admission with direct child requests. An impossible budget or invalid setup is an error, not indefinite capacity waiting.

## Lifecycle, readiness and monitoring

The lifecycle says where an owner is in its processing: Uninitialized, Reset, Idle, active execution, Completing, an abort path or Completed. Execution status is the externally useful interpretation of that state and its conditions. Result says what the test established. These are related but not interchangeable.

In particular:

- `IsInitialized` reports valid setup; it does not mean ready to Start.
- `IsReady` requires initialized, valid, error-free Idle and the relevant start prerequisites.
- `IsComplete` means terminal completion, not success.
- `Result = Error` can accompany controlled Completed; the owner need not be stuck in an Error state.

The Test Case can extend start readiness with resource-specific prerequisites while retaining the base checks. Suite and Run Control readiness summarize the children through their Orchestrator. Readiness is a start permission, not a replacement for detecting faults during active work.

The owner bases supervise their own execution, Reset and Abort timeouts. The Test Case also supervises Preparation. Configure deadlines for actual work, including cleanup and capacity waiting, and let the base handle expiration. Do not add duplicate parent-side checks of each child's timeout.

A Reset failure does not become an execution Abort. Execution errors use controlled error termination; Reset and Abort deadlines provide bounded termination when concrete work does not finish. Timeout flags remain available for diagnosis until initialization or a new Reset.

## Preparation and Assertion behavior

Preparation answers whether its target is currently reached. Ready means it can accept preparation work; Completed means the starting condition is reached. These may both be true when no work is necessary. Completed is not a latched success from an earlier call.

Disabled Preparation still reports observations but does not actively manipulate the resource. The Test Case interprets its status and owns the timeout. Multiple Preparation instances can serve one phase, or a scenario can have several Preparation phases; the instance count and phase count are not interchangeable.

An Assertion evaluates one condition and retains its result until Reset, allowing escalation to a more severe result. A later good sample does not erase Failed or Error. Disable is not Reset.

For checks with a separate Evaluate input, observation and evaluation are separate controls: an explicit evaluation may be meaningful even when Enable is false. ObserveFirstCycle controls the first enabled observation, not a separate evaluation request. Choose the family and activation pattern from what the scenario actually needs to observe.

Initialize gives each Assertion its identity and configuration. `Reset()` requests clearing on the next bound FB call; that call performs no observation or evaluation. The Test Case owns the calls and aggregation, while the Assertion owns its failed/error findings.

## Results and aggregation

Results flow from Assertions to Test Cases, from Test Cases to Suites, and from Suites to Run Control. Preparation contributes lifecycle conditions rather than an independent Passed/Failed result.

The Test Case's AggregateResults hook adds each owned Assertion once through the supplied I_ResultAggregator contribution view. The base starts the collection and interprets it afterwards. Suite and Run Control bases collect their registered children's results themselves.

The distinction matters: collecting current child results is not publishing an event and does not execute the children. Adding the same Assertion twice would count it twice. Do not reconstruct counters separately from the same checks.

A false expected condition is Failed; unusable configuration or an execution problem is Error. Error takes precedence over Failed, and successful later samples do not undo either. A failed child does not by itself stop the remaining Suite tests. An explicit Abort is a different outcome from error-driven termination.

The owner may remain NotEvaluated during normal active execution while its Assertions already show individual outcomes. It derives the final owner result during finalization. Completed retains that result until Reset; status observations and counters may still refresh without changing already published final evidence.

## Events, communication and diagnosis

The Event Stream is the result log for the external runner. PLC status snapshots support orchestration, HMI views and engineering diagnosis; they are not a substitute for the completed event log.

The bases publish lifecycle triggers/transitions and final owner Result and Aggregation events. Assertions publish their own failed/error findings. A framework diagnostic explains an exceptional condition but does not replace a final result.

Finalization publishes Result, then Aggregation, then the transition to Completed in a later cycle. Run Control additionally observes its CompletionDelay before that final transition. Do not publish another copy of these events from concrete hooks. Technical Orchestrator diagnostics are not another completed test level.

For online diagnosis, inspect the named owner's State, IsInitialized, IsReady, Result, Status and timeout flags, then the affected child's or Assertion's observations. A stable Completed with Error is a completed error path, not a reason to force the state back to Idle.

External communication uses dedicated global data, not FB instance internals or interface arrays. The normal binding uses `GVL_UnitTest.RunControl` for run control and `GVL_UnitTest.EventStream` for event storage/status. An application-specific HMI view can explicitly copy identity and status snapshots into its own communication variables.

Event Buffer Reset is destructive log cleanup. It discards event evidence and is separate from lifecycle Reset, which restores test execution state. During an active run, Buffer Reset invalidates that run's log and may cause framework errors. Use the Run Control command path so reservation release is coordinated; do not clear storage directly.

## Names and identification

Names identify the hierarchy to both engineers and the external runner:

| Element | Example |
| --- | --- |
| Run Control | `UnitTest` |
| Suite | `UnitTest.Valves` |
| Test Case | `UnitTest.Valves.OpenCommand` |
| Assertion | `UnitTest.Valves.OpenCommand.PositionReached` |

Pass the local name and parent to Initialize; the base constructs and validates the full name. Run Control receives its root name from the PLC program. Use distinct local names among siblings so separate objects cannot produce indistinguishable event identities.

Run Control, Suite and Test Case segments contain ASCII letters, digits, underscores or hyphens, with no spaces or dots. Assertion-local names are nonempty ASCII suffixes and may contain further dots. The complete name must fit 80 characters. Truncation retained for diagnostics does not make an invalid name usable.

ResourceName is optional diagnostic context, not a replacement for hierarchical identity. Keep names stable across runs and meaningful to someone reading a failed test log.

## Before writing the concrete blocks

Define the scenario, expected behavior, starting condition and completion condition. Decide who calls the tested logic and owns each stimulus. Identify any resources that prevent parallel execution.

Then use the supplied bases to implement only the scenario and composition hooks. Keep the generic lifecycle, child dispatch, timeout reaction, reservation accounting and standard event publication in the framework. The detailed authoring chapters build on these boundaries rather than requiring you to reconstruct them.
