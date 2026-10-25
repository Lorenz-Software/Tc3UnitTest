$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/BuildInputs.psm1" -Force -DisableNameChecking
$checks=0
function Check([bool]$Ok,[string]$Why){if(-not $Ok){throw $Why};$script:checks++}
function Reject([scriptblock]$Action){$rejected=$false;try{& $Action | Out-Null}catch{$rejected=$true};Check $rejected 'Unsafe documentation was accepted'}
$decl=@'
(*!<summary>Use &lt;bound&gt; and <c>Count</c>.</summary><description>Long usage.</description>
<param name="Value">Borrowed input.</param>*)
FUNCTION_BLOCK Fixture
VAR_INPUT
    // SA0033: Retained API.
    {attribute 'analysis' := '-33'}
    Value : STRING := '//! $' (*! literal *)'; //! Actual meaning.
END_VAR
'@
$projected=[Tc3UnitTest.Build.NativeDocumentation]::Declaration($decl)
Check ($projected.Contains('Use <bound> and Count.')) 'XML text/inline code not rendered'
Check ($projected.Contains('Value: Borrowed input.')) 'Named parameter meaning lost'
Check (-not $projected.Contains('SA0033:')) 'Maintenance rationale leaked into native documentation'
Check ($projected.Contains('Value : STRING := ''//! $'' (*! literal *)''; // Actual meaning.')) 'Quoted source was changed'
Check ($projected.Contains("{attribute 'analysis' := '-33'}")) 'Analysis exception changed'
Check ([Tc3UnitTest.Build.NativeDocumentation]::Declaration('A(* nested (* ordinary *) *)B') -eq 'A(* nested (* ordinary *) *)B') 'Ordinary nested comments changed'
Reject {[Tc3UnitTest.Build.NativeDocumentation]::Declaration('(*!<summary>Bad <unknown>markup</unknown>.</summary>*)')}
Reject {[Tc3UnitTest.Build.NativeDocumentation]::Declaration('(*!<summary>Unsafe *&#41; text.</summary>*)')}
Reject {[Tc3UnitTest.Build.NativeDocumentation]::Declaration("X : STRING := 'unterminated")}
$xml='<TcPlcObject Version="1"><POU Name="Fixture" Id="{id}"><Declaration><![CDATA['+$decl+']]></Declaration><Implementation><ST><![CDATA[X := ''//! literal''; // untouched implementation]]></ST></Implementation></POU></TcPlcObject>'
$result=[Tc3UnitTest.Build.NativeDocumentation]::Project($xml)
Check ($result.CodeHash -eq [Tc3UnitTest.Build.NativeDocumentation]::CodeHash($xml)) 'Code equivalence proof failed'
Check ($result.CodeHash -eq [Tc3UnitTest.Build.NativeDocumentation]::CodeHash($result.Content)) 'Read-back code differs'
Check ($result.CodeHash -ne [Tc3UnitTest.Build.NativeDocumentation]::CodeHash($result.Content.Replace('X :=','Y :='))) 'Implementation change went undetected'
Check ($result.CodeHash -ne [Tc3UnitTest.Build.NativeDocumentation]::CodeHash($result.Content.Replace("'-33'","'-34'"))) 'Attribute change went undetected'
Check ($result.CodeHash -ne [Tc3UnitTest.Build.NativeDocumentation]::CodeHash($result.Content.Replace('FUNCTION_BLOCK Fixture','FUNCTION_BLOCK Fix ture'))) 'Token-boundary change went undetected'
Check ($result.Content.Contains("X := '//! literal'; // untouched implementation")) 'Implementation rewritten'
# Real Framework corpus; fail on unsupported syntax instead of silently dropping prose.
$repo=(Resolve-Path "$PSScriptRoot/../..").Path
$inputs=Get-LibraryInputs (Join-Path $repo 'projects/Tc3UnitTest.4026/Tc3UnitTest/Tc3UnitTest.plcproj')
foreach($source in $inputs.Framework){
 if($source.Relative -eq $inputs.Generated.Relative){continue}
 $projection=[Tc3UnitTest.Build.NativeDocumentation]::Project([IO.File]::ReadAllText($source.Path))
 Check ($projection.CodeHash -eq [Tc3UnitTest.Build.NativeDocumentation]::CodeHash([IO.File]::ReadAllText($source.Path))) ('Real source: '+$source.Relative)
}
Write-Output "PASS: $checks native documentation checks; real Framework code unchanged."
