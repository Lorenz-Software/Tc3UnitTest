// Exercise cross-file version consistency with isolated saved-source fixtures.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const repo = path.resolve(__dirname, '../../..');
const fixture = path.join(repo, 'artifacts/documentation/metadata-check');
fs.mkdirSync(path.join(fixture, 'plc'), { recursive:true });
const program = path.join(repo, 'artifacts/documentation/compiler/bin/Release/net9.0/TwinCatDocumentation.dll');
const template = path.join(repo, 'tools/documentation/generator/assets/default-template');
const original = JSON.parse(fs.readFileSync(path.join(repo, 'tools/documentation/projects/tc3-unittest/sample.json'), 'utf8'));
const project = '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><PropertyGroup><Company>Example Publisher</Company><Title>ExampleLibrary</Title><ProjectVersion>4.5.6.0</ProjectVersion><DefaultNamespace>Example</DefaultNamespace></PropertyGroup></Project>';
const xml = (name, declaration, parameter=false) => `<TcPlcObject><GVL Name="${name}" ParameterList="${parameter}"><Declaration><![CDATA[${declaration}]]></Declaration></GVL></TcPlcObject>`;
const generated = xml('Global_Version', "VAR_GLOBAL CONSTANT stLibVersion_Example : ST_LibVersion := (iMajor := 4, iMinor := 5, iBuild := 6, iRevision := 0, nFlags := 0, sVersion := '4.5.6.0'); END_VAR");
const constants = xml('Constants', "VAR_GLOBAL CONSTANT VersionLength : UINT := 10; Direct : STRING(VersionLength) := '7.8.9'; Stream : STRING(VersionLength) := '2.3.4'; END_VAR");
const parameters = xml('Limits', '/// Fixture parameters.\nVAR_GLOBAL CONSTANT /// Maximum samples.\nSamples : UINT := 12; END_VAR', true);
const files = { 'plc/library.plcproj':project, 'plc/Global_Version.TcGVL':generated, 'plc/Constants.TcGVL':constants,
  'plc/Limits.TcGVL':parameters, 'direct.md':'- Contract version: `7.8.9`\r\n', 'stream.md':'- Contract version: `2.3.4`\r\n', 'LICENSE':'Fixture only.', 'project.css':':root {}' };
const config = {...original, sourceRoot:'plc', includeTypes:['Constants','Limits'], product:'Fixture',
  stylesheet:'project.css', attribution:{...original.attribution, licenseFile:'LICENSE',logoFile:null,headerLogoFile:null},
  groups:[{title:'Configuration',description:'Fixture',types:['Constants','Limits']}], guide:null,
  library:{projectFile:'plc/library.plcproj',generatedVersionFile:'plc/Global_Version.TcGVL',generatedVersionSymbol:'stLibVersion_Example',
    contracts:[{title:'Direct',file:'direct.md',constantsFile:'plc/Constants.TcGVL',constant:'Direct'},
      {title:'Stream',file:'stream.md',constantsFile:'plc/Constants.TcGVL',constant:'Stream'}]} };
function reset() {
  for (const [name, text] of Object.entries(files)) fs.writeFileSync(path.join(fixture,name),text);
  fs.writeFileSync(path.join(fixture,'help.json'), JSON.stringify(config));
}
function run() { return spawnSync('dotnet',[program,fixture,path.join(fixture,'output'),path.join(fixture,'help.json'),template],{encoding:'utf8'}); }
reset();
let result=run(); assert.equal(result.status,0,result.stderr);
const evidence=JSON.parse(fs.readFileSync(path.join(fixture,'output/help-build.json'),'utf8'));
assert.equal(evidence.library.Version,'4.5.6.0');
assert.equal(evidence.library.FrameworkVersion,'4.5.6');
assert.deepEqual(evidence.library.Contracts.map(c=>c.Version),['7.8.9','2.3.4']);
assert.equal(evidence.source.Commit,null,'Nested fixture must not inherit the parent repository identity');
const rejected = [
  ['plc/library.plcproj', project.replace('4.5.6.0','4.5.7.0'), /Generated library version differs/],
  ['plc/Global_Version.TcGVL', generated.replace('iMinor := 5','iMinor := 6'), /Generated library version differs/],
  ['plc/Global_Version.TcGVL', generated.replace("sVersion := '4.5.6.0'","sVersion := '4.5.7.0'"), /Generated library version differs/],
  ['direct.md','- Contract version: `7.8.8`\r\n',/Contract version differs/],
  ['stream.md','- Contract version: `2.3.5`\r\n',/Contract version differs/],
  ['plc/Constants.TcGVL',constants.replace('VersionLength : UINT := 10','VersionLength : UINT := 4'),/exceeds its declared PLC capacity/],
  ['plc/library.plcproj',project.replace('<ProjectVersion>','<ProjectVersion Condition="test">'),/Conditional library identity/],
  ['plc/library.plcproj',project.replace('4.5.6.0','$(LibraryVersion)'),/unconditional literal project property/]
];
for (const [file, text, expected] of rejected) {
  reset(); fs.writeFileSync(path.join(fixture,file),text); result=run();
  assert.equal(result.status,1,'Inconsistent inputs must fail: '+file); assert.match(result.stderr,expected);
}
reset(); const conflict={...config,libraryNamespace:'WrongNamespace'};
fs.writeFileSync(path.join(fixture,'help.json'),JSON.stringify(conflict)); result=run();
assert.equal(result.status,1); assert.match(result.stderr,/Configured namespace differs/);
reset();
console.log('PASS: source-derived identity, independent contract versions, snapshot evidence and nine mismatch cases.');
