param()
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$primary = Join-Path $repo 'artifacts/documentation/reference'
$repeat = Join-Path $repo ('artifacts/documentation/reference-repeat-' + [guid]::NewGuid().ToString('N'))
$program = Join-Path $repo 'artifacts/documentation/compiler/bin/Release/net9.0/TwinCatDocumentation.dll'
& dotnet $program $repo $repeat (Join-Path $repo 'tools/documentation/projects/tc3-unittest/reference.json') (Join-Path $repo 'tools/documentation/generator/assets/default-template')
if ($LASTEXITCODE -ne 0) { throw 'Repeated extraction failed.' }
& (Join-Path $repo 'local/tools/docfx/docfx.exe') build (Join-Path $repeat 'docfx.json') --warningsAsErrors
if ($LASTEXITCODE -ne 0) { throw 'Repeated HTML generation failed.' }
$manifest = @(Get-Content (Join-Path $primary 'package-manifest.json') -Raw | ConvertFrom-Json)
foreach ($entry in $manifest) {
    $actual = (Get-FileHash -LiteralPath (Join-Path (Join-Path $repeat 'site') $entry.path) -Algorithm SHA256).Hash
    if ($actual -ne $entry.sha256) { throw "Regenerated content differs: $($entry.path)" }
}
[ordered]@{ result = 'PASS'; comparedFiles = $manifest.Count; repeatOutput = $repeat; scope = 'All intended help files including the input manifest; ZIP container timestamps excluded.' } |
    ConvertTo-Json | Set-Content (Join-Path $primary 'validation/reproducibility.json') -Encoding utf8
Write-Output "PASS: $($manifest.Count) intended help files regenerated with identical SHA-256 content."
