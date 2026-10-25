Set-StrictMode -Version Latest

function Initialize-XaeInterop {
    param($Settings)
    if ('Tc3UnitTest.Build.XaeInterop' -as [type]) { return }
    $public = $Settings.PublicAssembliesPath
    if (-not $public) {
        $public = @("$env:ProgramFiles/Beckhoff/TcXaeShell/Common7/IDE/PublicAssemblies",
            "${env:ProgramFiles(x86)}/Beckhoff/TcXaeShell/Common7/IDE/PublicAssemblies") |
            Where-Object { Test-Path -LiteralPath (Join-Path $_ 'envdte80.dll') } | Select-Object -First 1
    }
    $interop = $Settings.InteropAssemblyPath
    if (-not $interop) {
        $interop = Get-ChildItem "${env:ProgramFiles(x86)}/Beckhoff/TwinCAT/Functions" -Recurse -Filter TCatSysManagerLib.dll -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $public -or -not $interop) {
        throw 'XAE interop assemblies not found; set PublicAssembliesPath and InteropAssemblyPath in local/build-settings.psd1.'
    }
    $references = @($interop,(Join-Path $public 'envdte.dll'),(Join-Path $public 'envdte80.dll'),(Join-Path $public 'Microsoft.VisualStudio.Interop.dll'))
    foreach ($reference in $references) { [void][Reflection.Assembly]::LoadFrom($reference) }
    Add-Type -Path (Join-Path $PSScriptRoot 'XaeInterop.cs') -ReferencedAssemblies $references
    [Tc3UnitTest.Build.XaeMessageFilter]::Install()
}

function Get-XaeSessionPlan {
    param([object[]]$Sessions, [string]$SolutionPath, [string]$ProjectPath,
        [ValidateSet('Auto','Existing','Isolated')][string]$Mode='Auto', [string]$Moniker)
    $solution = [IO.Path]::GetFullPath($SolutionPath)
    $project = [IO.Path]::GetFullPath($ProjectPath)
    $matching = @($Sessions | Where-Object {
        ($_.SolutionPath -and [IO.Path]::GetFullPath($_.SolutionPath) -eq $solution) -or
        @($_.Projects | Where-Object { $_ -and [IO.Path]::GetFullPath($_) -eq $project }).Count
    })
    if ($Mode -eq 'Isolated') { return [pscustomobject]@{Mode='Isolated'; Session=$null; Matching=$matching} }
    if ($Moniker) { $matching=@($matching | Where-Object Moniker -EQ $Moniker) }
    if ($matching.Count -gt 1) { throw 'Multiple XAE instances contain the project; select one explicitly with -XaeMoniker, or use -SessionMode Isolated.' }
    if ($matching.Count -eq 0) {
        if ($Mode -eq 'Existing' -or $Moniker) { throw 'No matching existing XAE instance; inspect the project path or use -SessionMode Isolated.' }
        return [pscustomobject]@{Mode='Isolated'; Session=$null; Matching=$matching}
    }
    return [pscustomobject]@{Mode='Existing'; Session=$matching[0]; Matching=$matching}
}

function Write-BuildJson {
    param($Value,[string]$Path)
    $Value | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-XaeBuildHost {
    param($Settings,[string]$SolutionPath,[int]$TimeoutSeconds)
    $existing=@(Get-Process TcXaeShell -ErrorAction SilentlyContinue | ForEach-Object Id)
    $dte=New-Object -ComObject $Settings.DteProgId
    $id=[Tc3UnitTest.Build.XaeInterop]::ProcessId($dte)
    if($id -in $existing) { throw 'XAE activation reused an existing host; ownership refused.' }
    $hostInfo=[pscustomobject]@{Dte=$dte;ProcessId=$id;EngineeringVersion=$null}
    try {
        $dte.SuppressUI=$true
        $dte.UserControl=$false
        # The native Error List requires a visible host to expose PLC detail rows.
        $dte.MainWindow.Visible=$true
        $automation=$dte.GetObject('TcAutomationSettings')
        # Initialize PLC diagnostic reporting while the saved project loads.
        # SuppressUI remains enabled; SilentMode can hide PLC detail diagnostics.
        $automation.SilentMode=$false
        if($automation.SilentMode) { throw 'XAE diagnostic reporting could not be enabled.' }
        $dte.Solution.Open($SolutionPath)
        $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
        while($dte.Solution.Projects.Count -ne 1) {
            if((Get-Date) -gt $deadline) { throw 'XAE solution load timed out.' }
            Start-Sleep -Milliseconds 500
        }
        $hostInfo.EngineeringVersion=[string]$dte.GetObject('TcRemoteManager').Version
        if($hostInfo.EngineeringVersion -notlike '3.1.4026.*') { throw "Expected TwinCAT Build 4026; loaded '$($hostInfo.EngineeringVersion)'." }
        [Tc3UnitTest.Build.XaeInterop]::SelectConfiguration($dte,$Settings.Configuration)
        return $hostInfo
    } catch {
        $failure=$_
        try { Close-XaeBuildHost $hostInfo } catch { throw "Host initialization failed: $failure. Cleanup failed: $_" }
        throw $failure
    }
}

function Close-XaeBuildHost {
    param($HostInfo)
    $process=Get-Process -Id $HostInfo.ProcessId -ErrorAction SilentlyContinue
    $HostInfo.Dte.Quit()
    if($process -and -not $process.WaitForExit(15000)) { throw 'Owned XAE has not exited; inspect it manually before retrying.' }
}

function Assert-XaeDiagnosticEntries {
    param([object[]]$Entries)
    foreach($entry in $Entries) {
        if([string]::IsNullOrWhiteSpace([string]$entry.Description)) {
            throw 'XAE Error List returned an incomplete diagnostic without a description.'
        }
        if($entry.Severity -notin @('vsBuildErrorLevelHigh','vsBuildErrorLevelMedium','vsBuildErrorLevelLow')) {
            throw 'XAE Error List returned an unknown diagnostic severity.'
        }
    }
}

function Get-XaeDiagnosticDisposition {
    param([object[]]$Entries,[string]$PackagingRoot)
    # Owner-approved exception for externally consumed publication data only.
    # Match the observed native text and exact file in the isolated library root.
    # A different message, declaration, location or locale requires fresh review.
    $publications=@{
        'Framework/Common/GlobalVariables/GVL_UnitTest.TcGVL'=@('RunControl','EventStream')
        'Framework/EventBuffer/DataTypes/ST_EventStream.TcDUT'=@('FifoControl','Status','Buffer')
        'Framework/RunControl/DataTypes/ST_RunControlCommunication.TcDUT'=@('ControlData')
    }
    $accepted=@()
    $blocking=@()
    Assert-XaeDiagnosticEntries $Entries
    foreach($entry in $Entries) {
        if($entry.Severity -ne 'vsBuildErrorLevelHigh') { continue }
        $expected=$false
        if($PackagingRoot) {
            foreach($relative in $publications.Keys) {
                $path=[IO.Path]::GetFullPath((Join-Path $PackagingRoot $relative))
                if([string]$entry.File -eq $path) {
                    foreach($name in $publications[$relative]) {
                        if($entry.Description -ceq "Nicht verwendet: Variable '$name'") { $expected=$true }
                    }
                }
            }
        }
        if($expected) { $accepted+=$entry } else { $blocking+=$entry }
    }
    return [pscustomobject]@{Accepted=$accepted;Blocking=$blocking}
}

function Save-XaeDiagnostics {
    param($Dte,[string]$Path)
    # An unavailable read is a failure, not an empty Error List.
    $entries=@()
    try {
        $entries=@([Tc3UnitTest.Build.XaeInterop]::Errors($Dte))
        Assert-XaeDiagnosticEntries $entries
        Write-BuildJson @{CapturedAt=(Get-Date).ToString('o');Available=$true;Entries=$entries} $Path
        return ,$entries
    } catch {
        Write-BuildJson @{CapturedAt=(Get-Date).ToString('o');Available=$false;Entries=$entries;Error=$_.Exception.Message} $Path
        throw
    }
}

function Invoke-XaeValidation {
    param($Dte,$Project,[string]$Evidence,[int]$TimeoutSeconds=300,[string]$PackagingRoot)
    New-Item -ItemType Directory -Path $Evidence -Force | Out-Null
    $sm=[Tc3UnitTest.Build.XaeInterop]::SystemManager($Project)
    $plc=$sm.LookupTreeItem('TIPC')
    if($plc.ChildCount -ne 1) { throw 'Expected exactly one PLC project in the selected TwinCAT project.' }
    $root=$plc.Child(1)
    $nested=[Tc3UnitTest.Build.XaeInterop]::NestedProject($root)
    $result=[ordered]@{Rebuild='not-run';CheckAll='not-run';RequiresDiagnosticReview=$true}
    $automation=$null
    $previousSilentMode=$null
    try {
        $automation=$Dte.GetObject('TcAutomationSettings')
        $previousSilentMode=[bool]$automation.SilentMode
        $result.PreviousSilentMode=$previousSilentMode
        # SilentMode suppresses PLC detail diagnostics in the tested isolated host.
        # Keep SuppressUI unchanged and restore this instance setting after validation.
        $automation.SilentMode=$false
        if($automation.SilentMode) { throw 'Cannot enable PLC diagnostic reporting for validation.' }
        $result.DiagnosticSilentMode=$false
        $before=Save-XaeDiagnostics $Dte (Join-Path $Evidence 'rebuild-before.json')
        $result.RebuildStartedAt=(Get-Date).ToString('o')
        $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
        foreach($phase in @('Clean','Build')) {
            $result.Phase=$phase
            Write-BuildJson @{Phase=$phase;Time=(Get-Date).ToString('o')} (Join-Path $Evidence 'operation.json')
            if($phase -eq 'Clean') { [Tc3UnitTest.Build.XaeInterop]::BeginClean($Dte) }
            else { [Tc3UnitTest.Build.XaeInterop]::BeginBuild($Dte,$Project) }
            Start-Sleep -Milliseconds 750
            while($true) {
                if((Get-Date) -gt $deadline) { throw "XAE $phase wait timed out; inspect XAE before retrying." }
                try {
                    if(-not [Tc3UnitTest.Build.XaeInterop]::Busy($Dte)) { break }
                } catch {
                    $cause=$_.Exception
                    while($null -ne $cause.InnerException) { $cause=$cause.InnerException }
                    # XAE may reject status reads while compiling; never repeat an accepted operation.
                    if($cause.HResult -notin @(-2147418111,-2147417846)) { throw }
                }
                Start-Sleep -Milliseconds 500
            }
        }
        $result.FailedProjects=[Tc3UnitTest.Build.XaeInterop]::LastBuildInfo($Dte)
        $after=Save-XaeDiagnostics $Dte (Join-Path $Evidence 'rebuild-after.json')
        $result.RebuildFinishedAt=(Get-Date).ToString('o')
        if($result.FailedProjects -ne 0) { throw "XAE rebuild failed for $($result.FailedProjects) project(s)." }
        $result.Rebuild='succeeded'
        $checkBefore=Save-XaeDiagnostics $Dte (Join-Path $Evidence 'check-before.json')
        $result.CheckStartedAt=(Get-Date).ToString('o')
        $result.CheckAll=[Tc3UnitTest.Build.XaeInterop]::CheckAll($nested)
        $checkAfter=Save-XaeDiagnostics $Dte (Join-Path $Evidence 'check-after.json')
        $result.CheckFinishedAt=(Get-Date).ToString('o')
        if(-not $result.CheckAll) { throw 'CheckAllObjects reported errors.' }
        $result.RequiresDiagnosticReview=(@($before).Count + @($after).Count + @($checkBefore).Count + @($checkAfter).Count) -gt 0
        # Preserve every capture; classify the approved library-only exceptions
        # separately without changing native diagnostics or PLC analysis settings.
        $result.AcceptedDiagnostics=@()
        $result.BlockingDiagnostics=@()
        foreach($capture in @(
            @{Stage='rebuild-before';Entries=$before},@{Stage='rebuild-after';Entries=$after},
            @{Stage='check-before';Entries=$checkBefore},@{Stage='check-after';Entries=$checkAfter})) {
            $disposition=Get-XaeDiagnosticDisposition $capture.Entries $PackagingRoot
            foreach($entry in $disposition.Accepted) {
                $result.AcceptedDiagnostics+=@{Stage=$capture.Stage;Diagnostic=$entry;Reason='Approved external publication; Framework-only packaging has no application consumer.'}
            }
            foreach($entry in $disposition.Blocking) {
                $result.BlockingDiagnostics+=@{Stage=$capture.Stage;Diagnostic=$entry}
            }
        }
        if($result.BlockingDiagnostics.Count) { throw 'XAE Error List contains errors; inspect the captured stages. Compiler success does not waive diagnostics.' }
        return [pscustomobject]$result
    } catch {
        $result.Error=$_.Exception.Message
        # Capture failure-stage diagnostics too; an unreadable list is explicitly unavailable.
        try { $failureEntries=Save-XaeDiagnostics $Dte (Join-Path $Evidence 'failure-after.json') }
        catch { $result.FailureDiagnosticReadError=$_.Exception.Message }
        throw
    } finally {
        try {
            if($null -ne $automation -and $null -ne $previousSilentMode) {
                $automation.SilentMode=$previousSilentMode
                $result.SilentModeRestored=([bool]$automation.SilentMode -eq $previousSilentMode)
                if(-not $result.SilentModeRestored) { throw 'XAE validation could not restore the previous instance SilentMode.' }
            }
        } finally { Write-BuildJson $result (Join-Path $Evidence 'validation.json') }
    }
}

function Get-BuildDependencies {
    param($References,$Lock)
    $resolved=@([Tc3UnitTest.Build.XaeInterop]::References($References))
    $expected=@($Lock.Declared.Keys)+@($Lock.Automatic.Keys)
    if($resolved.Count -ne $expected.Count) { throw 'Native dependency inventory differs from producer baseline.' }
    foreach($name in $expected) {
        $actual=@($resolved | Where-Object Name -EQ $name)
        if($actual.Count -ne 1 -or $actual[0].Title -ne $name -or $actual[0].Company -ne $Lock.Company) {
            throw "Unexpected or missing dependency: $name"
        }
        $version=if($Lock.Declared.ContainsKey($name)){$Lock.Declared[$name]}else{$Lock.Automatic[$name]}
        if($actual[0].Version -ne $version -or $actual[0].Kind -ne 'placeholder') {
            throw "Producer dependency resolution mismatch: $name"
        }
    }
    return ,$resolved
}


function Get-PackagingNames {
    param([string[]]$ExistingNames,[string]$Token)
    if(-not $Token) { $Token=[guid]::NewGuid().ToString('N').Substring(0,8) }
    if($Token -notmatch '^[a-zA-Z0-9_]{1,16}$') { throw 'Packaging name token must contain 1-16 letters, digits or underscores.' }
    $hostName='UTHost_'+$Token
    $plcName='UTLib_'+$Token
    foreach($name in @($hostName,$plcName)) {
        if($name -in $ExistingNames) { throw "Packaging project name already exists: $name. Use a new run token." }
    }
    return [pscustomobject]@{Host=$hostName;Plc=$plcName}
}

function New-XaeLibraryProject {
    param($Dte,[string]$Template,[string]$Directory,[string]$Token,[string]$Configuration)
    $names=Get-PackagingNames ([Tc3UnitTest.Build.XaeInterop]::ProjectNames($Dte)) $Token
    if(Test-Path -LiteralPath $Directory) {
        if(@(Get-ChildItem -LiteralPath $Directory -Force).Count) {
            throw "Temporary packaging directory is not empty: $Directory. Use a fresh directory."
        }
    }
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $project=[Tc3UnitTest.Build.XaeInterop]::AddProject($Dte,$Template,$Directory,$names.Host)
    $nativePath=Join-Path $Directory ($names.Host+'.tsproj')
    $sm=[Tc3UnitTest.Build.XaeInterop]::SystemManager($project)
    $root=$sm.LookupTreeItem('TIPC').CreateChild($names.Plc,0,'','Empty PLC Template')
    [Tc3UnitTest.Build.XaeInterop]::SaveProject($project)
    [xml]$xml=Get-Content -LiteralPath $nativePath -Raw -Encoding UTF8
    $guid=$xml.TcSmProject.Project.ProjectGUID
    $solutionPath=Join-Path $Directory ($names.Host+'.sln')
    # A minimal saved solution, opened in a fresh owned host after composition.
    $solution=@"
Microsoft Visual Studio Solution File, Format Version 12.00
Project("{B1E792BE-AA5F-4E3C-8C82-674BF9C0715B}") = "$($names.Host)", "$($names.Host).tsproj", "$guid"
EndProject
Global
 GlobalSection(SolutionConfigurationPlatforms) = preSolution
  $Configuration = $Configuration
 EndGlobalSection
 GlobalSection(ProjectConfigurationPlatforms) = postSolution
  $guid.$Configuration.ActiveCfg = $Configuration
  $guid.$Configuration.Build.0 = $Configuration
 EndGlobalSection
EndGlobal
"@
    [IO.File]::WriteAllText($solutionPath,($solution -replace '\r?\n',"`r`n"),[Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{Path=(Join-Path $Directory "$($names.Plc)/$($names.Plc).plcproj");Solution=$solutionPath;Names=$names}
}

function Test-NativeLibraryFormat {
    param([string]$Path,[ValidateSet('library','compiled-library')][string]$Format)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $names=@($archive.Entries | ForEach-Object FullName)
        # Observed and natively verified Build 4026 storage layouts, not filename inference.
        $hasSourceProfile=$names -contains 'profile.auxiliary'
        $hasLanguageModel=$names -contains '__languagemodel2.auxiliary'
        if(($Format -eq 'library' -and (-not $hasSourceProfile -or $hasLanguageModel)) -or
            ($Format -eq 'compiled-library' -and (-not $hasLanguageModel -or $hasSourceProfile))) {
            throw "Unrecognized native $Format storage layout: $Path"
        }
        return [pscustomobject]@{Format=$Format;Path=$Path;Length=(Get-Item -LiteralPath $Path).Length;Sha256=(Get-FileHash -LiteralPath $Path).Hash;Entries=$names}
    } finally { $archive.Dispose() }
}

Export-ModuleMember -Function New-XaeBuildHost,Close-XaeBuildHost,Get-PackagingNames,New-XaeLibraryProject,Initialize-XaeInterop,Get-XaeSessionPlan,Write-BuildJson,Assert-XaeDiagnosticEntries,Get-XaeDiagnosticDisposition,Save-XaeDiagnostics,Invoke-XaeValidation,Get-BuildDependencies,Test-NativeLibraryFormat
