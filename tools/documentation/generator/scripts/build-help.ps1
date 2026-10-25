param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$ProjectConfig,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$DocfxPath,
    [string]$CompilerPath,
    [switch]$VerifyBrowser,
    [string]$BrowserPath
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$ProjectConfig = (Resolve-Path -LiteralPath $ProjectConfig).Path
$output = [IO.Path]::GetFullPath($OutputPath)
$docfx = (Resolve-Path -LiteralPath $DocfxPath).Path
$compiler = if ($CompilerPath) { [IO.Path]::GetFullPath($CompilerPath) } else { Join-Path $output '_compiler' }
$configuration = Get-Content -LiteralPath $ProjectConfig -Raw | ConvertFrom-Json
$version = & $docfx --version
if ($LASTEXITCODE -ne 0 -or $version -notlike '2.81.0*') { throw "Expected DocFX 2.81.0; found $version" }
$env:DOTNET_CLI_HOME = Join-Path $output '_dotnet-home'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_ADD_GLOBAL_TOOLS_TO_PATH = 'false'
$env:DOTNET_NOLOGO = 'true'
$project = Join-Path $PSScriptRoot 'src/TwinCatDocumentation.csproj'
$template = (Resolve-Path (Join-Path $PSScriptRoot '../assets/default-template')).Path
New-Item -ItemType Directory -Path $output -Force | Out-Null
& dotnet build $project --configuration Release --nologo "-p:BaseOutputPath=$compiler/bin/" "-p:BaseIntermediateOutputPath=$compiler/obj/"
if ($LASTEXITCODE -ne 0) { throw 'Documentation converter build failed.' }
$program = Join-Path $compiler 'bin/Release/net9.0/TwinCatDocumentation.dll'
& dotnet $program --self-test
if ($LASTEXITCODE -ne 0) { throw 'Parser/model checks failed.' }
& dotnet $program $repo $output $ProjectConfig $template
if ($LASTEXITCODE -ne 0) { throw 'Source conversion failed.' }
$unpacked = $null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
& $docfx build (Join-Path $output 'docfx.json') --warningsAsErrors --log (Join-Path $output "build-$stamp.log")
if ($LASTEXITCODE -ne 0) { throw 'HTML generation failed.' }

# Package only the intended user-facing files, excluding generator metadata and stale output.
$pages = Get-Content (Join-Path $output 'help-pages.json') -Raw | ConvertFrom-Json
$resources = Get-Content (Join-Path $output 'help-resources.json') -Raw | ConvertFrom-Json
$files = @('public/help.css', 'public/help.js') + @($resources) + @($pages)
$package = Join-Path $output ('package-' + $stamp + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path $package -Force | Out-Null
$manifest = @(foreach ($relative in $files) {
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[/\\])\.\.([/\\]|$)') { throw "Invalid package path: $relative" }
    $source = Join-Path (Join-Path $output 'site') $relative
    $destination = Join-Path $package $relative
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
    [ordered]@{ path = $relative; sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash }
})
$buildIdentity = Get-Content (Join-Path $output 'help-build.json') -Raw | ConvertFrom-Json
$packageName = $configuration.packageFile.Replace('{version}', [string]$buildIdentity.library.Version)
if ($packageName -match '[{}]' -or [IO.Path]::GetFileName($packageName) -ne $packageName) { throw 'Unresolved or invalid package filename.' }
$zip = Join-Path $output $packageName
Compress-Archive -Path (Join-Path $package '*') -DestinationPath $zip -Force
$manifest | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $output 'package-manifest.json') -Encoding utf8
if ($VerifyBrowser) {
    $unpacked = Join-Path $output ('unpacked-' + $stamp + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    Expand-Archive -LiteralPath $zip -DestinationPath $unpacked
    $unpackedFiles = @(Get-ChildItem -LiteralPath $unpacked -Recurse -File)
    if ($unpackedFiles.Count -ne $manifest.Count) { throw 'ZIP file count does not match the intended package.' }
    foreach ($entry in $manifest) {
        if ((Get-FileHash -LiteralPath (Join-Path $unpacked $entry.path) -Algorithm SHA256).Hash -ne $entry.sha256) { throw "ZIP content mismatch: $($entry.path)" }
    }
    $browserArguments = @()
    if ($BrowserPath) { $browserArguments = @('--browser', $BrowserPath) }
    & node (Join-Path $PSScriptRoot 'verify-help.cjs') --site $unpacked --output $output @browserArguments
    if ($LASTEXITCODE -ne 0) { throw 'Offline HTML/browser verification failed.' }
}
[ordered]@{ scope = $configuration.edition; zip = (Split-Path $zip -Leaf); files = $files.Count; zipSha256 = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash; html = 'site/index.html'; verificationRequested = [bool]$VerifyBrowser; extractedPackage = $unpacked } |
    ConvertTo-Json | Set-Content (Join-Path $output 'package-result.json') -Encoding utf8
Write-Output "HTML: $(Join-Path $output 'site/index.html')"
Write-Output "Package: $zip"
