const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { pathToFileURL } = require('node:url');
const assert = require('node:assert/strict');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

// A browser owned by this check only; never attach to the user's normal profile.
async function openBrowser({ browserPath: requestedBrowser, evidence }) {
  const candidates = requestedBrowser ? [path.resolve(requestedBrowser)] : [
    path.join(process.env.LOCALAPPDATA || '', 'Google/Chrome/Application/chrome.exe'),
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe'
  ];
  const browserPath = candidates.find(candidate => fs.existsSync(candidate));
  assert(browserPath, 'Chrome is required; use --browser <path> for another Chromium browser');
  fs.mkdirSync(evidence, { recursive: true });
  const profile = path.join(evidence, 'browser-profile-' + process.pid + '-' + Date.now());
  const browser = spawn(browserPath, ['--headless=new', '--disable-gpu', '--no-first-run',
    '--no-default-browser-check', '--remote-debugging-port=0', '--user-data-dir=' + profile, 'about:blank'],
  { windowsHide: true, stdio: 'ignore' });
  let launchError, socket, sequence = 0;
  const pending = new Map(), remoteRequests = [];
  browser.on('error', error => { launchError = error; });
  function cdp(method, params = {}) {
    const id = ++sequence;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { pending.delete(id); reject(new Error('CDP timeout: ' + method)); }, 15000);
      pending.set(id, message => { clearTimeout(timer); message.error ? reject(new Error(JSON.stringify(message.error))) : resolve(message.result); });
      socket.send(JSON.stringify({ id, method, params }));
    });
  }
  async function close() {
    if (socket?.readyState === WebSocket.OPEN) {
      try { await cdp('Browser.close'); } catch {}
      socket.close();
    }
    if (browser.exitCode === null) browser.kill();
  }
  try {
    const activePort = path.join(profile, 'DevToolsActivePort');
    for (let i = 0; i < 100 && !fs.existsSync(activePort) && !launchError; i++) await delay(100);
    if (launchError) throw launchError;
    assert(fs.existsSync(activePort), 'Isolated browser debug port available');
    const port = Number(fs.readFileSync(activePort, 'utf8').split('\n')[0]);
    const version = await (await fetch('http://127.0.0.1:' + port + '/json/version')).json();
    const targets = await (await fetch('http://127.0.0.1:' + port + '/json/list')).json();
    const target = targets.find(item => item.type === 'page');
    assert(target?.webSocketDebuggerUrl, 'Isolated browser startup page available');
    socket = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => { socket.addEventListener('open', resolve, { once: true }); socket.addEventListener('error', reject, { once: true }); });
    socket.addEventListener('message', event => {
      const message = JSON.parse(event.data);
      if (message.method === 'Network.requestWillBeSent' && /^https?:/.test(message.params.request.url)) remoteRequests.push(message.params.request.url);
      if (pending.has(message.id)) { const done = pending.get(message.id); pending.delete(message.id); done(message); }
    });
    await cdp('Page.enable'); await cdp('Runtime.enable'); await cdp('Network.enable');
    const evaluate = expression => cdp('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
      .then(result => { if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails)); return result.result.value; });
    async function navigate(file) {
      const url = pathToFileURL(file).href;
      const result = await cdp('Page.navigate', { url });
      if (result.errorText) throw new Error(result.errorText);
      for (let i = 0; i < 100; i++) {
        if (await evaluate('location.href === ' + JSON.stringify(url) + ' && document.readyState === "complete"')) return delay(100);
        await delay(100);
      }
      throw new Error('Navigation timed out: ' + file);
    }
    async function screenshot(file) {
      const metrics = await cdp('Page.getLayoutMetrics');
      const result = await cdp('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true,
        clip: { x: 0, y: 0, width: Math.ceil(metrics.cssLayoutViewport.clientWidth), height: Math.min(7000, metrics.cssContentSize.height), scale: 1 } });
      fs.writeFileSync(file, Buffer.from(result.data, 'base64'));
    }
    return { cdp, evaluate, navigate, screenshot, close, version, browserPath, remoteRequests };
  } catch (error) { await close(); throw error; }
}
module.exports = { openBrowser };
