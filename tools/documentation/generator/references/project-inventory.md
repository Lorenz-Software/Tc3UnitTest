# Saved-project review inventory

`scripts/inventory-project.ps1` reads literal Compile membership in a saved PLC
project and reconciles PLC source files below that project directory. Conditional,
imported, missing, duplicate or unreferenced membership fails explicitly. Optional
scope JSON contains `areas` (`prefix`, `name`, `role`) and `excludedDirectories`
(`path`, `reason`), with paths relative to the PLC project directory. An exclusion
cannot hide a Compile entry. Project roles and directory names belong to this
configuration, not the generic inventory engine.

Outputs are `files.json`, `items.json`, `items.csv`, `input-hashes.json` and
`summary.json`. They are generated review inputs in an ignored artifact directory.
Each object/member, declared variable/parameter, DUT field, enumerator and result
has a stable path/qualified-name identity and saved-source hash. Property accessors
are separate rows. Task files, declared external dependencies and adjacent solution
and system-project files receive explicit metadata rows. Generated objects remain
visible and are labelled for disposition rather than hand-editing.

The inventory uses lexical declaration enumeration, not a complete IEC compiler.
It records signatures, visibility modifiers, parameter direction, types, defaults
and adjacent comment forms without evaluating expressions. An unsupported field
or unresolved block is an error. An unparsed-segment row prevents successful
completion. Alias targets, inherited obligations, effective visibility and
semantic relationships still require review; no resolved inheritance is claimed.

The separate `--audit-comments` command reads this ledger and rejects stale source
hashes before reporting comment conformance. It never uses the HTML parser's
ordinary-comment fallback to pass a header. Its project-owned JSON policy has
`region` (the required folding-region name) and `reviewedMarkup` (the explicitly
reviewed XML vocabulary). The header must be one TE-marked block comment inside
that region, without signatures or attributes inside the folding boundary.
Unknown markup is a review finding, not a claim that TE1030 rejects that syntax.

Audit outputs are `findings.json`, `dispositions.json`, `input-hashes.json` and
`summary.json`. They distinguish format findings from element relevance review.
They explicitly identify generated sources, metadata/dependencies, accessors,
local implementation elements and declared inheritance/interface relationships.
These treatments do not certify behavior or resolve inherited documentation.
Missing element text and parent/markup alternatives require area review; local
variables do not automatically require filler text. Every reported finding keeps
the audit unsuccessful until it is resolved; no source edits are performed.

All review dimensions start Open. Presence flags are candidates, including for
private/local elements; they do not require filler comments on every local variable.
Marking a row Verified or not applicable requires a reasoned review and evidence
appropriate to its role. Metadata and generated sources also need an explicit
disposition. Enumeration does not imply eligibility for consumer help.

Regeneration replaces the generated tables and starts all dimensions Open again.
Keep acceptance decisions and evidence in the consuming project's designated
review record, keyed by item identity and source hash. Do not edit generated JSON
or CSV as the only durable record. A changed source hash requires reconciling the
affected decisions; a stable identity alone does not preserve acceptance.

HTML rendering coverage is narrower than inventory coverage. In particular, enum,
union and general mutable GVL export are not implemented by this command. Native
XAE pattern checks, when requested, must be captured separately through the
engineering workflow, without implying permission for runtime access. A verified
representative pattern may cover repeated syntax forms; a separate TE1030 preview
for every declaration is unnecessary. Keep source-format validation independent
of tolerant HTML extraction and record the final complete-rendering check separately.
