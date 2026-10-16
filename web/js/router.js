// A tiny history-API router. Screens that Version 1 reached with
// Navigator.push are pushed here too (so the browser Back button pops them);
// the drawer replaces, as v1's pushReplacement did.

import { dialogIsOpen } from './ui.js';

const routes = [];
let current = null;
let pollTimer = null;
let depth = 0;
let enabled = false; // nothing renders until someone is signed in and the app has started

/** route('/products/:uuid/edit', (params) => page) — handler returns { el, destroy?, refresh? } */
export function route(pattern, handler) {
  const keys = [];
  const regex = new RegExp(
    '^' + pattern.replace(/:([a-zA-Z]+)/g, (_, key) => { keys.push(key); return '([^/]+)'; }) + '$',
  );
  routes.push({ regex, keys, handler });
}

const here = () => (location.hash.startsWith('#') ? location.hash.slice(1) : '') || '/';

export function navigate(path) {
  if (!enabled) return;
  depth += 1;
  history.pushState({ depth }, '', '#' + path);
  render();
}

export function replace(path) {
  history.replaceState({ depth }, '', '#' + path);
  if (enabled) render();
}

/** Navigator.pop(): back if there is somewhere in-app to go back to. */
export function goBack(fallback = '/products') {
  if (depth > 0) history.back();
  else replace(fallback);
}

window.addEventListener('popstate', (e) => {
  depth = e.state?.depth ?? 0;
  if (enabled) render();
});

export function start() {
  enabled = true;
  depth = history.state?.depth ?? 0;
  render();
}

export function currentPath() { return here(); }

/** Tears down the current screen without rendering another (used on sign-out). */
export function stop() {
  enabled = false;
  teardown();
}

function teardown() {
  clearInterval(pollTimer);
  pollTimer = null;
  current?.destroy?.();
  current = null;
}

async function render() {
  const path = here();
  const app = document.getElementById('app');
  teardown();

  let match = null;
  let params = {};
  for (const r of routes) {
    const m = r.regex.exec(path);
    if (m) {
      match = r;
      params = Object.fromEntries(r.keys.map((k, i) => [k, decodeURIComponent(m[i + 1])]));
      break;
    }
  }
  if (!match) {
    if (path !== '/products') replace('/products'); // an unknown path falls back to home
    return;
  }

  const token = Symbol();
  render.token = token;
  const page = await match.handler(params);
  if (render.token !== token) { page?.destroy?.(); return; } // navigated away while loading

  current = page;
  app.replaceChildren(page.el);
  window.scrollTo(0, 0);
  if (page.refresh) {
    pollTimer = setInterval(() => {
      // Pick up changes made at other tills, but never while someone is
      // typing into a dialog or the tab is in the background.
      if (document.hidden || dialogIsOpen()) return;
      page.refresh();
    }, 10_000);
  }
}
