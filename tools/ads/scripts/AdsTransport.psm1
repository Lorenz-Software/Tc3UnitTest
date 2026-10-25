Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-UsermodeRegistry {
    param([string]$Content, [string]$ExpectedTargetNetId)

    $settings = New-Object Xml.XmlReaderSettings
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.CloseInput = $true
    $reader = [Xml.XmlReader]::Create((New-Object IO.StringReader($Content)), $settings)
    $registry = New-Object Xml.XmlDocument
    $registry.XmlResolver = $null
    try { $registry.Load($reader) } finally { $reader.Dispose() }
    $values = $registry.SelectNodes('/TcRegistry/Key[@Name="HKLM"]/Key[@Name="Software"]/Key[@Name="Beckhoff"]/Key[@Name="TwinCAT3"]/Key[@Name="System"]/Value[@Name="AmsNetId"]')
    if ($values.Count -ne 1 -or $values[0].GetAttribute('Type') -ne 'BIN') {
        throw 'UmRT_Default must contain exactly one binary System/AmsNetId.'
    }
    $hex = $values[0].InnerText.Trim()
    if ($hex -notmatch '\A[0-9a-fA-F]{12}\z') { throw 'UmRT_Default AmsNetId must contain six hexadecimal bytes.' }
    $octets = for ($i = 0; $i -lt 12; $i += 2) { [Convert]::ToByte($hex.Substring($i, 2), 16) }
    $netId = $octets -join '.'
    if ($netId -in '0.0.0.0.0.0', '127.0.0.1.1.1') { throw 'UmRT_Default requires a concrete Net ID, not a local alias.' }
    if ($ExpectedTargetNetId -and $netId -cne $ExpectedTargetNetId) {
        throw "UmRT_Default target $netId differs from the expected XAE target $ExpectedTargetNetId. No connection attempted."
    }
    return $netId
}

function Get-DefaultUsermodeTarget {
    param([string]$ExpectedTargetNetId)

    $registryPath = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'Beckhoff\TwinCAT\3.1\Runtimes\UmRT_Default\3.1\TcRegistry.xml'
    $content = [IO.File]::ReadAllText($registryPath)
    $netId = ConvertFrom-UsermodeRegistry $content $ExpectedTargetNetId
    [pscustomobject]@{ RuntimeName = 'UmRT_Default'; NetId = $netId; RegistryPath = $registryPath }
}

function Import-LocalAdsAssembly {
    param([string]$TwinCatRoot, [string]$AssemblyPath)

    if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess) {
        throw 'Use 64-bit Windows PowerShell 5.1 for the ADS 4.x transport.'
    }
    if (-not $TwinCatRoot) {
        $TwinCatRoot = Join-Path ${env:ProgramFiles(x86)} 'Beckhoff\TwinCAT'
    }
    $nativeDirectory = Join-Path $TwinCatRoot 'Common64'
    if (-not (Test-Path -LiteralPath (Join-Path $nativeDirectory 'TcAdsDll.dll'))) {
        throw 'ADS x64 native dependency missing. Supply -TwinCatRoot; no installation is attempted.'
    }
    if (-not $AssemblyPath) {
        $assemblyDirectory = Join-Path $TwinCatRoot '3.1\Components\Plc\LacBinaries\GAC_MSIL\TwinCAT.Ads'
        $candidates = @(Get-ChildItem -LiteralPath $assemblyDirectory -Filter TwinCAT.Ads.dll -Recurse |
            Where-Object { [Reflection.AssemblyName]::GetAssemblyName($_.FullName).Version.Major -eq 4 } |
            Sort-Object { [Reflection.AssemblyName]::GetAssemblyName($_.FullName).Version } -Descending)
        if ($candidates.Count -eq 0) { throw 'ADS 4.x assembly missing. Supply -AssemblyPath.' }
        $AssemblyPath = $candidates[0].FullName
    }
    $AssemblyPath = (Resolve-Path -LiteralPath $AssemblyPath).ProviderPath
    $identity = [Reflection.AssemblyName]::GetAssemblyName($AssemblyPath)
    if ($identity.Name -ne 'TwinCAT.Ads' -or $identity.Version.Major -ne 4) {
        throw 'This transport requires TwinCAT.Ads 4.x; other SDKs are not silently substituted.'
    }
    $loaded = @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'TwinCAT.Ads' })
    if ($loaded.Count -gt 0 -and $loaded[0].Location -ne $AssemblyPath) {
        throw 'Another ADS assembly is already loaded. Use a fresh Windows PowerShell process.'
    }
    Add-Type -Path $AssemblyPath
    [pscustomobject]@{ AssemblyPath = $AssemblyPath; Version = $identity.Version.ToString(); NativeDirectory = $nativeDirectory }
}

function Open-LocalAdsTransport {
    param(
        [Parameter(Mandatory)]$Dependencies,
        [ValidateRange(1, 65535)][int]$Port,
        [ValidateRange(100, 10000)][int]$IoTimeoutMs = 3000,
        [ValidateRange(1000, 300000)][int]$TimeoutMs = 30000,
        [string]$ExpectedTargetNetId
    )

    # Resolve only the standard local instance; never fall back to Connect(port).
    $target = Get-DefaultUsermodeTarget $ExpectedTargetNetId
    $oldPath = $env:PATH
    $env:PATH = $Dependencies.NativeDirectory + ';' + $oldPath
    $client = $null
    try {
        $client = New-Object TwinCAT.Ads.TcAdsClient
        $client.Timeout = $IoTimeoutMs
        $client.Connect([string]$target.NetId, $Port)
        if ($client.ServerNetID.ToString() -ne $target.NetId) { throw 'ADS connection target differs from the selected instance.' }
        $session = [pscustomobject]@{
            Client = $client; Port = $Port; Target = $client.ServerNetID.ToString()
            Instance = $target
            Clock = [Diagnostics.Stopwatch]::StartNew(); TimeoutMs = $TimeoutMs
            IoTimeoutMs = $IoTimeoutMs; OriginalPath = $oldPath; Dependencies = $Dependencies
        }
        return $session
    } catch {
        if ($null -ne $client) { $client.Dispose() }
        $env:PATH = $oldPath
        throw
    }
}

function Set-AdsCallDeadline {
    param($Session)
    $remaining = $Session.TimeoutMs - $Session.Clock.ElapsedMilliseconds
    if ($remaining -le 0) { throw 'ADS operation deadline exceeded; no command is retried.' }
    $Session.Client.Timeout = [int][Math]::Min($Session.IoTimeoutMs, $remaining)
}

function Read-AdsBytes {
    param($Session, [uint32]$Group, [uint32]$Offset, [ValidateRange(1, 16777216)][int]$Size)
    $bytes = New-Object byte[] $Size
    for ($position = 0; $position -lt $Size; $position += $length) {
        Set-AdsCallDeadline $Session
        $length = [Math]::Min(32768, $Size - $position)
        $read = $Session.Client.Read($Group, [uint32]($Offset + $position), $bytes, $position, $length)
        if ($read -ne $length) { throw "Incomplete ADS read: $read/$length bytes." }
    }
    return ,$bytes
}

function ConvertFrom-AdsSymbol {
    param([object]$Symbol, [string]$Name)
    if ($null -eq $Symbol) { throw "Missing runtime symbol: $Name" }
    # ADS 4.x can return DataType and Datatype on the same object. Bypass the
    # case-insensitive PowerShell adapter, including for GetType().
    $symbolType = [object].GetMethod('GetType').Invoke($Symbol, @())
    $values = @{}
    foreach ($propertyName in 'TypeName', 'ByteSize', 'IndexGroup', 'IndexOffset',
        'IsBitType', 'IsPointer', 'IsReference', 'IsTcComInterfacePointer', 'IsReadOnly') {
        $property = $symbolType.GetProperty($propertyName)
        if ($null -eq $property) { throw "Missing ADS symbol property: $propertyName" }
        $values[$propertyName] = $property.GetValue($Symbol, $null)
    }
    if ($values.IsBitType -or $values.IsPointer -or $values.IsReference -or $values.IsTcComInterfacePointer) {
        throw "Unsupported address-based or bit-packed symbol: $Name"
    }
    [pscustomobject]@{
        Name = $Name; Type = $values.TypeName; Size = [int]$values.ByteSize
        Group = [uint32]$values.IndexGroup; Offset = [uint32]$values.IndexOffset
        ReadOnly = [bool]$values.IsReadOnly
    }
}

function Get-AdsSymbol {
    param($Session, [string]$Name)
    Set-AdsCallDeadline $Session
    ConvertFrom-AdsSymbol -Symbol ($Session.Client.ReadSymbolInfo($Name)) -Name $Name
}

function Get-AdsSymbolVersion {
    param($Session)
    # ADSIGRP_SYM_VERSION is a one-byte symbol-table generation, not an epoch ID.
    $bytes = Read-AdsBytes $Session 0xF008 0 1
    return [int]$bytes[0]
}

function Get-AdsRuntimeState {
    param($Session)
    Set-AdsCallDeadline $Session
    $state = $Session.Client.ReadState()
    [pscustomobject]@{ AdsState = $state.AdsState.ToString(); DeviceState = [int]$state.DeviceState }
}

function Write-AdsCommandField {
    param($Session, $Field, $Value)
    # Resolve again before writing; only callers with an explicit contract command use this function.
    $current = Get-AdsSymbol $Session $Field.Name
    if ($current.Type -ne $Field.Type -or $current.Size -ne $Field.Size -or $current.ReadOnly) {
        throw "Command symbol changed or is read-only: $($Field.Name)"
    }
    Set-AdsCallDeadline $Session
    $handle = $Session.Client.CreateVariableHandle($Field.Name)
    try {
        Set-AdsCallDeadline $Session
        $Session.Client.WriteAny($handle, $Value)
    } finally {
        $Session.Client.DeleteVariableHandle($handle)
    }
}

function Set-AdsSystemMode {
    param($Session, [ValidateSet('Run', 'Config')][string]$Mode, [int]$DeviceState)
    if ($Session.Port -ne 10000) { throw 'System-mode commands require system service port 10000.' }
    Set-AdsCallDeadline $Session
    $request = New-Object TwinCAT.Ads.StateInfo
    $request.AdsState = if ($Mode -eq 'Run') { [TwinCAT.Ads.AdsState]::Reset } else { [TwinCAT.Ads.AdsState]::Reconfig }
    $request.DeviceState = $DeviceState
    $Session.Client.WriteControl($request)
}

function Close-LocalAdsTransport {
    param($Session)
    if ($null -eq $Session) { return }
    try { $Session.Client.Dispose() } finally { $env:PATH = $Session.OriginalPath }
}

Export-ModuleMember -Function Get-DefaultUsermodeTarget, Import-LocalAdsAssembly, Open-LocalAdsTransport, Read-AdsBytes,
    Get-AdsSymbol, Get-AdsSymbolVersion, Get-AdsRuntimeState, Write-AdsCommandField,
    Set-AdsSystemMode, Close-LocalAdsTransport
