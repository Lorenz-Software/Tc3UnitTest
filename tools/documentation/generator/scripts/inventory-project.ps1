param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$ProjectFile,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$CompilerPath,
    [string]$ScopeConfig
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$project = (Resolve-Path -LiteralPath $ProjectFile).Path
$output = [IO.Path]::GetFullPath($OutputPath)
$compiler = if ($CompilerPath) { [IO.Path]::GetFullPath($CompilerPath) } else { Join-Path $output '_compiler' }
New-Item -ItemType Directory -Path $output -Force | Out-Null
$env:DOTNET_CLI_HOME = Join-Path $output '_dotnet-home'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_ADD_GLOBAL_TOOLS_TO_PATH = 'false'
$env:DOTNET_NOLOGO = 'true'
& dotnet build (Join-Path $PSScriptRoot 'src/TwinCatDocumentation.csproj') --configuration Release --nologo "-p:BaseOutputPath=$compiler/bin/" "-p:BaseIntermediateOutputPath=$compiler/obj/"
if ($LASTEXITCODE -ne 0) { throw 'Inventory converter build failed.' }
$program = Join-Path $compiler 'bin/Release/net9.0/TwinCatDocumentation.dll'
& dotnet $program --self-test
if ($LASTEXITCODE -ne 0) { throw 'Inventory/parser checks failed.' }
$scopeArguments = @()
if ($ScopeConfig) { $scopeArguments = @((Resolve-Path -LiteralPath $ScopeConfig).Path) }
& dotnet $program --inventory $repo $project $output @scopeArguments
if ($LASTEXITCODE -ne 0) { throw 'Project inventory failed; inspect the reported gaps.' }
