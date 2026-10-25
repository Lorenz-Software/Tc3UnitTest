$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Import-Module "$PSScriptRoot/BuildInputs.psm1" -Force -DisableNameChecking
Import-Module "$PSScriptRoot/XaeBuild.psm1" -Force -DisableNameChecking
$repo=(Resolve-Path "$PSScriptRoot/../..").Path
$directory=Join-Path $repo ('artifacts/validation/build-offline/'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$directory/Framework","$directory/SelfTests" -Force | Out-Null
& "$PSScriptRoot/test-native-documentation.ps1"
$checks=0
function Assert-True([bool]$Condition,[string]$Message) {
    if(-not $Condition) { throw $Message }
    $script:checks++
}
function Assert-Rejected([scriptblock]$Action,[string]$Expected) {
    $rejected=$false
    try { & $Action | Out-Null } catch {
        if($_.Exception.Message -notlike "*$Expected*") { throw }
        $rejected=$true
    }
    Assert-True $rejected "Expected rejection: $Expected"
}
$projectPath="$directory/Fixture.plcproj"
$fixture=@'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
<PropertyGroup><Company>Fixture</Company><Title>Fixture</Title><ProjectVersion>1.2.3.0</ProjectVersion><DefaultNamespace>Fixture</DefaultNamespace></PropertyGroup>
<ItemGroup><Compile Include="Framework\Global_Version.TcGVL"/><Compile Include="Framework\Production.TcPOU"/><Compile Include="SelfTests\Test.TcPOU"/></ItemGroup>
</Project>
'@
$generated=@'
{attribute 'TcGenerated'}
VAR_GLOBAL CONSTANT
stLibVersion_Fixture : ST_LibVersion := (iMajor := 1, iMinor := 2, iBuild := 3, iRevision := 0, nFlags := 0, sVersion := '1.2.3.0');
END_VAR
'@
Set-Content -LiteralPath $projectPath -Value $fixture
Set-Content -LiteralPath "$directory/Framework/Global_Version.TcGVL" -Value $generated
Set-Content -LiteralPath "$directory/Framework/Production.TcPOU" -Value '<TcPlcObject Version="1"><POU Name="Production"><Declaration><![CDATA[FUNCTION Production : BOOL]]></Declaration></POU></TcPlcObject>'
Set-Content -LiteralPath "$directory/SelfTests/Test.TcPOU" -Value 'FUNCTION Test : BOOL'
Set-Content -LiteralPath $projectPath -Encoding UTF8 -Value ($fixture.Replace('<Company>Fixture</Company>',('<Company>Fixture '+[char]0x00dc+'</Company>')))
Assert-True ((Get-LibraryInputs $projectPath).Identity.Company -eq ('Fixture '+[char]0x00dc)) 'UTF-8 company metadata was corrupted.'
Set-Content -LiteralPath $projectPath -Value $fixture
$libraryInputs=Get-LibraryInputs $projectPath
Assert-True ($libraryInputs.Framework.Count -eq 2 -and $libraryInputs.Sources.Count -eq 3) 'Positive source boundary failed.'
Set-Content -LiteralPath "$directory/Framework/Global_Version.TcGVL" -Value ($generated.Replace('nFlags := 0, ',''))
Assert-True ((Get-LibraryInputs $projectPath).Identity.ProjectVersion -eq '1.2.3.0') 'Native omitted default nFlags was rejected.'
Set-Content -LiteralPath "$directory/Framework/Global_Version.TcGVL" -Value ($generated.Replace('nFlags := 0','nFlags := 1'))
Assert-Rejected { Get-LibraryInputs $projectPath } 'Unsupported generated'
Set-Content -LiteralPath "$directory/Framework/Global_Version.TcGVL" -Value $generated
Set-Content -LiteralPath $projectPath -Value ($fixture.Replace('Framework\Production.TcPOU','Framework\..\SelfTests\Test.TcPOU'))
Assert-Rejected { Get-LibraryInputs $projectPath } 'escapes its declared area'
Set-Content -LiteralPath $projectPath -Value ($fixture.Replace('Framework\Production.TcPOU','..\outside.TcPOU'))
Assert-Rejected { Get-LibraryInputs $projectPath } 'Unclassified Compile'
Set-Content -LiteralPath $projectPath -Value ($fixture.Replace('SelfTests\Test.TcPOU','Framework\Production.TcPOU'))
Assert-Rejected { Get-LibraryInputs $projectPath } 'Duplicate Compile'
Set-Content -LiteralPath $projectPath -Value ($fixture.Replace('1.2.3.0','1.2.4.0'))
Assert-Rejected { Get-LibraryInputs $projectPath } 'Generated version differs'
Set-Content -LiteralPath $projectPath -Value ($fixture.Replace('<Company>Fixture</Company>','<Company>Fixture</Company><Company>Other</Company>'))
Assert-Rejected { Get-LibraryInputs $projectPath } 'one unconditional literal'
Set-Content -LiteralPath $projectPath -Value $fixture
$solution="$directory/Fixture.sln"
$tcProject="$directory/Fixture.tsproj"
Set-Content $solution 'fixture'
Set-Content $tcProject '<TcSmProject/>'
Set-Content "$directory/ignored.cache" 'must not be copied'
$snapshot=Copy-BuildSnapshot $repo $solution $tcProject $libraryInputs "$directory/snapshot"
Assert-True ((Test-Path "$directory/snapshot/Framework/Production.TcPOU") -and (Test-Path $snapshot)) 'Snapshot lost declared source.'
Assert-True (-not (Test-Path "$directory/snapshot/ignored.cache")) 'Snapshot copied undeclared state.'

# Exercise packaging composition from a native-shaped Empty PLC project.
New-Item -ItemType Directory -Path "$directory/package" -Force | Out-Null
$packagePath="$directory/package/Package.plcproj"
Set-Content $packagePath '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><PropertyGroup><Name>Package</Name></PropertyGroup><ItemGroup><PlaceholderReference Include="NativeSystem"><DefaultResolution>NativeSystem, * (Vendor)</DefaultResolution></PlaceholderReference></ItemGroup></Project>'
Set-PackagingInputs $packagePath $libraryInputs @{Declared=@{NativeSystem='1.2.3.4'};Company='Vendor'}
[xml]$package=Get-Content $packagePath -Raw
Assert-True ($package.Project.ItemGroup[0].PlaceholderReference.Include -eq 'NativeSystem') 'Native template system reference was removed.'
Assert-True ($package.Project.ItemGroup[1].PlaceholderResolution.Resolution -eq 'NativeSystem, 1.2.3.4 (Vendor)') 'Producer resolution was not saved before project load.'
Assert-True (-not (Test-Path "$directory/package/SelfTests")) 'SelfTests leaked into library project.'
Assert-True (-not (Test-Path "$directory/package/Framework/Global_Version.TcGVL")) 'Generated source was copied instead of natively generated.'
Copy-Item "$directory/Framework/Global_Version.TcGVL" "$directory/package/Global_Version.TcGVL"
$nativeVersion=$package.CreateElement('Compile',$package.DocumentElement.NamespaceURI)
$nativeVersion.SetAttribute('Include','Global_Version.TcGVL')
[void]$package.Project.ItemGroup[1].AppendChild($nativeVersion)
$package.Save($packagePath)
Assert-PackagingInputs $packagePath $libraryInputs
$script:checks++
Set-Content "$directory/package/Global_Version.TcGVL" ($generated.Replace('iMinor := 2','iMinor := 9'))
Assert-Rejected { Assert-PackagingInputs $packagePath $libraryInputs } 'Generated version differs'
Set-Content "$directory/package/Global_Version.TcGVL" $generated
Set-Content "$directory/package/Framework/Production.TcPOU" 'unexpected edit'
Assert-Rejected { Assert-PackagingInputs $packagePath $libraryInputs } 'differs from captured input'

$session=[pscustomobject]@{Moniker='!TcXaeShell.DTE.17.0:123';SolutionPath=$solution;Projects=@($tcProject)}
Assert-True ((Get-XaeSessionPlan @($session) $solution $tcProject Auto).Mode -eq 'Existing') 'Auto did not reuse matching session.'
Assert-True ((Get-XaeSessionPlan @() $solution $tcProject Auto).Mode -eq 'Isolated') 'Auto did not choose owned session.'
Assert-Rejected { Get-XaeSessionPlan @($session,$session) $solution $tcProject Auto } 'Multiple XAE'
Assert-Rejected { Get-XaeSessionPlan @() $solution $tcProject Existing } 'No matching existing'
Assert-True ((Get-XaeSessionPlan @($session,$session) $solution $tcProject Isolated).Mode -eq 'Isolated') 'Explicit isolation failed.'
$other=[pscustomobject]@{Moniker='other';SolutionPath="$directory/Other.sln";Projects=@($tcProject)}
Assert-True ((Get-XaeSessionPlan @($other) $solution $tcProject Auto).Mode -eq 'Existing') 'Project opened from another solution was missed.'
$names=Get-PackagingNames @('Tc3UnitTest.4026','Tc3UnitTest') 'a1b2c3d4'
Assert-True ($names.Host -ne $names.Plc) 'TwinCAT and PLC project names must differ.'
Assert-Rejected { Get-PackagingNames @('uthost_a1b2c3d4') 'a1b2c3d4' } 'already exists'
Assert-Rejected { Get-PackagingNames @('UTLib_a1b2c3d4') 'a1b2c3d4' } 'already exists'
Assert-Rejected { Get-PackagingNames @() '../bad' } 'name token'
$next=Get-PackagingNames @($names.Host,$names.Plc)
Assert-True ($next.Host -notin @($names.Host,$names.Plc) -and $next.Plc -notin @($names.Host,$names.Plc)) 'A fresh run reused a project name.'
# Empty lists and global diagnostics without a file are valid; placeholder rows are not.
Assert-XaeDiagnosticEntries @()
$script:checks++
Assert-XaeDiagnosticEntries @([pscustomobject]@{Severity='vsBuildErrorLevelLow';Description="Called 'Fixture'.";File='';Line=0})
$script:checks++
Assert-Rejected { Assert-XaeDiagnosticEntries @([pscustomobject]@{Severity='vsBuildErrorLevelMedium';Description='';File='';Line=0}) } 'incomplete diagnostic'
Assert-Rejected { Assert-XaeDiagnosticEntries @([pscustomobject]@{Severity='vsBuildErrorLevelLow';Description='   '}) } 'incomplete diagnostic'
Assert-Rejected { Assert-XaeDiagnosticEntries @([pscustomobject]@{Severity='unknown';Description='Unrecognized record'}) } 'unknown diagnostic severity'
# The packaging exception must never weaken development or other-error gates.
$publication=[pscustomobject]@{Severity='vsBuildErrorLevelHigh';Description="Nicht verwendet: Variable 'RunControl'";File=(Join-Path $directory 'Framework/Common/GlobalVariables/GVL_UnitTest.TcGVL');Line=13}
$classification=Get-XaeDiagnosticDisposition @($publication) $directory
Assert-True ($classification.Accepted.Count -eq 1 -and $classification.Blocking.Count -eq 0) 'Approved packaging publication was not classified.'
$classification=Get-XaeDiagnosticDisposition @($publication)
Assert-True ($classification.Accepted.Count -eq 0 -and $classification.Blocking.Count -eq 1) 'Packaging exception leaked into development validation.'
$classification=Get-XaeDiagnosticDisposition @($publication) (Join-Path $directory 'other-project')
Assert-True ($classification.Blocking.Count -eq 1) 'A diagnostic from another project was accepted.'
$otherMessage=[pscustomobject]@{Severity=$publication.Severity;Description="Invalid assignment to 'RunControl'";File=$publication.File}
$classification=Get-XaeDiagnosticDisposition @($publication,$otherMessage) $directory
Assert-True ($classification.Accepted.Count -eq 1 -and $classification.Blocking.Count -eq 1) 'Another error on an approved declaration was waived.'
$otherVariable=[pscustomobject]@{Severity=$publication.Severity;Description="Nicht verwendet: Variable 'OtherVariable'";File=$publication.File}
$classification=Get-XaeDiagnosticDisposition @($otherVariable) $directory
Assert-True ($classification.Blocking.Count -eq 1) 'An additional unused declaration was waived.'
$otherFile=[pscustomobject]@{Severity=$publication.Severity;Description=$publication.Description;File=(Join-Path $directory 'Framework/Other/GVL_UnitTest.TcGVL')}
$classification=Get-XaeDiagnosticDisposition @($otherFile) $directory
Assert-True ($classification.Blocking.Count -eq 1) 'Matching names in another file were waived.'
$passed=[ordered]@{Passed=$true;Checks=$checks;Directory=$directory}
Write-BuildJson $passed "$directory/result.json"
$passed | ConvertTo-Json
