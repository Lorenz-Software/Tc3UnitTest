#requires -Version 5.1
#requires -PSEdition Desktop
<#
.SYNOPSIS
Inspects the local UnitTest application or performs one explicitly authorized command.
.DESCRIPTION
Requires Windows PowerShell 5.1 x64. No runtime access occurs without
-AllowRuntimeAccess. This switch and -ConfirmMutation record operator intent;
they do not replace owner approval. Runtime supports only SystemRun/SystemConfig;
PLC commands and deployment use the MCP routes documented in the skill.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Inspect', 'Command', 'Acknowledge', 'Runtime')][string]$Operation,
    [ValidateSet('Framework', 'PlcState', 'SystemState', 'Symbols')][string]$Scope = 'Framework',
    [ValidateSet('Start', 'Abort', 'Reset', 'BufferReset')][string]$Command,
    [ValidateSet('SystemRun', 'SystemConfig')][string]$RuntimeCommand,
    [ValidateSet('Accepted', 'Completed')][string]$WaitFor = 'Completed',
    [ValidateRange(851, 899)][int]$PlcPort = 851,
    [string]$ExpectedTargetNetId,
    [string]$ExpectedName,
    [string[]]$Symbol,
    [string]$CapturePath,
    [uint32]$Watermark = 0,
    [switch]$ExclusiveConsumer,
    [switch]$EpochUnchanged,
    [switch]$AllowRuntimeAccess,
    [switch]$ConfirmMutation,
    [ValidateRange(100, 10000)][int]$IoTimeoutMs = 3000,
    [ValidateRange(1000, 300000)][int]$TimeoutMs = 30000,
    [string]$TwinCatRoot,
    [string]$AssemblyPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# All permission and parameter checks precede dependency loading or client construction.
if (-not $AllowRuntimeAccess) { throw 'Runtime access is disabled. Obtain owner approval before supplying -AllowRuntimeAccess.' }
if ($Operation -ne 'Inspect' -and -not $ConfirmMutation) { throw 'Mutation requires -ConfirmMutation and owner approval.' }
if ($Operation -eq 'Command' -and -not $Command) { throw '-Command is required.' }
if ($Operation -eq 'Runtime' -and -not $RuntimeCommand) { throw '-RuntimeCommand is required.' }
$frameworkOperation = $Operation -in 'Command', 'Acknowledge' -or ($Operation -eq 'Inspect' -and $Scope -eq 'Framework')
if ($frameworkOperation -and -not $ExpectedName) { throw '-ExpectedName must identify the intended Run Control.' }
if ($Operation -eq 'Inspect' -and $Scope -eq 'Symbols' -and @($Symbol).Count -eq 0) { throw '-Symbol is required.' }
if ($Operation -eq 'Acknowledge' -and
    (-not $CapturePath -or $Watermark -eq 0 -or -not $ExclusiveConsumer -or -not $EpochUnchanged)) {
    throw 'Acknowledge requires an inspected -CapturePath, positive -Watermark, -ExclusiveConsumer and -EpochUnchanged.'
}

Import-Module (Join-Path $PSScriptRoot 'UnitTestAds.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AdsTransport.psm1') -Force
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$evidenceRoot = Join-Path $repoRoot 'artifacts/validation/tc3-engineering'
$operationId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N')
$evidenceDirectory = Join-Path $evidenceRoot $operationId
[void][IO.Directory]::CreateDirectory($evidenceDirectory)

function Save-Evidence {
    param([string]$Name, $Value)
    $path = Join-Path $evidenceDirectory $Name
    $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 30) + "`r`n")
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    return $path
}

function Test-CommandObservation {
    param($Before, $After)
    $commands = $After.Root.ControlData.Cmd
    $cleared = if ($Command -eq 'BufferReset') { -not $After.Root.ControlData.BufferCmd.Reset } else { -not $commands.$Command }
    $execution = $After.Root.ControlData.Status.Execution
    $completed = $false
    $condition = 'No lifecycle completion evidence yet.'
    if ($Command -eq 'BufferReset') {
        $completed = $cleared -and ($After.Status.SequenceId -eq 0) -and
            ($After.Status.DeletedSequenceId -eq 0) -and ($After.Status.LostEventCount -eq 0) -and $After.Fifo.BufferEmpty
        $condition = 'Buffer command cleared and empty/reset metadata observed; no persistent epoch ID exists.'
    } else {
        $newRootTransitions = @($After.Events | Where-Object {
            $_.Value.SequenceId -gt $Before.Status.SequenceId -and $_.Value.OwnerScope -eq 10 -and
            $_.Value.EventType -eq 30 -and $_.Value.Name -ceq $ExpectedName
        })
        $hasCompletedAnchor = @($newRootTransitions | Where-Object { $_.Value.State -eq 89 }).Count -gt 0
        if ($Command -eq 'Reset') {
            $hasIdle = @($newRootTransitions | Where-Object { $_.Value.State -eq 10 }).Count -gt 0
            $completed = $cleared -and (($hasIdle -and $execution.Ready) -or ($hasCompletedAnchor -and $execution.Completed))
        } else { $completed = $cleared -and $hasCompletedAnchor -and $execution.Completed }
        $condition = 'New root lifecycle transition plus current status; not a claim of complete event-log validation.'
    }
    [pscustomobject]@{
        RequestFieldCleared = $cleared; LifecycleCompleted = $completed; Condition = $condition
        State = $execution.State; Result = $execution.Result; Passed = ($execution.Result -eq 10); Error = $execution.Error
    }
}

$session = $null
$context = $null
$after = $null
$report = [ordered]@{
    Format = 'tc3-engineering-operation/1'; Operation = $Operation; StartedUtc = [DateTime]::UtcNow.ToString('o')
    Target = $null; Instance = $null; ExpectedTargetNetId = $ExpectedTargetNetId
    Port = $null; Dependencies = $null; TimeoutMs = $TimeoutMs
    Scope = $Scope; Command = $Command; RuntimeCommand = $RuntimeCommand; WaitFor = $WaitFor
    CommandAttempted = $false; CommandSubmitted = $false; ObservationSatisfied = $false
    BeforePath = $null; AfterPath = $null; SourceCapture = $null; Observation = $null; Error = $null
}
$exitCode = 0
try {
    $dependencies = Import-LocalAdsAssembly -TwinCatRoot $TwinCatRoot -AssemblyPath $AssemblyPath
    $report.Dependencies = $dependencies
    $port = if ($Operation -eq 'Runtime' -or ($Operation -eq 'Inspect' -and $Scope -eq 'SystemState')) { 10000 } else { $PlcPort }
    $session = Open-LocalAdsTransport $dependencies $port $IoTimeoutMs $TimeoutMs -ExpectedTargetNetId $ExpectedTargetNetId
    $report.Target = $session.Target
    $report.Instance = $session.Instance
    $report.Port = $port

    if ($Operation -eq 'Runtime') {
        $before = Get-AdsRuntimeState $session
        $report.BeforePath = Save-Evidence 'before.json' $before
        $mode = if ($RuntimeCommand -eq 'SystemRun') { 'Run' } else { 'Config' }
        [void](Save-Evidence 'intent.json' ([pscustomobject]@{ Command = $RuntimeCommand; Target = $session.Target; Port = $port }))
        $report.CommandAttempted = $true
        Set-AdsSystemMode $session $mode $before.DeviceState
        $report.CommandSubmitted = $true
        $lastReadError = $null
        do {
            Start-Sleep -Milliseconds 100
            try {
                $after = Get-AdsRuntimeState $session
                $report.Observation = $after
                if ($after.AdsState -eq $mode) { $report.ObservationSatisfied = $true; break }
            } catch { $lastReadError = $_.Exception.Message }
        } while ($session.Clock.ElapsedMilliseconds -lt $TimeoutMs)
        if (-not $report.ObservationSatisfied) { throw "System $mode not observed before timeout. Last read failure: $lastReadError" }
        $report.AfterPath = Save-Evidence 'after.json' $after
    } elseif ($Operation -eq 'Inspect' -and -not $frameworkOperation) {
        if ($Scope -eq 'Symbols') {
            $version = Get-AdsSymbolVersion $session
            $values = @($Symbol | ForEach-Object { Read-SelectedScalar $session $_ })
            if ((Get-AdsSymbolVersion $session) -ne $version) { throw 'Symbols changed during scalar inspection.' }
            $value = [pscustomobject]@{ SymbolVersion = $version; Values = $values; Atomic = $false }
        } else { $value = Get-AdsRuntimeState $session }
        $report.AfterPath = Save-Evidence 'inspection.json' $value
        $report.ObservationSatisfied = $true
    } else {
        $context = New-FrameworkContext $session $ExpectedName
        $before = Get-FrameworkCapture $context
        $report.BeforePath = Save-Evidence 'before.json' $before
        if ($Operation -eq 'Inspect') {
            $report.ObservationSatisfied = $true
        } else {
            if ($before.Root.ControlData.Cmd.Start -or $before.Root.ControlData.Cmd.Abort -or
                $before.Root.ControlData.Cmd.Reset -or $before.Root.ControlData.BufferCmd.Reset -or
                $before.Root.ControlData.BufferCmd.DeleteSequenceId -ne 0) {
                throw 'Another command is pending; coordinate ownership rather than overwriting it.'
            }
            if ($Operation -eq 'Acknowledge') {
                $sourcePath = (Resolve-Path -LiteralPath $CapturePath).ProviderPath
                $archived = Get-Content -Raw -LiteralPath $sourcePath | ConvertFrom-Json
                Assert-Acknowledgement $archived $before $Watermark
                $report.SourceCapture = [pscustomobject]@{ Path = $sourcePath; Sha256 = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash; Watermark = $Watermark }
                [void](Save-Evidence 'source-capture.json' $archived)
                $field = Get-CommandField $context 'Delete'
                $value = [uint32]$Watermark
            } else {
                if ($Command -eq 'Start' -and -not $before.Root.ControlData.Status.Execution.Ready) { throw 'Run Control is not ready to Start.' }
                if ($Command -eq 'Abort' -and $before.Root.ControlData.Status.Execution.Completed) { throw 'Abort requires a non-final lifecycle.' }
                $field = Get-CommandField $context $Command
                $value = [bool]$true
            }
            # Persist intent/evidence before the sole mutation; a later failure never retries it.
            [void](Save-Evidence 'intent.json' ([pscustomobject]@{ Symbol = $field.Name; Value = $value; Target = $session.Target; Port = $port }))
            Assert-FrameworkBinding $context
            $report.CommandAttempted = $true
            Write-AdsCommandField $session $field $value
            $report.CommandSubmitted = $true
            do {
                Start-Sleep -Milliseconds 20
                $after = Get-FrameworkCapture $context
                if ($Operation -eq 'Acknowledge') {
                    if ($after.Status.SequenceId -lt $before.Status.SequenceId -or
                        $after.Status.DeletedSequenceId -gt $Watermark) { throw 'Epoch changed or another consumer intervened.' }
                    $remainingPrefix = @($after.Events | Where-Object { $_.Value.SequenceId -le $Watermark })
                    $report.ObservationSatisfied = $after.Root.ControlData.BufferCmd.DeleteSequenceId -eq 0 -and
                        $after.Status.DeletedSequenceId -eq $Watermark -and $remainingPrefix.Count -eq 0
                    $report.Observation = [pscustomobject]@{ DeletedSequenceId = $after.Status.DeletedSequenceId; RemainingEvents = $after.Fifo.ElementCount }
                } else {
                    if ($Command -ne 'BufferReset' -and $after.Status.SequenceId -lt $before.Status.SequenceId) { throw 'Event-buffer epoch changed while observing the command.' }
                    $report.Observation = Test-CommandObservation $before $after
                    $report.ObservationSatisfied = if ($WaitFor -eq 'Accepted') { $report.Observation.RequestFieldCleared } else { $report.Observation.LifecycleCompleted }
                }
                if ($report.ObservationSatisfied) { break }
            } while ($session.Clock.ElapsedMilliseconds -lt $TimeoutMs)
            $report.AfterPath = Save-Evidence 'after.json' $after
            if (-not $report.ObservationSatisfied) { throw 'Requested observation not reached before timeout; no retry/reset performed.' }
        }
    }
} catch {
    $exitCode = 1
    $report.Error = $_.Exception.ToString()
    if ($null -ne $after -and -not $report.AfterPath) {
        $report.AfterPath = Save-Evidence 'last-observation.json' $after
    }
} finally {
    try { Close-LocalAdsTransport $session } catch {
        $exitCode = 1
        $report.Error = [string]$report.Error + "`nClient cleanup failed: " + $_.Exception.Message
    }
    $report['FinishedUtc'] = [DateTime]::UtcNow.ToString('o')
    $reportPath = Save-Evidence 'operation.json' ([pscustomobject]$report)
    [pscustomobject]@{ Evidence = $reportPath; ObservationSatisfied = $report.ObservationSatisfied; Error = $report.Error } | ConvertTo-Json -Depth 5
}
exit $exitCode
