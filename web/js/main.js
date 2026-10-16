// Boot: load the session, then either show first-run setup / sign-in or hand
// over to the router. The gate wraps the whole app rather than each screen
// redirecting for itself — nothing is reachable until someone signs in.

import { currentPath, route, start, stop } from './router.js';
import { loadSession, onSessionChange } from './session.js';
import { applyTheme, state } from './store.js';
import { setupScreen, signInScreen } from './screens/auth.js';
import { routes } from './routes.js';

applyTheme();
const app = document.getElementById('app');
let routerStarted = false;

function showGate() {
  stop();
  const screen = state.isSetUp ? signInScreen() : setupScreen();
  app.replaceChildren(screen.el);
  document.title = 'Duka POS';
}

function showApp() {
  if (!routerStarted) {
    routes.forEach(([pattern, handler]) => route(pattern, handler));
    routerStarted = true;
  }
  // A fresh visit opens on Products, as Version 1 did.
  if (!currentPath() || currentPath() === '/') history.replaceState({ depth: 0 }, '', '#/products');
  start();
}

function paint() {
  if (state.user) showApp();
  else showGate();
}

// Signing in from the gate lands on the home screen (the sign-in screens set the
// path first); a "switch user" keeps whatever screen is open.
onSessionChange(paint);

try {
  await loadSession();
} catch (e) {
  app.replaceChildren(
    document.createRange().createContextualFragment(
      `<div class="center-screen"><div class="empty">Could not open the shop database: ${String(e.message).replace(/</g, '&lt;')}</div></div>`,
    ),
  );
  throw e;
}
