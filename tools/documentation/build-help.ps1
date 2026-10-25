param([switch]$Sample, [switch]$VerifyBrowser, [string]$BrowserPath,
    [string]$ProjectConfig)
$ErrorActionPreference = 'Stop'
if (-not $ProjectConfig) { $ProjectConfig = Join-Path $PSScriptRoot $(if ($Sample) { 'projects/tc3-unittest/sample.json' } else { 'projects/tc3-unittest/reference.json' }) }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$output = Join-Path $repo $(if ($Sample) { 'artifacts/documentation/sample' } else { 'artifacts/documentation/reference' })
$generator = Join-Path $repo 'tools/documentation/generator/scripts/build-help.ps1'
& $generator -RepositoryRoot $repo -ProjectConfig $ProjectConfig -OutputPath $output `
    -CompilerPath (Join-Path $repo 'artifacts/documentation/compiler') `
    -DocfxPath (Join-Path $repo 'local/tools/docfx/docfx.exe') -VerifyBrowser:$VerifyBrowser -BrowserPath $BrowserPath
if ($VerifyBrowser -and $Sample) {
    $result = Get-Content (Join-Path $output 'package-result.json') -Raw | ConvertFrom-Json
    $browserArguments = @()
    if ($BrowserPath) { $browserArguments = @('--browser', $BrowserPath) }
    & node (Join-Path $PSScriptRoot 'tests/verify-sample.cjs') --site $result.extractedPackage --output $output @browserArguments
    if ($LASTEXITCODE -ne 0) { throw 'Project-specific documentation regression checks failed.' }
}
