# Select and adapt a starting point

Use these optional native source assets only after the scenario and framework version are known. They preserve two small, concrete patterns from the Authoring Guide; they are not a universal test generator, supplied library types or an alternative API definition.

| Asset | Applicable scope | Dependency and important limit |
| --- | --- | --- |
| [Single-state Test Case](../assets/templates/test-case-single-state.TcPOU) | One immediate Boolean sample with no stateful resource or Preparation | Calls the application example `IsPositive(Value : DINT) : BOOL` with 1 and expects TRUE. The guide defines that function; the library does not supply it. Replace the call and expectation only from agreed intent. |
| [Value-at-target Preparation](../assets/templates/preparation-value-at-target.TcPOU) | Scalar request/feedback target condition with no internal sequence | ActualValue and ResourceError are read inputs; RequestedValue is caller-owned writable storage. The caller executes the real resource. This is not the concrete SelfTest helper with the same POU name. |

Resolve the current guide's `docs/authoring/test-case.md#a-complete-single-state-example` and `docs/authoring/preparation.md#an-active-multi-cycle-example` from the framework checkout root. Check its actual declarations if adapting to another library version or namespace. The assets use the external library namespace `Tc3UnitTest`. Inside the framework's own PLC source project, use the locally visible type names instead; its export namespace is not a self-reference through the Library Manager. The isolated source-project compile check makes exactly that prefix adaptation.

## Test Case adaptation

The asset includes the FB body, all seven abstract hooks and the child initialization check. Configuration initializes the Assertion; Reset requests its deferred reset and restores local progress. Disabled calls retain valid Assertion bindings. A completed evaluation is recorded separately from Passed, so an incorrect Boolean sample can finish as Failed on the next active call. Aggregation reads the one owned result once.

The default application function and literal value are an explicit illustrative requirement, not inferred acceptance criteria for another subject. For a new scenario, rename the concrete type and Assertion identity, replace the sample source and independently define the expected relationship. Inspect inherited declarations before adding fields.

Do not stretch this pattern into a timer, edge count, sequence or continuously operating resource test by waiting for Passed or calling the DUT repeatedly until it matches. Those scenarios require their own call/window/completion and cleanup design. An empty Preparation hook is valid here because the configured Preparation count is zero. Reset/Abort completion is appropriate here because the example owns no persistent resource action; add real owned cleanup for a different scenario.

## Preparation adaptation

The asset includes its FB body and protected Prepare override. It changes a request only while enabled, checks the error before writing, never assigns feedback and refreshes the current target/status even while disabled. It has no hidden mode or latched completion. Keep the target stable for its intended phase.

Reuse the type with separate instances and separate RequestedValue bindings, supplying the actual feedback at every call. Scalar bindings do not prove that parallel access to the underlying equipment is safe. A resource needing cancellation, availability rules, hysteresis or ordered setup is outside this simple example; resolve those semantics before extending it.

## Copying and verification

Create fresh application-owned POUs and methods from the relevant declarations/bodies, or assign fresh exported object IDs when copying native XML files. The asset names and IDs are examples, not registration identities to duplicate in one project. Preserve native declaration/implementation separation and check for collisions with existing application and inherited names.

The native XML is text source. No binary installation or runtime permission follows from copying it. The templates are outside the production Framework source boundary and must not be packaged as library contents.

Compile the adapted objects, including otherwise unused methods, and inspect diagnostics. Compilation of these starting points does not establish the behavior of changed calls or bindings. Run relevant normal, failure and repeat/reset paths before claiming them executed. A previous successful example does not replace that verification.
