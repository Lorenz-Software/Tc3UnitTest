// Integration check: use the same sources with a different project identity and grouping.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { execFileSync, spawnSync } = require('node:child_process');
const repo = path.resolve(__dirname, '../..');
const output = path.join(repo, 'artifacts/documentation/configuration-check');
fs.mkdirSync(output, { recursive: true });
const original = JSON.parse(fs.readFileSync(path.join(__dirname, 'projects/tc3-unittest/sample.json'), 'utf8'));
const config = structuredClone(original);
delete config.guide;
delete config.library;
Object.assign(config, { libraryNamespace: 'ExampleLibrary', product: 'Example Library', publisher: 'Example Publisher',
  brandMark: 'EX', subtitle: 'Example reference', edition: 'Configuration check', stylesheet: 'custom.css' });
config.attribution.author = 'Example Author';
config.attribution.website = 'https://example.com/';
config.attribution.logoFile = null;
config.attribution.headerLogoFile = null;
config.attribution.contactEmail = 'author@example.com';
config.attribution.copyright = 'Copyright Example Publisher';
config.overview = { title: 'Example overview', introduction: 'Independent project introduction.', sections: [] };
config.groups = [{ title: 'Example catalog', description: 'Project-defined grouping.', types: config.includeTypes }];
const configPath = path.join(output, 'project.json');
fs.writeFileSync(configPath, JSON.stringify(config));
fs.writeFileSync(path.join(output, 'custom.css'), ':root { --accent: #732b80; }\r\n');
const program = path.join(repo, 'artifacts/documentation/compiler/bin/Release/net9.0/TwinCatDocumentation.dll');
execFileSync('dotnet', [program, repo, output, configPath, path.join(repo, 'tools/documentation/generator/assets/default-template')], { stdio: 'pipe' });
execFileSync(path.join(repo, 'local/tools/docfx/docfx.exe'), ['build', path.join(output, 'docfx.json'), '--warningsAsErrors'], { stdio: 'pipe' });
const html = fs.readFileSync(path.join(output, 'site/index.html'), 'utf8');
for (const text of ['Example Library', 'Example Publisher', 'Example catalog', 'Independent project introduction.', '>EX</span>']) assert(html.includes(text), text);
assert(!html.includes('TC3 UnitTest') && !html.includes('Tc3UnitTest.'), 'No original project identity in alternate output');
assert.equal(fs.readFileSync(path.join(output, 'site/help-project.css'), 'utf8'), fs.readFileSync(path.join(output, 'custom.css'), 'utf8'));
assert(html.includes('Copyright Example Publisher'), 'Copyright is project configuration');
const about = fs.readFileSync(path.join(output, 'site/about.html'), 'utf8');
assert(about.includes('Example Author') && about.includes('author@example.com'), 'Author and contact are project configuration');
assert(about.includes('https://example.com/') && !about.includes('lorenz-software.solutions'), 'Website is project configuration');
assert(!html.includes('class="header-author-link"'), 'Header branding is optional project configuration');
assert.equal(fs.readFileSync(path.join(output, 'site/LICENSE.txt'), 'utf8'), fs.readFileSync(path.join(repo, config.attribution.licenseFile), 'utf8'));
const primary = JSON.parse(fs.readFileSync(path.join(repo, 'artifacts/documentation/sample/api-model.json'), 'utf8'));
const alternate = JSON.parse(fs.readFileSync(path.join(output, 'api-model.json'), 'utf8'));
assert.deepEqual(alternate.map(a => ({ ...a, Uid: a.Uid.replace(/^ExampleLibrary\./, 'Tc3UnitTest.') })), primary,
  'Branding and grouping do not change extracted API semantics');
for (const change of [c => c.groups[0].types.push(c.includeTypes[0]), c => c.libraryNamespace = '../invalid',
  c => c.stylesheet = '../outside.css', c => c.unrecognized = true]) {
  const invalid = structuredClone(config); change(invalid);
  const invalidPath = path.join(output, 'invalid.json'); fs.writeFileSync(invalidPath, JSON.stringify(invalid));
  const result = spawnSync('dotnet', [program, repo, path.join(output, 'rejected'), invalidPath, path.join(repo, 'tools/documentation/generator/assets/default-template')], { encoding: 'utf8' });
  assert.equal(result.status, 1, 'Invalid configuration must fail explicitly');
}
console.log('PASS: alternate project identity, grouping, stylesheet, unchanged API semantics and four invalid configurations.');
