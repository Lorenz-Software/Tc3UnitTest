# Build And Validation Workflow

Status: Active

This document defines the supported engineering environment and repository-owned local build interface. Offline validation and native library packaging use XAE; runtime deployment and test execution remain separate operations.

## Supported Engineering Environments

TwinCAT XAE Shell is the supported engineering host. Visual Studio Professional is not required by this project.

The development environment is TwinCAT 3.1 Build 4026.

Required capabilities for project build and validation are:

- TwinCAT XAE Shell for Build 4026;
- TwinCAT PLC Engineering;
- TwinCAT Automation Interface;
- Windows PowerShell for the stable repository build entry point.

Registered XAE Shell Automation Interface hosts currently include `TcXaeShell.DTE.17.0` and `TcXaeShell.DTE.15.0`. The build automation must validate the configured host and project environment.

Runtime selftests additionally require an accessible Build 4026 XAR and a configured local ADS route.

Visual Studio Professional, TE1200 Static Analysis, TE1030 Documentation Generation, measurement products, and ADS Monitor are optional. Their absence must not prevent the baseline project build. Optional tools may add validation stages only when those stages are explicitly enabled and their results are identified separately.

## Stable Entry Point

Local development and a future Windows CI runner use the same repository-owned command:

```powershell
.\tools\build\build.ps1
```

The script uses XAE Shell DTE and the TwinCAT Automation Interface for TwinCAT operations. Plain MSBuild is not the complete validation path because it does not replace PLC object checks, controlled XAE project handling, library creation, or runtime operations.

The versioned TwinCAT solution is the authoritative build input: `projects/Tc3UnitTest.4026/Tc3UnitTest.4026.sln`. Interactive engineering uses that solution. Offline build automation may use a disposable saved snapshot below `artifacts/`; that snapshot is not another development source.

## Session Selection

Ordinary development builds offer `-SessionMode Auto|Existing|Isolated`. Inspect running XAE instances and match solution/project paths before mutation. Auto reuses one suitable matching session; with no match it creates a build-owned offline host. Ambiguous matches, unsaved edits or a busy session require operator intervention. An inspection failure is not evidence that no project is open.

Packaging always uses build-owned hosts and saved copies at different physical paths. `-Package` selects Isolated automatically and rejects Existing or an explicit attached moniker. It never adds projects to, saves, closes or reloads the owner's working solution. Unsaved editor content is excluded; save first or explicitly use `-UseSavedInputs`.

Temporary TwinCAT and PLC projects receive distinct names with a fresh run token (`UTHost_<token>` and `UTLib_<token>`). Check both names before creation and reject a nonempty temporary destination.

The first owned host validates the saved development snapshot and creates the native Empty PLC Project. Close that host before composing Framework sources, metadata and resolutions on disk. Open the resulting standalone packaging solution in a fresh owned host for validation and export. This avoids relying on type-system initialization after live project/reference changes. A controlled minimal project failed with an unknown ST_LibVersion when composed and checked in place, but passed after opening its saved solution in a fresh host; the exact native cause is not established.

This is an occasional operator-assisted workflow: direct Automation Interface calls, bounded polling, ordinary cleanup and actionable errors. No MCP server, session broker, automatic process killer or recovery service is needed. Close only a host whose process ownership was verified. No library installation, shared IDE setting changes or runtime operations are permitted.

`TcPkg` is not part of a normal build. Even nominally read-only calls can attempt system-wide logging or permission changes and open error dialogs; installation is a separate operator task.

## Command Interface

The command interface is:

```powershell
# Default Build 4026 check and rebuild
.\tools\build\build.ps1

# Create library artifacts after successful validation
.\tools\build\build.ps1 -Package
```

`4026` is the supported target. `-RunSelfTests` and `-Deploy` are reserved switches rejected by this offline command; they are not runnable selftest/deployment examples. Use the separately authorized engineering workflow for runtime validation.

Every selected target receives a complete rebuild. A failed structure check, PLC object check, rebuild, requested runtime operation, or requested packaging operation produces a nonzero process exit code. Warnings are captured in full. Review all warnings under the consuming project's coding policy; successful build status alone is not acceptance.

Each invocation records evidence below `artifacts/build/<target>/<run-id>/`. Disposable saved projects and staged libraries are below `artifacts/<target>/.work/<token>/`. A complete native library pair is copied to `artifacts/<target>/packages/<run-id>/`, together with its manifest; incomplete stages are not promoted. All output remains ignored.

## Local Build Operation

PowerShell 7 forwards the command to Windows PowerShell 5.1 in STA mode for the .NET Framework XAE interop assemblies. The script discovers installed XAE assemblies and the TwinCAT project template; optional installation-path overrides belong in `local/build-settings.psd1`. It calls the Automation Interface directly, without an MCP server, daemon or additional service. An owned host opens its saved snapshot with TwinCAT automation SilentMode disabled and its window visible so that native PLC detail diagnostics are available. Validation temporarily disables SilentMode in an attached host and restores its previous value afterwards; it does not change a shared IDE setting.

```powershell
# Inspect saved inputs and visible sessions without changing XAE
.\tools\build\build.ps1 -Preflight -NonInteractive

# Validate saved inputs in a disposable owned host
.\tools\build\build.ps1 -SessionMode Isolated -Configuration "Release|TwinCAT OS (x64)"

# Package saved disk content even when XAE has unsaved changes; never saves those changes
.\tools\build\build.ps1 -Package -SessionMode Isolated -Configuration "Release|TwinCAT OS (x64)" -UseSavedInputs -NonInteractive

# Run source-boundary, metadata and session-selection checks without XAE
.\tools\build\test-offline.ps1
```

`-XaeMoniker` selects one matching instance when necessary. Preflight lists the visible monikers and reports unsaved elements. An existing session must be saved and idle; the script does not save it or log it out. Use XAE yourself to resolve its state, or explicitly select an isolated saved-input build.

Run native automation in the same desktop and privilege context as XAE. A sandboxed process can see XAE in the process list while its COM instance is inaccessible. If a running XAE process has no corresponding visible COM instance, the script stops instead of interpreting that as an unopened project.

An attached host retains its active configuration. If `-Configuration` or local settings specify an expected configuration, it must already match. An owned host requires an explicit configuration and selects it; it does not rely on the new IDE's default. The complete rebuild uses native Clean followed by BuildProject for the selected TwinCAT project, then CheckAllObjects. Error List reads are required and are never replaced by an empty success result. Existing errors block progress even when compiler status is successful, except for the six explicitly accepted library-publication findings described below; uncertain attribution requires review. Warnings are retained and marked for diagnostic review.

A controlled invalid-project probe on Build 4026 showed that a hidden host could return blank diagnostic rows or only a general build-failure message; making that host visible exposed the concrete PLC errors. The diagnostic reader initializes the Error List view and enables errors, warnings and information before enumerating entries. Records without a description or with an unknown severity are incomplete reads: the capture retains the returned rows and error, and validation stops. An empty list is valid; placeholder records are not silently accepted as warnings or matched to earlier findings by count. The reader never clears the list.

`-TimeoutSeconds` bounds project-load polling and the asynchronous build wait. Native synchronous COM calls, including CheckAllObjects, cannot be forcibly cancelled by this small script; a blocked call requires operator inspection. There is no process-killing watchdog or automatic recovery of the owner's session.

## Packaging Inputs And Provenance

The saved PLC project's Company, Title, ProjectVersion and DefaultNamespace are the effective library identity. The script rejects missing/conditional identity, duplicate or escaping Compile inputs, and inconsistent generated ST_LibVersion fields. It copies ordinary Framework sources and responsible project options into the saved native Empty PLC Project with its preparation host closed, then opens the standalone packaging solution in a fresh host; XAE generates exactly one matching Global_Version declaration. Before XAE loads that copy, packaging renders the existing TE1030 declaration documentation as native plain-text comments and removes the `!` marker from element comments. Canonical repository comments and HTML extraction retain TE1030 markup. SA rationale stays as ordinary maintenance comments in the repository; packaging omits it from its copy because even ordinary leading comments can become native GVL field descriptions. Analysis attributes remain unchanged. The generated source-visible `.library` therefore contains native comment text rather than a byte-for-byte source copy. The manifest records original/projected hashes and a non-comment code fingerprint; saved-file checks reject changed ST tokens, attributes or implementation, unsupported markup and unexpected copy changes. No development project is converted into a library by deleting unwanted objects.

`tools/build/dependency-versions.psd1` records exact producer resolutions. Tc3_GlobalTypes is an automatic reference already present in a fresh Empty PLC Project; the four declared placeholders come from the saved source project. Write the four producer resolutions into the temporary project before loading it; live reference edits would require reloading. Verify all effective references after validation. Do not override the automatic reference or freeze placeholders in the development project. Consumer resolution behavior must still be verified against the generated libraries before release.

Both formats use native ITcPlcIECProject.SaveAsLibrary with installation disabled. The local native probe verified that the source form reopens with its function and that the compiled form cannot be imported as an editable project. The script also checks the observed Build 4026 archive layout; extension and size alone do not prove format.

Manifests record source hashes, source commit and dirty state, identity, configuration, resolved dependencies, diagnostics, output hashes and cleanup results. Packages are local candidates with `ReleaseEligible=false`; a successful script is not release approval, consumer validation, runtime evidence or proof of byte-identical generation. Repeated full generation and consumer checks are separate validation steps.

## Static Analysis Baseline

Required build and validation use the license-free Static Analysis Light; no TE1200 or other additional analysis license is required. The PLC project explicitly enables `PerformStaticAnalyse` and rules SA0004, SA0006, SA0027, SA0028, SA0033, SA0167, and SA0175 in `PlcProjectOptions`. Each rule is stored with `bActive=True` and `bWarning=False`.

Use a complete PLC rebuild to trigger the build-coupled analysis and inspect the XAE Error List afterwards. The Build 4026 functional probe produced an unused-variable finding with source file and declaration line. XAE exposed that finding as a warning despite the stored rule setting, so successful build status alone is not evidence of an analysis-clean project. Review findings explicitly; no individual-rule coverage is claimed by this smoke test.

Keep the configuration versioned in the PLC project. Apply and validate it in an XAE instance containing only this repository solution; do not silently change global IDE settings or other projects. The analysis editor uses shared engineering option services, so serialized project storage alone does not establish isolation across projects or sessions.

## Build Diagnostic Evidence

Use native operation results and before/after observations of the XAE Error List for build validation. Interactive engineering uses the MCP; the build script records equivalent evidence through typed Automation Interface calls. Do not clear the Error List automatically. The Build Output is not a required diagnostic source and need not be cleared or retrieved.

1. Identify the active solution, configuration, and source state, including any temporary probe.
2. Capture the existing Error List without clearing it.
3. Perform a complete rebuild (Neu erstellen), wait for completion, and capture its operation result and subsequent Error List.
4. Afterwards run `CheckAllObjects` (Alle Objekte prüfen), wait for completion, and capture its operation result and final Error List. A regular build does not cover unused PLC objects; do not end validation with another rebuild after the all-object check.
5. Evaluate stages separately and together. A successful return code alone does not establish the absence of warnings. Do not reuse earlier entries as current findings or assume that identical entries must be stale; identify uncertain attribution explicitly.
6. Report failed reads or unresolved diagnostic inconsistencies. Keep observations, suspected causes, and confirmed defects distinct. Do not infer an implementation or analysis bug from an entry whose current-run origin is unverified.

Temporary-probe results and regular-project results must be recorded separately. A clean build after removing a probe does not prove that a finding observed with the probe was fixed.

This procedure requires neither Error List clearing nor a Build Output workaround and does not broaden XAE-command or runtime permissions.

## Reference-Property Compatibility Warnings

Compiler warnings `410` and `5410` shall not be suppressed project-wide. Removing their entries from `DisabledWarningIds` preserves compiler checking and makes any corresponding diagnostics visible; it does not change PLC behavior.

Read-only inspection of the Build 4026.26 compiler metadata identifies `410` as `Wrn_CompatibilityProblemForRefProperty` and `5410` as `Wrn_CompatibilityProblemForRefProperty2`. Both belong to the reference-property compatibility warning family. The exact distinction between their trigger conditions remains unverified.

For properties returning `REFERENCE TO`, Beckhoff documents an accessor behavior change at Build 4022: assignment with `:=` formerly invoked Set to assign the reference, whereas newer builds invoke Get to write the referenced value. Reference assignment requires `REF=` on newer builds. Build 4026 uses the newer behavior. See [Beckhoff: Object Property](https://infosys.beckhoff.com/content/1033/tc3_plc_intro/2530335371.html).

These identifiers describe reference-property compatibility; they are not the stack-analysis findings handled by narrowly scoped source exceptions. Their presence in project settings alone does not establish a compiler finding or justify suppressing the family globally.

When no warnings are suppressed, omit `DisabledWarningIds` rather than serializing an empty filter. Do not serialize an empty string: Build 4026.26 failed with a `FormatException` in `WarningHelper.ReadDisabledWarningIds` for that representation. Removing the option entirely passed the subsequent rebuild. Any suppression requires a specific, documented justification.

## Build Stages

The mandatory build path performs these stages in order:

1. validate repository structure and required versioned inputs;
2. open the selected project through the configured XAE Shell;
3. perform a complete TwinCAT project rebuild;
4. call `CheckAllObjects` for the PLC project, including unused objects;
5. capture diagnostics and fail on errors;
6. write a machine-readable and a human-readable result below the target artifact directory;
7. close only its owned hosts, leave attached development sessions open, and verify that original saved inputs are unchanged.

Runtime selftests and library packaging are explicit additional stages. A successful compile-only build does not claim runtime validation, and a successful runtime test does not claim that release artifacts were packaged.

The PLC-side structure, isolation, and evidence rules for those tests are defined in [Framework Selftest Strategy](selftest-strategy.md).

## Local Configuration

The versioned configuration template is located at:

```text
tools/build/build-settings.example.psd1
```

Machine-specific values are stored only at:

```text
local/build-settings.psd1
```

The local file selects the XAE Shell host, configuration, project paths and optional installed-assembly/template paths used by the offline build. It does not select a runtime target for this command. It must not contain values that are required to understand repository behavior. Routes, credentials, machine-specific installation paths, and target identities are not committed.

Explicit command-line parameters override local configuration. Missing required settings produce an actionable error rather than an unverified automatic fallback.

## Runtime Safety

A normal build does not activate, restart, stop, reset, or modify a TwinCAT runtime.

During initial Build 4026 development, deployment and runtime validation use only the local TwinCAT route and local runtime instance. Automation must not create or select a remote ADS route or operate on a remote target for the 4026 path. Introducing a remote target requires a separate project-owner decision.

`-RunSelfTests` and `-Deploy` fail before XAE acquisition in the current build command. Runtime validation uses the approved engineering operations and event/ADS tooling separately; neither packaging nor help generation downloads an application or implicitly activates a configuration.

The automation must display and record the selected build line and AMS target before a state-changing runtime step.

## Packaging Boundary

`-Package` depends on a successful mandatory offline build, including compilation and all-object checks of selftest sources. It does not execute runtime selftests. The packaging stage creates a native Empty PLC Project in a separate temporary TwinCAT project, then admits only saved Compile entries from the `Framework/` source boundary. It must not package `SelfTests/` or `Runtime/` through a negative exclusion list.

The repository release version uses three components, for example `1.0.0` and Git tag `v1.0.0`. TwinCAT library metadata uses the deterministically normalized four-component form `1.0.0.0`. The saved PLC project must already contain the four-component version; the current build rejects a three-component `ProjectVersion` and has no version-setting switch. Preparing a release therefore includes setting and saving the normalized metadata before packaging. `GetFrameworkVersion()` formats `ContractInfo.FrameworkVersion` as `Major.Minor.Build` from the automatically generated `ST_LibVersion` fields, without revision, within the existing `STRING(10)` capacity. A nonzero revision has no release meaning until that meaning is explicitly defined.

Packaging produces both supported library forms from the same approved source boundary and with the same library identity and effective four-component version:

- `.compiled-library` is the regular installation artifact;
- `.library` is the source-visible and debug-capable alternative.

Both files are generated release artifacts. They are delivered as release assets rather than committed source files. `.compiled-library-v3` is not a defined release artifact.

The release file names identify the producing TwinCAT build line and the effective four-component TwinCAT library version:

- `Tc3_UnitTest.<TwinCAT-build-line>-<major>.<minor>.<build>.<revision>.library`;
- `Tc3_UnitTest.<TwinCAT-build-line>-<major>.<minor>.<build>.<revision>.compiled-library`.

For release `1.0.0` produced with Build 4026, the resulting names are `Tc3_UnitTest.4026-1.0.0.0.library` and `Tc3_UnitTest.4026-1.0.0.0.compiled-library`. The file name is descriptive only; TwinCAT library identity and resolution are governed by the embedded company, title, version, and namespace metadata.

Build 4026 packaging writes artifacts below `artifacts/4026/`. Local packaging output names remain unchanged; release staging adds the producing build line without modifying the library bytes. This label identifies the producer and validated baseline; it does not establish incompatibility with other build lines. The release process publishes only the approved validated Build 4026 artifacts.

Saved PLC project metadata supplies company, title, version and namespace. The temporary native project regenerates its own `Global_Version`; the build verifies that its fields match the effective identity instead of copying a stale generated object. Producer placeholder versions are pinned by `tools/build/dependency-versions.psd1` and checked against native effective resolutions, including the automatic `Tc3_GlobalTypes` reference. Consumer resolution remains a separate validation.

Each package directory contains both native formats and a manifest with saved source hashes, build-tool hashes, engineering version, configuration, resolved dependencies and output hashes. Repeatability means the same saved inputs, identity and producer resolutions; it does not promise byte-identical native archives. Compare output hashes and retain differences explicitly. The manifest keeps `ReleaseEligible=false`: successful local packaging does not approve a final release or publication.

Only the isolated Framework packaging validation accepts the six observed unused-variable diagnostics for `GVL_UnitTest.RunControl`, `GVL_UnitTest.EventStream`, `ST_EventStream.FifoControl`, `ST_EventStream.Status`, `ST_EventStream.Buffer` and `ST_RunControlCommunication.ControlData`. These public communication declarations are consumed by the integrating application, whose Runtime/SelfTests are intentionally absent from the library project. The classification matches the exact observed German message and the exact source file below that packaging project's root; other text, files, declarations or diagnostic locales require review. Raw captures remain complete, and the validation manifest records each accepted diagnostic with its stage and reason. No PLC source pragma or global analysis-rule suppression is applied. Development validation retains the full error gate. Actual integration and use of the published data must be validated separately in a consumer project.

The native library package contains no example objects, example project or copy templates. Framework bases and their interface documentation define the extension model; selected selftests serve as executable usage examples. The separately maintained authoring skill offers optional text source starting points outside the production Framework boundary. Those assets are not library contents and do not expand the library release artifact set.

## Offline Help and Release Preparation

Build the separate HTML help from the same saved source state used for the library:

```powershell
.\tools\documentation\build-help.ps1 -VerifyBrowser
```

The [documentation adapter](../tools/documentation/README.md) describes prerequisites, version checks, offline packaging and detailed regressions. The help generator checks saved PLC identity/generated-version fields and independent contract versions. It does not read a built library to prove binary provenance or apply a consumer's parameter overrides.

The release deliverables are the approved library pair and `tc3-unittest-help-<effective-four-component-version>.zip`. Recipients extract the help and open `index.html`; no server or TE1030 license is required. Author/license resources and guide chapters are packaged locally.

Prepare those files from the approved source commit and version, inspect their manifests and exact checksums, reconcile consumer/runtime evidence with any changed inputs, then obtain approval of the concrete release assets and notes. The source tag/commit, effective identity, input hashes and validation evidence establish the association between the library and help; equal filenames or version labels alone do not. A dirty local candidate or `ReleaseEligible=false` manifest is not release approval.

Generation does not publish or commit the files. Upload/tag/publication and verification of downloaded release assets remain the separate release operation. No generated library or help ZIP is added to the source branch.

## Future CI Use

The future CI runner is a dedicated Windows machine or Windows VM with the same required XAE Shell and Automation Interface capabilities. A container is not the primary XAE/COM automation environment.

CI calls the same `tools/build/build.ps1` entry point and parameters as local development. Machine-specific values are provided through protected CI variables or runner configuration. CI must not maintain a separate implementation of the build logic.

The availability of a CI runner does not change the safety boundary: compile-only jobs do not modify a runtime, while deployment and runtime tests require a deliberately assigned target and job configuration.

## Evidence

The build automation retains at least:

- selected target build line and XAE host;
- project and PLC object check outcome;
- rebuild outcome;
- warnings and errors;
- whether deployment was requested and the selected target identity;
- whether runtime selftests executed and their result;
- whether packaging executed and the produced artifact identities;
- final process exit code.

This evidence is generated below `artifacts/` and is not committed.
