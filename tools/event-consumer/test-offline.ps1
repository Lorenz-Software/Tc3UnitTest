#requires -Version 5.1
#requires -PSEdition Desktop
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Import-Module (Join-Path $repo 'tools/ads/scripts/UnitTestAds.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Consumer.psm1') -Force
$results = New-Object 'Collections.Generic.List[object]'
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Capture([int]$Deleted, [int]$Last, [int]$Pending = 0) {
    $events = @()
    for ($i = $Deleted + 1; $i -le $Last; $i++) {
        $events += [pscustomobject]@{ Index = (($i - 1) % 8 + 1); Raw = "raw-$i"; Value = [pscustomobject]@{
            SequenceId = $i; Timestamp = '9223372036854775807'; Message = "Event $i"
        } }
    }
    [pscustomobject]@{
        Format = 'tc3-engineering-capture/1'; Target = 'offline'; Port = 851; Name = 'SelfTests'; SymbolVersion = 1
        CapturedUtc = '2026-10-04T00:00:00Z'; ContractInfo = @{ ContractVersion = '1.0.0' }
        Root = @{ ControlData = @{ BufferCmd = @{ Reset = $false; DeleteSequenceId = $Pending } } }
        Fifo = @{ IndexIn = ($Last % 8 + 1); IndexOut = ($Deleted % 8 + 1); ElementCount = ($Last - $Deleted)
            BufferLength = 8; ConfigError = $false; IndexError = $false; BufferEmpty = ($Last -eq $Deleted); BufferFull = (($Last - $Deleted) -eq 7) }
        Status = @{ SequenceId = $Last; DeletedSequenceId = $Deleted; LostEventCount = 0 }
        Events = $events; SequenceGaps = @(); LogIncomplete = $false
    }
}
function Run($Captures, [string]$Fault = '', [string]$StopAt = '', [switch]$RepeatLast, [int]$WaitMs = 0) {
    $state = @{ Position = 0; Stop = $false; Records = (New-Object 'Collections.Generic.List[object]')
        Writes = (New-Object 'Collections.Generic.List[uint32]'); Trace = (New-Object 'Collections.Generic.List[string]') }
    $report = [pscustomobject]@{ InitialDeletedSequenceId = 0; LastPersistedSequenceId = 0; LastAcknowledgedSequenceId = 0
        PendingWatermark = 0; EventCount = 0; BatchCount = 0; DeleteAttemptCount = 0; DeleteReturnedCount = 0 }
    $read = {
        if ($state.Position -ge $Captures.Count) {
            if ($RepeatLast) { return $Captures[-1] }
            throw 'Fixture exhausted.'
        }
        $item = $Captures[$state.Position]; $state.Position++
        if ($item -is [string]) { throw $item }
        return $item
    }.GetNewClosure()
    $save = {
        param($record)
        if ($Fault -eq $record.Kind) { throw "Injected persistence failure: $Fault" }
        $state.Records.Add($record); $state.Trace.Add($record.Kind)
        if ($StopAt -eq $record.Kind) { $state.Stop = $true }
    }.GetNewClosure()
    $write = {
        param($watermark)
        $state.Writes.Add($watermark); $state.Trace.Add("Write:$watermark")
        if ($Fault -eq 'Write') { throw 'Injected ambiguous ADS write failure.' }
        if ($StopAt -eq 'Write') { $state.Stop = $true }
    }.GetNewClosure()
    $stop = { $state.Stop -or ((-not $RepeatLast) -and $state.Position -ge $Captures.Count -and $report.PendingWatermark -eq 0) }.GetNewClosure()
    $wait = { if ($WaitMs -gt 0) { Start-Sleep -Milliseconds $WaitMs } }.GetNewClosure()
    $failure = $null
    try { Invoke-EventConsumer -ReadCapture $read -WriteDelete $write -SaveRecord $save -ShouldStop $stop -Wait $wait -Report $report -AcknowledgementTimeoutMs 100 }
    catch { $failure = $_.Exception.Message }
    [pscustomobject]@{ State = $state; Report = $report; Error = $failure }
}
function Check([string]$Name, [scriptblock]$Body) {
    & $Body
    $results.Add([pscustomobject]@{ Name = $Name; Passed = $true })
    Write-Host "PASS $Name"
}
Check 'Concurrent production, repeated reads, two batches and ordered acknowledgements' {
    $r = Run @((Capture 0 2), (Capture 0 3), (Capture 0 3 2), (Capture 2 3), (Capture 2 3), (Capture 2 3), (Capture 3 3))
    Assert ($null -eq $r.Error) $r.Error
    Assert (($r.State.Trace -join ',') -eq 'Baseline,Events,AcknowledgeIntent,Write:2,Acknowledged,Events,AcknowledgeIntent,Write:3,Acknowledged') 'Incorrect persistence/ack ordering.'
    Assert ($r.Report.EventCount -eq 3 -and $r.Report.LastAcknowledgedSequenceId -eq 3) 'Events counted twice or not acknowledged.'
}
Check 'Already deleted prefix and wrapped indices' {
    $r = Run @((Capture 39 42), (Capture 39 42), (Capture 42 42))
    Assert ($null -eq $r.Error) $r.Error
    Assert ($r.Report.InitialDeletedSequenceId -eq 39 -and $r.Report.EventCount -eq 3) 'Wrong capture baseline.'
}
foreach ($fault in @('Events', 'AcknowledgeIntent')) {
    Check "Persistence failure at $fault prevents delete" {
        $r = Run @((Capture 0 2), (Capture 0 2), (Capture 2 2)) -Fault $fault
        Assert ($r.Error -like 'Injected persistence*' -and $r.State.Writes.Count -eq 0) 'Persistence failure did not stop delete.'
    }
}
foreach ($stopAt in @('Events', 'AcknowledgeIntent', 'Write')) {
    Check "Cancellation after $stopAt does not advance or resend" {
        $r = Run @((Capture 0 2), (Capture 0 2), (Capture 2 2)) -StopAt $stopAt
        Assert ($null -eq $r.Error) $r.Error
        Assert ($r.Report.LastPersistedSequenceId -eq 2 -and $r.Report.LastAcknowledgedSequenceId -eq 0) 'Wrong cancellation watermark.'
        Assert ($r.State.Writes.Count -eq [int]($stopAt -eq 'Write')) 'Unexpected delete call.'
    }
}
Check 'Ambiguous ADS write is never retried' {
    $r = Run @((Capture 0 2), (Capture 0 2), (Capture 2 2)) -Fault Write
    Assert ($r.Error -like 'Injected ambiguous*' -and $r.State.Writes.Count -eq 1 -and $r.Report.PendingWatermark -eq 2) 'Ambiguous write handling.'
}
Check 'Acknowledgement timeout is bounded and does not resend' {
    $r = Run @((Capture 0 2), (Capture 0 2), (Capture 0 2 2)) -RepeatLast -WaitMs 30
    Assert ($r.Error -like 'Delete acknowledgement timeout*' -and $r.State.Writes.Count -eq 1) 'Timeout handling.'
}
Check 'Read failure after persistence prevents delete' {
    $r = Run @((Capture 0 2), 'Injected read failure')
    Assert ($r.Error -eq 'Injected read failure' -and $r.State.Writes.Count -eq 0) 'Read failure handling.'
}
foreach ($kind in @('Gap', 'Duplicate', 'Bytes', 'Symbol', 'Regression', 'OtherDelete', 'Lost', 'Reset')) {
    Check "Reject $kind before deletion" {
        $first = Capture 0 2; $next = Capture 0 2
        switch ($kind) {
            Gap { $next.Events[1].Value.SequenceId = 3 }
            Duplicate { $next.Events[1].Value.SequenceId = 1 }
            Bytes { $next.Events[0].Raw = 'changed' }
            Symbol { $next.SymbolVersion = 2 }
            Regression { $next = Capture 0 1 }
            OtherDelete { $next.Root.ControlData.BufferCmd.DeleteSequenceId = 1 }
            Lost { $next.Status.LostEventCount = 1 }
            Reset { $next.Root.ControlData.BufferCmd.Reset = $true }
        }
        $r = Run @($first, $next, (Capture 2 2))
        Assert ($null -ne $r.Error -and $r.State.Writes.Count -eq 0) "Did not reject $kind."
    }
}
$output = Join-Path $repo ('artifacts/validation/event-consumer/offline-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($output)
Check 'Durable JSONL roundtrip retains 64-bit timestamp strings and complete records' {
    $path = Join-Path $output 'roundtrip.jsonl'
    $stream = [IO.File]::Open($path, 'CreateNew', 'Write', 'Read')
    try {
        Write-ConsumerRecord $stream ([pscustomobject]@{ Kind = 'Events'; Capture = (Capture 0 2) })
        Write-ConsumerRecord $stream ([pscustomobject]@{ Kind = 'Acknowledged'; Watermark = 2 })
    } finally { $stream.Dispose() }
    $lines = [IO.File]::ReadAllLines($path)
    $record = ConvertFrom-Json $lines[0]
    Assert ($lines.Count -eq 2 -and $record.Capture.Events[0].Value.Timestamp -ceq '9223372036854775807') 'JSONL precision or record boundary lost.'
}
Check 'Entry point refuses unapproved access before connecting' {
    $message = ''
    try { & (Join-Path $PSScriptRoot 'consume-events.ps1') } catch { $message = $_.Exception.Message }
    Assert ($message -like 'Obtain owner approval*') "Permission gate failed: $message"
}
Check 'Long capture duration still requires approval before connecting' {
    $message = ''
    try { & (Join-Path $PSScriptRoot 'consume-events.ps1') -DurationSeconds 3600 } catch { $message = $_.Exception.Message }
    Assert ($message -like 'Obtain owner approval*') "Long duration rejected incorrectly or bypassed approval: $message"
}
$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'results.json') -Encoding UTF8
Write-Host "Passed $($results.Count) offline consumer checks. No ADS client created. Evidence: $output"
