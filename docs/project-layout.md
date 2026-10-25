# TwinCAT Project Layout

Status: Active

This document defines the repository layout and artifact ownership for TC3 UnitTest. Build and validation details are defined in [Build And Validation Workflow](build-workflow.md).

## Project Layout

TwinCAT 3.1 Build 4026 is the initial and authoritative development environment.

```text
projects/
├── Tc3UnitTest.4026/
│   ├── Tc3UnitTest.4026.sln       authoritative engineering entry point
│   ├── Tc3UnitTest.4026.tsproj
│   └── Tc3UnitTest/
│       ├── Tc3UnitTest.plcproj
│       ├── Framework/
│       ├── SelfTests/
│       └── Runtime/

tools/
├── build/                         local build and packaging automation
├── event-consumer/                event archive and acknowledgement tooling
├── ads/                           shared ADS helpers and instructions
└── documentation/                 offline help adapter and bundled generator

artifacts/                         generated and ignored
```

The 4026 PLC project is an embedded Standard PLC Project named `Tc3UnitTest`. Framework sources, selftests, and the executable selftest runtime are kept in this project for the normal edit, build, and debug cycle.

The [event consumer](../tools/event-consumer/README.md) is repository tooling, not
part of the PLC library or a PC runner. Its captures remain below ignored
`artifacts/validation/`.

## PLC Project Areas

- `Framework/` contains production library objects and defines the positive input boundary for library packaging.
- `SelfTests/` contains framework verification, fixtures, Test Cases, and Test Suites.
- `Runtime/` contains executable composition, `MAIN`, task binding, and selftest application initialization.

Objects are grouped by functional context, with related interfaces, bases, and DUTs located together. Only genuinely cross-cutting types are grouped separately. Folder depth follows actual object count and navigability; detailed subfolders are introduced when justified by the implementation. `GVL_UnitTest` is library-owned and therefore belongs below `Framework/`.

`Framework/Common/Fifo/` contains the internal FIFO utility, included in the library rather than supplied through a separate library dependency. Internal owners compose the concrete `Fifo` FB without an `I_Fifo` interface. It is not part of the public framework API. FIFO tests remain under `SelfTests/`. See [FIFO Design](fifo-design.md) for behavior and ownership.

### Selftest Organization

Selftests use role and Suite context directly, without redundant `POU` subfolders:

```text
SelfTests/
├── RunControl/                    concrete selftest Run Control
├── TestSuites/                    concrete Suite FBs
└── TestCases/
    └── TestSuite_<Context>/       Test Cases belonging to that Suite
        └── Helper/               helpers used only by this test group
```

Run Control and Suite FBs reside directly in their role folders. Test Cases are grouped by their owning Suite. Helpers remain with the test group that uses them; extract shared helpers only when actual use across test groups requires it. Do not create empty helper folders or additional artifact levels in anticipation of future objects.

This describes the selftest layout; it does not require reorganizing the existing `Framework/` tree.

## Library Identity

| Property | Value |
| --- | --- |
| Product name | `TC3 UnitTest` |
| PLC project | `Tc3UnitTest` |
| Library title | `Tc3_UnitTest` |
| Company | `Lorenz Software` |
| Default namespace | `Tc3UnitTest` |

The build and release process supplies the library version.

## Versioned Inputs

The following artifacts are repository inputs and are committed when they exist:

- TwinCAT project files (`.tsproj`);
- PLC project files (`.plcproj`) and stand-alone refactoring metadata (`.tpr`) if introduced;
- independent TwinCAT project fragments (`.xti`);
- PLC object files such as `.TcPOU`, `.TcDUT`, `.TcGVL`, and `.TcTTO`;
- hand-authored scripts and build configuration below `tools/`;
- contracts, architecture, and authoring documentation;
- intentionally maintained small textual fixtures and configuration files.

TwinCAT Multiple Files is used. The logical PLC project tree is mirrored in physical directories. Methods and properties remain nested in their owning TwinCAT object.

## Ignored Local And Generated Artifacts

The following artifacts are not ordinary repository inputs:

- solution-specific user state such as `.suo`, `.user`, and `.vs/`;
- TwinCAT backups and temporary project variants;
- generated PLC outputs such as `.tpy`, ordinary PLC `.tmc`, compile information, assembly, core, boot, deployment, and repository directories;
- generated `.library`, `.compiled-library`, and `.compiled-library-v3` files, whether produced for local development or release publication;
- the complete `artifacts/` output directory;
- local engineering workspaces below `local/`;
- temporary analysis and reference material below `.tmp/`;
- local task records and session handoffs below `.local-work/`.

A generated PLC `.tmc` remains ignored while the repository contains only ordinary PLC code. If shared TMC types or TcCOM modules are introduced, their required TMC inputs must be explicitly allowlisted and reviewed rather than enabling all TMC files globally.

The authoritative Build 4026 `.sln` is versioned with its TwinCAT and PLC projects and is the single engineering entry point edited by developers and automation. Additional generated or local `.sln` files remain ignored.

## Line Endings And TwinCAT Merges

Repository text uses CRLF line endings. TwinCAT project and PLC object files are treated as text for source-control purposes.

TwinCAT project XML must not be treated as arbitrary hand-mergeable XML. Structural conflicts in `.tsproj`, `.plcproj`, `.xti`, and PLC object files are resolved using TwinCAT Project Compare where practical. Object deletion and recreation are not equivalent because TwinCAT identifies objects through GUIDs.

The Build 4026 convention may use the available LineID tooling where it provides a concrete engineering benefit.

## Generated Deliverables And LFS

Normal build and packaging output is written below `artifacts/` and remains untracked. Build 4026 packaging output is written below `artifacts/4026/`. Distribute the approved `.library` and `.compiled-library` files as release assets rather than committing them to the source tree.

If a binary library, TwinCAT archive (`.tpzip`, `.tszip`, or `.tnzip`), PDF or Office document, ISO image, or other large binary reference is exceptionally approved for repository versioning, Git LFS is mandatory. Such a file requires both an explicit `.gitignore` exception for its exact location when its type is otherwise ignored and the applicable `.gitattributes` LFS rule. An LFS rule does not itself authorize versioning. Broadly force-adding ignored generated output is not permitted.

`.tmp/` is unconditionally temporary. Content below it is never a release input and must not receive selective source-control exceptions. An artifact that becomes durable must first be moved to its responsible repository location and reviewed there.

## Packaging Boundary

The development PLC project is not itself the released library project. The packaging stage of the local automated process performs these offline steps:

1. rebuild and check a saved snapshot of the authoritative development project, including its selftest sources;
2. create a clean temporary Empty PLC Project;
3. include only approved objects from `Framework/`, projecting their documentation comments to native plain text in the temporary copy;
4. apply the configured library identity and version;
5. check the generated library project;
6. emit library artifacts and their provenance manifest below `artifacts/`.

This stage compiles selftest sources but does not execute them. Runtime selftests and standalone consumer verification are separate evidence.

The library distribution includes no separate example objects, example project or copy templates. Framework bases and their interface documentation define the extension model; selected selftests provide executable usage examples. The PLC library binary artifact set contains only the approved `.library` and `.compiled-library` files.

Standalone offline HTML help is a separate documentation deliverable supplied alongside the library pair, with the same effective library version. Its versioned inputs, generation and ignored output are described in the [documentation adapter](../tools/documentation/README.md). Generating that help does not publish a release.
