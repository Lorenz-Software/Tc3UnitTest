// Exercise the source audit without the tolerant HTML extraction/rendering path.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const repo=path.resolve(__dirname,'../../..');
const root=path.join(repo,'artifacts/documentation/comment-audit-check');
const plc=path.join(root,'plc');
fs.mkdirSync(plc,{recursive:true});
const program=path.join(repo,'artifacts/documentation/compiler/bin/Release/net9.0/TwinCatDocumentation.dll');
const ledger=path.join(root,'inventory');
const output=path.join(root,'audit');
const policy=path.join(root,'policy.json');
fs.writeFileSync(policy,JSON.stringify({region:'Documentation',reviewedMarkup:['summary','description','param','c','code']}));
const decl=text=>`<Declaration><![CDATA[${text}]]></Declaration>`;
const wrap=(name,text)=>`<TcPlcObject><POU Name="${name}">${decl(text)}</POU></TcPlcObject>`;
const canonical=`{region 'Documentation'}
(*!
<summary>Fixture role.</summary>
<description>Usage detail.</description>
*)
{endregion}
FUNCTION_BLOCK Fixture
VAR_INPUT
 Value : INT; //! Input meaning.
END_VAR
VAR
 Internal : INT;
END_VAR`;
const generated='<TcPlcObject><GVL Name="Generated">'+decl("{attribute 'TcGenerated'}\nVAR_GLOBAL CONSTANT Version : UINT := 1; END_VAR")+'</GVL></TcPlcObject>';
const source=path.join(plc,'Fixture.TcPOU');
fs.writeFileSync(source,wrap('Fixture',canonical));
fs.writeFileSync(path.join(plc,'Generated.TcGVL'),generated);
fs.writeFileSync(path.join(plc,'Task.TcTTO'),'<TcPlcObject><Task Name="Task"/></TcPlcObject>');
const project=path.join(plc,'Fixture.plcproj');
fs.writeFileSync(project,'<Project><ItemGroup><Compile Include="Fixture.TcPOU"/><Compile Include="Generated.TcGVL"/><Compile Include="Task.TcTTO"/><PlaceholderReference Include="ExternalTypes"/></ItemGroup></Project>');
function invoke(...args) { return spawnSync('dotnet',[program,...args],{encoding:'utf8'}); }
function inventory() { const r=invoke('--inventory',root,project,ledger); assert.equal(r.status,0,r.stderr); }
function audit() { return invoke('--audit-comments',root,ledger,output,policy); }
function findings() { return JSON.parse(fs.readFileSync(path.join(output,'findings.json'),'utf8')); }
inventory(); let result=audit(); assert.equal(result.status,0,result.stderr); assert.deepEqual(findings(),[]);
const dispositions=JSON.parse(fs.readFileSync(path.join(output,'dispositions.json'),'utf8'));
assert(dispositions.some(d=>d.category==='Generated source'));
assert(dispositions.some(d=>d.category==='Library dependency'));
assert(dispositions.some(d=>d.category==='Task/project metadata'));
assert(dispositions.some(d=>d.category==='Local implementation element'));
const before=fs.readFileSync(source,'utf8');
fs.writeFileSync(source,wrap('Fixture',canonical.replace('Usage detail.','Reworded detail.')));
result=audit(); assert.notEqual(result.status,0); assert.match(result.stderr,/Stale review ledger/);
inventory(); result=audit(); assert.equal(result.status,0,result.stderr);
fs.writeFileSync(source,wrap('Fixture',canonical.replace("{region 'Documentation'}\n",'').replace('{endregion}\n','')));
inventory(); result=audit(); assert.notEqual(result.status,0);
assert(findings().some(f=>f.Code==='documentation-region'));
fs.writeFileSync(source,wrap('Fixture',canonical.replace('//! Input meaning.','// Input meaning.')));
inventory(); result=audit(); assert.notEqual(result.status,0);
assert(findings().some(f=>f.Code==='native-marker'));
fs.writeFileSync(source,wrap('Fixture',canonical.replace(' //! Input meaning.','')));
inventory(); result=audit(); assert.notEqual(result.status,0);
assert(findings().some(f=>f.Category==='Review' && f.Code==='element-description'));
fs.writeFileSync(source,before); inventory(); result=audit(); assert.equal(result.status,0,result.stderr);
assert.equal(fs.readFileSync(source,'utf8'),before,'The audit never rewrites sources');
console.log('PASS: independent source-format success/failure, stale evidence rejection, generated/metadata/local dispositions and source preservation.');
