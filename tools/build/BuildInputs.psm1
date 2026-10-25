Set-StrictMode -Version Latest
if (-not ('Tc3UnitTest.Build.NativeDocumentation' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'NativeDocumentation.cs') -ReferencedAssemblies @('System.dll','System.Xml.dll')
}

function Get-ConfinedFile {
    param([string]$Root, [string]$Relative)
    if ([IO.Path]::IsPathRooted($Relative)) { throw "Expected relative input path: $Relative" }
    $path = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not $path.StartsWith($Root.TrimEnd('\')+'\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Input escapes its source boundary: $Relative"
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing input: $path" }
    return $path
}

function Assert-LibraryVersion {
    param([string]$Text,$Identity)
    $symbol = 'stLibVersion_' + $Identity.Title
    if ($Text -notmatch ([regex]::Escape($symbol)+'\s*:\s*ST_LibVersion\s*:=\s*\(\s*iMajor\s*:=\s*(\d+)\s*,\s*iMinor\s*:=\s*(\d+)\s*,\s*iBuild\s*:=\s*(\d+)\s*,\s*iRevision\s*:=\s*(\d+)\s*,\s*(?:nFlags\s*:=\s*0\s*,\s*)?sVersion\s*:=\s*''([^'']+)''\s*\)')) {
        throw 'Unsupported generated library version declaration.'
    }
    if (($Matches[1..4] -join '.') -ne $Identity.ProjectVersion -or $Matches[5] -ne $Identity.ProjectVersion) {
        throw 'Generated version differs from saved ProjectVersion; regenerate/save it in XAE first.'
    }
}

function Get-LibraryInputs {
    param([string]$ProjectPath)
    $projectFile = (Resolve-Path -LiteralPath $ProjectPath).Path
    $root = Split-Path $projectFile
    [xml]$xml = Get-Content -LiteralPath $projectFile -Raw -Encoding UTF8
    $ns = [Xml.XmlNamespaceManager]::new($xml.NameTable)
    $ns.AddNamespace('p', $xml.DocumentElement.NamespaceURI)
    $identity = [ordered]@{}
    foreach ($name in @('Company','Title','ProjectVersion','DefaultNamespace')) {
        $values = @($xml.SelectNodes("//p:PropertyGroup/p:$name", $ns))
        if ($values.Count -ne 1 -or $values[0].HasAttribute('Condition') -or
            $values[0].ParentNode.HasAttribute('Condition') -or
            $values[0].InnerText -match '\$\(' -or [string]::IsNullOrWhiteSpace($values[0].InnerText)) {
            throw "Expected one unconditional literal project property: $name"
        }
        $identity[$name] = $values[0].InnerText.Trim()
    }
    if ($identity.ProjectVersion -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$' -or
        @($identity.ProjectVersion.Split('.') | Where-Object { [long]$_ -gt 65535 }).Count) {
        throw 'ProjectVersion must contain four unsigned 16-bit components.'
    }
    if ($identity.Title -match '[<>:"/\\|?*]' -or $identity.Title -match '\.$') { throw 'Library title is not a valid artifact basename.' }

    $sources = @()
    $seen = @{}
    foreach ($entry in $xml.SelectNodes('//p:Compile', $ns)) {
        $relative = $entry.GetAttribute('Include').Replace('/','\')
        if ($entry.HasAttribute('Condition') -or $entry.ParentNode.HasAttribute('Condition')) { throw "Conditional Compile input: $relative" }
        if ($relative -notmatch '^(Framework|SelfTests|Runtime)\\') { throw "Unclassified Compile input: $relative" }
        $file = Get-ConfinedFile $root $relative
        $areaRoot=Join-Path $root ($relative.Split('\')[0])
        if(-not $file.StartsWith($areaRoot+'\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Compile input escapes its declared area: $relative"
        }
        if ($seen.ContainsKey($file)) { throw "Duplicate Compile input: $relative" }
        $seen[$file] = $true
        $isFramework = $relative.StartsWith('Framework\', [StringComparison]::OrdinalIgnoreCase)
        if ($isFramework -and [IO.Path]::GetExtension($relative) -notin @('.TcPOU','.TcDUT','.TcIO','.TcGVL')) {
            throw "Unsupported library object: $relative"
        }
        $sources += [pscustomobject]@{ Relative=$relative; Path=$file; Framework=$isFramework; Hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash }
    }
    $framework = @($sources | Where-Object Framework)
    if ($framework.Count -eq 0) { throw 'Framework Compile inventory is empty.' }
    $generated = @($framework | Where-Object { (Get-Content -LiteralPath $_.Path -Raw -Encoding UTF8) -match "attribute 'TcGenerated'" })
    if ($generated.Count -ne 1 -or $generated[0].Relative -notmatch '\\Global_Version\.TcGVL$') {
        throw 'Expected exactly one generated Framework version declaration.'
    }
    $versionText = Get-Content -LiteralPath $generated[0].Path -Raw -Encoding UTF8
    Assert-LibraryVersion $versionText ([pscustomobject]$identity)
    return [pscustomobject]@{
        ProjectPath=$projectFile; Root=$root; Xml=$xml; Namespace=$ns
        Identity=[pscustomobject]$identity; Sources=$sources; Framework=$framework; Generated=$generated[0]
        NativeDocumentation=@{}
    }
}

function Copy-BuildSnapshot {
    param([string]$RepositoryRoot, [string]$SolutionPath, [string]$TwinCatProjectPath, $Inputs, [string]$Destination)
    # Copy declared source/project files only, never caches, boot files or local engineering state.
    $SolutionPath=(Resolve-Path -LiteralPath $SolutionPath).Path
    $TwinCatProjectPath=(Resolve-Path -LiteralPath $TwinCatProjectPath).Path
    $solutionRoot = Split-Path $SolutionPath
    $files = @($SolutionPath,$TwinCatProjectPath,$Inputs.ProjectPath) + @($Inputs.Sources | ForEach-Object Path)
    foreach ($file in $files) {
        if (-not $file.StartsWith($solutionRoot+'\', [StringComparison]::OrdinalIgnoreCase)) { throw "Snapshot input outside solution directory: $file" }
        $target = Join-Path $Destination $file.Substring($solutionRoot.Length+1)
        New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
        Copy-Item -LiteralPath $file -Destination $target
    }
    return Join-Path $Destination (Split-Path $SolutionPath -Leaf)
}

function Set-XmlProperty {
    param([xml]$Xml, [string]$Name, [string]$Value)
    $ns = [Xml.XmlNamespaceManager]::new($Xml.NameTable)
    $ns.AddNamespace('p', $Xml.DocumentElement.NamespaceURI)
    $nodes = @($Xml.SelectNodes("//p:PropertyGroup/p:$Name", $ns))
    foreach ($node in $nodes) { [void]$node.ParentNode.RemoveChild($node) }
    $group = $Xml.SelectSingleNode('/p:Project/p:PropertyGroup', $ns)
    $element = $Xml.CreateElement($Name, $Xml.DocumentElement.NamespaceURI)
    $element.InnerText = $Value
    [void]$group.AppendChild($element)
}

function Set-PackagingInputs {
    param([string]$ProjectPath, $Inputs, $Lock)
    [xml]$xml = Get-Content -LiteralPath $ProjectPath -Raw -Encoding UTF8
    $ns = [Xml.XmlNamespaceManager]::new($xml.NameTable)
    $ns.AddNamespace('p', $xml.DocumentElement.NamespaceURI)
    # Start from a native Empty PLC Project, preserving its generated identity.
    foreach ($element in @($xml.SelectNodes('//p:Compile|//p:Folder|//p:ProjectExtensions', $ns))) {
        [void]$element.ParentNode.RemoveChild($element)
    }
    foreach ($property in $Inputs.Identity.PSObject.Properties) { Set-XmlProperty $xml $property.Name $property.Value }
    Set-XmlProperty $xml 'GlobalVersionStructureIncluded' 'true'
    $group = $xml.CreateElement('ItemGroup', $xml.DocumentElement.NamespaceURI)
    [void]$xml.DocumentElement.AppendChild($group)
    $root = Split-Path $ProjectPath
    foreach ($source in $Inputs.Framework) {
        if ($source.Relative -eq $Inputs.Generated.Relative) { continue }
        $target = Join-Path $root $source.Relative
        New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
        if ((Get-FileHash -LiteralPath $source.Path).Hash -ne $source.Hash) { throw "Source changed before projection: $($source.Relative)" }
        $projection=[Tc3UnitTest.Build.NativeDocumentation]::Project([IO.File]::ReadAllText($source.Path))
        [IO.File]::WriteAllText($target,$projection.Content,[Text.UTF8Encoding]::new($false))
        $Inputs.NativeDocumentation[$source.Relative]=[pscustomobject]@{
            Relative=$source.Relative;SourceSha256=$source.Hash
            PackagedSha256=(Get-FileHash -LiteralPath $target).Hash;CodeSha256=$projection.CodeHash
        }
        $compile = $xml.CreateElement('Compile', $xml.DocumentElement.NamespaceURI)
        $compile.SetAttribute('Include', $source.Relative)
        $subtype = $xml.CreateElement('SubType', $xml.DocumentElement.NamespaceURI)
        $subtype.InnerText = 'Code'
        [void]$compile.AppendChild($subtype)
        [void]$group.AppendChild($compile)
    }
    foreach ($node in $Inputs.Xml.SelectNodes('//p:PlaceholderReference|//p:PlaceholderResolution', $Inputs.Namespace)) {
        # Replace declared entries, retaining native template system references.
        foreach($existing in @($xml.SelectNodes('//p:'+ $node.LocalName,$ns))) {
            if($existing.GetAttribute('Include') -eq $node.GetAttribute('Include')) {
                [void]$existing.ParentNode.RemoveChild($existing)
            }
        }
        [void]$group.AppendChild($xml.ImportNode($node,$true))
    }
    if($Lock) {
        foreach($name in $Lock.Declared.Keys) {
            foreach($existing in @($xml.SelectNodes('//p:PlaceholderResolution',$ns))) {
                if($existing.GetAttribute('Include') -eq $name) { [void]$existing.ParentNode.RemoveChild($existing) }
            }
            $resolution=$xml.CreateElement('PlaceholderResolution',$xml.DocumentElement.NamespaceURI)
            $resolution.SetAttribute('Include',$name)
            $value=$xml.CreateElement('Resolution',$xml.DocumentElement.NamespaceURI)
            $value.InnerText="$name, $($Lock.Declared[$name]) ($($Lock.Company))"
            [void]$resolution.AppendChild($value)
            [void]$group.AppendChild($resolution)
        }
    }
    $extensions = $Inputs.Xml.SelectSingleNode('/p:Project/p:ProjectExtensions', $Inputs.Namespace)
    if ($null -ne $extensions) { [void]$xml.DocumentElement.AppendChild($xml.ImportNode($extensions,$true)) }
    $xml.Save($ProjectPath)
}

function Assert-PackagingInputs {
    param([string]$ProjectPath, $Inputs)
    [xml]$xml=Get-Content -LiteralPath $ProjectPath -Raw -Encoding UTF8
    $ns=[Xml.XmlNamespaceManager]::new($xml.NameTable)
    $ns.AddNamespace('p',$xml.DocumentElement.NamespaceURI)
    foreach($property in $Inputs.Identity.PSObject.Properties) {
        $actual=@($xml.SelectNodes("//p:PropertyGroup/p:$($property.Name)",$ns))
        if($actual.Count -ne 1 -or $actual[0].InnerText -ne $property.Value) { throw "Saved packaging metadata mismatch: $($property.Name)" }
    }
    $ordinary=@($xml.SelectNodes('//p:Compile',$ns) | Where-Object { $_.GetAttribute('Include') -notmatch '(^|[\\/])Global_Version\.TcGVL$' })
    $expected=@($Inputs.Framework | Where-Object { $_.Relative -ne $Inputs.Generated.Relative })
    if($ordinary.Count -ne $expected.Count) { throw 'Saved library object inventory count differs from approved Framework inputs.' }
    foreach($compile in $ordinary) {
        $relative=$compile.GetAttribute('Include').Replace('/','\')
        $source=@($expected | Where-Object Relative -EQ $relative)
        if($source.Count -ne 1) { throw "Unexpected packaged source: $relative" }
        $path=Get-ConfinedFile (Split-Path $ProjectPath) $relative
        $projection=$Inputs.NativeDocumentation[$relative]
        if(-not $projection -or $projection.SourceSha256 -ne $source[0].Hash) { throw "Missing native documentation provenance: $relative" }
        if((Get-FileHash -LiteralPath $path).Hash -ne $projection.PackagedSha256) { throw "Packaged source differs from captured input projection: $relative" }
        if([Tc3UnitTest.Build.NativeDocumentation]::CodeHash([IO.File]::ReadAllText($path)) -ne $projection.CodeSha256) {
            throw "Packaged non-comment code differs: $relative"
        }
    }
    $generated=@($xml.SelectNodes('//p:Compile',$ns) | Where-Object { $_.GetAttribute('Include') -match '(^|[\\/])Global_Version\.TcGVL$' })
    if($generated.Count -ne 1) { throw 'Native-generated version is missing or duplicated.' }
    $generatedPath=Get-ConfinedFile (Split-Path $ProjectPath) $generated[0].GetAttribute('Include')
    $content=Get-Content -LiteralPath $generatedPath -Raw -Encoding UTF8
    Assert-LibraryVersion $content $Inputs.Identity
}

Export-ModuleMember -Function Get-LibraryInputs,Copy-BuildSnapshot,Set-PackagingInputs,Assert-PackagingInputs,Get-ConfinedFile
