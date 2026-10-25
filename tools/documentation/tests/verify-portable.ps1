param([switch]$VerifyBrowser, [string]$BrowserPath)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $repo 'artifacts/documentation'))
$checkRoot = Join-Path $artifactRoot ('portable-check-' + [guid]::NewGuid().ToString('N'))
if (-not ([IO.Path]::GetFullPath($checkRoot)).StartsWith($artifactRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Portable check must stay under documentation artifacts.' }
New-Item -ItemType Directory -Path $checkRoot -Force | Out-Null
$copiedSkill = Join-Path $checkRoot 'copied-skill'
Copy-Item -LiteralPath (Join-Path $repo 'tools/documentation/generator') -Destination $copiedSkill -Recurse
$fixtureRoot = Join-Path $checkRoot 'independent-project'
$source = Join-Path $fixtureRoot 'plc/exported'
New-Item -ItemType Directory -Path $source -Force | Out-Null
@'
<TcPlcObject><POU Name="PumpCheck"><Declaration><![CDATA[
//! <summary>Check the measured pump temperature.</summary>
FUNCTION_BLOCK PumpCheck IMPLEMENTS I_PumpView
VAR_INPUT
    Temperature : REAL := 20.0; // Measured process temperature.
END_VAR
]]></Declaration><Method Name="Initialize"><Declaration><![CDATA[
//! <summary>Initialize the independent fixture.</summary>
METHOD PUBLIC Initialize : BOOL // TRUE when the fixture is initialized.
VAR_INPUT
    Setpoint : REAL; // Expected temperature.
END_VAR
]]></Declaration></Method></POU></TcPlcObject>
'@ | Set-Content (Join-Path $source 'PumpCheck.TcPOU') -Encoding utf8
@'
<TcPlcObject><Itf Name="I_PumpView"><Declaration><![CDATA[
//! <summary>Read the current pump observation.</summary>
INTERFACE I_PumpView
]]></Declaration><Property Name="Ready"><Declaration><![CDATA[
//! <summary>Read fixture readiness.</summary>
PROPERTY Ready : BOOL // TRUE when ready.
]]></Declaration></Property></Itf></TcPlcObject>
'@ | Set-Content (Join-Path $source 'I_PumpView.TcIO') -Encoding utf8
@'
<TcPlcObject><DUT Name="ST_Measurement"><Declaration><![CDATA[
//! <summary>A measured process value.</summary>
TYPE ST_Measurement : STRUCT
    Value : REAL; // Measured value.
END_STRUCT
END_TYPE
]]></Declaration></DUT></TcPlcObject>
'@ | Set-Content (Join-Path $source 'ST_Measurement.TcDUT') -Encoding utf8
'Portable validation fixture only.' | Set-Content (Join-Path $fixtureRoot 'LICENSE') -Encoding utf8
':root { --accent:#732b80; }' | Set-Content (Join-Path $fixtureRoot 'project.css') -Encoding utf8
$guideRoot = Join-Path $fixtureRoot 'manual'
New-Item -ItemType Directory -Path $guideRoot -Force | Out-Null
@'
# Pump Setup

Configure the pump observation before starting a measurement.

## Connections

Read [measurement handling](measurement.md#sample-values) for the next step.

| Input | Meaning |
| --- | --- |
| Temperature | Observed value |

```iecst
Pump.Temperature := 42.0;
```
'@ | Set-Content (Join-Path $guideRoot 'setup.md') -Encoding utf8
@'
# Measurement Handling

Record the sample values before evaluating the pump.

## Sample values

Return to [setup](setup.md) when changing connections.
'@ | Set-Content (Join-Path $guideRoot 'measurement.md') -Encoding utf8
$configuration = [ordered]@{
    libraryNamespace = 'Example.Automation'; sourceRoot = 'plc/exported'
    includeTypes = @('PumpCheck', 'I_PumpView', 'ST_Measurement')
    product = 'Independent Example'; publisher = 'Fixture Publisher'; brandMark = 'EX'
    subtitle = 'Portable generator check'; edition = 'Synthetic validation fixture'
    packageFile = 'independent-example.zip'; stylesheet = 'project.css'
    overview = @{ title = 'Independent reference'; introduction = 'A separate project using an unchanged copied skill.'; sections = @() }
    groups = @(@{ title = 'Process control'; description = 'Independent source selection and grouping.'; types = @('PumpCheck', 'I_PumpView', 'ST_Measurement') })
    attribution = @{ author = 'Fixture Author'; contactEmail = 'author@example.com'; copyright = 'Fixture attribution'; licenseName = 'Validation notice'; licenseFile = 'LICENSE'; website = 'https://example.com/' }
    guide = @{ title = 'Pump Manual'; sourceRoot = 'manual'; chapters = @(
        @{ file = 'setup.md'; apiTypes = @('PumpCheck', 'ExternalPump') }
        @{ file = 'measurement.md'; apiTypes = @('ST_Measurement') }
    ) }
}
$configPath = Join-Path $fixtureRoot 'help.json'
$configuration | ConvertTo-Json -Depth 8 | Set-Content $configPath -Encoding utf8
$output = Join-Path $checkRoot 'output'
& (Join-Path $copiedSkill 'scripts/build-help.ps1') -RepositoryRoot $fixtureRoot -ProjectConfig $configPath `
    -OutputPath $output -DocfxPath (Join-Path $repo 'local/tools/docfx/docfx.exe') -VerifyBrowser:$VerifyBrowser -BrowserPath $BrowserPath
$model = @(Get-Content (Join-Path $output 'api-model.json') -Raw | ConvertFrom-Json)
if (@($model | Where-Object { -not $_.Owner }).Count -ne 3) { throw 'Independent three-type selection did not survive generation.' }
if (@($model | Where-Object { -not $_.Uid.StartsWith('Example.Automation.') }).Count) { throw 'Project namespace was not applied.' }
$html = Get-Content (Join-Path $output 'site/index.html') -Raw
if ($html -notmatch 'Independent Example' -or $html -match 'Lorenz|TC3 UnitTest|Tc3UnitTest') { throw 'Copied skill leaked original project identity.' }
if (-not (Test-Path -LiteralPath (Join-Path $output 'independent-example.zip'))) { throw 'Project package filename was not applied.' }
[ordered]@{ result = 'PASS'; sourceTypes = 3; apiPages = $model.Count; copiedSkill = $copiedSkill; output = $output; browserVerified = [bool]$VerifyBrowser } |
    ConvertTo-Json | Set-Content (Join-Path $checkRoot 'result.json') -Encoding utf8
Write-Output "PASS: unchanged skill copy built an independent three-type project. Evidence: $checkRoot"
