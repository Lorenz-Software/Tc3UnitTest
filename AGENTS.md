# Repository Agent Workflow

This file defines the collaboration rules for the public TC3 UnitTest repository.
Explicit user instructions take precedence. Keep these rules self-contained and
suitable for publication. Do not include private paths, hostnames, credentials,
internal work-item references, or confidential source identities.

## Product and responsibility

- TC3 UnitTest is an independent PLC-side unit-test framework for Beckhoff
  TwinCAT 3. A separate PC application consumes its results; that application
  is maintained outside this repository.
- The PLC product owns the PLC/PC contracts: published symbols and layouts,
  protocol versions, commands, status, results, events, and acknowledgement and
  error behavior. The PC application and import tools consume those contracts.
- The S7 predecessor is a design reference, not a dependency or a compatibility
  promise. Public builds and documentation must work without private repositories.
- This repository owns public presentation, import reconciliation, packaging,
  maintenance, release automation, and publication. Development snapshots arrive
  from a separate source project. Do not modify that project as a side effect.

## Start of work and Git

- Inspect the current branch, configured remotes, and tracked and untracked
  changes before substantial work. Fetch when remote freshness matters. Do not
  assume a branch name, remote destination, or integration branch already exists.
- Prefer short-lived task branches for substantial changes once the branch
  strategy is established. Do not introduce a permanent development branch or
  rename the default branch without agreement.
- Preserve unrelated user changes. Do not discard, overwrite, clean, or stash
  them without authorization covering those changes.
- Do not use blanket cleanup of ignored files, including `git clean -x` or `-X`.
  Inspect and scope authorized cleanup to named output paths; preserve task records.
- Commits, pushes, merges, branch deletion, history changes, tags, and release
  publication require explicit authorization unless already covered by the user's
  instructions. A task approval does not implicitly authorize publication.
- Before committing, inspect status and the complete intended diff, including
  new files. Stage named paths, keep commits focused, and use concrete messages.
- Confirm the actual remote destination before pushing. Do not force-push or
  rewrite shared history by default.

## Local TODO workflow

- Use ignored `.local-work/` for task tracking and session handoffs. There is no
  GitLab or remote issue workflow. Do not create issues, boards, or remote task
  records unless the user requests them.
- Read `.local-work/README.md` for the task index and current focus. Create tasks
  from `.local-work/TEMPLATE.md` in `.local-work/tasks/` using stable filenames
  such as `0001-public-product-setup.md`. Allocate the next unused number; do not
  renumber, relocate, or delete tasks merely because their status changes.
- Before non-trivial work, check for an existing task. Create or update the local
  TODO as part of authorized work; small direct requests need no separate TODO.
- Each TODO owns its objective, scope, deliverables, acceptance criteria,
  verification expectations, decisions, and detailed progress. Keep its summary
  row in the index consistent in the same update; avoid duplicating the work log.
- Split larger tasks into meaningful work packages based on their actual content,
  such as snapshot import, authoring documentation, packaging, or runtime validation.
  Keep tracking flat unless a split is agreed or requested.
- Work on one package at a time. Complete its implementation, documentation, and
  relevant checks. Continue with further packages when they are within the user's
  authorized scope; otherwise report the next proposed package.
- Use `open`, `in-progress`, `blocked`, `done`, and `cancelled` states. Record
  concrete blockers and unresolved decisions. Mark a package or task done only
  when its agreed deliverables and acceptance criteria are satisfied.
- If scope is unclear, record a refinement package and resolve material decisions
  before dependent implementation. A TODO is not authorization to change product
  contracts, access a runtime, or publish repository content.
- On completion, record changes, checks and results, limitations, remaining work,
  and the next step. Retain completed tasks for local continuity.
- If the local store is absent, recreate its index and template when needed and
  report missing historical context. Never infer past completion from missing files.
- Use `.tmp/` for temporary scripts, probes, and analysis output. Keep task records,
  temporary exports, and session notes untracked. Verify exclusion before writing
  them; never force-add or selectively unignore temporary content.

## Product orientation

Before relevant product work, read the available owning documents:

1. `README.md` and `LICENSE`.
2. `docs/authoring/framework-model.md`, `docs/framework-architecture.md`,
   `contracts/README.md`, and the detailed contracts relevant to the task.
3. The relevant authoring guides for Test Cases, Preparations, Assertions,
   Test Suites, and Run Control under `docs/authoring/`.
4. `docs/project-layout.md`, `docs/build-workflow.md`, and
   `docs/selftest-strategy.md`.
5. The documentation generator and event-consumer instructions under `tools/`,
   and `skills/tc3unittest-framework-authoring/SKILL.md` when authoring framework code.

These paths describe the expected product input, not files guaranteed to exist
before the first import. Inspect the repository first. Report missing materials
and obtain the prepared snapshot rather than inventing APIs or build commands.

## Snapshot integration and public delivery

- Treat each incoming snapshot as a deliberate integration, not an instruction
  to overwrite the checkout. Obtain its location and transfer evidence; verify
  recorded paths, hashes, source identity, and artifact provenance before import.
- Present a concrete import, removal, and retention plan before a replacement
  that deletes or overwrites existing material, unless that exact scope is already
  authorized. Preserve repository-owned collaboration rules, public documentation,
  packaging, and hosting configuration.
- Make additions, deletions, renames, and deliberate receiving-side adaptations
  reviewable. Record public-only adaptations so later imports can reconcile them.
  Distinguish presentation and tooling changes from framework changes; report
  framework changes for reconciliation with the source project.
- Keep transfer evidence in the ignored local store unless a reviewed public
  provenance policy defines a sanitized, durable destination. Do not publish
  raw transfer evidence or internal identifiers automatically.
- Preserve licensing, author attribution, product identity, and version semantics.
  Establish correspondence between each released artifact and its exact public
  source revision; verify or rebuild affected artifacts after public-side changes.
- The product includes the Build 4026 solution, framework library packages,
  architecture and authoring documentation, public contracts, offline HTML help,
  the canonical installable authoring skill, and required build and ADS tools.
  Preserve the product skill and its AI-assisted authoring guidance. Internal
  engineering skills, exporters, and session infrastructure are not product input.
- Use actual public URLs and download locations. Resolve missing repository or
  organization details rather than inventing links or badges.
- Scan public deliverables for private hostnames, machine paths, internal issue
  references, credentials, session instructions, broken links, and obsolete files.
  Public integration examples remain product content even when they mention GitLab.

## Design and implementation

- Preserve the documented hierarchy: Run Control owns Suites; Suites own Test
  Cases; Test Cases use Preparations and Assertions. The Orchestrator is a helper,
  not another reportable owner level.
- Respect owner-base lifecycle, timeout, result, and event responsibilities,
  static configuration, deterministic cyclic execution, and the distinction
  between initialization and lifecycle Reset. Consult contracts for exact behavior.
- The Event Buffer, FIFO, publisher, and external acknowledgement path are part
  of the system. Completion or a status bit alone does not establish valid results.
- Align material changes to architecture, contracts, public interfaces, behavior,
  lifecycle, result semantics, and normative style rules with the owner before
  applying them. Describe the concrete decision, options, and consequences.
  Routine implementation choices within approved scope need no repeated approval.
- For approved contract changes, update the responsible contracts and design
  documentation before deriving implementation. Do not adapt contracts merely
  to match an importer or current PC application behavior.
- Follow the available general TwinCAT styleguide, project-specific guidance,
  architecture, and contracts. Resolve conflicts explicitly; do not silently
  introduce a competing convention through code or append contradictory rules.
- Review readability, responsibility and state ownership, failure behavior,
  unnecessary indirection, cyclic execution cost, and practical testability.
  A successful build alone is not sufficient review evidence.
- Keep changes focused. Reconcile the agreed scope with source, declaration
  comments, contracts, and owning documentation before reporting completion.

## Artifacts and verification

- Follow `.gitattributes` where present; use CRLF for repository text by default.
  Prefer Windows and PowerShell-compatible commands. Inspect documented tool and
  dependency versions before rebuilding; do not assume prerequisites are installed.
- Put generated build, validation, help, packaging, and release output under ignored
  `artifacts/` unless a documented tool requires another ignored local directory.
- Treat libraries, compiled libraries, TwinCAT archives, and help ZIPs as generated
  artifacts. Prefer explicit release assets. Versioning binaries requires agreement
  on exact paths, ignore exceptions, and LFS handling. An LFS rule alone does not
  authorize committing a binary; do not force-add ignored output.
- Run checks appropriate to the change. For documentation changes, review text,
  links, and `git diff --check`. For implementation, build affected components and
  run relevant available tests. Add tests when behavior and risk justify them.
- Review dependency licenses and redistribution obligations when adding or updating
  production dependencies. Update the responsible notices and inventory.
- Keep source review, compiler/static checks, documentation builds and browser
  checks, and PLC runtime tests distinct in reports. Record unavailable prerequisites
  and unexecuted checks; do not report planned or inherited tests as executed.
- The supplied product targets TwinCAT Build 4026. Existing Windows Usermode
  Runtime / x64 evidence does not qualify other targets. Do not promise native
  TwinCAT builds on generic hosted runners without establishing prerequisites.
- Before each XAE object check or rebuild, capture existing diagnostics, run the
  operation to completion, and capture its result and subsequent diagnostics.
  Do not clear the Error List automatically or attribute old entries to a new run.
  Report failed reads or ambiguous attribution explicitly.
- Verify saved repository files after engineering edits. An in-memory compiler
  check or successful tool response does not establish persistence. Report any
  divergence between live XAE content and disk; do not mark unsaved work complete.

## Runtime and machine access

- Inspect and modify only the intended repository solution and authorized local
  outputs. Do not disturb another engineering session or consumer.
- Runtime downloads, configuration activation, online control, runtime restarts,
  boot-project creation, hardware scans, license changes, and global library
  repository changes require explicit authorization for the concrete operation
  and target. Do not select remote routes or targets without explicit authorization.
- Coordinate runtime testing with the owner. The event consumer needs exclusive
  acknowledgement ownership; do not compete with another consumer.
- Respect tool-specific confirmation requirements. Do not invoke arbitrary XAE
  commands as a workaround for missing authorization.
- Do not invoke `TcPkg` from the sandbox: even inspection can cause system-wide
  logging, permission changes, or dialogs. Leave provisioning to the owner unless
  an explicitly approved safe invocation is established.

## Documentation and session handoff

- Use English for repository content, comments, commit messages, and local task
  records. Conversation with the user may be in German.
- Keep durable product decisions in their responsible documentation. Keep task
  sequencing, execution notes, temporary analysis, and current progress in the
  local store. Agent instructions define stable rules, not the current work plan.
- Prefer concise Markdown. Keep public documentation independent of private
  infrastructure, local task IDs, machine-specific paths, and temporary evidence.
- At session end, update `.local-work/README.md` and the active task with the
  current branch, completed package, verification, open decisions, and next step.
  Report the handoff path and Git status. Do not assume a session script exists.
- For analysis-only requests, do not edit files. For implementation requests,
  complete the authorized work and report changes, verification, and limitations.
