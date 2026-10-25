#requires -Version 5.1
#requires -PSEdition Desktop
<#
.SYNOPSIS
Drains the approved local UnitTest event stream to JSONL.
.DESCRIPTION
Consumer only: no PLC/lifecycle commands or result evaluation. Requires exclusive
consumer ownership and an unchanged buffer epoch (no buffer reset, restart, download
or Online Change). Stop by creating the printed stop file, Ctrl+C, or duration expiry.
Every start uses a NEW evidence directory; automatic resume/reconnect is not supported.
An undetectable reset followed by identical data cannot be excluded by this protocol;
EpochUnchanged is an operator assertion, not an inferred epoch identifier.
#>
[CmdletBinding()]
param(
    [string]$ExpectedTargetNetId,
    [string]$ExpectedName = 'SelfTests',
    [ValidateRange(851, 899)][int]$PlcPort = 851,
    [ValidateRange(1, 3600)][int]$DurationSeconds = 120,
    [ValidateRange(10, 1000)][int]$PollIntervalMs = 50,
    [ValidateRange(100, 10000)][int]$IoTimeoutMs = 3000,
    [switch]$AllowRuntimeAccess,
    [switch]$ConfirmMutation,
    [switch]$ExclusiveConsumer,
    [switch]$EpochUnchanged
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $AllowRuntimeAccess -or -not $ConfirmMutation -or -not $ExclusiveConsumer -or -not $EpochUnchanged) {
    throw 'Obtain owner approval, then explicitly supply AllowRuntimeAccess, ConfirmMutation, ExclusiveConsumer and EpochUnchanged.'
}
if (-not $ExpectedTargetNetId -or -not $ExpectedName) { throw 'ExpectedTargetNetId and ExpectedName are required before connecting.' }

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$helpers = Join-Path $repoRoot 'tools/ads/scripts'
Import-Module (Join-Path $helpers 'UnitTestAds.psm1') -Force
Import-Module (Join-Path $helpers 'AdsTransport.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Consumer.psm1') -Force
$directory = Join-Path $repoRoot ('artifacts/validation/event-consumer/' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$capturePath = Join-Path $directory 'events.jsonl'
$stopPath = Join-Path $directory 'stop.request'
$stream = $null
$session = $null
$report = [pscustomobject][ordered]@{
    Format = 'event-consumer/1'; StartedUtc = [DateTime]::UtcNow.ToString('o')
    Target = $ExpectedTargetNetId; Port = $PlcPort; Name = $ExpectedName; Instance = $null
    ExclusiveConsumer = $true; EpochUnchangedAssertion = $true
    DurationSeconds = $DurationSeconds; PollIntervalMs = $PollIntervalMs
    InitialDeletedSequenceId = [uint32]0; LastPersistedSequenceId = [uint32]0
    LastAcknowledgedSequenceId = [uint32]0; PendingWatermark = [uint32]0
    EventCount = 0; BatchCount = 0; DeleteAttemptCount = 0; DeleteReturnedCount = 0
    StopReason = 'Interrupted'; Error = $null; FinishedUtc = $null
}
$exitCode = 0
try {
    $stream = [IO.File]::Open($capturePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    Write-ConsumerRecord $stream ([pscustomobject]@{ Kind = 'Session'; Settings = $report })
    $dependencies = Import-LocalAdsAssembly
    $session = Open-LocalAdsTransport $dependencies $PlcPort $IoTimeoutMs 30000 -ExpectedTargetNetId $ExpectedTargetNetId
    $report.Instance = $session.Instance
    $context = New-FrameworkContext $session $ExpectedName
    $deleteField = Get-CommandField $context 'Delete'
    $clock = [Diagnostics.Stopwatch]::StartNew()
    Write-Host "Capture: $capturePath"
    Write-Host "Stop safely: create $stopPath (or Ctrl+C). No other consumer or epoch-changing operation is allowed."
    # Each capture/write has its own bounded ADS budget; the separate run clock
    # bounds the polling session and is never restarted by successful operations.
    $read = {
        $session.Clock.Restart()
        Get-FrameworkCapture $context -Attempts 10
    }.GetNewClosure()
    $write = {
        param([uint32]$watermark)
        $session.Clock.Restart()
        Assert-FrameworkBinding $context
        Write-AdsCommandField $session $deleteField $watermark
    }.GetNewClosure()
    $save = { param($record) Write-ConsumerRecord $stream $record }.GetNewClosure()
    $stop = {
        if ([IO.File]::Exists($stopPath)) { $report.StopReason = 'StopRequested'; return $true }
        if ($clock.Elapsed.TotalSeconds -ge $DurationSeconds) { $report.StopReason = 'DurationElapsed'; return $true }
        return $false
    }.GetNewClosure()
    $wait = { Start-Sleep -Milliseconds $PollIntervalMs }.GetNewClosure()
    Invoke-EventConsumer -ReadCapture $read -WriteDelete $write -SaveRecord $save -ShouldStop $stop -Wait $wait -Report $report
} catch {
    $exitCode = 1
    $report.StopReason = 'Error'
    $report.Error = $_.Exception.ToString()
} finally {
    try { Close-LocalAdsTransport $session } catch { $exitCode = 1; $report.Error = [string]$report.Error + "`nCleanup: " + $_.Exception.Message }
    if ($null -ne $stream) { $stream.Dispose() }
    $report.FinishedUtc = [DateTime]::UtcNow.ToString('o')
    $summaryStream = [IO.File]::Open((Join-Path $directory 'operation.json'), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { Write-ConsumerRecord $summaryStream $report } finally { $summaryStream.Dispose() }
    $report | ConvertTo-Json -Depth 10
}
# DurationElapsed only means the bounded capture ended, not that tests passed or the FIFO is empty.
exit $exitCode
