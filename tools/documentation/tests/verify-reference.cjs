const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..');
const output = path.join(root, 'artifacts/documentation/reference');
const read = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
const model = read(path.join(output, 'api-model.json'));
const coverage = read(path.join(output, 'export-coverage.json'));
const ledger = read(path.join(root, 'artifacts/documentation/project-inventory/items.json'));
const files = read(path.join(root, 'artifacts/documentation/project-inventory/files.json'));
const roots = model.filter(a => !a.Owner);
const named = new Map(model.map(a => [(a.Owner ? a.Owner + '.' : '') + a.Name, a]));
const visible = item => !['PRIVATE', 'INTERNAL'].includes(item.Visibility);
const framework = files.filter(f => f.area.startsWith('Framework/'));
assert.equal(coverage.length, framework.length, 'Every framework source has an inclusion disposition');
for (const source of framework) assert.equal(coverage.filter(c => c.source === source.path).length, 1);
for (const item of ledger.filter(i => !i.Parent && i.Area.startsWith('Framework/'))) {
  const decision = coverage.find(c => c.source === item.Path);
  if (visible(item) && item.QualifiedName !== 'Global_Version')
    assert(decision.included, item.Id + ': public source cannot be omitted');
  if (decision.included && !visible(item))
    assert(decision.requiredDependency, item.Id + ': internal inclusion needs a declaration dependency');
}
let declarations = 0, elements = 0, returns = 0, accessors = 0;
for (const item of ledger) {
  if (!item.Area.startsWith('Framework/')) continue;
  const disposition = coverage.find(c => c.source === item.Path);
  assert(disposition?.reason, item.Id + ': explicit inclusion reason');
  if (!disposition.included) {
    assert(!model.some(a => a.Source === item.Path), item.Id + ': excluded source has no API pages');
    continue;
  }
  if (['POU', 'Itf', 'DUT', 'GVL', 'Method', 'Property'].includes(item.Kind) && (!item.Parent || visible(item))) {
    assert(named.has(item.QualifiedName), item.Id + ': exported declaration'); declarations++;
  }
  if (['Method', 'Property'].includes(item.Kind) && !visible(item))
    assert(!named.has(item.QualifiedName), item.Id + ': private/internal member excluded');
  const parent = ledger.find(p => p.Id === item.Parent);
  const api = parent && named.get(parent.QualifiedName);
  if (!api) continue;
  if (['DUT field', 'Enumerator', 'Variable/parameter'].includes(item.Kind) &&
      /^(STRUCT|UNION|ENUM|VAR_INPUT|VAR_OUTPUT|VAR_IN_OUT|VAR_GLOBAL)/.test(item.Direction)) {
    const field = api.Fields.find(f => f.Name === item.QualifiedName.split('.').at(-1));
    assert(field, item.Id + ': exported element');
    assert.equal(field.Comment, item.NativeComment, item.Id + ': native description');
    assert.equal(field.Default, item.Initializer, item.Id + ': initializer');
    if (item.Direction !== 'ENUM') assert.equal(field.Type, item.DeclaredType, item.Id + ': type');
    elements++;
  }
  if (['Return value', 'Property value'].includes(item.Kind)) {
    assert.equal(api.ReturnType, item.DeclaredType, item.Id + ': return type');
    assert.equal(api.ReturnComment, item.NativeComment, item.Id + ': return description'); returns++;
  }
  if (['Get', 'Set'].includes(item.Kind) && visible(item)) {
    assert(api.Accessors.includes(item.Kind), item.Id + ': accessor retained'); accessors++;
  }
}
const build = read(path.join(output, 'help-build.json'));
assert.equal(declarations, model.length, 'No additional unreviewed API declarations');
assert.equal(elements, model.reduce((count,a)=>count+a.Fields.length,0), 'No implementation variables leak into the API');
for (const [name, hash] of Object.entries(build.inputHashes)) {
  if (!name.startsWith('repository/')) continue;
  assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(root, name.slice(11)))).digest('hex').toUpperCase(), hash, name + ': saved input');
}
assert(roots.some(a => a.Name === 'TestCaseBase') && roots.some(a => a.Name === 'RunControlBase'));
assert(!model.some(a => /\/SelfTests\/|\/Runtime\//.test(a.Source)));
const inherited = read(path.join(output, 'probe-report.json')).inheritedMembers;
assert(inherited['Tc3UnitTest.AssertTrue'].includes('Tc3UnitTest.AssertionBase.Initialize'));
assert(inherited['Tc3UnitTest.I_TestSuite'].includes('Tc3UnitTest.I_ResultProvider.Result'));
const byName = new Map(roots.map(a=>[a.Name,a]));
function fieldsWithOrigin(api) {
  const own=api.Fields.map(field=>({field,origin:api}));
  return own.concat(api.Base ? fieldsWithOrigin(byName.get(api.Base)).filter(x=>!own.some(o=>o.field.Name===x.field.Name)) : []);
}
let fieldOrigins=0;
for(const api of model){
  const html=fs.readFileSync(path.join(output,'site',api.Uid+'.html'),'utf8');
  for(const {field,origin}of fieldsWithOrigin(api)){
    const row=html.match(new RegExp('<tr id="field-'+field.Name+'">([\\s\\S]*?)</tr>'))?.[1];
    assert(row,api.Uid+': rendered field row '+field.Name);
    if(origin===api)assert(!row.includes('<small>Inherited from '),api.Uid+': own field cannot inherit from an equal-valued field elsewhere');
    else assert(row.includes('Inherited from <a href="'+origin.Uid+'.html"'),api.Uid+': inherited field identifies its actual declaring type');
    fieldOrigins++;
  }
}
const result = {result:'PASS', sources:framework.length, included:roots.length, excluded:coverage.filter(c=>!c.included).length,
  requiredDependencies:coverage.filter(c=>c.requiredDependency).map(c=>c.name), pages:model.length, declarations,elements,returns,accessors,fieldOrigins,
  areas:[...new Set(framework.map(f=>f.area))]};
fs.mkdirSync(path.join(output,'validation'),{recursive:true});
fs.writeFileSync(path.join(output,'validation/coverage.json'),JSON.stringify(result,null,2));
console.log(JSON.stringify(result));
