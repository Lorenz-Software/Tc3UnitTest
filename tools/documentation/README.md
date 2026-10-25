# TC3 UnitTest documentation adapter

The reusable generator and its single default template are bundled under
`generator/`; see the [generator usage guide](generator-usage.md).
Project-specific configuration, branding, build entry points and regression
checks live alongside that generator. Configure project styling and assets
through the adapter rather than duplicating the converter or default template.

```powershell
.\tools\documentation\inventory-project.ps1
.\tools\documentation\build-help.ps1 -VerifyBrowser
node tools/documentation/tests/verify-reference.cjs
node tools/documentation/tests/verify-reference-browser.cjs
.\tools\documentation\tests\verify-reproducibility.ps1
node tools/documentation/tests/verify-selection.cjs
.\tools\documentation\build-help.ps1 -Sample -VerifyBrowser
node tools/documentation/tests/verify-inventory.cjs
.\tools\documentation\tests\verify-project-inventory.ps1
node tools/documentation/tests/verify-comment-audit.cjs
.\tools\documentation\audit-source-comments.ps1
node tools/documentation/verify-configuration.cjs
node tools/documentation/tests/verify-metadata.cjs
.\tools\documentation\tests\verify-portable.ps1 -VerifyBrowser
```

The default build uses `projects/tc3-unittest/reference.json` to select the
complete agreed consumer API from saved Framework Compile sources: public
objects, protected/public members and their required declaration dependencies.
It delegates extraction, rendering, packaging and generic offline verification
to the generator. Every Framework source receives a disposition in
`export-coverage.json`; `tests/verify-reference.cjs` independently reconciles
exported declarations, fields/parameters/enum values, returns and accessors
against the project inventory. Run the inventory wrapper first when sources
have changed.

`-Sample` retains the small regression selection: AssertionBase, AssertTrue,
I_Assertion, I_ResultProvider, ST_Event, two parameter lists and GVL_Constants.
With `-VerifyBrowser` it additionally runs `tests/verify-sample.cjs` for detailed
source-specific layout evidence.
`-BrowserPath <executable>` selects a Chromium browser explicitly; Chrome is the
default. These are hidden, isolated check sessions.

## Maintained project inputs

`projects/tc3-unittest/inventory.json` separately defines all framework areas,
Runtime and SelfTests, plus the explicitly excluded generated cache directories.
The inventory wrapper writes the complete saved-project ledger below
`artifacts/documentation/project-inventory/`. It is independent of the sample
HTML selection. Every acceptance dimension initially remains Open; presence
counts do not establish documentation quality. See the generator's
[inventory boundaries](../../tools/documentation/generator/references/project-inventory.md).

`projects/tc3-unittest/comment-format.json` selects the source profile from the
project's source documentation profile: one TE1030 block-comment header inside a `Documentation` region,
with the reviewed markup vocabulary. The audit wrapper refreshes the ledger and
writes findings below `artifacts/documentation/source-comment-audit/`. It returns
failure while format or relevance findings remain. The audit does not generate
HTML, modify PLC code or establish semantic acceptance.

- `projects/tc3-unittest/reference.json`: automatic source selection, explained exclusions, area prefixes and full-reference text.
- `projects/tc3-unittest/sample.json`: `sourceRoot`, `includeTypes`, metadata source bindings,
  overview text, area membership, product labels, author, contact and license.
- `projects/tc3-unittest/project.css`: project-specific style overrides.
- `projects/tc3-unittest/assets/`: unchanged owner-supplied original PNG files.
- The repository's PLC sources, `LICENSE` and `docs/authoring/` remain in their
  responsible source locations. The seven authoring chapters are selected in
  configuration, rendered from staged Markdown copies and included in the ZIP.
  Chapter order and related API names belong to project configuration; chapter
  navigation, shared search and bidirectional links belong to the reusable generator.

See the generator's [configuration reference](../../tools/documentation/generator/references/project-configuration.md)
for generic settings and extension points. Full output remains ignored under
`artifacts/documentation/reference/`; the sample uses
`artifacts/documentation/sample/`.

## Regeneration and delivery

Run the default build after saving sources. Prerequisites and pinned DocFX
version are described in [generator usage](generator-usage.md); use the existing local DocFX executable.
Open `artifacts/documentation/reference/site/index.html` in Chrome for local
inspection. Distribute the generated `tc3-unittest-help-<library-version>.zip`
as a separate help package alongside the matching library binary. Its filename
uses the checked PLC project version through `{version}`, without a duplicate
documentation version constant. The recipient extracts the ZIP and opens
`index.html`; no server, runtime connection or TE1030 license is required.

The ZIP contains only listed help pages, local CSS/JS/logos, the license and
source manifest. Intermediate models, YAML, build logs, compiler files and
browser evidence are excluded. The packager validates the extracted ZIP's
file count and SHA-256 content when `-VerifyBrowser` is used. Regeneration can
compare `package-manifest.json` entries byte for byte; ZIP container timestamps
need not be identical. A changed input snapshot requires regeneration.
Publishing the package or committing a generated/binary artifact still requires
the owner's separate approval.

The full export includes single-block mutable GVLs and public functions as well
as structures, enums, aliases, interfaces and function blocks. E_EventPublishResult
requires the internal E_FifoResult definition; GVL_EventBuffer exposes the internal
EventBuffer instance. These dependencies are included with an explicit internal
visibility note. Private members, unreferenced internal utilities and Runtime/
SelfTests are excluded. Generated Global_Version is validated as metadata and
presented on About instead of receiving a consumer extension page. All these
dispositions are checked against saved sources, not inferred from a page count.

The generator does not evaluate expressions or application parameter overrides,
resolve external-library symbols, evaluate conditional/imported MSBuild, or
support arbitrary ST grammar. It supports the declaration forms in this saved
consumer API; unsupported inputs fail. Plain ST declarations have no syntax
highlighting. Semantic documentation cross-review and offline PLC object checks
are separate evidence; a rendered page is not a runtime behavior test.

The full wordmark asset is 1711 × 632 pixels; the symbol is 425 × 422 pixels.
Both have transparency. This project sets a 400-CSS-pixel maximum wordmark width
and a 32-CSS-pixel header symbol. The full logo has a light underlay in both themes
because its slogan is dark. The header symbol opens the local author page, which
links to the owner-provided https://www.lorenz-software.solutions/ website.
No network image fetch is needed to open the help.

## Version and configuration provenance

Company, library title, namespace and version come from the saved PLC project.
Generation checks that its version equals the saved generated ST_LibVersion
numbers and string. Direct Access and Event Stream retain their independently
versioned contracts; their documented versions must match GVL_Constants.
These checks validate the existing version rules in
[build workflow](../../docs/build-workflow.md#packaging-boundary) and the responsible
contracts; they introduce no separately maintained documentation version.

The footer shows the library version; About includes identity, contract versions,
commit and local-change status. The packaged help-build.json identifies the
generation inputs by SHA-256. Per-block semantic versions are not maintained;
the XML TcPlcObject version is a file-format marker. The documentation does not
represent effective parameter overrides of a consumer project. Parameter-list
pages show declared compile-time defaults; the constant-list page shows fixed
values and references within the selected export. No source comments, PLC
declarations, contracts or runtime behavior are changed by generation. Native library packaging separately projects these same marked declaration comments to plain-text comments in its disposable copy; the source-visible library therefore has native documentation without changing the canonical TE1030 source format.

The generated authoring entry includes installation, direct dependency needs, parameter editing and version/visibility interpretation. Library default values and per-consumer effective overrides remain distinct. The release association with built binaries is established by the release provenance and consumer evidence, not by this source-only generator.

## Verification boundaries

`verify-configuration.cjs` uses the real source sample with different project
metadata to check that identity and grouping are not embedded in the template.
`tests/verify-metadata.cjs` independently checks saved-project identity, generated
metadata, different contract version numbers and mismatch rejection, using
isolated fixtures rather than edits to production sources.
`tests/verify-portable.ps1` copies the unchanged generator into an ignored validation
workspace and builds a separate synthetic three-type project with another source
layout, namespace and identity. It uses the generic entry point without this
repository's wrapper or source files. With `-VerifyBrowser`, its extracted ZIP is
also inspected through the generic offline browser checks.

The project regression additionally checks native/structured descriptions,
inherited-member links, logo scaling, frame scrolling, print styling and a
separate synthetic 620-entry catalog. That navigation fixture does not claim
full-library extraction coverage; the full-reference inventory reconciliation and generic all-page browser checks provide that separate evidence. None of these checks compile PLC code or run
a TwinCAT runtime. No generated output or binary release artifact is committed
by these commands.
