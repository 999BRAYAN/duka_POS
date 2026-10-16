// Application state that outlives a screen — the same things Version 1 kept in
// Riverpod providers: who is signed in, the order being built, held orders,
// and the filters each list remembers while you move between screens.

export const state = {
  user: null,
  permissions: new Set(),
  isSetUp: null,

  // The order being built on the New sale screen, shared with checkout.
  cart: [], // { productId, name, price, quantity }
  order: { discount: 0, customerId: null, paymentMethod: 'cash', amountPaid: null },
  held: [], // parked orders, in memory only (lost on refresh, as in v1)
  nextHeldId: 1,

  filters: {
    productSearch: '',
    productCategory: null,
    productLowOnly: false,
    purchaseSearch: '',
    purchaseStatus: null,
    customerSearch: '',
    reportPeriod: 'today',
  },
};

export const can = (permission) => state.permissions.has(permission);

export function setSession(payload) {
  state.user = payload.user || null;
  state.permissions = new Set(payload.permissions || []);
  state.isSetUp = payload.isSetUp;
}

// --- cart ---------------------------------------------------------------------

export const cart = {
  subtotal: () => state.cart.reduce((sum, l) => sum + l.price * l.quantity, 0),
  itemCount: () => state.cart.reduce((sum, l) => sum + l.quantity, 0),

  addProduct({ productId, name, price, quantity = 1 }) {
    const existing = state.cart.find((l) => l.productId === productId);
    if (existing) existing.quantity += quantity;
    else state.cart.push({ productId, name, price, quantity });
  },
  setQuantity(productId, quantity) {
    if (quantity <= 0) return cart.removeLine(productId);
    const line = state.cart.find((l) => l.productId === productId);
    if (line) line.quantity = quantity;
  },
  /** What this line will actually sell for. The floor still holds — the
   *  server refuses a sale below any product's minimum price. */
  setPrice(productId, price) {
    if (price < 0) return;
    const line = state.cart.find((l) => l.productId === productId);
    if (line) line.price = price;
  },
  removeLine(productId) {
    state.cart = state.cart.filter((l) => l.productId !== productId);
  },
  clear() { state.cart = []; },
  replaceAll(lines) { state.cart = lines.map((l) => ({ ...l })); },
};

export const orderTotal = () => Math.max(cart.subtotal() - state.order.discount, 0);

export function resetOrder() {
  state.order = { discount: 0, customerId: null, paymentMethod: 'cash', amountPaid: null };
}

// --- held orders -----------------------------------------------------------------

export const heldOrders = {
  hold({ customerName }) {
    const held = {
      id: state.nextHeldId++,
      heldAt: new Date(),
      cart: state.cart.map((l) => ({ ...l })),
      customerId: state.order.customerId,
      customerName,
      paymentMethod: state.order.paymentMethod,
      discount: state.order.discount,
      amountPaid: state.order.amountPaid ?? 0,
    };
    state.held.push(held);
    return held;
  },
  resume(id) {
    const held = state.held.find((h) => h.id === id);
    if (!held) return null;
    heldOrders.discard(id);
    return held;
  },
  discard(id) { state.held = state.held.filter((h) => h.id !== id); },
  subtotal: (held) => held.cart.reduce((sum, l) => sum + l.price * l.quantity, 0),
  itemCount: (held) => held.cart.reduce((sum, l) => sum + l.quantity, 0),
};

// --- theme ---------------------------------------------------------------------------

const THEME_KEY = 'duka_pos.theme_mode';

export function getThemeMode() {
  try { return localStorage.getItem(THEME_KEY) || 'system'; } catch { return 'system'; }
}

export function setThemeMode(mode) {
  try { localStorage.setItem(THEME_KEY, mode); } catch { /* private window */ }
  applyTheme();
}

export function applyTheme() {
  const mode = getThemeMode();
  const dark = mode === 'dark' || (mode === 'system' && matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.dataset.theme = dark ? 'dark' : 'light';
}

matchMedia('(prefers-color-scheme: dark)').addEventListener('change', applyTheme);

// --- backup reminder ----------------------------------------------------------------------

const BACKUP_KEY = 'duka_pos.last_backup_at';
export function lastBackupAt() {
  try { const v = localStorage.getItem(BACKUP_KEY); return v ? new Date(v) : null; } catch { return null; }
}
export function markBackedUp() {
  try { localStorage.setItem(BACKUP_KEY, new Date().toISOString()); } catch { /* ignore */ }
}
