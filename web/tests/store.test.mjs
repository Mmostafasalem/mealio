// After npm ci, install the pinned browser with:
// npx playwright install --with-deps chromium
// Run this local synthetic browser regression with npm test.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import http from "node:http";
import Module, { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import ts from "typescript";
import React from "react";
import { renderToString } from "react-dom/server";
import { chromium } from "playwright";
const require = createRequire(import.meta.url);

const storePath = fileURLToPath(new URL("../lib/store.ts", import.meta.url));
const storeCode = ts.transpileModule(fs.readFileSync(storePath, "utf8"), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2017 },
}).outputText;
const storeModule = new Module(storePath);
storeModule.filename = storePath;
storeModule.paths = Module._nodeModulePaths(path.dirname(storePath));
storeModule._compile(storeCode, storePath);

// Exercise the actual hook in React DOM, including server-to-client hydration.
function ServerProbe() {
  const [value, , loaded] = storeModule.exports.useLocalStorage("mealio.budget", 60);
  return React.createElement("output", null, JSON.stringify({ value, loaded }));
}
const serverHTML = renderToString(React.createElement(ServerProbe));
const modules = {};
// Resolve package entry points rather than relying on unexported package paths.
modules.react = fs.readFileSync(path.join(path.dirname(require.resolve("react")), "cjs/react.production.js"), "utf8");
modules["react-dom"] = fs.readFileSync(path.join(path.dirname(require.resolve("react-dom")), "cjs/react-dom.production.js"), "utf8");
modules["react-dom/client"] = fs.readFileSync(path.join(path.dirname(require.resolve("react-dom")), "cjs/react-dom-client.production.js"), "utf8");
modules.scheduler = fs.readFileSync(path.join(path.dirname(require.resolve("scheduler")), "cjs/scheduler.production.js"), "utf8");
modules.store = storeCode;

const browserCode = `
const sources = ${JSON.stringify(modules)};
const cache = {};
function require(id) {
  if (!cache[id]) {
    const module = { exports: {} };
    cache[id] = module;
    new Function('require', 'module', 'exports', sources[id])(require, module, module.exports);
  }
  return cache[id].exports;
}
const React = require('react');
const { createRoot, hydrateRoot } = require('react-dom/client');
const { useLocalStorage } = require('store');
window.probes = {};
function Probe({ id, storageKey, initial }) {
  const [value, setValue, loaded] = useLocalStorage(storageKey, initial);
  React.useLayoutEffect(() => { window.probes[id] = { value, setValue, loaded }; });
  return React.createElement('output', null, JSON.stringify({ value, loaded }));
}
const roots = {};
window.mount = (id, storageKey, initial, hydrate = false) => {
  let element = document.getElementById(id);
  if (!element) { element = document.createElement('div'); element.id = id; document.body.append(element); }
  const probe = React.createElement(React.StrictMode, null, React.createElement(Probe, { id, storageKey, initial }));
  if (hydrate) roots[id] = hydrateRoot(element, probe, { onRecoverableError: error => window.hydrationErrors.push(error.message) });
  else { roots[id] ??= createRoot(element); roots[id].render(probe); }
};
window.unmount = id => { roots[id].unmount(); delete roots[id]; delete window.probes[id]; document.getElementById(id).remove(); };
window.hydrationErrors = [];
`;

test("storage hydration, updater functions, shared hooks and storage failures", async () => {
  assert.equal(serverHTML, '<output>{&quot;value&quot;:60,&quot;loaded&quot;:false}</output>');
  const server = http.createServer((req, res) => {
    res.setHeader("Content-Type", req.url === "/test.js" ? "text/javascript" : "text/html");
    res.end(req.url === "/test.js" ? browserCode : `<div id="hydrated">${serverHTML}</div><script src="/test.js"></script>`);
  });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext();
    const page = await context.newPage();
    page.setDefaultTimeout(5000);
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    await page.goto(`http://127.0.0.1:${server.address().port}`);
    await page.evaluate(() => {
      localStorage.setItem("mealio.budget", "75");
      window.mount("hydrated", "mealio.budget", 60, true);
      window.mount("peer", "mealio.budget", 60);
    });
    await page.waitForFunction(() => window.probes.hydrated?.loaded && window.probes.peer?.loaded);
    assert.equal(await page.evaluate(() => window.probes.hydrated.value), 75);
    assert.equal(await page.evaluate(() => localStorage.getItem("mealio.budget")), "75");
    await page.evaluate(() => {
      window.probes.hydrated.setValue(value => value + 1);
      window.probes.hydrated.setValue(value => value + 1);
      window.probes.peer.setValue(value => value + 1);
    });
    await page.waitForFunction(() => window.probes.hydrated.value === 78 && window.probes.peer.value === 78);
    assert.equal(await page.evaluate(() => localStorage.getItem("mealio.budget")), "78");
    const otherPage = await page.context().newPage();
    await otherPage.goto(page.url());
    await otherPage.evaluate(() => localStorage.setItem("mealio.budget", "90"));
    await page.waitForFunction(() => window.probes.hydrated.value === 90 && window.probes.peer.value === 90);
    await otherPage.evaluate(() => localStorage.removeItem("mealio.budget"));
    await page.waitForFunction(() => window.probes.hydrated.value === 60 && window.probes.peer.value === 60);
    await page.evaluate(() => {
      localStorage.setItem("other", "12");
      window.mount("peer", "other", 60);
      localStorage.setItem("corrupt", "{broken");
      window.mount("corrupt", "corrupt", 7);
    });
    await page.waitForFunction(() => window.probes.peer.value === 12 && window.probes.peer.loaded && window.probes.corrupt?.value === 7 && window.probes.corrupt.loaded);
    assert.equal(await page.evaluate(() => localStorage.getItem("corrupt")), "{broken");
    await page.evaluate(() => {
      window.probes.peer.setValue(value => value + 1);
      window.mount("array", "array", []);
      window.mount("object", "object", null);
    });
    await page.waitForFunction(() => window.probes.peer.value === 13 && window.probes.array?.loaded && window.probes.object?.loaded);
    assert.equal(await page.evaluate(() => localStorage.getItem("other")), "13");
    assert.equal(await page.evaluate(() => localStorage.getItem("mealio.budget")), null);
    await page.evaluate(() => {
      window.probes.array.setValue(value => [...value, "a"]);
      window.probes.array.setValue(value => [...value, "b"]);
      window.probes.object.setValue({ goal: "maintain" });
    });
    await page.waitForFunction(() => window.probes.array.value.length === 2 && window.probes.object.value?.goal === "maintain");
    assert.deepEqual(await page.evaluate(() => window.probes.array.value), ["a", "b"]);
    await page.evaluate(() => {
      window.probes.object.setValue(null);
      Storage.prototype.setItem = () => { throw new DOMException("Full", "QuotaExceededError"); };
      window.probes.hydrated.setValue(value => value + 1);
      window.probes.hydrated.setValue(value => value + 1);
      window.mount("blockedPeer", "mealio.budget", 60);
    });
    await page.waitForFunction(() => window.probes.hydrated.value === 62 && window.probes.blockedPeer?.value === 62 && window.probes.object.value === null);
    await page.evaluate(() => {
      Storage.prototype.getItem = () => { throw new DOMException("Blocked", "SecurityError"); };
      window.mount("denied", "denied", 5);
    });
    await page.waitForFunction(() => window.probes.denied?.loaded && window.probes.denied.value === 5);
    await page.evaluate(() => window.probes.denied.setValue(value => value + 1));
    await page.waitForFunction(() => window.probes.denied.value === 6);
    await page.evaluate(() => window.unmount("denied"));
    assert.deepEqual(await page.evaluate(() => window.hydrationErrors), []);
    assert.deepEqual(errors, []);
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
});
