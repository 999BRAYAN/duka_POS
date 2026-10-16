// Reusable pieces: buttons, fields, chips, tables, dialogs, snackbar.

import { append, h, restrictInput } from './util.js';

// --- icons --------------------------------------------------------------------------------

/** A Material icon by ligature name. `outlined` picks the outlined font. */
export function icon(name, { outlined = false, size, color } = {}) {
  const el = h('span', { class: outlined ? 'mio' : 'mi', 'aria-hidden': 'true' }, name);
  if (size) el.style.fontSize = `${size}px`;
  if (color) el.style.color = color;
  return el;
}

export function iconButton({ name, outlined = false, title, onclick, disabled = false, compact = false, badge, size }) {
  const button = h(
    'button',
    { class: `icon-btn${compact ? ' compact' : ''}`, type: 'button', title, 'aria-label': title, onclick, disabled },
    icon(name, { outlined, size }),
  );
  if (badge) button.append(h('span', { class: 'badge' }, String(badge)));
  return button;
}

export function button({ label, icon: iconName, outlinedIcon = true, variant = 'filled', onclick, disabled = false, block = false, tall = false, title, type = 'button' }) {
  const el = h(
    'button',
    {
      class: ['btn', `btn-${variant}`, iconName && 'has-icon', block && 'btn-block', tall && 'btn-tall'].filter(Boolean).join(' '),
      type,
      onclick,
      disabled,
      title,
    },
    iconName && icon(iconName, { outlined: outlinedIcon }),
    h('span', { class: 'btn-label' }, label),
  );
  el.setLabel = (text) => { el.querySelector('.btn-label').textContent = text; };
  return el;
}

export function spinner(small = false) {
  return h('div', { class: `spinner${small ? ' small' : ''}`, role: 'progressbar' });
}

export const loading = () => h('div', { class: 'loading' }, spinner());

// --- fields --------------------------------------------------------------------------------

let fieldCounter = 0;

/**
 * A text box with a floating label, like Version 1's outlined fields.
 * Returns { el, input, setError(text|null), setHelper(text) }.
 */
export function field({
  label, value = '', type = 'text', helper, hint, dense = false, autofocus = false, rows, key,
  inputmode, onInput, onEnter, restrict, placeholder, leadIcon, multiline = false, autocomplete,
  className = '',
}) {
  const id = `f${++fieldCounter}`;
  const input = h(multiline ? 'textarea' : 'input', {
    id,
    type: multiline ? undefined : type,
    value,
    rows: multiline ? rows || 2 : undefined,
    placeholder: placeholder ?? (label ? ' ' : hint || ''),
    inputmode,
    autocomplete: autocomplete ?? (type === 'password' ? 'off' : undefined),
    'data-key': key,
    spellcheck: 'false',
  });
  if (restrict) restrictInput(input, restrict);
  if (onInput) input.addEventListener('input', () => onInput(input.value, input));
  if (onEnter) input.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); onEnter(input.value); } });
  if (label && hint) {
    // Flutter shows a hint only once the label has floated up.
    input.addEventListener('focus', () => { input.placeholder = hint; });
    input.addEventListener('blur', () => { input.placeholder = ' '; });
  }
  const labelEl = label ? h('label', { for: id }, label) : null;
  const helperEl = h('div', { class: helper ? 'help' : 'hidden' }, helper || '');
  const errorEl = h('div', { class: 'err hidden' });
  const el = h(
    'div',
    { class: ['field', dense && 'dense', leadIcon && 'has-lead', className].filter(Boolean).join(' ') },
    leadIcon && h('span', { class: 'lead' }, icon(leadIcon, { outlined: true, size: 20 })),
    input,
    labelEl,
    helperEl,
    errorEl,
  );
  if (autofocus) queueMicrotask(() => setTimeout(() => input.focus(), 30));
  return {
    el,
    input,
    get value() { return input.value; },
    set value(v) { input.value = v; },
    setError(text) {
      errorEl.textContent = text || '';
      errorEl.classList.toggle('hidden', !text);
      helperEl.classList.toggle('hidden', !!text || !helper);
      el.classList.toggle('invalid', !!text);
    },
    setHelper(text) {
      helperEl.textContent = text || '';
      helperEl.classList.toggle('hidden', !text);
    },
    append(node) { el.append(node); return this; },
  };
}

/** A dropdown. `options` is [{ value, label }]; values may be null/number/string. */
export function selectField({ label, options, value = null, onChange, dense = false, key, className = '' }) {
  const id = `f${++fieldCounter}`;
  const select = h('select', { id, 'data-key': key });
  let current = value;
  const render = (opts) => {
    select.replaceChildren(...opts.map((o, i) => h('option', { value: String(i) }, o.label)));
    const index = opts.findIndex((o) => o.value === current);
    select.value = String(index === -1 ? 0 : index);
  };
  let list = options;
  render(list);
  select.addEventListener('change', () => {
    current = list[Number(select.value)].value;
    onChange?.(current);
  });
  const el = h(
    'div',
    { class: ['field', dense && 'dense', className].filter(Boolean).join(' ') },
    select,
    label && h('label', { for: id }, label),
  );
  return {
    el,
    select,
    get value() { return current; },
    set value(v) {
      current = v;
      const index = list.findIndex((o) => o.value === v);
      select.value = String(index === -1 ? 0 : index);
    },
    setOptions(opts, nextValue = current) {
      list = opts;
      current = nextValue;
      render(list);
    },
  };
}

export function chip({ label, selected = false, onclick, check = false }) {
  const el = h('button', { class: 'chip', type: 'button', 'aria-pressed': String(selected), onclick });
  const paint = (on) => {
    el.setAttribute('aria-pressed', String(on));
    el.replaceChildren(...(check && on ? [icon('check')] : []), document.createTextNode(label));
  };
  paint(selected);
  el.setSelected = paint;
  return el;
}

// --- tables ---------------------------------------------------------------------------------------

/**
 * columns: [{ label, num }]; rows: [{ cells: [Node|string], tint: 'warn'|'debt'|'off', onclick }]
 */
export function dataTable({ columns, rows, tall = false, className = '' }) {
  const head = h('tr', {}, columns.map((c) => h('th', { class: c.num ? 'num' : '' }, c.label)));
  const body = rows.map((row) =>
    h(
      'tr',
      { class: row.tint ? `tint-${row.tint}` : '', onclick: row.onclick },
      row.cells.map((cell, i) => h('td', { class: columns[i]?.num ? 'num' : '' }, cell)),
    ),
  );
  return h('table', { class: `data${tall ? ' tall' : ''} ${className}`.trim() }, h('thead', {}, head), h('tbody', {}, body));
}

/** A card holding a table that scrolls sideways when it must. */
export function tableCard(table, { className = '', fill = false } = {}) {
  return h('div', { class: `card clip${fill ? ' fill-card' : ''} ${className}`.trim() }, h('div', { class: 'table-scroll' }, table));
}

// --- dialogs ---------------------------------------------------------------------------------------------

const dialogStack = [];

/**
 * Opens a modal. `actions` is [{ label, variant, value, primary, onclick }]; an action's `onclick`
 * may return false to keep the dialog open. Resolves with the pressed action's `value`
 * (undefined if dismissed).
 */
export function openDialog({ title, iconName, iconColor, body, actions = [], dismissible = true, centered = false, width }) {
  let resolve;
  const result = new Promise((r) => { resolve = r; });
  const actionButtons = actions.map((a) =>
    button({
      label: a.label,
      variant: a.variant || 'text',
      icon: a.icon,
      disabled: a.disabled,
      onclick: async () => {
        if (a.onclick) {
          const keep = await a.onclick(api);
          if (keep === false) return;
        }
        api.close(a.value);
      },
    }),
  );
  const dialog = h(
    'div',
    { class: `dialog${centered ? ' centered' : ''}`, role: 'dialog', 'aria-modal': 'true', style: width ? { width: `${width}px` } : undefined },
    iconName && h('div', { class: 'd-icon' }, icon(iconName, { color: iconColor })),
    title && h('h2', {}, title),
    h('div', { class: 'd-body' }, body),
    actions.length > 0 && h('div', { class: 'd-actions' }, actionButtons),
  );
  const scrim = h('div', { class: 'scrim' }, dialog);
  if (dismissible) scrim.addEventListener('mousedown', (e) => { if (e.target === scrim) api.close(undefined); });

  const api = {
    el: dialog,
    buttons: actionButtons,
    result,
    close(value) {
      const index = dialogStack.indexOf(api);
      if (index !== -1) dialogStack.splice(index, 1);
      scrim.remove();
      resolve(value);
    },
  };
  api.dismissible = dismissible;
  dialogStack.push(api);
  document.body.append(scrim);
  return api;
}

document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  const top = dialogStack[dialogStack.length - 1];
  if (top?.dismissible) top.close(undefined);
});

export const dialogIsOpen = () => dialogStack.length > 0;

/** Cancel / confirm. Resolves true or false. */
export async function confirmDialog({ title, message, confirmLabel = 'OK', cancelLabel = 'Cancel', danger = false }) {
  const d = openDialog({
    title,
    body: h('p', {}, message),
    actions: [
      { label: cancelLabel, variant: 'text', value: false },
      { label: confirmLabel, variant: 'filled', value: true },
    ],
  });
  return (await d.result) === true;
}

// --- snackbar -----------------------------------------------------------------------------------------------

let snackTimer;
export function snackbar(message) {
  document.querySelector('.snackbar')?.remove();
  clearTimeout(snackTimer);
  const bar = h('div', { class: 'snackbar', role: 'status' }, message);
  document.body.append(bar);
  snackTimer = setTimeout(() => bar.remove(), 4000);
}

// --- misc blocks ----------------------------------------------------------------------------------------------------

export function card(props, ...children) {
  return h('div', { ...props, class: `card ${props?.class || ''}`.trim() }, ...children);
}

export function emptyNote(text) {
  return h('div', { class: 'empty' }, text);
}

export function errorBox(text) {
  return h('div', { class: 'error-text' }, text);
}

export { append };
