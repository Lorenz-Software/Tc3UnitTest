# Project configuration

The JSON configuration is an internal generator input. It is maintained by the
consuming project and kept separate from the API model and default template.

| Field | Meaning |
| --- | --- |
| `libraryNamespace` | Optional explicit API namespace when no `library` source is configured; otherwise must match the project. |
| `sourceRoot` | Directory of saved TwinCAT sources, relative to the project root. |
| `includeTypes` | Explicit unique object names; each must resolve once under the source root. Empty in automatic selection mode. |
| `selection` | Optional public Compile-source selection with `projectFile` and explained `exclusions` (`name`, `reason`). |
| `product`, `publisher`, `brandMark`, `subtitle`, `edition` | Product labels and scope text. |
| `packageFile` | ZIP filename without a directory component; optional `{version}` is replaced by the checked library version. |
| `stylesheet` | Project CSS overrides, relative to the configuration directory. |
| `overview.title`, `overview.introduction`, `overview.sections` | Authored overview text; sections contain `heading` and `text`. |
| `groups` | Functional areas with `title`, `description` and selected `types`. Every included type belongs to exactly one area. |
| `attribution` | Author, contact, copyright, license and optional branding. |
| `guide` | Optional guide title, source root and ordered chapters with API associations. |
| `library` | Optional saved PLC project, generated-version and contract-version sources. |

Attribution requires `author`, `contactEmail`, `copyright`, `licenseName` and
`licenseFile`. The license path is relative to the project root; its bytes are
copied unchanged to `LICENSE.txt`. Optional `website` must be an HTTP(S) URL.
Optional `logoFile` and `headerLogoFile` are relative to the configuration
directory. These are original image assets, copied unchanged into the package.
The full logo links to the website on the About page; the compact header logo
links to that local page. No author block occupies the navigation sidebar.

Project paths stay below their owning directory. Unknown configuration fields,
duplicate selection or group membership and unresolved object names fail rather
than silently dropping content. `includeTypes` is a selection mechanism, not a
claim that all declaration forms are supported.

## Complete API selection

With `selection`, set `includeTypes: []` and give each group an empty `types`
list plus a `sourcePrefix` relative to `sourceRoot`. All public source roots are
included except explicitly explained exclusions; protected/public members and
required declaration dependencies follow transitively. Every selected source
must match exactly one area prefix. Adding a new public object under an existing
area needs no manually maintained name list. An unclassified area, stale
exclusion, missing/duplicate Compile source or unreferenced source fails.

Selection reads saved, unconditional literal Compile paths, without evaluating
imports, properties, wildcards or conditions. The configured source root is the
scope boundary; sources elsewhere in the project do not enter the consumer API.
Internal types required by exported signatures are included and marked with
their source visibility, rather than being advertised as general extension
points. Unreferenced internal objects and private/internal members stay out.
`export-coverage.json` records inclusion/exclusion reasons for every source under
that boundary. Reconcile it with the independent project inventory for acceptance.

Supported data forms are structures, unions, enums and aliases. Enum declared
values, underlying type and default are retained; no constant evaluation is
performed. Functions retain parameters and return descriptions. Property pages
identify available Get/Set accessors without making separate accessor pages.
Only the reviewed source forms are supported; selection does not grant full
grammar or external symbol resolution. No automatic description inheritance is
invented for overrides: their saved local declaration documentation is shown,
and inherited member links identify the actual declaring type.

## Library metadata, versions and parameters

`library` contains `projectFile`, `generatedVersionFile`,
`generatedVersionSymbol` and `contracts`. All file paths are project-root-relative.
The project supplies `Company`, `Title`, `DefaultNamespace` and the four-component
`ProjectVersion`; `publisher` and `libraryNamespace` can then be omitted. Explicit
duplicates must match. Company is the publisher; the configured product label,
author contact, copyright, website and logos remain presentation/project data.
Only unconditional literal identity properties are supported; this is not an
MSBuild evaluator. Version components must fit the generated UINT representation.

The generated version symbol must have the reviewed ST_LibVersion initializer
with matching iMajor/iMinor/iBuild/iRevision and sVersion. Three-component
FrameworkVersion omits revision as required by the consuming project's contract.
Each contract binding supplies `title`, `file`, `constantsFile` and `constant`.
The Markdown file must contain one `- Contract version: ` marker followed by a
backtick-quoted three-component version. Its bound string constant must match;
the referenced local numeric STRING capacity must accommodate version text.
Different contracts and the library may have different versions. XML format and
TwinCAT tool versions are never substituted for the library version.

Include constant lists and parameter lists by object name through `includeTypes`.
They require one VAR_GLOBAL CONSTANT block with explicit initializers. The saved
XML `ParameterList` attribute determines whether values are consumer-overridable
library defaults or fixed constants. Native comments and expressions are retained;
the extractor does not compute effective application overrides or constant values.
Selected qualified constant references link to field anchors; reverse references
cover declarations in this export only. Single-block mutable GVLs are also supported and identified as library-owned storage/bindings; their initializers are startup declarations, not runtime snapshots.

About shows library identity, independent contract versions and source identity.
The footer identifies the library version. Packaged `help-build.json` records
input SHA-256 hashes (selected PLC objects, or every source under an automatic selection boundary, project/generated metadata, contracts,
guides, configuration, assets, license, template and generator assembly), commit
and working-tree state. Nested non-repository fixtures do not inherit a parent
repository identity; unavailable identity is explicit. Inputs are rechecked before
the manifest is finalized. This internal evidence has no stable public schema and
does not define a release approval or prove a compiled library binary's provenance.

## Authored guides

`guide` contains `title`, `sourceRoot` (relative to the project root) and ordered
`chapters`. Each chapter has a `file` basename ending in `.md` and an `apiTypes`
list of related library type names. Optional `introduction` provides the project-specific
entry text for the guide overview and its link from the library overview.
Titles come from the chapter's opening H1.
The current ingestion supports selected chapters in one directory. Reserved page
names, duplicate chapters and API filename collisions fail explicitly.

The build stages copies of the Markdown without editing the authored files.
DocFX renders their tables, fenced examples and relative chapter/fragment links;
linked local chapters must be selected. The generic conceptual template uses the
same shell, styles, search and themes as the API pages. The guide overview and
related-API sections are generated. Included types receive working links and
reverse links to chapters; other names are labelled outside this API export.
API associations are curated project metadata. Identifiers inside examples are
not automatically interpreted as library symbols. Guide source hashes and the
rendered code examples are checked separately from PLC source extraction.

## Template and styling

The default template lives only in `assets/default-template/`. English UI labels,
element symbols, page composition and the catalog page size (50) are generic
presentation behavior. Project-specific names and categories do not belong there.
Element categories appear in the shared order Data types, Interfaces, Blocks,
then Parameters and constants and Other elements, independent of source-file or selection order.

Project CSS loads after default CSS. Override color, typography and spacing
tokens as required. Logo display uses `--author-logo-width`,
`--header-author-logo-width`, `--author-logo-background` and
`--author-logo-padding`. Responsive `max-width` and automatic height preserve
image proportions; choose sizes below the source resolution at the intended
device pixel ratio. Do not recolor or distort original logos implicitly.

The page frame reserves viewport rows for the header and persistent footer;
content, navigation and outline scroll between them. The theme control sits in
the footer. Printing removes those viewport constraints. Light/dark colors use
CSS variables selected by the root `data-theme` attribute, not stylesheet swaps.

Navigation starts with Documentation (overview, optional guide, API catalog),
followed by Areas and Element types. Guide chapters form a collapsible subtree
under the guide entry, automatically expanded on guide pages. Current-type members
appear in a contextual section. A filled highlight identifies the current page; a
lighter highlight indicates its parent section. Global search opens from the
header beside the optional author logo, or through Ctrl+K / the slash key.
Its modal keeps the navigation intact; Escape closes it. Catalog filters remain
local to the catalog.

## Build boundary

`scripts/build-help.ps1` takes explicit project, configuration, output and DocFX
paths. `-CompilerPath` optionally places the compiler cache outside the default
`<output>/_compiler`. Intermediate model/YAML, compiler output, HTML, browser
profiles and ZIPs are generated artifacts; maintain their sources instead.

The supplied CLI reads no project-specific test names or source layout. The
generic checks validate selected API descriptions, local links, catalog/search,
themes and offline resources. Projects may add more detailed regressions for
their real source content without changing the generator or template.
