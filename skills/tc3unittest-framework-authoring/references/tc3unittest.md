# Tc3UnitTest integration

Load this reference when implementing or reviewing an accepted scenario with Tc3UnitTest. It supplies navigation and high-risk integration checks, not a replacement API catalog.

## Resolve the actual framework

Identify the consumed library/source revision and namespace. Use its matching Authoring Guide and actual declarations or API help. Resolve the repository-relative paths below from the framework checkout root, not from the installed skill directory. When the sources are unavailable, use the corresponding sections in the matching guide/help. A copied skill does not require this checkout layout or another project.

Start with the framework model (`docs/authoring/framework-model.md`). Read only the relevant chapters:

| Work | Maintained guidance |
| --- | --- |
| Test Case, tested-object calls and reuse | Test Case authoring (`docs/authoring/test-case.md`) |
| Target establishment and resource bindings | Preparation authoring (`docs/authoring/preparation.md`) |
| Check family, type, observation and evaluation | Assertion authoring (`docs/authoring/assertions.md`) |
| Child composition and scheduling | Test Suite authoring (`docs/authoring/test-suite.md`) |
| Startup, root composition and cyclic wiring | Run Control authoring (`docs/authoring/run-control.md`) |
| Assisted-authoring brief and review | AI-assisted authoring (`docs/authoring/ai-assisted-framework-authoring.md`) |

Apply the consuming project's style rules alongside the framework contract. Use the relevant framework contracts (`contracts/README.md`) and the Authoring Guide alongside those project rules. For framework selftests, also use selftest strategy (`docs/selftest-strategy.md`). This skill does not generalize a selftest-only seam into a supported consumer API.

For a matching simple scenario, inspect [optional starting points](starting-points.md) before reconstructing its native declaration/method structure. Use their stated limits and current guide/API; other scenarios do not require a template.

## Map the agreed scenario

Use the supplied owner bases for their standard lifecycle. Normal Test Cases derive from TestCaseBase; the base body is called once through SUPER^(). Configure, reset, abort, preparation, testing, Assertion processing and result aggregation have distinct hooks. Resolve their exact signatures in the current version. Single-state and multi-state cases use that model, not copied S7 Sequencer templates.

Before declaring scenario fields, inspect inherited declarations as well as hook signatures; a local field must not collide with inherited owner storage. Follow the existing guide's state examples: declare named state constants for CASE labels and keep any state-offset derivation in those constant declarations. Do not infer accepted IEC syntax from a plausible expression. For record-valued status properties, follow the existing selftest pattern: assign the returned status to a typed local snapshot before accessing its fields, rather than chaining field access onto a property result.

Configure/Initialize establishes identity, configuration and owned transient state. Lifecycle Reset restores execution state without rebuilding composition. Assertion Reset requests are deferred until the next regular bound call, which suppresses evaluation. Review the complete reset sequence; reading Result immediately after Reset does not prove it was cleared.

Select Assertions by the accepted expected relationship and actual data type. Observation Enable, Evaluate and first-call observation have different meanings. Derive their timing from actual stimulus/call/sample order. Keep valid data/storage bindings on reset calls as well.

Complete the test at its defined observation endpoint, even when the Assertion fails. Keep each owned result contribution once; do not perform checks or emit a second final result in aggregation.

Preparations establish their target, observe current resource conditions and remain passive when disabled. They neither own the DUT call nor invent successful feedback. Reuse a general, resource-family or dedicated Preparation according to its actual bindings and target semantics. The scalar Prepare_ValueAtTarget example in the guide and the concrete resource-family selftest helper have different interfaces; do not conflate their signatures.

For Suites and Run Control, registration, array lookup and actual child calls must describe one composition. Do not duplicate base scheduling, reservations, result handling or events. Choose Serial/Parallel/ParallelSlots from required order and resource compatibility, including Reset/Abort.

## Check the fixture and call path

Normally give a stateful FB one execution owner and at most one body call per PLC cycle; any exception needs an explicit reason. Do not infer unconditional multiple calls from a selftest that deliberately probes immediate method or call semantics.

TestCaseBase skips scenario-processing hooks at Completed. A continuously operating resource needs an appropriate call path outside those hooks when continued execution is required. Establish ownership before adding a second call or changing its order.

Each reusable test use owns its state and Assertions. Each borrowed reference must remain valid throughout use. Restore the real nested fixture baseline before reporting reset complete; neutralizing test variables alone does not reset the DUT. Review repeated runs and interruption recovery without relying on unrelated tests or PLC restart.

For event-producing framework subjects, use the existing isolated publisher/capture patterns from selftest strategy. Do not drive the surrounding runner's communication storage to test a subject or introduce a new PLC/PC protocol.

## Learn from existing tests without copying their oracle

Find relevant saved SelfTests for fixture patterns and previously exposed defects. Useful starting points in the development project's SelfTests/TestCases tree are:

- TestSuite_AssertionLifecycle/Test_AssertionResetReuse.TcPOU: queued reset, coalescing, configuration retention, first observation and event checks.
- TestSuite_Preparation/: current-condition completion, disabled observation, resource feedback progression, commands and re-enable paths; its Helper/ directory contains the concrete resource family.
- TestSuite_TestSuiteLifecycle/Test_SuiteMockRepeatedReset.TcPOU: repeated requests and coherent reset progress.
- TestSuite_Orchestrator/: scheduling, reset/repeated execution and isolated child doubles.

These are development examples, not a supplied public fixture library. Check current declarations and requirements before reusing their mechanics. Existing runtime success concerns those exact tests; it does not validate newly generated bindings or test intent.

For a new scenario, trace the expected behavior to the applicable requirement or accepted characterization, then compare existing tests for omissions and reusable structure. Keep local doubles small and controlled; mirror-like production copies need the justification and divergence handling required by selftest strategy.

## Verification boundary

Review saved code and the complete wiring first. When engineering checks are requested, follow the project's separate build/runtime procedure and permissions; no particular tool is required by this skill. Report which objects were actually compiled and which scenarios actually ran. Source-reviewed examples and analytically predicted fault detection remain labeled as such.
