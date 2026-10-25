# Independently reconcile the real project's XML Declaration nodes with the lexical ledger.
param()
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$project=Join-Path $repo 'projects/Tc3UnitTest.4026/Tc3UnitTest/Tc3UnitTest.plcproj'
$projectRoot=Split-Path -Parent $project
$output=Join-Path $repo 'artifacts/documentation/project-inventory'
$rows=Get-Content -Raw (Join-Path $output 'items.json') | ConvertFrom-Json
$byPath=$rows | Group-Object Path -AsHashTable -CaseSensitive
$identities=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($row in $rows) { if (-not $identities.Add($row.Id)) { throw 'Duplicate review identities.' } }
$files=Get-Content -Raw (Join-Path $output 'files.json') | ConvertFrom-Json
$hashes=Get-Content -Raw (Join-Path $output 'input-hashes.json') | ConvertFrom-Json
$xml=[xml](Get-Content -Raw $project)
$compile=@($xml.SelectNodes('//*[local-name()="Compile"][@Include]'))
if ($compile.Count -ne $files.Count) { throw 'Compile/file ledger count differs.' }
$declarations=0
foreach($entry in $compile) {
    $source=[IO.Path]::GetFullPath((Join-Path $projectRoot $entry.Include))
    if ([IO.Path]::GetExtension($source) -notin @('.TcPOU','.TcDUT','.TcIO','.TcGVL')) { continue }
    $relative=[IO.Path]::GetRelativePath($repo,$source).Replace('\','/')
    $saved=[xml](Get-Content -Raw $source)
    $expected=@($saved.SelectNodes('//*[local-name()="Declaration"]'))
    $actual=@($byPath[$relative] | Where-Object { $_.Kind -in @('POU','DUT','GVL','Itf','Method','Property','Get','Set','Action','Transition') })
    if ($expected.Count -ne $actual.Count) { throw "Declaration ledger gap: $relative" }
    $declarations+=$expected.Count
}
foreach($inputHash in $hashes.PSObject.Properties) {
    if ($inputHash.Name.StartsWith('scope/')) { $source=Join-Path $repo 'tools/documentation/projects/tc3-unittest/inventory.json' }
    else { $source=Join-Path $repo $inputHash.Name }
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne $inputHash.Value) { throw "Stale inventory input: $($inputHash.Name)" }
}
foreach($row in $rows) {
    if ($row.Parent -and -not $identities.Contains($row.Parent)) { throw "Missing parent: $($row.Id)" }
    if (@($row.Review.PSObject.Properties | Where-Object Value -ne Open).Count) { throw 'Fresh inventory must not imply acceptance.' }
}
"PASS: $($compile.Count) Compile entries, $declarations XML declarations, unique identities, parent references and all input hashes independently reconciled."
