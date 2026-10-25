const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { parseArgs } = require('node:util');
const { openBrowser } = require('./browser-session.cjs');
const { values } = parseArgs({ options: { site: { type: 'string' }, output: { type: 'string' }, browser: { type: 'string' } } });
assert(values.site && values.output, 'Use --site <extracted package> --output <build output>');
const site = path.resolve(values.site), output = path.resolve(values.output);
const model = JSON.parse(fs.readFileSync(path.join(output, 'api-model.json'), 'utf8'));
const pages = JSON.parse(fs.readFileSync(path.join(output, 'help-pages.json'), 'utf8'));
const guide = pages.includes('guide.html') ? JSON.parse(fs.readFileSync(path.join(output, 'guide-model.json'), 'utf8')) : [];
const build = JSON.parse(fs.readFileSync(path.join(site, 'help-build.json'), 'utf8'));
const checks = [];
function check(value, description) { assert(value, description); checks.push(description); }
function plain(value) { return value.replace(/\s+/g, ' ').trim(); }
let links = 0, session;
(async () => {
  try {
    for (const name of pages) {
      const html = fs.readFileSync(path.join(site, name), 'utf8');
      check(!/<(?:script|link|img)\b[^>]*(?:src|href)\s*=\s*["']https?:/i.test(html), name + ': no remote presentation resources');
      for (const match of html.matchAll(/(?:href|src)\s*=\s*["']([^"']+)["']/gi)) {
        if (/^(?:https?:|mailto:|#|data:)/.test(match[1])) continue;
        const target = decodeURIComponent(match[1].split(/[?#]/)[0]);
        const absolute = path.resolve(site, target);
        check(absolute.startsWith(site + path.sep) && fs.existsSync(absolute), name + ': local target exists: ' + target);
        links++;
      }
    }
    const evidence = path.join(output, 'validation/generic');
    session = await openBrowser({ browserPath: values.browser, evidence });
    await session.cdp('Emulation.setDeviceMetricsOverride', { width:1440,height:1000,deviceScaleFactor:1,mobile:false });
    for (const item of model) {
      await session.navigate(path.join(site, item.Uid + '.html'));
      const text = plain(await session.evaluate('document.querySelector("article").innerText'));
      for (const description of [item.Docs.Summary, item.Docs.Remarks, item.Docs.Returns || item.ReturnComment,
        ...item.Fields.map(field => item.Docs.Parameters[field.Name] || field.Comment)].filter(Boolean))
        check(text.includes(plain(description)), item.Uid + ': effective description preserved');
      if (build.library) check(await session.evaluate('document.querySelector(".library-version").textContent') === 'v' + build.library.Version, item.Uid + ': page identifies its library version');
      if (item.Kind === 'GVL' && item.Signature !== 'VAR_GLOBAL') {
        check(text.includes(item.IsParameterList ? 'consumer-overridable compile-time library parameters' : 'fixed library constants'), item.Uid + ': parameter and constant semantics distinguished');
        for (const field of item.Fields) {
          const row = await session.evaluate('document.getElementById(' + JSON.stringify('field-' + field.Name) + ').innerText');
          check(plain(row).includes(plain(field.Default)), item.Uid + ': declared value preserved: ' + field.Name);
        }
        await session.screenshot(path.join(evidence, item.IsParameterList ? 'Parameters-desktop.png' : 'Constants-desktop.png'));
      }
    }
    const guideHashes = {};
    for (const chapter of guide) {
      await session.navigate(path.join(site, chapter.url));
      check(await session.evaluate('document.querySelector("article h1")?.textContent') === chapter.title, chapter.url + ': source title preserved');
      check(await session.evaluate('document.querySelector(".guide-navigation").open && document.querySelector("#context-navigation").hidden'), chapter.url + ': chapter navigation expands under guide entry');
      const source = fs.readFileSync(chapter.source, 'utf8');
      guideHashes[chapter.source] = require('node:crypto').createHash('sha256').update(fs.readFileSync(chapter.source)).digest('hex').toUpperCase();
      check(guideHashes[chapter.source] === chapter.hash, chapter.url + ': authored source remains unchanged');
      const firstParagraph = source.split(/\r?\n\s*\r?\n/)[1];
      check(plain(await session.evaluate('document.querySelector("article").innerText')).includes(plain(firstParagraph.replace(/`/g, ''))), chapter.url + ': opening paragraph preserved');
      const code = Array.from(source.matchAll(/^```[^\r\n]*\r?\n([\s\S]*?)^```/gm), match => match[1].trimEnd().replaceAll('\r\n', '\n'));
      const rendered = await session.evaluate('Array.from(document.querySelectorAll("article pre code"),c=>c.textContent.trimEnd().replaceAll("\\r\\n","\\n"))');
      check(JSON.stringify(code) === JSON.stringify(rendered), chapter.url + ': every source code example preserved');
      const targets = await session.evaluate('Array.from(document.querySelectorAll("article a[href]"),a=>a.getAttribute("href"))');
      for (const target of targets) {
        if (/^(https?:|mailto:)/.test(target) || !target.includes('#')) continue;
        const [filename, fragment] = target.split('#');
        await session.navigate(path.join(site, filename || chapter.url));
        check(await session.evaluate('Boolean(document.getElementById(' + JSON.stringify(decodeURIComponent(fragment)) + '))'), chapter.url + ': fragment target exists: ' + target);
      }
      for (const name of chapter.apiTypes) {
        const api = model.find(item => !item.Owner && item.Name === name);
        if (api) {
          check(targets.includes(api.Uid + '.html'), chapter.url + ': available API linked: ' + name);
          check(fs.readFileSync(path.join(site, api.Uid + '.html'), 'utf8').includes('href="' + chapter.url + '"'), name + ': API links back to guide');
        } else check(fs.readFileSync(path.join(site, chapter.url), 'utf8').includes(name + '</code> — not included in this API export.'), chapter.url + ': unavailable API marked: ' + name);
      }
    }
    if (guide.length) {
      await session.navigate(path.join(site, guide[0].url));
      await session.evaluate('document.querySelector("#help-search").value=' + JSON.stringify(guide[0].title) + ';document.querySelector("#help-search").dispatchEvent(new Event("input"))');
      check(await session.evaluate('Array.from(document.querySelectorAll("#help-results a")).some(a=>a.getAttribute("href")===' + JSON.stringify(guide[0].url) + ')'), 'Shared offline search finds guide content');
      await session.evaluate('document.querySelector("#help-search").value="";document.querySelector("#help-search").dispatchEvent(new Event("input"))');
      await session.screenshot(path.join(evidence, 'Guide-desktop.png'));
    }
    await session.navigate(path.join(site, 'index.html'));
    if (build.library) {
      await session.navigate(path.join(site, 'about.html'));
      const about = plain(await session.evaluate('document.querySelector("article").innerText'));
      for (const value of [build.library.Title, build.library.Company, build.library.Version, build.library.Namespace,
        build.library.FrameworkVersion, ...build.library.Contracts.map(contract=>contract.Version)])
        check(about.includes(value), 'About page preserves project metadata: ' + value);
      await session.screenshot(path.join(evidence, 'Metadata-desktop.png'));
      await session.navigate(path.join(site, 'index.html'));
    }
    await session.evaluate('document.querySelector(".header-search").click()');
    check(await session.evaluate('document.querySelector("#help-search-dialog").open && document.activeElement.id === "help-search"'), 'Header search opens modal with input focus');
    await session.evaluate('document.querySelector("#help-search").value=' + JSON.stringify(model[0].Name) + ';document.querySelector("#help-search").dispatchEvent(new Event("input"))');
    check(await session.evaluate('!document.querySelector("#help-navigation").hidden && document.querySelectorAll("#help-results a").length > 0'), 'Global search preserves navigation and provides results');
    await session.screenshot(path.join(evidence, 'Search-desktop.png'));
    await session.cdp('Input.dispatchKeyEvent', {type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});
    await session.cdp('Input.dispatchKeyEvent', {type:'keyUp',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});
    check(await session.evaluate('!document.querySelector("#help-search-dialog").open'), 'Escape dismisses modal search');
    await session.cdp('Input.dispatchKeyEvent', {type:'keyDown',key:'k',code:'KeyK',modifiers:2,windowsVirtualKeyCode:75});
    await session.cdp('Input.dispatchKeyEvent', {type:'keyUp',key:'k',code:'KeyK',modifiers:2,windowsVirtualKeyCode:75});
    check(await session.evaluate('document.querySelector("#help-search-dialog").open'), 'Ctrl+K opens search');
    await session.evaluate('document.querySelector(".search-close").click()');
    check(await session.evaluate('document.querySelector(".help-footer").parentElement === document.body'), 'Footer belongs to page frame');
    await session.evaluate('document.querySelector(".theme-toggle").click()');
    check(await session.evaluate('document.documentElement.dataset.theme === "dark"'), 'Dark theme is selectable');
    await session.navigate(path.join(site, 'catalog.html'));
    check(await session.evaluate('document.documentElement.dataset.theme === "dark"'), 'Theme survives page navigation');
    check(await session.evaluate('document.querySelectorAll("tr[data-entry]").length') === model.filter(item => !item.Owner).length, 'Catalog covers selected types');
    const selected = model[0];
    await session.evaluate('document.querySelector("#help-search").value=' + JSON.stringify(selected.Name) + ';document.querySelector("#help-search").dispatchEvent(new Event("input"))');
    check(await session.evaluate('Array.from(document.querySelectorAll("#help-results a")).some(a=>a.getAttribute("href")===' + JSON.stringify(selected.Uid + '.html') + ')'), 'Offline search finds an extracted API');
    await session.cdp('Emulation.setDeviceMetricsOverride', {width:390,height:844,deviceScaleFactor:2,mobile:true});
    await session.evaluate('document.querySelector(".header-search").click()');
    check(await session.evaluate('document.querySelector("#help-search-dialog").getBoundingClientRect().right<=innerWidth && document.activeElement.id === "help-search"'), 'Mobile search dialog fits viewport and receives focus');
    await session.screenshot(path.join(evidence, 'Search-mobile.png'));
    await session.evaluate('document.querySelector(".search-close").click()');
    if (guide.length) {
      await session.navigate(path.join(site, guide[0].url));
      check(await session.evaluate('document.documentElement.scrollWidth<=390 && document.querySelector("main").scrollWidth<=document.querySelector("main").clientWidth'), 'Guide tables and examples stay within mobile content');
      await session.screenshot(path.join(evidence, 'Guide-mobile.png'));
    }
    check(await session.evaluate('document.documentElement.scrollWidth<=390 && Math.abs(document.querySelector(".help-footer").getBoundingClientRect().bottom-innerHeight)<1'), 'Mobile frame fits viewport');
    check(session.remoteRequests.length === 0, 'Package opens without HTTP requests');
    await session.screenshot(path.join(evidence, 'Mobile.png'));
    const report = {result:'PASS',checks,pages:pages.length,guideChapters:guide.length,links,browser:session.version.Browser,remoteRequests:session.remoteRequests};
    fs.writeFileSync(path.join(evidence, 'verification.json'), JSON.stringify(report,null,2));
    console.log(JSON.stringify({...report,checks:checks.length}));
  } catch (error) { console.error(error); process.exitCode=1; }
  finally { await session?.close(); }
})();
