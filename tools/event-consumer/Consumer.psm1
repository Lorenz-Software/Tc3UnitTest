Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Polling only. ADS decoding and watermark validation belong to the shared helper.
function Assert-ConsumerCapture {
    param($Capture, $Identity, [uint32]$MinimumSequence)
    if ($Capture.Format -ne 'tc3-engineering-capture/1' -or
        $Capture.Target -cne $Identity.Target -or $Capture.Port -ne $Identity.Port -or
        $Capture.Name -cne $Identity.Name -or $Capture.SymbolVersion -ne $Identity.SymbolVersion) {
        throw 'Target, application or symbol generation changed; end this consumer session.'
    }
    if ($Capture.LogIncomplete -or $Capture.Status.LostEventCount -ne 0 -or
        @($Capture.SequenceGaps).Count -ne 0) { throw 'Incomplete event stream; nothing further acknowledged.' }
    if ($Capture.Status.SequenceId -lt $MinimumSequence) { throw 'Sequence regressed; possible buffer reset/restart.' }
    if ($Capture.Root.ControlData.BufferCmd.Reset) { throw 'Buffer Reset is pending; acknowledgement refused.' }
    $indices = @(Get-FifoIndices $Capture.Fifo $Capture.Fifo.BufferLength)
    if ($indices.Count -ne @($Capture.Events).Count) { throw 'Capture length differs from readable FIFO range.' }
    $sequence = [uint64]$Capture.Status.DeletedSequenceId
    for ($i = 0; $i -lt $indices.Count; $i++) {
        $entry = $Capture.Events[$i]
        $sequence++
        if ($entry.Index -ne $indices[$i] -or [uint64]$entry.Value.SequenceId -ne $sequence) {
            throw 'Duplicate, reordered or missing event in the readable prefix.'
        }
    }
    if ($sequence -ne [uint64]$Capture.Status.SequenceId) { throw 'Assigned sequence is not fully represented by readable events.' }
}

function Write-ConsumerRecord {
    param([IO.FileStream]$Stream, $Record)
    $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Record -Depth 30 -Compress) + "`r`n")
    $position = $Stream.Position
    try {
        $Stream.Write($bytes, 0, $bytes.Length)
        $Stream.Flush($true)
    } catch {
        # Best effort: retain complete JSONL records on a recoverable write failure.
        # Even if rollback also fails, the caller cannot proceed to acknowledgement.
        try { $Stream.SetLength($position); $Stream.Position = $position; $Stream.Flush($true) } catch { }
        throw
    }
}

function Invoke-EventConsumer {
    param(
        [Parameter(Mandatory)][scriptblock]$ReadCapture,
        [Parameter(Mandatory)][scriptblock]$WriteDelete,
        [Parameter(Mandatory)][scriptblock]$SaveRecord,
        [Parameter(Mandatory)][scriptblock]$ShouldStop,
        [Parameter(Mandatory)][scriptblock]$Wait,
        [Parameter(Mandatory)]$Report,
        [ValidateRange(100, 10000)][int]$AcknowledgementTimeoutMs = 3000
    )

    $identity = $null
    $lastSequence = [uint32]0
    $deleted = [uint32]0
    while (-not (& $ShouldStop)) {
        $capture = & $ReadCapture
        if ($null -eq $identity) {
            $identity = $capture
            Assert-ConsumerCapture $capture $identity 0
            $deleted = [uint32]$capture.Status.DeletedSequenceId
            $Report.InitialDeletedSequenceId = $deleted
            $Report.LastAcknowledgedSequenceId = $deleted
            $Report.LastPersistedSequenceId = $deleted
            & $SaveRecord ([pscustomobject]@{
                Kind = 'Baseline'; CapturedUtc = $capture.CapturedUtc
                Target = $capture.Target; Port = $capture.Port; Name = $capture.Name
                SymbolVersion = $capture.SymbolVersion; ContractInfo = $capture.ContractInfo
                InitialDeletedSequenceId = $deleted
                Note = 'Capture starts after this watermark; earlier deleted events are not part of this file.'
            })
        }
        Assert-ConsumerCapture $capture $identity $lastSequence
        $lastSequence = [uint32]$capture.Status.SequenceId
        if ($capture.Status.DeletedSequenceId -ne $deleted -or
            $capture.Root.ControlData.BufferCmd.DeleteSequenceId -ne 0) {
            throw 'Unexpected deletion or pending delete command; exclusive consumer ownership is not established.'
        }
        if (@($capture.Events).Count -eq 0) { & $Wait; continue }

        $watermark = [uint32]$capture.Events[-1].Value.SequenceId
        # One JSONL batch contains the complete helper capture, including exact raw event bytes.
        # Verification/pending-ack reads are NOT archived again as new event batches.
        & $SaveRecord ([pscustomobject]@{ Kind = 'Events'; Capture = $capture })
        $Report.LastPersistedSequenceId = $watermark
        $Report.EventCount += @($capture.Events).Count
        $Report.BatchCount++
        if (& $ShouldStop) { return }

        $current = & $ReadCapture
        Assert-ConsumerCapture $current $identity $lastSequence
        $lastSequence = [uint32]$current.Status.SequenceId
        if ($current.Root.ControlData.BufferCmd.DeleteSequenceId -ne 0) { throw 'Another delete request appeared before submission.' }
        Assert-Acknowledgement $capture $current $watermark
        & $SaveRecord ([pscustomobject]@{
            Kind = 'AcknowledgeIntent'; Utc = [DateTime]::UtcNow.ToString('o'); Watermark = $watermark
        })
        if (& $ShouldStop) { return }
        $Report.PendingWatermark = $watermark
        $Report.DeleteAttemptCount++
        & $WriteDelete $watermark
        $Report.DeleteReturnedCount++

        $ackClock = [Diagnostics.Stopwatch]::StartNew()
        while ($true) {
            if (& $ShouldStop) { return }
            if ($ackClock.ElapsedMilliseconds -ge $AcknowledgementTimeoutMs) {
                throw 'Delete acknowledgement timeout; the request is not resent.'
            }
            & $Wait
            if (& $ShouldStop) { return }
            $after = & $ReadCapture
            Assert-ConsumerCapture $after $identity $lastSequence
            $lastSequence = [uint32]$after.Status.SequenceId
            $observedDeleted = [uint32]$after.Status.DeletedSequenceId
            $command = [uint32]$after.Root.ControlData.BufferCmd.DeleteSequenceId
            if ($observedDeleted -lt $deleted -or $observedDeleted -gt $watermark -or
                $command -notin @([uint32]0, $watermark)) {
                throw 'Deletion crossed the requested range or another consumer intervened.'
            }
            # Deletion is synchronous in the PLC task, but ADS can observe it partway through.
            # Any still-readable archived prefix must remain byte-identical; no resubmission.
            $remaining = @($after.Events | Where-Object { $_.Value.SequenceId -le $watermark })
            foreach ($entry in $remaining) {
                $offset = [int]([uint64]$entry.Value.SequenceId - [uint64]$deleted - 1)
                if ($offset -lt 0 -or $offset -ge @($capture.Events).Count -or
                    $entry.Raw -cne $capture.Events[$offset].Raw) { throw 'Archived event prefix changed while waiting for deletion.' }
            }
            if ($observedDeleted -eq $watermark -and $command -eq 0 -and $remaining.Count -eq 0) {
                $deleted = $watermark
                $Report.LastAcknowledgedSequenceId = $watermark
                $Report.PendingWatermark = [uint32]0
                & $SaveRecord ([pscustomobject]@{
                    Kind = 'Acknowledged'; Utc = [DateTime]::UtcNow.ToString('o'); Watermark = $watermark
                })
                break
            }
        }
    }
}

Export-ModuleMember -Function Invoke-EventConsumer, Write-ConsumerRecord
