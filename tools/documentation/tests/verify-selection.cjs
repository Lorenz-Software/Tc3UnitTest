const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const repo = path.resolve(__dirname,'../../..');
const fixture = path.join(repo,'artifacts/documentation/selection-check-' + process.pid);
fs.mkdirSync(path.join(fixture,'plc/Area'),{recursive:true});
const program=path.join(repo,'artifacts/documentation/compiler/bin/Release/net9.0/TwinCatDocumentation.dll');
const template=path.join(repo,'tools/documentation/generator/assets/default-template');
const source = (kind,name,decl) => `<TcPlcObject><${kind} Name="${name}"><Declaration><![CDATA[${decl}]]></Declaration></${kind}></TcPlcObject>`;
const files={
  'plc/Area/Check.TcPOU':source('POU','Check','FUNCTION_BLOCK Check\nVAR_INPUT Data : ARRAY[0..1] OF Hidden; END_VAR'),
  'plc/Area/Hidden.TcDUT':source('DUT','Hidden','TYPE INTERNAL Hidden : UNION Number : REAL; Bits : DWORD; END_UNION END_TYPE'),
  'plc/Area/HiddenHelper.TcPOU':source('POU','HiddenHelper','FUNCTION INTERNAL HiddenHelper : BOOL'),
};
const project='<Project>'+Object.keys(files).map(f=>`<Compile Include="${f.slice(4)}"/>`).join('')+'</Project>';
const config={sourceRoot:'plc',includeTypes:[],libraryNamespace:'Fixture',publisher:'Fixture',product:'Fixture',brandMark:'F',subtitle:'Fixture',edition:'Fixture',
  packageFile:'fixture.zip',stylesheet:'style.css',overview:{title:'Fixture',introduction:'Fixture',sections:[]},
  groups:[{title:'Area',description:'Fixture',types:[],sourcePrefix:'Area'}],
  attribution:{author:'Fixture',contactEmail:'author@example.com',copyright:'Fixture',licenseName:'Fixture',licenseFile:'LICENSE'},
  selection:{projectFile:'plc/library.plcproj',exclusions:[]}};
function reset(){
  for(const [file,text] of Object.entries(files))fs.writeFileSync(path.join(fixture,file),text);
  fs.writeFileSync(path.join(fixture,'plc/library.plcproj'),project);
  fs.writeFileSync(path.join(fixture,'config.json'),JSON.stringify(config));
  fs.writeFileSync(path.join(fixture,'LICENSE'),'Fixture');fs.writeFileSync(path.join(fixture,'style.css'),':root{}');
}
function run(){return spawnSync('dotnet',[program,fixture,path.join(fixture,'output'),path.join(fixture,'config.json'),template],{encoding:'utf8'});}
reset(); let result=run();assert.equal(result.status,0,result.stderr);
const model=JSON.parse(fs.readFileSync(path.join(fixture,'output/api-model.json'),'utf8'));
assert.deepEqual(model.map(a=>a.Name).sort(),['Check','Hidden']);
assert(model.find(a=>a.Name==='Hidden').RequiredDependency);
assert(fs.readFileSync(path.join(fixture,'output/Fixture.Check.yml'),'utf8').includes('Fixture.Hidden.html'));
const cases=[
  [/Stale export exclusion/,()=>{const c=structuredClone(config);c.selection.exclusions=[{name:'Gone',reason:'Removed'}];fs.writeFileSync(path.join(fixture,'config.json'),JSON.stringify(c));}],
  [/Excluded object is required/,()=>{const c=structuredClone(config);c.selection.exclusions=[{name:'Hidden',reason:'Fixture'}];fs.writeFileSync(path.join(fixture,'config.json'),JSON.stringify(c));}],
  [/unreferenced PLC object/,()=>fs.writeFileSync(path.join(fixture,'plc/library.plcproj'),project.replace('<Compile Include="Area/HiddenHelper.TcPOU"/>',''))],
  [/Missing saved Compile source/,()=>fs.writeFileSync(path.join(fixture,'plc/library.plcproj'),project.replace('</Project>','<Compile Include="Area/Missing.TcPOU"/></Project>'))],
  [/Duplicate Compile references/,()=>fs.writeFileSync(path.join(fixture,'plc/library.plcproj'),project.replace('</Project>','<Compile Include="Area/Check.TcPOU"/></Project>'))],
  [/exactly one area prefix/,()=>{const c=structuredClone(config);c.groups[0].sourcePrefix='Missing';fs.writeFileSync(path.join(fixture,'config.json'),JSON.stringify(c));}],
];
for(const [expected,change]of cases){reset();change();result=run();assert.equal(result.status,1);assert.match(result.stderr,expected);}
reset();console.log('PASS: automatic public selection, required internal union closure, compound-type links and six invalid selection cases.');
