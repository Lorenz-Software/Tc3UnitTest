const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { parseArgs } = require('node:util');
const { spawn } = require('node:child_process');
const assert = require('node:assert/strict');
const { values } = parseArgs({ options: { site: { type: 'string' }, output: { type: 'string' }, browser: { type: 'string' } } });
const output = path.resolve(values.output || path.join(__dirname, '../../../artifacts/documentation/sample'));
const site = path.resolve(values.site || path.join(output, 'site'));
const evidence = path.join(output, 'validation');
fs.mkdirSync(evidence, { recursive: true });
const checks = [];
function check(value, description) { assert(value, description); checks.push(description); }
function html(name) { return fs.readFileSync(path.join(site, name + '.html'), 'utf8'); }
function text(value) {
  return value.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '').replace(/<[^>]*>/g, ' ')
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ');
}
function includes(name, value) { check(text(html(name)).includes(value), name + ': ' + value); }
const guide = JSON.parse(fs.readFileSync(path.join(output, 'guide-model.json'), 'utf8'));
check(guide.length === 7, 'All seven project authoring chapters are packaged');
check(guide.map(chapter=>chapter.file).join(',') === 'framework-model.md,test-case.md,preparation.md,assertions.md,test-suite.md,run-control.md,ai-assisted-framework-authoring.md', 'Project chapter order is preserved');
includes('guide', 'Authoring Guide');
includes('about', 'Lorenz Software');
includes('about', 'MIT License');
includes('about', '1.0.0.0');
includes('Tc3UnitTest.Param_Assertions', 'consumer-overridable compile-time library parameters');
includes('Tc3UnitTest.Param_EventBuffer', 'Library default');
includes('Tc3UnitTest.GVL_Constants', 'fixed library constants');
check(html('Tc3UnitTest.ST_Event').includes('Tc3UnitTest.GVL_Constants.html#field-NameLength'), 'structure capacity links to its declared constant');
const manifest = JSON.parse(fs.readFileSync(path.join(site, 'help-build.json'), 'utf8'));
check(manifest.library.Version === '1.0.0.0' && manifest.library.Namespace === 'Tc3UnitTest', 'package identity comes from PLC project metadata');
check(manifest.library.Contracts.length === 2 && manifest.source.Commit, 'package records independent contracts and source identity');
for (const [label, hash] of Object.entries(manifest.inputHashes).filter(([name])=>name.startsWith('repository/'))) {
  const input = path.join(__dirname, '../../..', label.slice('repository/'.length));
  check(require('node:crypto').createHash('sha256').update(fs.readFileSync(input)).digest('hex').toUpperCase() === hash, 'manifest identifies unchanged repository input: ' + label);
}
check(fs.readFileSync(path.join(site, 'author-logo.png')).equals(fs.readFileSync(path.join(__dirname, '../projects/tc3-unittest/assets/lorenz-software.png'))), 'package contains original author logo bytes');
check(fs.readFileSync(path.join(site, 'author-symbol.png')).equals(fs.readFileSync(path.join(__dirname, '../projects/tc3-unittest/assets/lorenz-software-symbol.png'))), 'package contains original compact logo bytes');
check(fs.readFileSync(path.join(site, 'LICENSE.txt')).equals(fs.readFileSync(path.join(__dirname, '../../../LICENSE'))), 'package license is byte-identical to repository license');
includes('Tc3UnitTest.AssertionBase', 'Reset queues work for the next FB call');
includes('Tc3UnitTest.AssertionBase.Initialize', 'The Parent Test Case identity must already be valid.');
includes('Tc3UnitTest.AssertionBase.Initialize', 'Owning Test Case with an established Name; read during initialization, not retained.');
includes('Tc3UnitTest.AssertionBase.Initialize', 'TRUE after successful identity and setup validation; FALSE leaves the object uninitialized.');
includes('Tc3UnitTest.AssertionBase.Result', 'Consuming Reset or calling Initialize clears the result to NotEvaluated.');
includes('Tc3UnitTest.I_Assertion', 'Assertion-specific identity and result view; initialization remains an instance API.');
includes('Tc3UnitTest.ST_Event', 'Event payload. Timestamp is UTC Unix nanoseconds; text is ASCII.');
includes('Tc3UnitTest.ST_Event', 'Producer-assigned event sequence within the current buffer epoch; zero is not a published event.');
includes('Tc3UnitTest.AssertTrue', 'Actual value checked or observed by this Assertion.');
check(html('Tc3UnitTest.AssertTrue').includes('Tc3UnitTest.AssertionBase.Initialize.html'), 'derived FB links inherited Initialize');
check(html('Tc3UnitTest.AssertTrue').includes('Tc3UnitTest.AssertionBase.ResetAssertion.html'), 'derived FB links inherited protected ResetAssertion');
check(html('Tc3UnitTest.I_Assertion').includes('Tc3UnitTest.I_ResultProvider.Result.html'), 'interface links inherited Result property');
check(!html('Tc3UnitTest.AssertionBase').includes('FEventPublisher'), 'private instance fields excluded');
const model = JSON.parse(fs.readFileSync(path.join(output, 'api-model.json'), 'utf8'));
for (const item of model) {
  const rendered = text(html(item.Uid));
  const descriptions = [item.Docs.Summary, item.Docs.Remarks, item.Docs.Returns, item.ReturnComment,
    ...item.Fields.map(field => item.Docs.Parameters[field.Name] || field.Comment)].filter(Boolean);
  for (const description of descriptions) {
    const expected = description.replace(/\s+/g, ' ').trim();
    check(rendered.includes(expected), item.Uid + ': extracted description preserved in HTML: ' + expected.slice(0, 65));
  }
}
let links = 0;
for (const name of fs.readdirSync(site).filter(n => n.endsWith('.html'))) {
  const source = html(name.slice(0, -5));
  check(source.includes('Copyright (c) 2026 Lorenz Software') && source.includes('href="about.html"'), name + ': copyright and license access available');
  check(!/docfx|logo\.svg|favicon\.ico/i.test(source), name + ': no default generator branding/assets');
  check(!/<(?:script|link|img)\b[^>]*(?:src|href)\s*=\s*["']https?:/i.test(source), name + ': no remote presentation resources');
  for (const match of html(name.slice(0, -5)).matchAll(/href\s*=\s*["']([^"']+)["']/gi)) {
    const href = match[1];
    if (/^(?:https?:|mailto:|javascript:|#|data:)/.test(href)) continue;
    const target = decodeURIComponent(href.split(/[?#]/)[0]);
    if (!target) continue;
    check(!target.endsWith('.yml'), name + ': no source-YAML hyperlink');
    assert(fs.existsSync(path.resolve(site, target)), name + ': missing link target ' + href);
    links++;
  }
}
const { openBrowser } = require('../../../tools/documentation/generator/scripts/browser-session.cjs');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
let session;
(async () => {
  try {
    session = await openBrowser({ browserPath: values.browser, evidence });
    const { cdp, version, browserPath, remoteRequests } = session;
    const sessionId = undefined;
    const runtime = session.evaluate;
    const navigate = file => session.navigate(path.isAbsolute(file) ? file : path.join(site, file));
    const screenshot = name => session.screenshot(path.join(evidence, name + '.png'));
    await cdp('Emulation.setDeviceMetricsOverride', { width:1440, height:1000, deviceScaleFactor:1, mobile:false });
    await navigate('Tc3UnitTest.AssertTrue.html');
    check((await runtime('document.querySelector("article").innerText')).includes('Inherited methods'), 'browser renders inherited methods');
    check((await runtime('location.protocol')) === 'file:', 'package opens directly from local files');
    check(await runtime('Boolean(document.querySelector("#help-navigation a[aria-current=page]"))'), 'offline API navigation marks current page');
    await runtime('document.querySelector("#help-search").value = "Owning Test Case"; document.querySelector("#help-search").dispatchEvent(new Event("input"));');
    check(await runtime('Array.from(document.querySelectorAll("#help-results a")).some(a => a.getAttribute("href") === "Tc3UnitTest.AssertionBase.Initialize.html")'), 'offline full-text search finds parameter descriptions');
    await runtime('document.querySelector("#help-search").value = ""; document.querySelector("#help-search").dispatchEvent(new Event("input"));');
    const initializeSelector = JSON.stringify('a[href="Tc3UnitTest.AssertionBase.Initialize.html"]');
    check(await runtime(`Boolean(document.querySelector(${initializeSelector}))`), 'inherited Initialize link visible in DOM');
    check(await runtime('document.querySelectorAll(".class-diagram svg").length === 1'), 'derived type has a static class diagram');
    check(await runtime('Array.from(document.querySelectorAll(".class-diagram a")).some(a => a.getAttribute("href") === "Tc3UnitTest.I_Assertion.html")'), 'diagram includes interface implemented by base class');
    check(await runtime('document.querySelectorAll(".api-table tbody tr").length > 1'), 'members and inputs use structured tables');
    check(await runtime('!document.querySelector(".declaration-details").open'), 'full declaration is collapsed initially');
    check(await runtime('!document.querySelector("#context-navigation").textContent.includes("ST_Event")'), 'context navigation excludes unrelated types');
    check(await runtime('document.querySelector(".help-footer").parentElement === document.body'), 'footer belongs to application frame outside main content');
    const footerBeforeScroll = await runtime('document.querySelector(".help-footer").getBoundingClientRect().top');
    await runtime('document.querySelector("main").scrollTop = document.querySelector("main").scrollHeight');
    check(await runtime('document.querySelector("main").scrollTop > 0 && window.scrollY === 0'), 'long content scrolls independently of page frame');
    check(Math.abs((await runtime('document.querySelector(".help-footer").getBoundingClientRect().top')) - footerBeforeScroll) < 1, 'footer remains stationary when content scrolls');
    check(await runtime('document.querySelector("main").getBoundingClientRect().bottom <= document.querySelector(".help-footer").getBoundingClientRect().top && document.querySelector(".declaration-details").getBoundingClientRect().bottom <= document.querySelector("main").getBoundingClientRect().bottom'), 'last content section is reachable above footer without overlap');
    await runtime('Array.from(document.querySelectorAll("#page-outline a")).find(a => a.getAttribute("href") === "#inherited-methods").click()');
    check(await runtime('document.querySelector("#inherited-methods").getBoundingClientRect().top >= document.querySelector("main").getBoundingClientRect().top'), 'outline anchor targets content scroll region');
    await runtime('document.querySelector("main").scrollTop = 0');
    await screenshot('AssertTrue');
    await runtime(`document.querySelector(${initializeSelector}).click()`);
    await delay(600);
    check((await runtime('location.pathname')).endsWith('/Tc3UnitTest.AssertionBase.Initialize.html'), 'browser follows derived-to-base method link offline');
    const initialize = await runtime('document.querySelector("article").innerText');
    check(initialize.includes('Owning Test Case with an established Name') && initialize.includes('TRUE after successful identity'), 'browser displays native parameter and return descriptions');
    check(initialize.includes('The Parent Test Case identity must already be valid.'), 'browser displays existing remarks');
    await screenshot('Initialize');
    await navigate('Tc3UnitTest.ST_Event.html');
    check((await runtime('document.querySelector("article").innerText')).includes('Producer-assigned event sequence'), 'browser displays native DUT field descriptions');
    await screenshot('ST_Event');
    await runtime('document.querySelector(".theme-toggle").click()');
    check(await runtime('document.documentElement.dataset.theme === "dark"'), 'custom dark theme is selectable');
    await screenshot('ST_Event-dark');
    await runtime('document.querySelector(".theme-toggle").click()');
    await navigate('index.html');
    check((await runtime('document.querySelector("article").innerText')).includes('TC3 UnitTest'), 'branded landing page renders');
    check(await runtime('document.querySelectorAll(".area-card").length === 3'), 'overview shows configured areas');
    check(await runtime('!Array.from(document.querySelectorAll("article a")).some(a => a.getAttribute("href").startsWith("Tc3UnitTest."))'), 'overview does not enumerate types');
    check(await runtime('document.querySelectorAll(".lead p").length >= 3 && document.querySelector(".lead").textContent.includes("separate PC runner")'), 'overview introduces purpose, framework roles and intended readers');
    check(await runtime('document.querySelectorAll(".element-card").length === 4 && document.querySelectorAll(".element-card svg[aria-hidden=true]").length === 4'), 'overview offers labeled element categories with decorative symbols');
    await screenshot('Overview');
    await runtime('Array.from(document.querySelectorAll(".element-card")).find(a => a.getAttribute("href").includes("category=data")).click()');
    await delay(500);
    check(await runtime('document.querySelector("#catalog-category").value === "data" && document.querySelectorAll("tr[data-entry]:not([hidden])").length === 1'), 'element category link opens a prefiltered catalog');
    check(await runtime('document.querySelector("tr[data-entry]:not([hidden])").textContent.includes("ST_Event")'), 'data-type category resolves to structure sample');
    await navigate('catalog.html');
    check(await runtime('document.querySelectorAll("tr[data-entry]:not([hidden])").length === 8'), 'catalog lists sample objects');
    await runtime('document.querySelector("#catalog-query").value = "AssertTrue"; document.querySelector("#catalog-query").dispatchEvent(new Event("input"))');
    check(await runtime('document.querySelectorAll("tr[data-entry]:not([hidden])").length === 1'), 'catalog filters by type name');
    await runtime('document.querySelector("#catalog-query").value = ""; document.querySelector("#catalog-query").dispatchEvent(new Event("input")); document.querySelector("#catalog-group").value = "1"; document.querySelector("#catalog-group").dispatchEvent(new Event("change"))');
    check(await runtime('document.querySelectorAll("tr[data-entry]:not([hidden])").length === 2 && Array.from(document.querySelectorAll("tr[data-entry]:not([hidden])")).some(row=>row.textContent.includes("ST_Event"))'), 'catalog filters configured area');
    check(await runtime('document.querySelectorAll("tr[data-entry] .element-symbol").length === 8'), 'catalog objects have symbols alongside text labels');
    await runtime('document.querySelector("#catalog-category").value = "blocks"; document.querySelector("#catalog-category").dispatchEvent(new Event("change"))');
    check(await runtime('document.querySelectorAll("tr[data-entry]:not([hidden])").length === 0'), 'area and element category filters combine');
    await runtime('document.querySelector("#catalog-category").value = "data"; document.querySelector("#catalog-category").dispatchEvent(new Event("change"))');
    check(await runtime('document.querySelectorAll("tr[data-entry]:not([hidden])").length === 1'), 'matching area and category restore correct result');
    await screenshot('Catalog');
    // A separate synthetic catalog checks navigation scale, without claiming additional PLC export coverage.
    const fixtureSite = path.join(evidence, 'catalog-scale-fixture');
    fs.mkdirSync(path.join(fixtureSite, 'public'), { recursive: true });
    for (const asset of ['help-search.js', 'help-project.css', 'public/help.css', 'public/help.js']) fs.copyFileSync(path.join(site, asset), path.join(fixtureSite, asset));
    const fixtureRows = Array.from({ length: 620 }, (_, i) => `<tr data-entry data-group="${i < 310 ? 0 : 1}" data-kind="Function block" data-category="blocks"><td>Fixture${String(i).padStart(4, '0')}</td><td>Synthetic navigation fixture</td><td>Area</td></tr>`).join('');
    fs.writeFileSync(path.join(fixtureSite, 'catalog.html'), html('catalog').replace(/<tbody>[\s\S]*?<\/tbody>/, '<tbody>' + fixtureRows + '</tbody>'));
    await navigate(path.join(fixtureSite, 'catalog.html'));
    check(await runtime('document.querySelectorAll("tr[data-entry]:not([hidden])").length === 50'), '620-entry fixture shows a bounded first page');
    await runtime('document.querySelector("#catalog-next").click()');
    check(await runtime('document.querySelector("tr[data-entry]:not([hidden])").textContent.includes("Fixture0050")'), 'catalog pagination advances to next 50 entries');
    await runtime('document.querySelector("#catalog-query").value = "Fixture0619"; document.querySelector("#catalog-query").dispatchEvent(new Event("input"))');
    check(await runtime('document.querySelectorAll("tr[data-entry]:not([hidden])").length === 1 && document.querySelector("tr[data-entry]:not([hidden])").textContent.includes("Fixture0619")'), 'filter searches all pages and resets pagination');
    await runtime('document.querySelector("#catalog-query").value = ""; document.querySelector("#catalog-query").dispatchEvent(new Event("input")); document.querySelector("#catalog-group").value = "1"; document.querySelector("#catalog-group").dispatchEvent(new Event("change"))');
    check(await runtime('document.querySelector("#catalog-status").textContent === "310 of 620 elements"'), 'area filtering spans all fixture pages');
    await runtime('document.querySelector("#catalog-kind").value = "Structure"; document.querySelector("#catalog-kind").dispatchEvent(new Event("change"))');
    check(await runtime('document.querySelectorAll("tr[data-entry]:not([hidden])").length === 0 && document.querySelector("#catalog-status").textContent === "0 of 620 elements"'), 'combined filters handle no matches');
    await navigate('index.html');
    await cdp('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true }, sessionId);
    check(await runtime('document.documentElement.scrollWidth <= 390'), 'narrow viewport has no horizontal overflow');
    await runtime('document.querySelector(".menu-toggle").click()');
    check(await runtime('getComputedStyle(document.querySelector("#sidebar")).display !== "none"'), 'narrow-screen navigation opens');
    check(await runtime('document.querySelector(".sidebar").getBoundingClientRect().bottom <= document.querySelector(".help-footer").getBoundingClientRect().top'), 'mobile navigation stops above fixed footer');
    const themePoint = await runtime('(() => {const r=document.querySelector(".theme-toggle").getBoundingClientRect(); return {x:r.x+r.width/2,y:r.y+r.height/2};})()');
    await cdp('Input.dispatchMouseEvent', {type:'mousePressed',...themePoint,button:'left',clickCount:1}, sessionId);
    await cdp('Input.dispatchMouseEvent', {type:'mouseReleased',...themePoint,button:'left',clickCount:1}, sessionId);
    check(await runtime('document.documentElement.dataset.theme === "dark"'), 'fixed footer theme control accepts pointer input while mobile menu is open');
    await runtime('document.querySelector(".theme-toggle").click()');
    await screenshot('Mobile');
    await runtime('document.querySelector(".menu-toggle").click()');
    await navigate('Tc3UnitTest.AssertTrue.html');
    check(await runtime('document.documentElement.scrollWidth <= 390'), 'detail tables and diagram stay within narrow page width');
    check(await runtime('document.querySelector(".class-diagram svg").getBoundingClientRect().width >= 520'), 'mobile diagram keeps readable sizing inside its scroll container');
    await screenshot('Mobile-detail');
    await navigate('about.html');
    check(await runtime('Array.from(document.querySelectorAll("article a")).some(a => a.getAttribute("href") === "mailto:mail@lorenz-software.net")'), 'author contact matches repository metadata');
    check(await runtime('document.querySelector(".author-logo").complete && document.querySelector(".author-logo").naturalWidth === 1711 && document.querySelector(".author-logo").naturalHeight === 632'), 'original author logo loads offline at its original aspect ratio');
    check(await runtime('document.querySelector(".author-logo-link").getAttribute("href") === "https://www.lorenz-software.solutions/"'), 'author logo links to owner-provided website');
    check(await runtime('document.querySelector(".header-author-link").getAttribute("href") === "about.html"'), 'compact header logo links to local author page');
    check(await runtime('document.querySelectorAll(".sidebar-branding,.sidebar-note,.sidebar-logo").length === 0'), 'navigation contains no author block');
    check(await runtime('document.querySelectorAll(".help-header .theme-toggle").length === 0 && document.querySelectorAll(".help-footer .theme-toggle").length === 1'), 'theme control is only in page footer');
    check(await runtime('!document.querySelector(".help-header").textContent.includes("API preview") && !document.querySelector(".help-footer").textContent.includes("API preview")'), 'preview status is absent from repeated page chrome');
    check(await runtime('document.querySelector(".header-author-link").title === "About Lorenz Software" && document.querySelector(".theme-toggle").getAttribute("aria-label").startsWith("Switch to")'), 'compact controls retain accessible names');
    const renderedLicense = await runtime('document.querySelector(".license-text").textContent');
    check(renderedLicense.trim() === fs.readFileSync(path.join(site, 'LICENSE.txt'), 'utf8').replace(/\r\n/g, '\n').trim(), 'license page displays complete packaged license');
    check(await runtime('document.documentElement.scrollWidth <= 390'), 'license page fits narrow viewport');
    await screenshot('About-mobile');
    const scalingEvidence = [];
    for (const width of [320, 390, 1440]) {
      for (const dpr of [1, 2, 3]) {
        await cdp('Emulation.setDeviceMetricsOverride', { width, height: 1000, deviceScaleFactor: dpr, mobile: width < 760 }, sessionId);
        await runtime('document.body.classList.remove("menu-open")');
        const fullLogo = await runtime(`(() => { const im = document.querySelector('.author-logo'); const r = im.getBoundingClientRect(); return {width:r.width,height:r.height,naturalWidth:im.naturalWidth,naturalHeight:im.naturalHeight,dpr:devicePixelRatio}; })()`);
        check(Math.abs(fullLogo.width / fullLogo.height - fullLogo.naturalWidth / fullLogo.naturalHeight) < 0.01, `full logo preserves aspect ratio at ${width}px DPR ${dpr}`);
        check(fullLogo.width * dpr <= fullLogo.naturalWidth && fullLogo.height * dpr <= fullLogo.naturalHeight, `full logo has sufficient source pixels at ${width}px DPR ${dpr}`);
        const compactLogo = await runtime(`(() => { const im = document.querySelector('.header-author-logo'); const r = im.getBoundingClientRect(); const brand = document.querySelector('.brand').getBoundingClientRect(); const header = document.querySelector('.help-header').getBoundingClientRect(); return {width:r.width,height:r.height,naturalWidth:im.naturalWidth,naturalHeight:im.naturalHeight,doesNotOverlap:r.left >= brand.right,withinHeader:r.right <= header.right && r.bottom <= header.bottom}; })()`);
        check(compactLogo.width > 0 && Math.abs(compactLogo.width / compactLogo.height - 425 / 422) < 0.01, `compact logo preserves aspect ratio at ${width}px DPR ${dpr}`);
        check(compactLogo.width * dpr <= compactLogo.naturalWidth, `compact logo has sufficient source pixels at ${width}px DPR ${dpr}`);
        check(compactLogo.doesNotOverlap && compactLogo.withinHeader, `author logo fits beside library identity at ${width}px DPR ${dpr}`);
        scalingEvidence.push({viewportWidth:width,dpr,fullLogo,compactLogo});
      }
    }
    fs.writeFileSync(path.join(evidence, 'branding-scaling.json'), JSON.stringify(scalingEvidence, null, 2));
    await cdp('Emulation.setDeviceMetricsOverride', {width:1440,height:1000,deviceScaleFactor:1,mobile:false}, sessionId);
    await runtime('document.body.classList.remove("menu-open")');
    await screenshot('About-desktop');
    await runtime('document.querySelector(".theme-toggle").click()');
    check(await runtime('getComputedStyle(document.querySelector(".author-logo-link")).backgroundColor === "rgb(255, 255, 255)"'), 'full wordmark retains light background in dark theme');
    await screenshot('About-dark');
    await runtime('document.querySelector(".theme-toggle").click()');
    // A short viewport with long local navigation must scroll without occupying header/footer controls.
    await cdp('Emulation.setDeviceMetricsOverride', {width:1440,height:600,deviceScaleFactor:1,mobile:false}, sessionId);
    await runtime('document.querySelector("#context-navigation").hidden=false; document.querySelector("#context-navigation").style.height="1800px"; document.querySelector(".sidebar-scroll").scrollTop=1000');
    check(await runtime('document.querySelector(".header-author-logo").getBoundingClientRect().bottom <= 78 && document.querySelector(".sidebar-scroll").scrollHeight > document.querySelector(".sidebar-scroll").clientHeight'), 'long navigation scrolls independently of header branding');
    check(await runtime('Math.abs(document.querySelector(".help-footer").getBoundingClientRect().bottom-innerHeight)<1 && document.querySelector("main").getBoundingClientRect().bottom <= document.querySelector(".help-footer").getBoundingClientRect().top'), 'footer stays at viewport bottom with a short window');
    await cdp('Emulation.setEmulatedMedia', {media:'print'}, sessionId);
    check(await runtime('getComputedStyle(document.body).overflow === "visible" && getComputedStyle(document.querySelector("main")).overflow === "visible" && getComputedStyle(document.querySelector(".help-footer")).display === "none"'), 'print layout releases scroll constraints and hides application footer');
    await cdp('Emulation.setEmulatedMedia', {media:''}, sessionId);
    check(remoteRequests.length === 0, 'offline help makes no HTTP requests');
    const report = { result: 'PASS', timestamp: new Date().toISOString(), browser: version.Browser, browserPath,
      staticChecks: checks.length, localLinksVerified: links, checks,
      offline: true, remoteRequests, scope: 'Packaged HTML opened through file:// in an isolated browser. Custom layout, navigation, full-text search, themes and local links. Five source types, two parameter lists and shared constants; complete library and native XAE views untested.' };
    fs.writeFileSync(path.join(evidence, 'verification.json'), JSON.stringify(report, null, 2) + '\r\n');
    console.log(JSON.stringify({ ...report, checks: undefined }, null, 2));
  } catch (error) { console.error(error); process.exitCode = 1; }
  finally { await session?.close(); }
})();
