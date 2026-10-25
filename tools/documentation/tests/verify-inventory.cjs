// Inventory evidence must cover saved declarations, preserve comments and reject scope gaps.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');
const repo = path.resolve(__dirname, '../../..');
const root = path.join(repo, 'artifacts/documentation/inventory-check');
const plc = path.join(root, 'plc');
fs.mkdirSync(plc, {recursive:true});
const program = path.join(repo, 'artifacts/documentation/compiler/bin/Release/net9.0/TwinCatDocumentation.dll');
const projectPath = path.join(plc, 'Fixture.plcproj');
const output = path.join(root, 'output');
const cdata = text => `<Declaration><![CDATA[${text}]]></Declaration>`;
const object = (kind, name, text, children='') => `<TcPlcObject><${kind} Name="${name}">${cdata(text)}${children}</${kind}></TcPlcObject>`;
const files = {
  'Kinds.TcPOU': object('POU','Kinds', `//! <summary>Fixture.</summary>
FUNCTION_BLOCK Kinds
VAR_INPUT
    A, B : STRING(40) := 'value; // text'; //! Shared input description.
    // Leading description for C.
    C : ARRAY[0..1] OF INT := [1, 2];
    D : BOOL;
END_VAR
VAR
    {attribute 'hide'}
    Local : INT; // Local note.
END_VAR`, `<Method Name="Calculate">${cdata(`//! <summary>Calculate.</summary>
//! <param name="Input">Explicit parameter text.</param>
METHOD PUBLIC Calculate : INT
VAR_INPUT
 Input : INT; //! Native input.
END_VAR`)}</Method><Property Name="Value">${cdata('PROPERTY PUBLIC Value : INT')}<Get Name="Get">${cdata('VAR END_VAR')}</Get><Set Name="Set">${cdata('VAR END_VAR')}</Set></Property>`),
  'Choice.TcDUT': object('DUT','Choice', `TYPE Choice : (
 First := 0, //! First item.
 Second := 1 //! Final item without comma.
); END_TYPE`),
  'Record.TcDUT': object('DUT','Record', `TYPE Record : STRUCT
 Payload : STRING(40) := '(* text; *)'; //! Payload description.
 Other : INT;
END_STRUCT END_TYPE`),
  'Overlay.TcDUT': object('DUT','Overlay', 'TYPE Overlay : UNION Word : DWORD; Bytes : ARRAY[0..3] OF BYTE; END_UNION END_TYPE'),
  'Alias.TcDUT': object('DUT','Alias','TYPE Alias : ARRAY[0..3] OF BYTE; END_TYPE'),
  'Settings.TcGVL': '<TcPlcObject><GVL Name="Settings" ParameterList="True">'+cdata("VAR_GLOBAL CONSTANT Limit : UINT := 4; END_VAR")+'</GVL></TcPlcObject>',
  'Task.TcTTO': '<TcPlcObject><Task Name="Task"/></TcPlcObject>'
};
for (const [name,text] of Object.entries(files)) fs.writeFileSync(path.join(plc,name),text);
const project = (entries=Object.keys(files)) => '<Project><ItemGroup>'+entries.map(name=>`<Compile Include="${name}"/>`).join('')+'</ItemGroup></Project>';
function run() { return spawnSync('dotnet',[program,'--inventory',root,projectPath,output],{encoding:'utf8'}); }
fs.writeFileSync(projectPath, project());
let result=run(); assert.equal(result.status,0,result.stderr);
const read = () => JSON.parse(fs.readFileSync(path.join(output,'items.json'),'utf8'));
const rows=read();
const row = name => { const found=rows.filter(r=>r.QualifiedName===name); assert.equal(found.length,1,name); return found[0]; };
assert.equal(rows.length,27,'Independently enumerated: 10 declarations, 15 elements, task and project metadata');
assert.deepEqual(rows.map(r=>r.QualifiedName).sort(), [
  'Kinds','Kinds.A','Kinds.B','Kinds.C','Kinds.D','Kinds.Local',
  'Kinds.Calculate','Kinds.Calculate.Input','Kinds.Calculate.$return',
  'Kinds.Value','Kinds.Value.$value','Kinds.Value.Get','Kinds.Value.Set',
  'Choice','Choice.First','Choice.Second','Record','Record.Payload','Record.Other',
  'Overlay','Overlay.Word','Overlay.Bytes','Alias','Settings','Settings.Limit','Task','Fixture.plcproj'
].sort());
assert.equal(row('Kinds.A').NativeComment,'Shared input description.');
assert.equal(row('Kinds.B').Initializer,"'value; // text'");
assert.equal(row('Kinds.C').NativeComment,'Leading description for C.');
assert.equal(row('Kinds.D').NativeComment,'','Previous element comments must not leak');
assert.equal(row('Kinds.Local').Visibility,'Local/internal');
assert.equal(row('Kinds.Calculate.Input').NamedParamMarkupObserved,true);
assert.equal(row('Kinds.Calculate.$return').DeclaredType,'INT');
assert.equal(row('Kinds.Value.$value').DeclaredType,'INT');
assert.equal(row('Kinds.Value.Get').Parent,row('Kinds.Value').Id);
assert.equal(row('Choice.Second').NativeComment,'Final item without comma.');
assert.equal(row('Record.Payload').Initializer,"'(* text; *)'");
assert.equal(row('Record.Other').NativeComment,'');
assert.equal(row('Overlay').DeclarationForm,'Union');
assert.equal(row('Settings').DeclarationForm,'Library parameter list');
assert(rows.every(r=>Object.values(r.Review).every(value=>value==='Open')));
const before=crypto.createHash('sha256').update(fs.readFileSync(path.join(plc,'Kinds.TcPOU'))).digest('hex');
result=run(); assert.equal(result.status,0,result.stderr);
assert.deepEqual(read().map(r=>r.Id),rows.map(r=>r.Id));
assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(plc,'Kinds.TcPOU'))).digest('hex'),before);
fs.writeFileSync(path.join(plc,'Kinds.TcPOU'),files['Kinds.TcPOU'].replace('Fixture.','Reworded purpose.'));
result=run(); assert.equal(result.status,0,result.stderr);
assert.deepEqual(read().map(r=>r.Id),rows.map(r=>r.Id),'Comment changes preserve review identities');
fs.writeFileSync(path.join(plc,'Kinds.TcPOU'),files['Kinds.TcPOU']);
const rejected = [
  [project([...Object.keys(files),'Kinds.TcPOU']),/Duplicate Compile/],
  [project([...Object.keys(files),'Missing.TcPOU']),/Missing Compile/],
  [project(Object.keys(files).filter(f=>f!=='Choice.TcDUT')),/Unreferenced PLC/],
  [project().replace('<Compile ', '<Compile Condition="Test" '),/Conditional Compile/],
  [project().replace('</Project>','<Import Project="Other.props"/></Project>'),/Imported\/updated\/removed/]
];
for (const [text,expected] of rejected) {
  fs.writeFileSync(projectPath,text); result=run(); assert.notEqual(result.status,0); assert.match(result.stderr,expected);
}
fs.writeFileSync(projectPath,project());
console.log('PASS: declaration/member/element inventory, comment boundaries, stable identities, source preservation and five scope-gap rejections.');
