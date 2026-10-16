// Small helpers shared by every screen: DOM building and number/date formats.

/** Build an element: h('div', {class: 'x', onclick: fn}, child, 'text', [more]) */
export function h(tag, props, ...children) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(props || {})) {
    if (value === undefined || value === null || value === false) continue;
    if (key === 'class') el.className = value;
    else if (key === 'style' && typeof value === 'object') Object.assign(el.style, value);
    else if (key.startsWith('on') && typeof value === 'function') el.addEventListener(key.slice(2).toLowerCase(), value);
    else if (key === 'value' || key === 'checked' || key === 'disabled' || key === 'selected' || key === 'textContent') el[key] = value;
    else el.setAttribute(key, value === true ? '' : value);
  }
  append(el, children);
  return el;
}

export function append(el, children) {
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    el.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return el;
}

/** Replace everything inside `el`. */
export function setChildren(el, ...children) {
  el.replaceChildren();
  return append(el, children);
}

// --- numbers (the shapes Version 1's intl formats produced) -----------------

const amountFormat = new Intl.NumberFormat('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const quantityFormat = new Intl.NumberFormat('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 3 });
const compactFormat = new Intl.NumberFormat('en-US', { notation: 'compact', maximumFractionDigits: 1 });

/** `#,##0.00` */
export const amount = (n) => amountFormat.format(Math.abs(n) < 0.005 ? 0 : n);
/** `#,##0.###` */
export const quantity = (n) => quantityFormat.format(n);
export const compact = (n) => compactFormat.format(n);

/** Plain decimal text for prefilling an editable field: no trailing ".00". */
export function plain(value) {
  const n = Number(value);
  return Number.isInteger(n) ? String(n) : String(parseFloat(n.toFixed(4)));
}

/** Lenient parse of what someone typed into a number box; NaN if not a number. */
export function parseNumber(text) {
  const t = String(text ?? '').trim();
  if (t === '' || !/^[-+]?(\d+\.?\d*|\.\d+)$/.test(t)) return NaN;
  return Number(t);
}

// --- dates ------------------------------------------------------------------

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const pad = (n) => String(n).padStart(2, '0');

export const toDate = (iso) => (iso instanceof Date ? iso : new Date(iso));
/** `d MMM yyyy` */
export const fmtDate = (iso) => { const d = toDate(iso); return `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`; };
/** `d MMM, HH:mm` */
export const fmtDateTime = (iso) => { const d = toDate(iso); return `${d.getDate()} ${MONTHS[d.getMonth()]}, ${pad(d.getHours())}:${pad(d.getMinutes())}`; };
/** `d MMM` */
export const fmtDayMonth = (iso) => { const d = toDate(iso); return `${d.getDate()} ${MONTHS[d.getMonth()]}`; };
/** `E` */
export const fmtWeekday = (iso) => WEEKDAYS[toDate(iso).getDay()];

// --- misc ----------------------------------------------------------------------

export function debounce(fn, ms) {
  let timer;
  return (...args) => { clearTimeout(timer); timer = setTimeout(() => fn(...args), ms); };
}

/** Keep typing position/focus when a container's contents are rebuilt. */
export function preserveFocus(container, rebuild) {
  const active = document.activeElement;
  const key = active && container.contains(active) ? active.dataset.key : null;
  const start = key ? active.selectionStart : null;
  const end = key ? active.selectionEnd : null;
  rebuild();
  if (!key) return;
  const next = container.querySelector(`[data-key="${CSS.escape(key)}"]`);
  if (!next) return;
  next.focus({ preventScroll: true });
  try { if (start !== null) next.setSelectionRange(start, end); } catch { /* not a text input */ }
}

/** Restrict a text input to characters matching `pattern` as the user types. */
export function restrictInput(input, pattern) {
  input.addEventListener('input', () => {
    const cleaned = [...input.value].filter((c) => pattern.test(c)).join('');
    if (cleaned !== input.value) input.value = cleaned;
  });
}

export function haystackMatches(query, ...parts) {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  return parts.map((p) => p ?? '').join(' ').toLowerCase().includes(q);
}
