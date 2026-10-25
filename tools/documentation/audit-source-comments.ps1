# Regenerate the complete inventory first; audit findings intentionally return failure.
param()
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
& (Join-Path $PSScriptRoot 'inventory-project.ps1')
$program=Join-Path $repo 'artifacts/documentation/compiler/bin/Release/net9.0/TwinCatDocumentation.dll'
& dotnet $program --audit-comments $repo (Join-Path $repo 'artifacts/documentation/project-inventory') `
    (Join-Path $repo 'artifacts/documentation/source-comment-audit') `
    (Join-Path $PSScriptRoot 'projects/tc3-unittest/comment-format.json')
if ($LASTEXITCODE -ne 0) { throw 'Saved-source comment findings remain open; inspect artifacts/documentation/source-comment-audit/.' }
