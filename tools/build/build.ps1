[CmdletBinding()]
param(
    [ValidateSet('4026')][string]$Target='4026',
    [switch]$RunSelfTests,
    [switch]$Deploy,
    [switch]$Package,
    [ValidateSet('Auto','Existing','Isolated')][string]$SessionMode='Auto',
    [string]$XaeMoniker,
    [string]$Configuration,
    [switch]$UseSavedInputs,
    [switch]$NonInteractive,
    [switch]$Preflight,
    [ValidateRange(10,3600)][int]$TimeoutSeconds=300
)

$ErrorActionPreference='Stop'
# XAE PIAs and the typed helper use .NET Framework COM interop.
if($PSVersionTable.PSEdition -eq 'Core') {
    $arguments=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$PSCommandPath)
    foreach($key in $PSBoundParameters.Keys) {
        $value=$PSBoundParameters[$key]
        if($value -is [Management.Automation.SwitchParameter]) { if($value.IsPresent) { $arguments+="-"+$key } }
        else { $arguments += "-$key"; $arguments += [string]$value }
    }
    & "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" @arguments
    exit $LASTEXITCODE
}
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'BuildInputs.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'XaeBuild.psm1') -Force -DisableNameChecking
if($RunSelfTests -or $Deploy) { throw 'Runtime/deployment automation is not implemented by this offline build command.' }

$repositoryRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$settingsPath=Join-Path $repositoryRoot 'local/build-settings.psd1'
if(-not (Test-Path -LiteralPath $settingsPath)) { $settingsPath=Join-Path $PSScriptRoot 'build-settings.example.psd1' }
$settings=(Import-PowerShellDataFile -LiteralPath $settingsPath).Targets[$Target]
if(-not $settings) { throw "No build settings for target $Target." }
# Optional workstation paths may be omitted from older local settings.
foreach($key in @('InteropAssemblyPath','PublicAssembliesPath','TwinCatTemplatePath')) {
    if(-not $settings.ContainsKey($key)) { $settings[$key]=$null }
}
if($Configuration) { $settings.Configuration=$Configuration }
elseif(-not $settings.ContainsKey('Configuration')) { $settings.Configuration=$null }
$solutionPath=Get-ConfinedFile $repositoryRoot $settings.SolutionPath
$projectPath=Get-ConfinedFile $repositoryRoot $settings.ProjectPath
[xml]$tcProject=Get-Content -LiteralPath $projectPath -Raw -Encoding UTF8
$plcNodes=@($tcProject.TcSmProject.Project.Plc.Project)
if($plcNodes.Count -ne 1) { throw 'Expected one embedded PLC project in the authoritative TwinCAT project.' }
$plcPath=Get-ConfinedFile (Split-Path $projectPath) $plcNodes[0].PrjFilePath
$inputs=Get-LibraryInputs $plcPath
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$runDirectory=Join-Path $repositoryRoot "artifacts/build/$Target/$runId"
$workToken=$runId.Substring($runId.Length-8)
$workDirectory=Join-Path $repositoryRoot "artifacts/$Target/.work/$workToken"
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
$result=[ordered]@{
    Target=$Target;StartedAt=(Get-Date).ToString('o');SessionMode=$SessionMode
    PackageRequested=[bool]$Package;Identity=$inputs.Identity;Inputs=$inputs.Sources
    Stage='preflight';ExitCode=1;Artifacts=@();ReleaseEligible=$false
}
$dte=$null
$owned=$false
$ownedHost=$null
$baselineFiles=@($solutionPath,$projectPath,$plcPath)+@($inputs.Sources | ForEach-Object Path)
$baseline=@{}
foreach($file in $baselineFiles) { $baseline[$file]=(Get-FileHash -LiteralPath $file).Hash }
try {
    Initialize-XaeInterop $settings
    $sessions=@()
    foreach($progId in @($settings.DteProgId,'TcXaeShell.DTE.17.0','TcXaeShell.DTE.15.0') | Select-Object -Unique) {
        $sessions+=@([Tc3UnitTest.Build.XaeInterop]::FindSessions($progId))
    }
    $visibleIds=@($sessions | ForEach-Object { if($_.Moniker -match ':(\d+)$') { [int]$Matches[1] } } | Select-Object -Unique)
    $inaccessible=@(Get-Process -Name TcXaeShell -ErrorAction SilentlyContinue | Where-Object { $_.Id -notin $visibleIds })
    if($inaccessible.Count) {
        throw "Running XAE processes are not visible through COM (IDs: $($inaccessible.Id -join ', ')). Run from the same desktop and privilege context as XAE; no new host was started."
    }
    if($Package) {
        if($SessionMode -eq 'Existing' -or $XaeMoniker) { throw 'Packaging always uses an owned host. Omit -SessionMode Existing and -XaeMoniker.' }
        $SessionMode='Isolated'
    }
    $plan=Get-XaeSessionPlan $sessions $solutionPath $projectPath $SessionMode $XaeMoniker
    $result.SessionMode=$plan.Mode
    $result.Sessions=@($sessions | Select-Object Moniker,SolutionPath,Projects)
    $result.FrameworkCount=$inputs.Framework.Count
    $result.SourceCommit=(& git -C $repositoryRoot rev-parse HEAD)
    if($LASTEXITCODE -ne 0) { throw 'Cannot identify source commit.' }
    $result.WorkingTree=@(& git -C $repositoryRoot status --porcelain)
    if($LASTEXITCODE -ne 0) { throw 'Cannot inspect source working tree.' }
    $result.OriginalInputHashes=$baseline
    $result.ToolInputHashes=@(Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object Name -NE 'test-offline.ps1' | ForEach-Object {
        [pscustomobject]@{Name=$_.Name;Sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
    })
    $result.DependencyBaselineHash=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'dependency-versions.psd1')).Hash
    foreach($session in $plan.Matching) {
        if(-not [Tc3UnitTest.Build.XaeInterop]::IsSaved($session.Dte)) {
            if($Preflight) { $result.UnsavedSession=$session.Moniker; $result.UnsavedItems=@([Tc3UnitTest.Build.XaeInterop]::UnsavedItems($session.Dte)) }
            elseif(-not $UseSavedInputs -or $plan.Mode -eq 'Existing') {
                throw 'Matching XAE session has unsaved changes. Save/retry, or select Isolated -UseSavedInputs to explicitly build disk content.'
            }
        }
    }
    if($Preflight) {
        $result.Stage='preflight-completed'
        $result.ExitCode=0
        Write-Output "Preflight: $($plan.Mode); $($inputs.Framework.Count) Framework objects; evidence: $runDirectory"
        return
    }
    if($plan.Mode -eq 'Existing') {
        if(-not [Tc3UnitTest.Build.XaeInterop]::IsSaved($plan.Session.Dte)) { throw 'Existing XAE has unsaved changes; save/retry or use Isolated -UseSavedInputs.' }
        if([Tc3UnitTest.Build.XaeInterop]::Busy($plan.Session.Dte)) { throw 'Existing XAE is building; wait/retry or use Isolated.' }
        $dte=$plan.Session.Dte
        $result.Moniker=$plan.Session.Moniker
        $result.OriginalProjectPaths=@([Tc3UnitTest.Build.XaeInterop]::ProjectPaths($dte))
        $project=@($dte.Solution.Projects | Where-Object { $_.FullName -eq $projectPath })
        if($project.Count -ne 1) { throw 'Cannot uniquely identify the authoritative TwinCAT project in the selected session.' }
        $project=$project[0]
    } else {
        if(-not $settings.Configuration) { throw 'An isolated host requires -Configuration or Configuration in local build settings.' }
        New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null
        $snapshotSolution=Copy-BuildSnapshot $repositoryRoot $solutionPath $projectPath $inputs (Join-Path $workDirectory 'validation')
        # Read back copied sources: subsequent packaging uses the same immutable saved inputs.
        $snapshotProject=Join-Path (Split-Path $snapshotSolution) $plcNodes[0].PrjFilePath
        $inputs=Get-LibraryInputs $snapshotProject
        $result.Stage='open-validation-snapshot'
        Write-BuildJson @{Stage=$result.Stage;Time=(Get-Date).ToString('o');Solution=$snapshotSolution} (Join-Path $runDirectory 'progress.json')
        $ownedHost=New-XaeBuildHost $settings $snapshotSolution $TimeoutSeconds
        $dte=$ownedHost.Dte
        $owned=$true
        $result.OwnedProcessIds=@($ownedHost.ProcessId)
        $project=$dte.Solution.Projects.Item(1)
    }
    $result.Stage='select-configuration'
    Write-BuildJson @{Stage=$result.Stage;Time=(Get-Date).ToString('o')} (Join-Path $runDirectory 'progress.json')
    $result.EngineeringVersion=[string]$dte.GetObject('TcRemoteManager').Version
    if($result.EngineeringVersion -notlike '3.1.4026.*') { throw "Expected TwinCAT Build 4026; loaded '$($result.EngineeringVersion)'." }
    $result.Configuration=[Tc3UnitTest.Build.XaeInterop]::Configuration($dte)
    if($settings.Configuration -and $result.Configuration -ne $settings.Configuration) { throw "Existing XAE configuration differs from $($settings.Configuration); select it explicitly in XAE or use Isolated." }
    $result.Stage='development-validation'
    $result.DevelopmentValidation=Invoke-XaeValidation $dte $project (Join-Path $runDirectory 'development') $TimeoutSeconds
    if(-not $Package) {
        $result.Stage='validation-completed'
        $result.ExitCode=0
        return
    }
    $result.Stage='prepare-library'
    Write-BuildJson @{Stage=$result.Stage;Time=(Get-Date).ToString('o')} (Join-Path $runDirectory 'progress.json')
    $template=$settings.TwinCatTemplatePath
    if(-not $template) { $template="${env:ProgramFiles(x86)}/Beckhoff/TwinCAT/3.1/Components/Base/PrjTemplate/TwinCAT Project.tsproj" }
    if(-not (Test-Path -LiteralPath $template)) { throw 'TwinCAT project template missing; set TwinCatTemplatePath in local settings.' }
    $directory=Join-Path $workDirectory 'library'
    $lock=Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'dependency-versions.psd1')
    $prepared=New-XaeLibraryProject $dte $template $directory $workToken $settings.Configuration
    Close-XaeBuildHost $ownedHost
    $ownedHost=$null
    $dte=$null
    Set-PackagingInputs $prepared.Path $inputs $lock
    $result.Stage='open-saved-library'
    Write-BuildJson @{Stage=$result.Stage;Time=(Get-Date).ToString('o');Solution=$prepared.Solution} (Join-Path $runDirectory 'progress.json')
    $ownedHost=New-XaeBuildHost $settings $prepared.Solution $TimeoutSeconds
    $dte=$ownedHost.Dte
    $result.OwnedProcessIds+=@($ownedHost.ProcessId)
    $temporaryProject=$dte.Solution.Projects.Item(1)
    $sm=[Tc3UnitTest.Build.XaeInterop]::SystemManager($temporaryProject)
    $nested=[Tc3UnitTest.Build.XaeInterop]::NestedProject($sm.LookupTreeItem("TIPC^$($prepared.Names.Plc)"))
    $references=$sm.LookupTreeItem(([Tc3UnitTest.Build.XaeInterop]::TreePath($nested))+'^References')
    [Tc3UnitTest.Build.XaeInterop]::SaveProject($temporaryProject)
    $packageProjectPath=$prepared.Path
    Assert-PackagingInputs $packageProjectPath $inputs
    $result.NativeDocumentation=@($inputs.NativeDocumentation.Values | Sort-Object Relative)
    $result.PackagingNames=$prepared.Names
    $result.EngineeringVersion=$ownedHost.EngineeringVersion
    $result.Stage='library-validation'
    Write-BuildJson @{Stage=$result.Stage;Time=(Get-Date).ToString('o')} (Join-Path $runDirectory 'progress.json')
    $result.LibraryValidation=Invoke-XaeValidation $dte $temporaryProject (Join-Path $runDirectory 'library') $TimeoutSeconds -PackagingRoot (Split-Path $prepared.Path)
    $result.Dependencies=Get-BuildDependencies $references $lock
    [Tc3UnitTest.Build.XaeInterop]::SaveProject($temporaryProject)
    $result.Stage='native-library-export'
    Write-BuildJson @{Stage=$result.Stage;Time=(Get-Date).ToString('o')} (Join-Path $runDirectory 'progress.json')
    $staging=Join-Path $workDirectory 'staging'
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    foreach($format in @('library','compiled-library')) {
        $output=Join-Path $staging "$($inputs.Identity.Title)-$($inputs.Identity.ProjectVersion).$format"
        [Tc3UnitTest.Build.XaeInterop]::SaveLibrary($nested,$output)
        $result.Artifacts+=Test-NativeLibraryFormat $output $format
    }
    Assert-PackagingInputs $packageProjectPath $inputs
    $destination=Join-Path $repositoryRoot "artifacts/$Target/packages/$runId"
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    foreach($artifact in $result.Artifacts) {
        $path=Join-Path $destination (Split-Path $artifact.Path -Leaf)
        Copy-Item -LiteralPath $artifact.Path -Destination $path
        $artifact.Path=$path
    }
    $result.PackageDirectory=$destination
    $result.Stage='package-completed'
    $result.ExitCode=0
} catch {
    $result.Error=$_.Exception.ToString()
    $result.ErrorPosition=$_.InvocationInfo.PositionMessage
    $result.ErrorScriptStackTrace=$_.ScriptStackTrace
    Write-Error $_ -ErrorAction Continue
} finally {
    $cleanupErrors=@()
    if($null -ne $ownedHost) {
        try { Close-XaeBuildHost $ownedHost } catch { $cleanupErrors+=$_.Exception.Message }
    }
    if('Tc3UnitTest.Build.XaeMessageFilter' -as [type]) { [Tc3UnitTest.Build.XaeMessageFilter]::Restore() }
    $changed=@($baseline.Keys | Where-Object { -not (Test-Path -LiteralPath $_) -or (Get-FileHash -LiteralPath $_).Hash -ne $baseline[$_] })
    $result.ChangedOriginalInputs=$changed
    $result.CleanupErrors=$cleanupErrors
    if($changed.Count -or $cleanupErrors.Count) { $result.ExitCode=1 }
    $result.FinishedAt=(Get-Date).ToString('o')
    Write-BuildJson $result (Join-Path $runDirectory 'result.json')
    @("Stage: $($result.Stage)","Exit code: $($result.ExitCode)","Release eligible: False","Evidence: $runDirectory") |
        Set-Content -LiteralPath (Join-Path $runDirectory 'result.txt') -Encoding UTF8
    if($result.Contains('PackageDirectory')) { Write-BuildJson $result (Join-Path $result.PackageDirectory 'manifest.json') }
    Write-Output "Build stage: $($result.Stage); exit code: $($result.ExitCode); evidence: $runDirectory"
    exit $result.ExitCode
}
