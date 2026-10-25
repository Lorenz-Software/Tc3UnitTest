# Contracts

This directory contains the PLC-owned interface contracts for the TC3 UnitTest library.

Contracts define externally visible behavior that consumers can rely on. They are not a place for historical analysis, implementation notes, target vision, or unresolved design discussion.

## Scope

Contracts in this directory may define:

- PLC/PC protocol semantics
- PLC data structures exposed to the PC runner
- symbolic access paths
- status, error, and result semantics
- protocol versioning and compatibility rules
- acknowledgement and handover behavior

Contracts in this directory must not define:

- PC-side implementation details
- TwinCAT project setup instructions
- open brainstorming notes
- draft ideas that are not ready to become part of the repository state

## Ownership

The PLC project owns the PLC/PC interface contract.

The PC-side runner consumes the contract. It must not independently define PLC symbol names, symbolic paths, exposed data types, status values, or error semantics.

## Authoring Rules

Use standardized normative language where possible:

- `MUST` / `MUST NOT` for mandatory requirements
- `SHOULD` / `SHOULD NOT` for recommended requirements
- `MAY` for explicitly allowed optional behavior

Normative requirements must be written in a consistent leading requirements list or table.

Each normative requirement must have a stable requirement ID.

Complex requirements should first be checked for possible split into smaller requirements.

If a complex requirement intentionally remains a single requirement, its compact list entry must reference a dedicated details section.

Requirement details sections may clarify conditions, behavior, examples, or explanations, but must not introduce hidden additional normative requirements.

## Document Structure

Contract documents should use this structure unless there is a specific reason to deviate:

1. Purpose
2. Scope
3. Terms
4. Version
5. Requirements
6. Requirement Details
7. Compatibility
8. Non-Requirements, only when explicit in-topic exclusions need to be made visible

The `Requirements` section is the leading normative structure. Other sections must not hide additional normative requirements.

`Non-Requirements` is not a mandatory filler section. Use it only for explicit exclusions that are close enough to the contract topic that readers could otherwise reasonably expect them to be covered.

## Versioning

Contract documents are not committed as drafts. When a contract is added, it must be brought to an explicit semantic version starting with `1.0.0`.

Contract document filenames do not carry version suffixes. The latest valid contract state is represented by the repository content.

## Change Control

Any definition or modification of contracts or contract-like documents must be coordinated with the project owner before it is applied.

## Current Contracts

- `general-framework-contract.md`
- `run-control-contract.md`
- `test-suite-contract.md`
- `test-case-contract.md`
- `event-stream-contract.md`

The generic FIFO is an internal implementation utility and does not own PLC/PC communication semantics or the external symbol surface.
