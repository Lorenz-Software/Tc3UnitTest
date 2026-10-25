#requires -Version 5.1
[CmdletBinding()]
param([switch]$CheckInstalledDependencies, [switch]$CheckLocalInstance, [string]$CapturePath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object Extension -in '.ps1', '.psm1') {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
}

Import-Module (Join-Path $PSScriptRoot 'UnitTestAds.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AdsTransport.psm1') -Force
if ($null -eq (Get-Command Import-LocalAdsAssembly -ErrorAction SilentlyContinue)) { throw 'Transport not exported.' }
& (Get-Module UnitTestAds) {
    foreach ($name in 'Read-AdsBytes', 'Get-AdsSymbol', 'Get-AdsSymbolVersion', 'Get-AdsRuntimeState') {
        if ($null -eq (Get-Command $name -ErrorAction SilentlyContinue)) { throw "Missing nested transport command: $name" }
    }
}

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ([string]$Expected -cne [string]$Actual) { throw "$Message : expected '$Expected', got '$Actual'." }
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    if (-not $failed) { throw "Expected rejection: $Message" }
}

$transportModule = Get-Module AdsTransport
Add-Type -TypeDefinition @'
public sealed class AdsSymbolFixture {
    public string DataType { get { return "UINT"; } }
    public int Datatype { get { return 18; } }
    public string TypeName { get { return "UINT"; } }
    public int ByteSize { get { return 2; } }
    public long IndexGroup { get { return 16448; } }
    public long IndexOffset { get { return 32; } }
    public bool IsBitType { get { return false; } }
    public bool IsPointer { get; set; }
    public bool IsReference { get { return false; } }
    public bool IsTcComInterfacePointer { get { return false; } }
    public bool IsReadOnly { get { return true; } }
}
'@
$symbolFixture = New-Object AdsSymbolFixture
$projectSymbol = { param($symbol) ConvertFrom-AdsSymbol $symbol 'Offline.Value' }
$projected = & $transportModule $projectSymbol $symbolFixture
Assert-Equal 'UINT' $projected.Type 'Symbol projection with case-clashing SDK members'
Assert-Equal 2 $projected.Size 'Symbol size'
Assert-Equal 32 $projected.Offset 'Symbol offset'
Assert-Equal True $projected.ReadOnly 'Read-only symbol'
[AdsSymbolFixture].GetProperty('IsPointer').SetValue($symbolFixture, $true, $null)
Assert-Throws { & $transportModule $projectSymbol $symbolFixture } 'Pointer symbol rejected'

$registryFixture = '<TcRegistry><Key Name="HKLM"><Key Name="Software"><Key Name="Beckhoff"><Key Name="TwinCAT3"><Key Name="System"><Value Name="AmsNetId" Type="BIN">010203040506</Value><Value Name="DefaultTransportAmsNetId" Type="BIN">060504030201</Value></Key></Key></Key></Key></Key></TcRegistry>'
$resolveFixture = { param($content, $expected) ConvertFrom-UsermodeRegistry $content $expected }
Assert-Equal '1.2.3.4.5.6' (& $transportModule $resolveFixture $registryFixture '') 'Configured instance, not transport Net ID'
Assert-Equal '1.2.3.4.5.6' (& $transportModule $resolveFixture $registryFixture '1.2.3.4.5.6') 'Matching XAE target'
Assert-Throws { & $transportModule $resolveFixture $registryFixture '6.5.4.3.2.1' } 'Mismatched XAE target'
Assert-Throws { & $transportModule $resolveFixture ($registryFixture.Replace('010203040506', '0102')) '' } 'Short Net ID'
Assert-Throws { & $transportModule $resolveFixture ($registryFixture.Replace('010203040506', '000000000000')) '' } 'Local alias'
Assert-Throws { & $transportModule $resolveFixture ($registryFixture.Replace('Type="BIN"', 'Type="SZ"')) '' } 'Wrong registry value type'
Assert-Throws { & $transportModule $resolveFixture '<TcRegistry />' '' } 'Missing configured Net ID'
Assert-Throws { & $transportModule $resolveFixture ($registryFixture.Replace('<Value Name="DefaultTransportAmsNetId"', '<Value Name="AmsNetId"')) '' } 'Ambiguous Net ID'

Assert-Equal '9223372036854775807' (ConvertFrom-AdsScalar LINT ([BitConverter]::GetBytes([long]::MaxValue))) 'LINT precision'
Assert-Equal '-9223372036854775808' (ConvertFrom-AdsScalar LINT ([BitConverter]::GetBytes([long]::MinValue))) 'Negative LINT'
Assert-Equal '18446744073709551615' (ConvertFrom-AdsScalar ULINT ([BitConverter]::GetBytes([uint64]::MaxValue))) 'ULINT precision'
$timestamp = ConvertFrom-AdsScalar LINT ([BitConverter]::GetBytes([long]::MaxValue))
$roundTrip = [pscustomobject]@{ Timestamp = $timestamp } | ConvertTo-Json | ConvertFrom-Json
Assert-Equal $timestamp $roundTrip.Timestamp 'JSON timestamp precision'
if ($roundTrip.Timestamp -isnot [string]) { throw 'Timestamp JSON must use a decimal string.' }
Assert-Equal 'AB' (ConvertFrom-AdsScalar 'STRING(3)' ([byte[]](65, 66, 0, 0))) 'ASCII'
Assert-Throws { ConvertFrom-AdsScalar 'STRING(3)' ([byte[]](65, 66, 67, 68)) } 'Missing terminator'
Assert-Throws { ConvertFrom-AdsScalar LINT ([byte[]](1, 2)) } 'Short read'
Assert-Throws { ConvertFrom-AdsScalar BOOL ([byte[]](2)) } 'Invalid BOOL'

$fifo = [pscustomobject]@{ ConfigError = $false; IndexError = $false; BufferLength = 4
    IndexIn = 2; IndexOut = 3; ElementCount = 3; BufferEmpty = $false; BufferFull = $true }
Assert-Equal '3,4,1' ((Get-FifoIndices $fifo 4) -join ',') 'Wrapped FIFO order'
$fifo.ElementCount = 2
Assert-Throws { Get-FifoIndices $fifo 4 } 'Inconsistent count'
$fifo.IndexIn = 3; $fifo.ElementCount = 0; $fifo.BufferEmpty = $true; $fifo.BufferFull = $false
Assert-Equal 0 @(Get-FifoIndices $fifo 4).Count 'Empty FIFO'

$capture = [pscustomobject]@{ Format = 'tc3-engineering-capture/1'; Target = 'offline'; Port = 851
    Name = 'Offline'; SymbolVersion = 7; Status = [pscustomobject]@{ SequenceId = 2; DeletedSequenceId = 0 }
    Events = @([pscustomobject]@{ Raw = 'AQ=='; Value = [pscustomobject]@{ SequenceId = 1 } },
        [pscustomobject]@{ Raw = 'Ag=='; Value = [pscustomobject]@{ SequenceId = 2 } }) }
$current = $capture | ConvertTo-Json -Depth 10 | ConvertFrom-Json
Assert-Acknowledgement $capture $current 2
Assert-Throws { Assert-Acknowledgement $capture $current 3 } 'Unarchived watermark'
$current.Events[0].Raw = 'Aw=='
Assert-Throws { Assert-Acknowledgement $capture $current 2 } 'Changed event bytes'
$current.Events[0].Raw = 'AQ=='
$current.Status.DeletedSequenceId = 1
Assert-Throws { Assert-Acknowledgement $capture $current 2 } 'Competing consumer'

if ($CapturePath) {
    $saved = Get-Content -Raw -LiteralPath $CapturePath | ConvertFrom-Json
    $indices = @(Get-FifoIndices $saved.Fifo $saved.Fifo.BufferLength)
    Assert-Equal $indices.Count @($saved.Events).Count 'Saved capture count'
    if ($indices.Count -eq 0) { throw 'Choose a nonempty saved capture for fixture validation.' }
    for ($i = 0; $i -lt $indices.Count; $i++) {
        $event = $saved.Events[$i]
        Assert-Equal $indices[$i] $event.Index 'Saved FIFO order'
        Assert-Equal $event.Value.SequenceId (ConvertFrom-AdsScalar UDINT ([Convert]::FromBase64String($event.Raw))) 'Saved raw sequence'
        if ($event.Value.Timestamp -isnot [string]) { throw 'Saved timestamp lost its decimal-string representation.' }
        [void][long]::Parse($event.Value.Timestamp, [Globalization.CultureInfo]::InvariantCulture)
    }
    $savedCurrent = $saved | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $savedWatermark = [uint32]$saved.Events[-1].Value.SequenceId
    Assert-Acknowledgement $saved $savedCurrent $savedWatermark
    $savedCurrent.Events[0].Raw = 'changed'
    Assert-Throws { Assert-Acknowledgement $saved $savedCurrent $savedWatermark } 'Changed saved prefix'
    Write-Output "Saved capture helper checks passed: $($indices.Count) events; no runtime connection."
}

# No client is instantiated here. Assembly loading/reflection only, explicitly optional.
if ($CheckInstalledDependencies) {
    $dependency = Import-LocalAdsAssembly
    if ($null -eq [TwinCAT.Ads.TcAdsClient].GetMethod('ReadSymbolInfo', [type[]]@([string]))) { throw 'Missing symbol API.' }
    if ($null -eq [TwinCAT.Ads.TcAdsClient].GetMethod('Connect', [type[]]@([string], [int]))) { throw 'Missing explicit-target connection API.' }
    foreach ($name in 'TypeName', 'ByteSize', 'IndexGroup', 'IndexOffset', 'IsBitType', 'IsPointer',
        'IsReference', 'IsTcComInterfacePointer', 'IsReadOnly') {
        $returnedType = [TwinCAT.Ads.TcAdsClient].Assembly.GetType('TwinCAT.Ads.Internal.TcAdsSymbol')
        if ($null -eq $returnedType -or $null -eq $returnedType.GetProperty($name)) { throw "Missing returned symbol property: $name" }
    }
    foreach ($name in 'ServerNetID', 'Timeout') {
        if ($null -eq [TwinCAT.Ads.TcAdsClient].GetProperty($name)) { throw "Missing client property: $name" }
    }
    Write-Output "Offline ADS dependency check passed: $($dependency.Version)"
}

if ($CheckLocalInstance) {
    $target = Get-DefaultUsermodeTarget
    Write-Output "Offline instance resolution: $($target.RuntimeName) -> $($target.NetId). Configuration only; not a runtime identity check."
}

# The public entry point must reject missing runtime permission before any ADS setup.
Assert-Throws { & (Join-Path $PSScriptRoot 'ads.ps1') -Operation Inspect } 'Runtime gate'
Write-Output 'Offline implementation checks passed; no ADS client or runtime connection created.'
