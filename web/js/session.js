// Signing in and out, and telling the rest of the app when it changes.

import { api, setSignedOutHandler } from './api.js';
import { cart, heldOrders, resetOrder, setSession, state } from './store.js';

const listeners = new Set();
export const onSessionChange = (fn) => listeners.add(fn);
const emit = () => listeners.forEach((fn) => fn());

export async function loadSession() {
  setSession(await api.get('/api/session'));
  emit();
}

/** Called with the payload a login / setup response returns. */
export function applySession(payload) {
  setSession(payload);
  emit();
}

export async function signOut() {
  try { await api.post('/api/auth/logout'); } catch { /* already signed out */ }
  // The next person at the till shouldn't inherit this one's half-built order.
  cart.clear();
  resetOrder();
  state.held = [];
  setSession({ user: null, permissions: [], isSetUp: true });
  emit();
}

setSignedOutHandler(() => {
  if (!state.user) return;
  setSession({ user: null, permissions: [], isSetUp: true });
  emit();
});
