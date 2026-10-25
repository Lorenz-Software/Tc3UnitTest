# Assertion Authoring

Assertions check defined expectations against observed values. They do not own the Test Case lifecycle, generate its stimuli or decide how long the scenario should run. The Test Case initializes, resets and calls its Assertion instances, then contributes their results to the supplied aggregator.

Choose checks from the expected behavior, not from whichever result the tested implementation currently produces. Use one instance for one independently identifiable condition. Separate conditions should retain separate names and results, even when they use the same Assertion type.

This chapter explains the supplied families and their application. [Test Case authoring](test-case.md) supplies the complete surrounding FB and hook implementations. The focused calls below belong in that Test Case's ProcessAssertions hook: Enable is the hook input, State is the current owner state, and measured values/window flags come from the scenario. Initialize, reset and aggregate every illustrated Assertion instance using the common pattern below; the later examples do not repeat those steps.

## Select by intent and datatype

| Intent | Family or example |
| --- | --- |
| Boolean condition | AssertTrue, AssertFalse, AssertEqual_Bool, AssertNotEqual_Bool |
| Exact scalar comparison | AssertEqual_DInt, AssertNotEqual_LInt and the corresponding typed variants |
| Numeric limit or interval | AssertLessThan_*, AssertLessEqual_*, AssertGreaterThan_*, AssertGreaterEqual_*, AssertInRange_*, AssertNotInRange_* |
| Absolute floating-point tolerance | AssertEqualTolerance_Real/LReal, AssertNotEqualTolerance_Real/LReal |
| Floating-point classification | AssertIsNaN_Real/LReal, AssertIsFinite_Real/LReal, AssertIsInfinite_Real/LReal |
| Floating-point classification within an array region | AssertArrayAllElementsFinite_*, AssertArrayContainsNonFinite_*, AssertArrayContainsNaN_*, AssertArrayHasNoNaN_*, AssertArrayContainsInfinity_*, AssertArrayHasNoInfinity_* |
| No change between successive scalar observations | AssertNoValueChange_* |
| No rising/falling edge or a specified edge count | AssertNoRisingEdge, AssertNoFallingEdge, AssertRisingEdgeCnt*, AssertFallingEdgeCnt* |
| Selected bits or masks | AssertTrueBit_*, AssertEqualMask_*, AssertContainsBit_* and related variants |
| Ordered observed values | AssertSequence_* |
| An array region, pattern or unchanged snapshot | AssertEqualArray_*, AssertArrayAllEqual_*, AssertArrayContainsValue_*, AssertArrayContainsArray_*, AssertArrayNoValueChange_* |
| Characters or PLC text | *_Char, *_WChar, *_String and *_WString |
| Text represented by array elements | AssertArrayEqualString_*, AssertArrayContainsString_*, prefix/suffix and WString variants |
| Delimiter position or token occurrences | AssertLengthUntilValue*, AssertLengthUntilArray*, AssertValueTokenCnt*, AssertArrayTokenCnt*, AssertNoValueToken_*, AssertNoArrayToken_* |
| Duration, date or time of day | AssertEqual_*, AssertEarlierThan_*, AssertLaterThan_*, AssertInTimespan_* and related temporal variants |

The suffix identifies the checked datatype or interpretation. It is not a request for the Assertion to convert arbitrary input types. Prefer the matching type rather than narrowing a value to fit a convenient check.

The scalar integer families cover SINT, INT, DINT, LINT and their unsigned counterparts. REAL/LREAL add tolerance checks. BYTE, WORD, DWORD and LWORD have exact equality, bitfield, no-change and sequence checks; use integer types when the requirement is numeric ordering. Available array families include these numeric and bit-string types plus BOOL and character-code views. Scalar availability does not imply an equivalent array or sequence family for every type.

A range check expresses one interval more clearly than two unrelated limit Assertions. A single-bit check expresses one named flag more clearly than a mask when no other bits matter.

## Initialize identity and settings once

Declare Assertions as local Test Case instances. Initialize them in the Test Case's Configure method, after the base has established the Test Case identity:

```iecst
VAR
    FOutputValue : Tc3UnitTest.AssertEqual_DInt;
END_VAR
```

Within Configure:

```iecst
FOutputValue.Initialize(Parent := THIS^,
    AssertionName := 'OutputValue',
    ResourceName := 'SimulatedDrive',
    ObserveFirstCycle := TRUE);
```

THIS^ is the concrete Test Case. Initialize builds the full event identity:

```text
<runControlName>.<suiteName>.<testCaseName>.<assertionName>
```

Pass the local AssertionName, not the whole path. It must be nonempty ASCII; additional dots in this local suffix are allowed. The complete name must fit the framework's 80-character capacity. Choose unique local names: the base checks structure and length, not whether another sibling uses the same name.

ResourceName is optional diagnostic context, defaults to an empty string and has capacity 32. It does not identify the Test Case or Assertion. ObserveFirstCycle defaults to TRUE. Name, ResourceName and ObserveFirstCycle are read-only after configuration.

Check the returned BOOL or IsInitialized as part of the Test Case's initialization validation. For the single instance above, extend the normal checks as follows:

```iecst
{region 'Documentation'}
(*!
<summary>Rejects an unusable Assertion in addition to the base configuration checks.</summary>
*)
{endregion}
METHOD PROTECTED CheckInitialization : BOOL //! TRUE when inherited setup and the owned Assertions are initialized.

CheckInitialization := FALSE;
IF NOT SUPER^.CheckInitialization() THEN
    RETURN;
END_IF;
IF NOT FOutputValue.IsInitialized THEN
    RETURN;
END_IF;

CheckInitialization := TRUE;
```

A rejected Assertion initialization emits a Framework diagnostic and leaves checking disabled. A length-limited Name may still be retained for diagnosis; readable text in Name is not proof of successful initialization. Do not continue a scenario with an unusable Assertion.

Initialize clears the shared result/history and queues a reset. The first following FB call consumes that reset and performs no check. This is intentional: family-specific reset work runs only with the concrete FB inputs bound. Normal application startup calls the Assertions through the Test Case hooks before testing begins.

A lifecycle Reset keeps the identity and settings. Do not call Initialize cyclically or use it to erase an unfavorable result.

## Select a publisher when needed

Normally the inherited read-only EventPublisher view retains the global default on
first access. To isolate an Assertion or explicitly route its findings, call
BindPublisher(Publisher := LocalPublisher) on the concrete instance. No derived
adapter is required. Bind before Initialize when initialization diagnostics must
also use that publisher.

The method immediately accepts any nonzero I_EventPublisher. Passing zero leaves
the current binding unchanged. There is no lifecycle or initialization guard:
another valid binding replaces the previous one without changing identity,
result, observation history or pending reset. Earlier findings are not replayed.
Initialize and Reset retain the binding; the caller must keep the publisher alive.
This Assertion-specific API does not rebind the parent or other framework objects.

## Call, reset and aggregate through the Test Case

A direct comparison belongs in ProcessAssertions. Here ActualValue and ExpectedValue are the Test Case's scenario data, and Enable is that hook's active-test permission:

```iecst
FOutputValue(Enable := Enable,
    State := State,
    IN := ActualValue,
    Expected := ExpectedValue);
```

State is the current owning Test Case state. It gives findings their lifecycle context; it is not an Assertion-local state. Pass it on every call, including calls with checking disabled.

Keep normal FB calls present when their Enable is FALSE. They consume pending resets and update accepted activity/history. Omitting the call is not equivalent to calling with Enable FALSE: the instance cannot observe a disabled interval that it was never called through.

In ProcessReset, request the reset:

```iecst
FOutputValue.Reset();
```

Reset records a request; it does not immediately change Result. The next bound FB call clears resettable state and suppresses observation, evaluation and findings for that call, even if Enable or Evaluate is TRUE. The normal Test Case hook order provides that call after ProcessReset. Bind array inputs and external memory on reset calls too; a sequence reset, for example, uses the supplied Expected array's lower bound.

In AggregateResults, add the existing result:

```iecst
{region 'Documentation'}
(*!
<summary>Contributes the owned Assertion without executing it.</summary>
*)
{endregion}
METHOD PROTECTED AggregateResults
VAR_INPUT
    Aggregator : Tc3UnitTest.I_ResultAggregator; //! Borrowed owner-held result sink; contribute each owned Assertion once without resetting or retaining the sink.
END_VAR

Aggregator.AddProvider(Provider := FOutputValue);
```

Add every owned Assertion once per collection, including currently disabled instances and collection in Completed. The base resets the aggregator before calling your hook. Do not reset it again, call the Assertions here, maintain parallel counters or publish final events.

I_Assertion is the shared Name/Result view inherited from I_ResultProvider. It does not replace the concrete typed FB call or provide generic initialization/reset. No separate status array or interface array is required for ordinary Assertion use.

### Held results and findings

An Assertion starts at NotEvaluated. A valid successful check can make it Passed; an incorrect observed value makes it Failed; invalid prerequisites for a meaningful check can make it Error. Results escalate but do not recover within the same run:

- Pass does not clear Failed or Error.
- Failed can still escalate to Error if a later applicable check detects invalid data/configuration.
- After Error, no lower-severity finding is emitted.
- Disabling does not clear the result.
- Reset starts a new evaluation history.

The first transition into Failed emits a failed finding. A later transition into Error can emit an error finding. Repeated calls at the same held severity do not generate cyclic finding spam. Successful evaluation does not produce a separate Passed finding on every call.

A Passed result during an observation window is not proof that the whole scenario is complete. Conversely, waiting for Result = Passed before ending every scenario can turn an ordinary failed check into a Test Case timeout. End the scenario at its defined endpoint after the required evaluation, regardless of success.

## Observation and evaluation are different operations

The common observations are:

| Member | Meaning |
| --- | --- |
| Enabled | Enable accepted at the latest FB call |
| ObservationActive | This call may observe checked data under the family's observation rules |
| EvaluationActive | This call may evaluate under the family's evaluation rules |
| Result | Held result, not a universal indication that the observation window has ended |

For direct predicates, evaluation follows observation. For stateful families with Evaluate, observation and result evaluation can be controlled independently. These properties describe processing permission; they do not prove valid input data or a newly produced result.

### ObserveFirstCycle

With TRUE, the first enabled non-reset call may contribute an observation. With FALSE, that call is skipped; observation can begin on the following enabled call.

A disabled call makes the next enabled call a new first call. Reset also restarts this history. ObserveFirstCycle FALSE is useful when a command is issued before the tested object has had a chance to process it, but it is not a substitute for a defined call order or a multi-cycle settling condition.

Some families need a baseline even when ObserveFirstCycle is TRUE. A scalar no-change check or edge detector cannot compare two samples on its first observation. FALSE delays baseline capture as well; it does not manufacture an earlier sample.

ObserveFirstCycle does not delay a separate Evaluate request. Reset still takes priority over both controls.

### Explicit Evaluate

Sequence and edge-count Assertions expose Evaluate. Supply it deliberately; do not leave it TRUE throughout a window that is still being collected.

- Sequence: observation checks the order as values arrive. Evaluate also checks the current IN and whether the expected sequence is complete, even with Enable FALSE.
- Edge count: observation collects edges. Evaluate compares the accumulated count. If observation is enabled in the same call, that observation happens first. Evaluate alone does not create another edge.

Complete the required evaluation before calling CompleteTests. In the normal hook order, CompleteTests in ProcessTests changes the phase before ProcessAssertions runs. Either finish on the next scenario call after recording that evaluation occurred, or use another explicitly ordered completion path. [Test Case authoring](test-case.md#cyclic-order-and-same-cycle-transitions) explains this interaction.

## Scalar values, limits and tolerances

Equality uses IN and Expected. LessThan/LessEqual use Maximum; GreaterThan/GreaterEqual use Minimum. InRange/NotInRange use Minimum and Maximum.

For example, with FSpeed declared as AssertInRange_DInt:

```iecst
FSpeed(Enable := Enable,
    State := State,
    IN := MeasuredSpeed,
    Minimum := 950,
    Maximum := 1050);
```

The range is inclusive. Equal bounds are valid; Minimum greater than Maximum is Error, not Failed. NotInRange succeeds strictly outside that inclusive interval.

For floating-point calculations, decide whether exact equality really expresses the requirement. AssertEqual_Real/LReal compares exact values. Tolerance variants use an absolute tolerance in the same units as IN and Expected, not a percentage or relative error:

```iecst
FPosition(Enable := Enable,
    State := State,
    IN := MeasuredPosition,
    Expected := LREAL#100.0,
    Tolerance := LREAL#0.01);
```

Here FPosition is AssertEqualTolerance_LReal. Equality includes the tolerance boundary; AssertNotEqualTolerance_LReal succeeds only beyond it. Zero tolerance requests exact equality. Negative or non-finite tolerance is Error.

Scalar REAL/LREAL comparison and no-change families reject NaN and either infinity as Error when the relevant checking/observation is active. Large finite operands remain valid; the tolerance implementation avoids a difference-overflow becoming a false configuration error. Do not copy this scalar non-finite policy onto the array families; their expected-data rules are described separately below.

### Floating-point classification

Use the classification Assertions when a special value is deliberately part of the expectation, rather than invalid input to an ordinary comparison. Each family has separate _Real and _LReal variants and takes only IN in addition to inherited Enable and State:

| Assertion | Passing input |
| --- | --- |
| AssertIsNaN_* | NaN, including quiet and signaling representations |
| AssertIsFinite_* | Any finite value, including positive/negative zero and subnormal values |
| AssertIsInfinite_* | Positive or negative infinity; no sign-selection input |

A different classification produces Failed, not Error. These predicates inspect the binary representation without floating-point arithmetic or comparisons on special values. Failure messages use the safe numeric formatter, including explicit NaN, +Inf and -Inf text. Do not generate special values by dividing by zero in application code.

For example, with FFiniteOutput declared as AssertIsFinite_LReal and initialized using the common pattern:

```iecst
FFiniteOutput(Enable := Enable,
    State := State,
    IN := MeasuredValue);
```

Initialization, ObserveFirstCycle, reset requests and held results follow AssertionBase unchanged. Classification does not alter the non-finite policies of comparison, tolerance or array Assertions.

### Scalar no-value-change checks

AssertNoValueChange_* compares consecutive active observations:

1. The first observation establishes a baseline without producing a comparison result.
2. The next observation is compared with that baseline.
3. Subsequent comparisons use the preceding active observation.
4. A disabled call invalidates the comparison baseline but retains the held Result.

After re-enable, the first active observation establishes a new baseline. It does not detect a change that happened while observation was disabled. If the requirement is to preserve one initial value across disabled intervals, this scalar family is not that check.

This model also applies to scalar BOOL, character, text and temporal no-change checks. Arrays intentionally use the different snapshot model below.

## Boolean conditions and edges

Use AssertTrue or AssertFalse for a directly named condition; use AssertEqual_Bool/AssertNotEqual_Bool when the expected Boolean value is itself scenario data.

AssertNoRisingEdge and AssertNoFallingEdge monitor consecutive active observations. Their first observation establishes the signal baseline; they do not assume a transition from a declaration-initialized FALSE. A disabled interval breaks that baseline, so a transition across the gap is not counted as an observed edge.

The edge-count families provide equality, inequality, limits and inclusive ranges over a UINT count. For example, FRisingEdges : AssertRisingEdgeCntEqual:

```iecst
FRisingEdges(Enable := Enable AND FObserveWindow,
    Evaluate := Enable AND FFinishWindow,
    State := State,
    IN := Feedback,
    Expected := UINT#2);
```

FObserveWindow and FFinishWindow are scenario-owned flags. Clear them during Configure and Reset. Normally the finish flag is a one-call evaluation request at a defined endpoint; it must not depend on the count already being correct.

EdgeCount is a read-only observation. It persists across disabled intervals until Reset, but each newly active interval needs a fresh signal baseline. Evaluate with observation disabled checks the accumulated count without counting the current input transition. More than 65535 observed matching edges causes Error rather than wrapping the count.

Do not confuse these temporal edge counts with token counts in an array: token counts describe one data region at an evaluation call, not events accumulated over PLC cycles.

## Bitfields and masks

Bit numbering starts at the least significant bit, index zero:

| Type | BitIndex range |
| --- | --- |
| BYTE | 0..7 |
| WORD | 0..15 |
| DWORD | 0..31 |
| LWORD | 0..63 |

AssertTrueBit/AssertFalseBit check one bit. AssertEqualBit/AssertNotEqualBit add Expected : BOOL. An out-of-range BitIndex causes Error.

For FReadyBit : AssertTrueBit_Word:

```iecst
FReadyBit(Enable := Enable,
    State := State,
    IN := StatusWord,
    BitIndex := 3);
```

Mask predicates select several bits:

- TrueMask requires all selected bits TRUE.
- FalseMask requires all selected bits FALSE.
- EqualMask compares IN AND Mask with Expected AND Mask.
- NotEqualMask requires those selected bit patterns to differ.
- ContainsTrue/ContainsFalse/ContainsBit require at least one selected bit with the requested Boolean state.

For FModeBits : AssertEqualMask_Byte:

```iecst
FModeBits(Enable := Enable,
    State := State,
    IN := ModeByte,
    Mask := BYTE#16#0F,
    Expected := BYTE#16#05);
```

Bits outside Mask do not affect this result. Scalar mask/contains predicates default to all bits; an empty mask causes Error. These rules describe the scalar bitfield family, not a universal validation rule for every array/token Mask parameter.

Use full-value equality when all bits are meaningful. Diagnostic hexadecimal widths follow the checked type; a BYTE finding is not rendered as an unrelated full-width LWORD value.

## Ordered value sequences

AssertSequence_* is supplied for signed/unsigned integer and BYTE/WORD/DWORD/LWORD values. Expected is a read-only ARRAY[*] of the matching element type. The whole Expected array describes the order; there is no StartIndex/Length selection on that parameter.

Example Test Case fields:

```iecst
VAR
    FSequence : Tc3UnitTest.AssertSequence_DInt;
    FExpectedSequence : ARRAY[1..3] OF DINT := [10, 20, 30];
END_VAR
```

After normal identity initialization, call from ProcessAssertions:

```iecst
FSequence(Enable := Enable AND FObserveWindow,
    Evaluate := Enable AND FFinishWindow,
    State := State,
    IN := ObservedStep,
    Expected := FExpectedSequence);
```

The sequence 10, 10, 20, 20, 30 is valid for this expectation. Repeated observations do not advance. A changed value must match the next entry; the Assertion does not search ahead. Skipping 20 or continuing to another value after 30 fails.

Consequently, adjacent duplicate Expected entries do not describe two distinguishable steps. This family checks changes in value order, not how many cycles a value was repeated. Keep duration, dwell and deadline checks in the Test Case.

The result need not become Passed merely because the final expected value has been observed. Evaluate checks completeness and the current value. Evaluating while still at the second entry fails as incomplete. Evaluating with Enable FALSE still requires a meaningful current IN; it is not only a query of historical progress.

Disabling preserves sequence progress. Reset restarts it at Expected's lower bound. Keep the expected array, its bounds and its contents stable for the sequence run, and supply it even on reset/disabled calls. Use another instance or a deliberate new reset cycle for another independent sequence.

## Array regions and pattern checks

Array APIs use typed, read-only VAR_IN_OUT CONSTANT array bindings, except writable snapshot Memory. They do not retain a generic copied dataset for every check. Provide valid application-owned arrays and keep the inspected data stable for the call. These comparisons and searches execute synchronously in the PLC task; select the relevant region instead of scanning unused capacity. Pattern search can compare several elements at each candidate position, so array size and call frequency still matter for cycle cost.

StartIndex is an actual index in IN, not an offset from its lower bound. Nonzero and negative array lower bounds are supported. Where present, Length is USINT and counts 1..255 elements; zero is invalid. The selected end index is StartIndex + Length - 1 and must fit IN.

### Equality versus search ranges

The principal interfaces differ:

| Family | Selected data |
| --- | --- |
| AssertEqualArray_* | All of Expected compared with IN from StartIndex; expected-array length defines the compared length |
| AssertArrayAllEqual_* | Length elements of IN from StartIndex, each compared with one Expected value |
| AssertArrayContainsValue_* | At least one match for Expected in the selected IN region |
| AssertArrayContainsArray_* | Complete contiguous Expected pattern somewhere in the selected IN region |
| AssertArrayNoValueChange_* | Selected IN region compared with a retained external snapshot |

AssertEqualArray has no Length input. It does not require the entire IN array to equal Expected. For example:

```iecst
VAR
    FValues : ARRAY[10..14] OF DINT;
    FExpectedValues : ARRAY[-1..1] OF DINT := [2, 4, 6];
    FValuesEqual : Tc3UnitTest.AssertEqualArray_DInt;
END_VAR
```

```iecst
FValuesEqual(Enable := Enable,
    State := State,
    StartIndex := 11,
    IN := FValues,
    Expected := FExpectedValues);
```

This compares IN[11..13] with Expected[-1..1]. IN[10] and IN[14] are outside the check. Expected starts at its own lower bound; the two arrays do not need matching bounds.

ContainsArray uses the whole Expected pattern and searches only the selected range:

```iecst
FPattern(Enable := Enable,
    State := State,
    StartIndex := 10,
    Length := 5,
    IN := FValues,
    Expected := FExpectedValues);
```

Here FPattern is AssertArrayContainsArray_DInt. A nonempty pattern longer than the selected region is invalid configuration, not a successful vacuous match. A valid pattern with no occurrence produces Failed.

BYTE/WORD families also provide ArrayStartsWithArray and ArrayEndsWithArray for the selected region. Bit-string array comparisons expose Mask where applicable; it is applied per element and defaults to all bits. Character-code array checks are exact and have no mask. Select a meaningful mask deliberately rather than assuming all families reject an empty one.

### Retained snapshot for array no-change

Provide dedicated static Memory with enough elements. The Assertion writes its first Length elements starting at Memory's own lower bound; Memory and IN need not have the same lower bound.

```iecst
VAR
    FBuffer : ARRAY[10..13] OF DINT;
    FSnapshot : ARRAY[0..3] OF DINT;
    FBufferStable : Tc3UnitTest.AssertArrayNoValueChange_DInt;
END_VAR
```

```iecst
FBufferStable(Enable := Enable,
    State := State,
    StartIndex := 10,
    Length := 4,
    IN := FBuffer,
    Memory := FSnapshot);
```

The first active observation captures the snapshot and does not compare. Later eligible observations compare with that original snapshot, not with the preceding cycle. Memory belongs exclusively to this Assertion's snapshot operation and must not overlap IN. Do not use temporary method storage or share one snapshot region between simultaneous Assertion instances.

A disabled call preserves the snapshot and result. On re-enable, the first active observation restores consecutive-observation history; the following active observation can compare again, still against the original snapshot. ObserveFirstCycle FALSE additionally delays the first observation. Disabling therefore neither replaces the baseline nor guarantees a comparison on the first re-enabled call.

Reset invalidates the snapshot without clearing the caller-owned Memory bytes. The next active observation captures a new baseline. Keep input binding, selected range and Memory binding/content ownership stable until Reset.

### REAL/LREAL array expectations

Floating-point array comparisons have a Tolerance input, default zero, that must be finite and nonnegative. Equal finite values or finite values within absolute tolerance match. The non-finite rules depend on the role of the data:

| Operation | Expected/reference requirements | Non-finite actual data |
| --- | --- | --- |
| EqualArray | Every Expected element must be finite; otherwise Error | Does not match a finite expected element; Failed |
| ContainsValue, ContainsArray, AllEqual | Expected must not be NaN; signed infinities are allowed | NaN does not match; equal signed infinities match |
| ArrayNoValueChange snapshot capture | Initial snapshot must not contain NaN; signed infinities are allowed | Later NaN does not match; unchanged signed infinity matches |

An irrelevant NaN elsewhere in a search region does not make the entire search configuration invalid. A valid match may still be found elsewhere. AllEqual, by contrast, requires every selected element to match.

### Floating-point array classification

Each classification family has _Real and _LReal variants. Supply IN through the read-only open-array interface, StartIndex as the actual first checked array index, and Length as the number of elements (1..255). No Expected or Tolerance is needed. The array may have a negative or nonzero lower bound; the entire selected range must lie within its actual bounds. Length zero or an invalid range/binding produces Error, including after a held Failed result.

| Assertion | Passing condition in the selected range |
| --- | --- |
| AssertArrayAllElementsFinite_* | Every element is finite, including signed zero and subnormal values |
| AssertArrayContainsNonFinite_* | At least one element is NaN or either infinity |
| AssertArrayContainsNaN_* | At least one element is NaN |
| AssertArrayHasNoNaN_* | No element is NaN; infinities are allowed |
| AssertArrayContainsInfinity_* | At least one element is positive or negative infinity |
| AssertArrayHasNoInfinity_* | No element is infinity; NaN is allowed |

For example, with FFiniteSamples declared as AssertArrayAllElementsFinite_Real and initialized using the common pattern:

```iecst
FFiniteSamples(Enable := Enable,
    State := State,
    StartIndex := FirstSampleIndex,
    Length := SampleCount,
    IN := Samples);
```

Special values are checked data, not configuration errors. A violated expectation produces Failed. Only the selected region contributes; special values elsewhere in IN are ignored. HasNoNaN and HasNoInfinity are not interchangeable with AllElementsFinite: each excludes only its named classification.

AllElementsFinite and HasNo failures identify the first offending element and its actual index. Contains failures identify the searched range and missing classification; there is no offending element to report. Classification uses integer bit tests, including for quiet/signaling NaN; diagnostics use the safe numeric formatter. Keep the array stable throughout the FB call. These Assertions retain no array reference or snapshot between calls.

Do not prefilter or coerce the actual data merely to avoid a Failed result. If a scenario requires specifically testing non-finite values, choose a family whose defined semantics match that requirement rather than assuming the scalar and array policies are identical.

## Characters and PLC strings

### Character codes

The Char-named Assertions accept BYTE; WChar-named Assertions accept WORD. These names describe character interpretation, not additional PLC CHAR/WCHAR storage types.

Equal/NotEqual compare exact codes. NoValueChange uses the consecutive-observation model. They do not fold case, normalize text or validate an encoding.

Use a typed character code when the intent is one character. Printable ASCII findings include the character and its hexadecimal code; other values use a code representation. This is why a Char Assertion may be more informative than plain BYTE equality even though the storage type is the same.

### STRING and WSTRING

Both families provide Equal, NotEqual, Contains, StartsWith, EndsWith and NoValueChange.

The scalar text inputs are read-only reference parameters. Their capacities are consumer-configurable library parameters:

- Param_Assertions.AssertionStringLength, default 80.
- Param_Assertions.AssertionWStringLength, default 80 wide characters/code units, not 80 bytes.

These limits are independent of the shorter event-message value preview. Keep the text stable during a call; do not first assign an overlength value into a shorter temporary and accidentally test the truncated text instead.

Exact equality is case-sensitive. Contains uses Fragment, StartsWith uses Prefix and EndsWith uses Suffix. Empty equality operands are valid. Empty Fragment, Prefix or Suffix is Error, including when IN is empty. A valid nonempty search text that is not found is Failed.

For FContains : AssertContains_String:

```iecst
VAR
    FReply : STRING(Tc3UnitTest.Param_Assertions.AssertionStringLength);
    FRequiredText : STRING(Tc3UnitTest.Param_Assertions.AssertionStringLength) := 'READY';
END_VAR
```

```iecst
FContains(Enable := Enable,
    State := State,
    IN := FReply,
    Fragment := FRequiredText);
```

No trimming, wildcard matching or case-insensitive comparison is implied. WSTRING checks operate on the wide text; the framework's diagnostic preview is not a lossless Unicode representation. String/WString and their byte/word-array previews retain printable ASCII and replace other bytes or wide code units with one reserved byte, `16#D7`; the consumer's displayed glyph is not prescribed. Selected array zeros are replaced, while STRING/WSTRING zeros terminate input. Quotes and backslashes remain literal. A shortened/rendered message is not the data used for comparison.

NoValueChange_String/WString keeps its previous active text internally and compares consecutive observations. Unlike array no-change, it needs no external Memory and does not preserve one original snapshot across disabled intervals.

## Text stored in arrays

Use array-to-text checks when a byte/word region represents text but is not a PLC STRING/WSTRING object:

| Array element storage | Expected text | Family suffixes |
| --- | --- | --- |
| BYTE | STRING | Byte or Char |
| WORD | WSTRING | Word or WChar |

The families are AssertArrayEqualString, AssertArrayContainsString, AssertArrayStartsWithString and AssertArrayEndsWithString, with WString counterparts for WORD storage.

They use StartIndex, Length, IN and Expected. The selected region contains exactly Length code units. They do not stop at a zero element in IN, trim padding or normalize/convert encodings. Expected follows the configured scalar text capacity and must not be empty.

For FHeader : AssertArrayStartsWithString_Byte:

```iecst
VAR
    FPacket : ARRAY[0..15] OF BYTE;
    FPrefix : STRING(Tc3UnitTest.Param_Assertions.AssertionStringLength) := 'OK:';
END_VAR
```

```iecst
FHeader(Enable := Enable,
    State := State,
    StartIndex := 0,
    Length := 16,
    IN := FPacket,
    Expected := FPrefix);
```

Only the prefix must match here. With AssertArrayEqualString_Byte, the whole selected region must have the same content length as Expected; padding and a trailing zero are not silently ignored. Select the actual meaningful region if equality is the requirement.

A valid nonempty text too long to match the selected region yields Failed for these text-bridge predicates. This differs from an oversized array pattern in ContainsArray, which is rejected as invalid configuration. Use the actual family's interface and semantics rather than treating every pattern check as interchangeable.

## Token positions and counts

These families operate on BYTE or WORD array elements, not protocol frames. The Test Case still owns framing, checksums and protocol interpretation.

All select IN through StartIndex and Length : USINT. A value token is one BYTE/WORD, optionally compared through Mask. An array token is a complete read-only ARRAY[*] of that element type and is compared exactly. An array token must be nonempty and fit within the selected search length; invalid ranges or tokens cause Error.

### Length before the first token

AssertLengthUntilValue* and AssertLengthUntilArray* find the first token and compare the number of preceding elements, excluding the token itself.

All six relations use Expected : USINT for the comparison value, including LessThan and GreaterThan. Do not substitute Maximum/Minimum from the scalar numeric API.

For FPayloadLength : AssertLengthUntilValueEqual_Byte:

```iecst
FPayloadLength(Enable := Enable,
    State := State,
    StartIndex := 0,
    Length := 16,
    Expected := 5,
    Token := BYTE#16#00,
    IN := FPacket);
```

A zero token at index 5 yields measured length 5. A token at StartIndex yields zero. Missing tokens always produce Failed, including NotEqual: the check requires an actual delimiter position before comparing its distance.

Length is measured in array elements. A WORD token at distance five is five elements, not ten bytes.

### Number of occurrences

AssertValueTokenCnt* and AssertArrayTokenCnt* compare a UINT count using equality, inequality, limits or inclusive ranges. Here the parameter names follow the relation: Expected, Minimum, Maximum, or both bounds. AssertNoValueToken and AssertNoArrayToken express zero occurrences directly.

Array tokens occupy their entire matched range. Counting is non-overlapping: after a match, the next search begins after that token. For input [1, 1, 1] and token [1, 1], the count is one, not two.

```iecst
VAR
    FTokenData : ARRAY[0..5] OF BYTE := [1, 2, 1, 2, 0, 0];
    FToken : ARRAY[0..1] OF BYTE := [1, 2];
    FTokenOccurrences : Tc3UnitTest.AssertArrayTokenCntEqual_Byte;
END_VAR
```

```iecst
FTokenOccurrences(Enable := Enable,
    State := State,
    StartIndex := 0,
    Length := 6,
    Expected := UINT#2,
    IN := FTokenData,
    Token := FToken);
```

TokenCount is the last evaluated count, not an always-live query of the array. It is retained when disabled or after a held Failed result, and cleared by Reset or applicable configuration-error handling. Use Result and activity context with it; zero alone is not evidence that a valid search ran.

A missing token is count zero and can therefore satisfy an appropriate count predicate. That is deliberately different from LengthUntil, where no token means no position to compare.

## Durations, dates and time of day

Temporal families cover TIME, LTIME, DATE, DT, LDT, TOD and LTOD. Use the datatype that represents the requirement:

- TIME/LTIME for durations.
- DATE for calendar days.
- DT/LDT for date-and-time values.
- TOD/LTOD for time of day.

Equality uses Expected. EarlierThan uses Maximum and is strict; LaterThan uses Minimum and is strict. InTimespan/NotInTimespan use StartTime and EndTime with inclusive boundaries. Reversed boundaries are Error; equal boundaries are valid.

For FDuration : AssertInTimespan_Time:

```iecst
FDuration(Enable := Enable,
    State := State,
    IN := MeasuredDuration,
    StartTime := T#90ms,
    EndTime := T#110ms);
```

These Assertions compare supplied values; they do not start a timer, wait until a deadline or enforce the Test Case timeout. Measure the scenario duration separately and decide when its value should be evaluated.

DATE comparisons use calendar-day identity and ignore hidden time-of-day components in the underlying representation. TOD/LTOD require values below 24 hours; out-of-range values are Error. A timespan that crosses midnight is not expressed by StartTime greater than EndTime: define an appropriate application check or split the requirement.

LDT/LTOD types require a target supporting them; the Build 4026 path supplies those variants. Do not infer older-target availability from a type name in this chapter. There is no DTL Assertion family. Event timestamps and the event communication contract are not substitutes for the checked-value types.

## Diagnostics and custom checks

Assertion findings carry the configured hierarchical Name, optional ResourceName and the owning State passed at the call. The concrete family formats relevant expected/actual values, limits or indices. Value previews are bounded (normally 40 output bytes), and event messages have capacity 254; a preview is not a lossless dump of the compared object.

String, WString, ByteArray and WordArray previews retain printable ASCII code units and replace each other input byte or wide code unit with exactly one byte `16#D7` (decimal 215). This is a diagnostic replacement marker with no required glyph. It does not expand one input unit into several escape characters, and it does not change comparison inputs or results. Zero terminates STRING/WSTRING input; zero inside the selected array range is data and receives the marker. Quotes and backslashes are retained without escaping. The 40-byte bound includes enclosing quotes and any shortening ellipsis.

The owning Test Case aggregates results and emits its final Result and Assertion aggregation events. Do not publish another copy from ProcessAssertions or interpret free-form finding text as the machine-readable result.

When a check does not behave as expected, inspect in this order:

1. IsInitialized and identity diagnostics.
2. Whether a queued Reset consumed this call.
3. Enabled, ObservationActive and EvaluationActive.
4. The scenario's observation/evaluation endpoint and call order.
5. The actual typed bindings, selected ranges, expected data and snapshot ownership.
6. The held Result and its first Failed/Error finding.

If no supplied family expresses a recurring condition clearly, a dedicated Assertion may derive from AssertionBase, or AssertionWithEvaluationBase when observation and evaluation genuinely differ. The derived FB body calls SUPER^ once; protected Assert performs the typed work; ResetAssertion clears only its own resettable state.

Use the supplied protected Pass, Fail and Error methods. Validate prerequisites before accessing data, consider errors before ordinary failures, and do not skip an applicable Error check solely because a prior call failed. Preserve observation/evaluation gates and first-cycle/reset behavior. Do not turn the Assertion into a second Test Case with stimuli, lifecycle control or timeout orchestration.

Prefer combining existing focused Assertions in the Test Case when that already expresses the intent. More generic plumbing is not useful merely to avoid a few explicit calls.

## Authoring checklist

- Each independently meaningful condition has its own initialized, uniquely named instance.
- The selected family matches the checked datatype and intended relation.
- Resource stimuli and the observation window belong to the Test Case.
- Calls continue with appropriate disabled inputs so reset/history processing remains correct.
- Explicit evaluation occurs at the defined endpoint before test completion.
- ObserveFirstCycle matches the tested block's actual call order.
- Array bounds, expected-pattern length and snapshot storage are valid and stable.
- Scalar history and array snapshot semantics are not confused.
- Empty text, non-finite values and missing tokens use the chosen family's rules.
- Each owned Assertion contributes once to every aggregation, irrespective of its current Enable.
- Held failures are not erased by reinitializing or resetting during the scenario.
- Findings supply context without duplicate owner finalization events.

Return to [Test Case authoring](test-case.md) to integrate the checks into the lifecycle, or the [framework model](framework-model.md) for the complete hierarchy.
