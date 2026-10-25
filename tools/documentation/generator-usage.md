# Offline help generator

The generator reads saved TwinCAT sources and produces standalone HTML and a ZIP. It requires no running PLC, Codex installation or TE1030 license.

## Requirements

- .NET SDK 9 and Git CLI.
- DocFX 2.81.0 installed locally.
- For browser verification: Node.js 22 or newer and Chrome, or another Chromium browser selected with `-BrowserPath`.
- Saved PLC sources, project configuration and matching authoring documentation.

The repository wrapper expects DocFX at `local/tools/docfx/docfx.exe`. Obtain prerequisites separately; the build performs no global tool installation.

When multiple SDK majors are installed, check `dotnet --version` in the invocation directory and select SDK 9 there, for example with a locally scoped `global.json`. Merely installing SDK 9 does not make it the default when a newer major is present.

## Build

From the checkout root:

```powershell
.\tools\documentation\build-help.ps1 -VerifyBrowser
```

The wrapper selects the complete API configuration. Use `-Sample` for the small regression selection or `-ProjectConfig` for an explicit configuration. Outputs are written below `artifacts/documentation/`.

The reusable generator contains `scripts/src/`, `scripts/build-help.ps1`, browser checks and `assets/default-template/`. Its entry point accepts explicit `RepositoryRoot`, `ProjectConfig`, `OutputPath`, `CompilerPath` and `DocfxPath` arguments. Keep output and compiler paths outside production sources.

Project metadata, source selection, authoring chapters, logos and branding belong to project configuration. Use the configured stylesheet and assets for branding instead of copying the default template.

## Outputs and verification

Extract the help ZIP and open `index.html`. Pages, search, navigation, styles, logos and license work offline. External author links open only on user request.

Generation records source identity and input hashes in `help-build.json`. `package-result.json` identifies the ZIP; `package-manifest.json` records its file hashes. Keep these records with the build output when selecting help for export.

`-VerifyBrowser` checks the extracted package with an isolated hidden browser profile. Parser/model checks also run during generation. These validate documentation generation, not PLC compilation or runtime behavior. Unsupported source syntax and inconsistent metadata fail explicitly.

See [project configuration](../../tools/documentation/generator/references/project-configuration.md), [inventory boundaries](../../tools/documentation/generator/references/project-inventory.md) and the [project adapter](README.md) for the selection model and detailed checks.
