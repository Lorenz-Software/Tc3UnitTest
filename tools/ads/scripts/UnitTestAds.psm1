Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AdsTransport.psm1') -Force

# Consumer schemas for contract 1.0.0: offsets and structure sizes always come from live symbols.
$script:Schemas = @{
    ST_ContractInfo = [ordered]@{ ContractVersion = 'STRING(10)'; FrameworkVersion = 'STRING(10)' }
    ST_Command = [ordered]@{ Start = 'BOOL'; Abort = 'BOOL'; Reset = 'BOOL' }
    ST_EventBufferCommand = [ordered]@{ Reset = 'BOOL'; DeleteSequenceId = 'UDINT' }
    ST_ExecutionStatus = [ordered]@{
        State = 'E_State'; ExecutionStatus = 'E_ExecutionStatus'; Result = 'E_Result'
        Uninitialized = 'BOOL'; ConfigError = 'BOOL'; Ready = 'BOOL'; Running = 'BOOL'
        Completed = 'BOOL'; Aborted = 'BOOL'; Inactive = 'BOOL'; Error = 'BOOL'
    }
    ST_RunControlStatus = [ordered]@{
        Execution = 'ST_ExecutionStatus'; SuiteCountTotal = 'UINT'; SuiteCountInactive = 'UINT'
        SuiteCountIdle = 'UINT'; SuiteCountRunning = 'UINT'; SuiteCountCompleted = 'UINT'
        SuiteCountPassed = 'UINT'; SuiteCountFailed = 'UINT'; SuiteCountError = 'UINT'; Runtime = 'TIME'
    }
    ST_RunControl = [ordered]@{
        Name = 'STRING(80)'; Cmd = 'ST_Command'; BufferCmd = 'ST_EventBufferCommand'; Status = 'ST_RunControlStatus'
    }
    ST_RunControlCommunication = [ordered]@{ ContractInfo = 'ST_ContractInfo'; ControlData = 'ST_RunControl' }
    ST_FifoStatus = [ordered]@{
        IndexOut = 'UINT'; IndexIn = 'UINT'; BufferEmpty = 'BOOL'; BufferFull = 'BOOL'
        BufferAlmostFull = 'BOOL'; ElementCount = 'UINT'; BufferLength = 'UINT'; ConfigError = 'BOOL'; IndexError = 'BOOL'
    }
    ST_EventBufferStatus = [ordered]@{ SequenceId = 'UDINT'; DeletedSequenceId = 'UDINT'; LostEventCount = 'UINT' }
    ST_Event = [ordered]@{
        SequenceId = 'UDINT'; Timestamp = 'LINT'; OwnerScope = 'E_OwnerScope'; EventType = 'E_EventType'
        Severity = 'E_EventSeverity'; Name = 'STRING(80)'; ResourceName = 'STRING(32)'
        State = 'E_State'; Result = 'E_Result'; Message = 'STRING(254)'
    }
}
$script:EnumTypes = @{
    E_State = 'INT'; E_Result = 'INT'; E_ExecutionStatus = 'INT'
    E_OwnerScope = 'USINT'; E_EventType = 'USINT'; E_EventSeverity = 'USINT'
}

function Get-ScalarSize {
    param([string]$Type)
    if ($script:EnumTypes.ContainsKey($Type)) { $Type = $script:EnumTypes[$Type] }
    if ($Type -match '^STRING\((\d+)\)$') { return [int]$Matches[1] + 1 }
    switch ($Type) {
        { $_ -in 'BOOL', 'BYTE', 'USINT', 'SINT' } { return 1 }
        { $_ -in 'INT', 'UINT', 'WORD' } { return 2 }
        { $_ -in 'DINT', 'UDINT', 'DWORD', 'TIME', 'REAL' } { return 4 }
        { $_ -in 'LINT', 'ULINT', 'LWORD', 'LREAL', 'LTIME' } { return 8 }
        default { throw "Unsupported scalar type: $Type" }
    }
}

function ConvertFrom-AdsScalar {
    param([string]$Type, [byte[]]$Bytes, [int]$Offset = 0)
    $size = Get-ScalarSize $Type
    if ($Offset -lt 0 -or ($Offset + $size) -gt $Bytes.Length) { throw 'Scalar exceeds the received byte range.' }
    if ($script:EnumTypes.ContainsKey($Type)) { $Type = $script:EnumTypes[$Type] }
    if ($Type -match '^STRING\(') {
        $end = $Offset
        while ($end -lt ($Offset + $size) -and $Bytes[$end] -ne 0) {
            if ($Bytes[$end] -gt 127) { throw 'Non-ASCII text in an ASCII contract field.' }
            $end++
        }
        if ($end -eq ($Offset + $size)) { throw 'Unterminated PLC string.' }
        return [Text.Encoding]::ASCII.GetString($Bytes, $Offset, $end - $Offset)
    }
    switch ($Type) {
        'BOOL' { if ($Bytes[$Offset] -gt 1) { throw 'Invalid BOOL representation.' }; return $Bytes[$Offset] -eq 1 }
        { $_ -in 'BYTE', 'USINT' } { return $Bytes[$Offset] }
        'SINT' { return [sbyte]([int]$Bytes[$Offset] - 256 * [int]($Bytes[$Offset] -gt 127)) }
        'INT' { return [BitConverter]::ToInt16($Bytes, $Offset) }
        { $_ -in 'UINT', 'WORD' } { return [BitConverter]::ToUInt16($Bytes, $Offset) }
        'DINT' { return [BitConverter]::ToInt32($Bytes, $Offset) }
        { $_ -in 'UDINT', 'DWORD', 'TIME' } { return [BitConverter]::ToUInt32($Bytes, $Offset) }
        'REAL' { return [BitConverter]::ToSingle($Bytes, $Offset) }
        # Decimal strings in the evidence format prevent downstream JSON/JavaScript precision loss.
        'LINT' { return [BitConverter]::ToInt64($Bytes, $Offset).ToString([Globalization.CultureInfo]::InvariantCulture) }
        { $_ -in 'ULINT', 'LWORD', 'LTIME' } { return [BitConverter]::ToUInt64($Bytes, $Offset).ToString([Globalization.CultureInfo]::InvariantCulture) }
        'LREAL' { return [BitConverter]::ToDouble($Bytes, $Offset) }
    }
}

function New-AdsLayout {
    param($Session, [string]$Name, [string]$Type)
    $symbol = Get-AdsSymbol $Session $Name
    $actualType = $symbol.Type -replace '^.*\.', '' -replace '\s+', ''
    if ($actualType -ine $Type) { throw "Type mismatch for ${Name}: expected $Type, got $($symbol.Type)." }
    $fields = [ordered]@{}
    if ($script:Schemas.ContainsKey($Type)) {
        $ranges = @()
        foreach ($field in $script:Schemas[$Type].GetEnumerator()) {
            $child = New-AdsLayout $Session ($Name + '.' + $field.Key) $field.Value
            $offset = [long]$child.Symbol.Offset - [long]$symbol.Offset
            if ($child.Symbol.Group -ne $symbol.Group -or $offset -lt 0 -or
                ($offset + $child.Symbol.Size) -gt $symbol.Size) { throw "Invalid member range: $($child.Symbol.Name)" }
            foreach ($range in $ranges) {
                if ($offset -lt $range.End -and ($offset + $child.Symbol.Size) -gt $range.Start) { throw 'Overlapping struct fields.' }
            }
            $ranges += [pscustomobject]@{ Start = $offset; End = $offset + $child.Symbol.Size }
            $fields[$field.Key] = $child
        }
    } elseif ($symbol.Size -ne (Get-ScalarSize $Type)) { throw "Size mismatch: $Name" }
    [pscustomobject]@{ Symbol = $symbol; Type = $Type; Fields = $fields }
}

function ConvertFrom-AdsLayout {
    param($Layout, [byte[]]$Bytes, [int]$Offset = 0)
    if ($Offset -lt 0 -or ($Offset + $Layout.Symbol.Size) -gt $Bytes.Length) { throw 'Layout exceeds the received byte range.' }
    if ($Layout.Fields.Count -eq 0) { return ConvertFrom-AdsScalar $Layout.Type $Bytes $Offset }
    $result = [ordered]@{}
    foreach ($entry in $Layout.Fields.GetEnumerator()) {
        $childOffset = $Offset + $entry.Value.Symbol.Offset - $Layout.Symbol.Offset
        $result[$entry.Key] = ConvertFrom-AdsLayout $entry.Value $Bytes $childOffset
    }
    [pscustomobject]$result
}

function Read-AdsLayout {
    param($Session, $Layout)
    $bytes = Read-AdsBytes $Session $Layout.Symbol.Group $Layout.Symbol.Offset $Layout.Symbol.Size
    ConvertFrom-AdsLayout $Layout $bytes
}

function Assert-FrameworkBinding {
    param($Context)
    if ((Get-AdsSymbolVersion $Context.Session) -ne $Context.SymbolVersion) {
        throw 'PLC symbols changed. End the operation and establish a fresh binding; do not retry a write.'
    }
    if ((Get-AdsRuntimeState $Context.Session).AdsState -ne 'Run') { throw 'PLC application is not in Run.' }
}

function New-FrameworkContext {
    param($Session, [string]$ExpectedName)
    $version = Get-AdsSymbolVersion $Session
    $root = New-AdsLayout $Session 'GVL_UnitTest.RunControl' 'ST_RunControlCommunication'
    $info = New-AdsLayout $Session 'GVL_UnitTest.EventStream.ContractInfo' 'ST_ContractInfo'
    $fifo = New-AdsLayout $Session 'GVL_UnitTest.EventStream.FifoControl' 'ST_FifoStatus'
    $status = New-AdsLayout $Session 'GVL_UnitTest.EventStream.Status' 'ST_EventBufferStatus'
    $rootValue = Read-AdsLayout $Session $root
    $eventInfo = Read-AdsLayout $Session $info
    if ($rootValue.ContractInfo.ContractVersion -ne '1.0.0' -or $eventInfo.ContractVersion -ne '1.0.0') {
        throw 'Unsupported or uninitialized Run Control/Event Stream contract. Only 1.0.0 is supported.'
    }
    if (-not $ExpectedName -or $rootValue.ControlData.Name -cne $ExpectedName) { throw 'Unexpected Run Control name; no write allowed.' }
    $fifoValue = Read-AdsLayout $Session $fifo
    $capacity = [int]$fifoValue.BufferLength
    if ($capacity -lt 3 -or $capacity -gt 32767) { throw 'Uninitialized or unsupported event buffer length.' }
    $buffer = Get-AdsSymbol $Session 'GVL_UnitTest.EventStream.Buffer'
    if ($buffer.Type -notmatch '^ARRAY\s*\[\s*1\s*\.\.\s*(\d+)\s*\]\s*OF\s+(?:\w+\.)?ST_Event$' -or
        [int]$Matches[1] -ne $capacity) { throw 'Live event-array bounds/type do not match BufferLength.' }
    $event = New-AdsLayout $Session 'GVL_UnitTest.EventStream.Buffer[1]' 'ST_Event'
    $last = Get-AdsSymbol $Session "GVL_UnitTest.EventStream.Buffer[$capacity]"
    if ($buffer.Group -ne $event.Symbol.Group -or $buffer.Offset -ne $event.Symbol.Offset -or
        $buffer.Size -ne ($capacity * $event.Symbol.Size) -or $last.Group -ne $buffer.Group -or
        $last.Offset -ne ($buffer.Offset + ($capacity - 1) * $event.Symbol.Size) -or $last.Size -ne $event.Symbol.Size) {
        throw 'Event-array storage/stride mismatch.'
    }
    $context = [pscustomobject]@{
        Session = $Session; SymbolVersion = $version; Root = $root; ContractInfo = $info
        Fifo = $fifo; Status = $status; Buffer = $buffer; Event = $event; Capacity = $capacity; ExpectedName = $ExpectedName
    }
    Assert-FrameworkBinding $context
    return $context
}

function Get-FifoIndices {
    param($Fifo, [int]$Capacity)
    if ($Fifo.ConfigError -or $Fifo.IndexError -or $Fifo.BufferLength -ne $Capacity -or
        $Fifo.IndexIn -lt 1 -or $Fifo.IndexIn -gt $Capacity -or $Fifo.IndexOut -lt 1 -or $Fifo.IndexOut -gt $Capacity) {
        throw 'Invalid FIFO metadata.'
    }
    $count = ([int]$Fifo.IndexIn - [int]$Fifo.IndexOut + $Capacity) % $Capacity
    if ($Fifo.ElementCount -ne $count -or $Fifo.BufferEmpty -ne ($count -eq 0) -or
        $Fifo.BufferFull -ne ($count -eq ($Capacity - 1))) { throw 'Inconsistent FIFO metadata.' }
    for ($i = 0; $i -lt $count; $i++) { ([int]$Fifo.IndexOut - 1 + $i) % $Capacity + 1 }
}

function Read-EventRange {
    param($Context, [int[]]$Indices)
    $events = New-Object 'Collections.Generic.List[object]'
    $position = 0
    while ($position -lt $Indices.Count) {
        $runLength = 1
        while (($position + $runLength) -lt $Indices.Count -and
            $Indices[$position + $runLength] -eq ($Indices[$position] + $runLength)) { $runLength++ }
        $elementSize = $Context.Event.Symbol.Size
        $offset = $Context.Buffer.Offset + ($Indices[$position] - 1) * $elementSize
        $bytes = Read-AdsBytes $Context.Session $Context.Buffer.Group $offset ($runLength * $elementSize)
        for ($i = 0; $i -lt $runLength; $i++) {
            $events.Add([pscustomobject]@{
                Index = $Indices[$position + $i]; Raw = [Convert]::ToBase64String($bytes, $i * $elementSize, $elementSize)
                Value = (ConvertFrom-AdsLayout $Context.Event $bytes ($i * $elementSize))
            })
        }
        $position += $runLength
    }
    return ,$events.ToArray()
}

function Get-ObjectFingerprint {
    param($Value)
    ConvertTo-Json -InputObject $Value -Depth 20 -Compress
}

function Get-FrameworkCapture {
    param($Context, [ValidateRange(1, 10)][int]$Attempts = 3)
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        Assert-FrameworkBinding $Context
        $fifo = Read-AdsLayout $Context.Session $Context.Fifo
        $status = Read-AdsLayout $Context.Session $Context.Status
        $indices = @(Get-FifoIndices $fifo $Context.Capacity)
        $events = Read-EventRange $Context $indices
        $root = Read-AdsLayout $Context.Session $Context.Root
        $info = Read-AdsLayout $Context.Session $Context.ContractInfo
        $repeatedEvents = Read-EventRange $Context $indices
        $afterStatus = Read-AdsLayout $Context.Session $Context.Status
        $afterFifo = Read-AdsLayout $Context.Session $Context.Fifo
        Assert-FrameworkBinding $Context
        if ((Get-ObjectFingerprint $fifo) -ne (Get-ObjectFingerprint $afterFifo) -or
            (Get-ObjectFingerprint $status) -ne (Get-ObjectFingerprint $afterStatus) -or
            (Get-ObjectFingerprint $events) -ne (Get-ObjectFingerprint $repeatedEvents)) {
            continue
        }
        if ($root.ControlData.Name -cne $Context.ExpectedName -or
            $root.ContractInfo.ContractVersion -ne '1.0.0' -or $info.ContractVersion -ne '1.0.0') { throw 'Framework identity changed.' }
        $previous = [uint32]$status.DeletedSequenceId
        $gaps = @()
        foreach ($entry in $events) {
            $sequence = [uint32]$entry.Value.SequenceId
            if ($sequence -le $previous -or $sequence -gt $status.SequenceId) { throw 'Invalid event sequence in readable FIFO range.' }
            if ([uint64]$sequence -ne ([uint64]$previous + 1)) { $gaps += "$previous->$sequence" }
            $previous = $sequence
        }
        return [pscustomobject][ordered]@{
            Format = 'tc3-engineering-capture/1'; CapturedUtc = [DateTime]::UtcNow.ToString('o')
            Target = $Context.Session.Target; Port = $Context.Session.Port; SymbolVersion = $Context.SymbolVersion
            Name = $Context.ExpectedName; Root = $root; ContractInfo = $info; Fifo = $fifo; Status = $status
            Events = $events; SequenceGaps = $gaps; LogIncomplete = ($gaps.Count -gt 0 -or $status.LostEventCount -gt 0)
            Consistency = 'Repeated event bytes and stable FIFO/status; diagnostic Root is a separate read, not an atomic PLC snapshot.'
        }
    }
    throw 'No stable event capture within the bounded attempts. Nothing acknowledged.'
}

function Assert-Acknowledgement {
    param($Archived, $Current, [uint32]$Watermark)
    if ($Archived.Format -ne 'tc3-engineering-capture/1' -or $Current.Format -ne $Archived.Format) { throw 'Unsupported capture format.' }
    if ($Archived.Target -ne $Current.Target -or $Archived.Port -ne $Current.Port -or
        $Archived.Name -cne $Current.Name -or $Archived.SymbolVersion -ne $Current.SymbolVersion) { throw 'Capture target/application changed.' }
    if ($Watermark -eq 0 -or $Watermark -le $Current.Status.DeletedSequenceId -or
        $Archived.Status.DeletedSequenceId -ne $Current.Status.DeletedSequenceId -or
        $Current.Status.SequenceId -lt $Archived.Status.SequenceId) { throw 'Stale watermark, competing consumer or epoch change.' }
    $archivedPrefix = @($Archived.Events | Where-Object { [uint32]$_.Value.SequenceId -le $Watermark })
    $currentPrefix = @($Current.Events | Where-Object { [uint32]$_.Value.SequenceId -le $Watermark })
    if ($archivedPrefix.Count -eq 0 -or $archivedPrefix.Count -ne $currentPrefix.Count -or
        [uint32]$archivedPrefix[-1].Value.SequenceId -ne $Watermark) { throw 'Watermark is not an archived readable event.' }
    $previous = [uint64]$Current.Status.DeletedSequenceId
    for ($i = 0; $i -lt $archivedPrefix.Count; $i++) {
        if ([uint64]$currentPrefix[$i].Value.SequenceId -ne ($previous + 1) -or
            $archivedPrefix[$i].Raw -cne $currentPrefix[$i].Raw) { throw 'Acknowledgement prefix has gaps or changed bytes.' }
        $previous++
    }
}

function Get-CommandField {
    param($Context, [ValidateSet('Start', 'Abort', 'Reset', 'BufferReset', 'Delete')][string]$Command)
    $control = $Context.Root.Fields.ControlData
    switch ($Command) {
        'BufferReset' { return $control.Fields.BufferCmd.Fields.Reset.Symbol }
        'Delete' { return $control.Fields.BufferCmd.Fields.DeleteSequenceId.Symbol }
        default { return $control.Fields.Cmd.Fields[$Command].Symbol }
    }
}

function Read-SelectedScalar {
    param($Session, [string]$Name)
    $symbol = Get-AdsSymbol $Session $Name
    $type = $symbol.Type -replace '^.*\.', '' -replace '\s+', ''
    if ($symbol.Size -ne (Get-ScalarSize $type)) { throw 'Selected scalar size mismatch.' }
    $bytes = Read-AdsBytes $Session $symbol.Group $symbol.Offset $symbol.Size
    [pscustomobject]@{ Symbol = $Name; Type = $symbol.Type; Value = (ConvertFrom-AdsScalar $type $bytes) }
}

Export-ModuleMember -Function New-FrameworkContext, Get-FrameworkCapture, Assert-FrameworkBinding,
    Assert-Acknowledgement, Get-CommandField, Read-SelectedScalar, Get-FifoIndices, ConvertFrom-AdsScalar
