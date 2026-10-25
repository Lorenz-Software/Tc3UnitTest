# Fixed-Capacity FIFO Design

## Boundary and execution

The `Fifo` function block is an internal, `ST_Event`-specific utility under `Framework/Common/Fifo/`, included in the development solution and the UnitTest library packaging boundary. Consumers do not need a separate FIFO library. Separate library extraction is not planned.

The FIFO stores complete `ST_Event` values but does not interpret their fields. Sequence assignment, timestamps, reservations, deletion watermarks and external publication remain Event Buffer responsibilities. No command/control DUT or global communication variables are required by the FIFO itself.

Internal framework owners compose the concrete `Fifo` FB. Its methods encapsulate storage and ring management without an `I_Fifo` or separate role interfaces. All operations use the same authoritative state. The FIFO is not part of the public framework API; packaging inclusion does not imply public API exposure. FIFO tests remain under `SelfTests/`.

Methods execute immediately, as an explicit exception to the normal cyclic FB execution model: insertion/removal must finish in the caller's operation sequence. Calls are serialized within one PLC task. This design does not provide multi-task synchronization or asynchronous external access to the storage.

## Storage binding and ownership

- `Initialize` binds `Buffer : ARRAY[*] OF ST_Event` through `VAR_IN_OUT` and accepts `OverwriteIfFull : BOOL := FALSE` as configuration. No empty-element argument is required.
- Physical length is calculated from `LOWER_BOUND` and `UPPER_BOUND`, not from an `ANY` descriptor or pointer size. It must be between 3 and 32767 inclusive. The first array element maps to logical FIFO index 1, regardless of the array's declared lower bound.
- The FIFO retains a typed `POINTER TO ST_Event` to the first array element. This encapsulated binding is needed for subsequent method calls without passing the array again. The owner must keep that array alive and stable; no storage is allocated internally.
- `Push(Data : ST_Event)` receives a value copy, so even an aliased input cannot be overwritten while it is being copied into its destination slot. `Read` and `Pop` receive `Target : ST_Event` through `VAR_IN_OUT`; the target must not overlap the bound array.
- Payload transfer and slot clearing use typed assignments. An internal constant holding the default `ST_Event` value clears removed entries. There are no byte-copy operations, externally supplied element sizes, or externally retained empty-element addresses.
- Configuration and index checks precede every payload access. Output-target overlap is checked before mutation. Type correctness is enforced by the PLC compiler rather than inferred from equal byte sizes.

`FB_reinit` invalidates the binding, and configuration checks reject an altered application Online Change counter. Renewed initialization requires the owner to provide storage again and starts logically empty. This is invalidation, not transparent Online Change continuation. Runtime state and stored addresses are not a persistence mechanism.

## Ring and status

Read and write indices are one-based `UINT` values. One physical slot remains unused, so usable capacity is `BufferLength - 1`, at most 32766 elements. No separately maintained occupancy counter is introduced.

Occupancy is derived from the two indices:

- If the write index is at or after the read index: write index minus read index.
- Otherwise: buffer length minus read index plus write index.

Empty means zero occupied slots. Full means `BufferLength - 1` occupied slots. AlmostFull means exactly `BufferLength - 2` occupied slots and is false when full.

A status snapshot is optional external information, never authoritative input for later operations. Compute it completely from the current binding and indices. Invalid configuration or indices must be distinguishable from a valid empty FIFO; do not expose stale count or flag values as current valid status.

## Operations

| Operation | Behavior |
| --- | --- |
| Initialize | Bind and validate storage; initialize both indices to 1 without clearing payload storage. |
| Reset | Set both indices to 1 without clearing payload storage; discard logical contents, not the existing binding. |
| Push | Copy into the write slot, then advance the write index with wraparound. When full, reject unless the `OverwriteIfFull` configuration selected at Initialize is enabled. With overwrite enabled, also advance the read index to discard the oldest entry. |
| Read | Copy the oldest element into the target without clearing its slot or advancing an index. |
| Pop | Copy the oldest element into the target, copy the empty element into the removed slot, then advance the read index. |
| Release(Count) | Clear and release the oldest contiguous logical range, including across wraparound. Validate the whole requested range before mutation. An excessive count changes nothing; zero is a no-op. |

Push, Read, and Pop return `INT`: a positive physical slot index on success, zero for full rejection or empty as applicable, -1 for configuration error, -2 for index error, and -3 for data error. Restricting physical length to 32767 preserves the positive-slot result range without widening index or result types.

`Initialize` returns `BOOL`; status reports configuration failure. `Reset` has no return value and always resets both indices without accessing payload memory, even when unbound. It does not repair invalid configuration.

`Release` returns `INT`: the requested count on success, zero for a zero-count no-op, or a named negative error. A count greater than current occupancy returns the dedicated range error without changing indices or payloads; it never releases a partial range. This count check does not replace configuration/index validation for nonzero operations.

Use the named `E_FifoResult` members converted to `INT` for the mixed numeric operation result space, not naked error literals. The return remains `INT` because positive values also carry slot indices or counts. Configuration, index, and data errors retain -1, -2, and -3; the additional release-count error is -4. Zero means no transferred elements, not a failed configuration check.

Configuration errors take precedence over index handling. On an index error, Push/Pop reset the indices, return the index error, and do not continue the requested data operation. This discards logical contents; it does not reconstruct damaged indices or clear payload storage. Apply the same error handling model to the added consumer operations. Status queries report errors without resetting indices.

Data errors do not advance indices. Read and Pop reject an output target overlapping the bound array before copying. Pop then copies the oldest event, clears that slot with the default event and advances the read index. Typed access does not make an expired or corrupted stored address safe; storage lifetime remains an owner obligation.

Wraparound checks the last valid slot before incrementing. Initialization rejects larger arrays instead of silently narrowing lengths or returning negative slot numbers.

## Implementation notes and verification boundaries

Internal PLC declarations carry concise source-level purpose and usage notes; no separate internal API reference is maintained.

Successful compilation or an individual payload-copy test does not establish complete FIFO memory safety or Online Change handling. Relevant verification boundaries include minimum and maximum physical lengths, non-default array lower bounds, repeated mixed wraparound, Release across a wrap boundary, invalid binding configuration, corrupted indices and recovery, output alias rejection, and Online Change invalidation. Execution evidence belongs in the responsible validation records, not in this design description.

Index/status work is constant-time; copies scale with element byte size and Release clearing scales with count times element size. Real-time suitability requires bounded configuration and measurement, not assumptions based on CPU speed.
