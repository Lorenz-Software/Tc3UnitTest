param()
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
& (Join-Path $repo 'tools/documentation/generator/scripts/inventory-project.ps1') `
    -RepositoryRoot $repo -ProjectFile (Join-Path $repo 'projects/Tc3UnitTest.4026/Tc3UnitTest/Tc3UnitTest.plcproj') `
    -OutputPath (Join-Path $repo 'artifacts/documentation/project-inventory') `
    -CompilerPath (Join-Path $repo 'artifacts/documentation/compiler') `
    -ScopeConfig (Join-Path $PSScriptRoot 'projects/tc3-unittest/inventory.json')
