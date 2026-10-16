// Goods coming in: the purchases list, the receive-stock form, and paying a
// supplier off afterwards.

import { api } from '../api.js';
import { goBack, navigate } from '../router.js';
import { scaffold } from '../scaffold.js';
import { can, state } from '../store.js';
import {
  button, dataTable, emptyNote, field, icon, iconButton, loading, openDialog, selectField, snackbar, tableCard,
} from '../ui.js';
import { amount, fmtDate, h, haystackMatches, parseNumber, plain } from '../util.js';

const PAYMENT_LABELS = { paid: 'Paid', partial: 'Partially paid', unpaid: 'Credit' };
const label = (status) => PAYMENT_LABELS[status] ?? status;

export function paymentStatusChip(status) {
  const cls = { paid: 'status-ok', partial: 'status-warn', unpaid: 'status-bad' }[status] ?? 'status-neutral';
  return h('span', { class: `status-chip ${cls}` }, label(status));
}

// --- list ------------------------------------------------------------------------------

export async function purchaseListScreen() {
  const canReceive = can('receiveStock');
  const sc = scaffold({
    title: 'Purchases',
    destination: 'purchases',
    noScroll: true,
    actions: [button({ label: 'Receive stock', icon: 'add', outlinedIcon: false, onclick: () => navigate('/purchases/receive') })],
  });

  let purchases = [];
  let suppliers = [];
  const f = state.filters;

  const search = field({
    placeholder: 'Search by PO reference or supplier', dense: true, leadIcon: 'search', value: f.purchaseSearch,
    onInput: (v) => { f.purchaseSearch = v; paint(); },
  });
  search.el.style.width = '320px';
  const status = selectField({
    dense: true, value: f.purchaseStatus,
    options: [{ value: null, label: 'All statuses' }, ...['paid', 'partial', 'unpaid'].map((s) => ({ value: s, label: label(s) }))],
    onChange: (v) => { f.purchaseStatus = v; paint(); },
  });
  status.el.style.width = '220px';

  const results = h('div', { style: { flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' } });
  sc.content.append(h('div', { class: 'fill-col', style: { gap: '16px' } }, h('div', { class: 'wrap' }, search.el, status.el), results));
  results.append(loading());

  function paint() {
    const supplierName = new Map(suppliers.map((s) => [s.id, s.name]));
    const rows = purchases.filter((p) => {
      if (f.purchaseStatus !== null && p.paymentStatus !== f.purchaseStatus) return false;
      return haystackMatches(f.purchaseSearch, p.referenceNumber, supplierName.get(p.supplierId));
    });
    if (rows.length === 0) {
      results.replaceChildren(emptyNote('No purchases match your filters.'));
      return;
    }
    results.replaceChildren(
      tableCard(
        dataTable({
          columns: [
            { label: 'PO Reference' }, { label: 'Supplier' }, { label: 'Date' }, { label: 'Total', num: true },
            { label: 'Amount Paid', num: true }, { label: 'Status' }, ...(canReceive ? [{ label: '' }] : []),
          ],
          rows: rows.map((p) => {
            // Only a received purchase carries a real debt to settle, and only
            // when something is still owed.
            const canPay = canReceive && p.status === 'received' && p.paymentStatus !== 'paid';
            return {
              cells: [
                p.referenceNumber ?? '—',
                supplierName.get(p.supplierId) ?? '—',
                fmtDate(p.createdAt),
                amount(p.total),
                amount(p.amountPaid),
                paymentStatusChip(p.paymentStatus),
                ...(canReceive
                  ? [canPay ? button({ label: 'Record payment', variant: 'text', onclick: async () => { if (await showRecordPaymentDialog(p)) load(); } }) : '']
                  : []),
              ],
            };
          }),
        }),
        { fill: true },
      ),
    );
  }

  async function load() {
    try {
      [purchases, suppliers] = await Promise.all([
        api.get('/api/purchases').then((r) => r.purchases),
        api.get('/api/suppliers').then((r) => r.suppliers),
      ]);
    } catch (e) {
      results.replaceChildren(emptyNote(`Failed to load purchases: ${e.message}`));
      return;
    }
    paint();
  }
  await load();
  return { el: sc.el, refresh: load };
}

// --- record a payment against a purchase on credit ------------------------------------------

/** The only way to move a credit purchase toward 'paid' after stock has come in. */
export function showRecordPaymentDialog(purchase) {
  const outstanding = purchase.total - purchase.amountPaid;
  // Defaults to paying it off in full — the common case — while staying
  // editable for a partial top-up.
  const amountField = field({ label: 'Amount paid', value: outstanding.toFixed(2), inputmode: 'decimal', autofocus: true, onEnter: () => submit() });
  const error = h('div', { class: 'error-text hidden', style: { marginTop: '12px' } });
  let busy = false;

  const dialog = openDialog({
    title: `Record payment — ${purchase.referenceNumber ?? 'purchase'}`,
    width: 380,
    body: h('div', {},
      h('div', { class: 'muted', style: { fontSize: '12px', marginBottom: '16px' } },
        `${amount(outstanding)} owed of ${amount(purchase.total)} total.`),
      amountField.el, error),
    actions: [
      { label: 'Cancel', variant: 'text', value: false },
      { label: 'Record payment', variant: 'filled', onclick: () => { submit(); return false; } },
    ],
  });
  const fail = (text) => { error.textContent = text; error.classList.remove('hidden'); };

  async function submit() {
    if (busy) return;
    const value = parseNumber(amountField.value);
    if (Number.isNaN(value) || value <= 0) return fail('Enter an amount greater than zero.');
    if (value > outstanding + 0.00005) return fail(`Only ${amount(outstanding)} is owed on this purchase.`);
    busy = true;
    error.classList.add('hidden');
    try {
      await api.post(`/api/purchases/${purchase.uuid}/payments`, { amount: value });
      dialog.close(true);
    } catch (e) {
      fail(e.code === 'unauthorized' ? "You don't have permission to record this payment." : `Could not record this payment: ${e.message}`);
    } finally {
      busy = false;
    }
  }
  return dialog.result;
}

// --- receive stock ---------------------------------------------------------------------------

/**
 * A type-ahead product picker: a hardware catalog runs to hundreds of
 * near-identical fittings, and typing "elb 1" beats scrolling for it.
 * Matches on name, SKU and barcode, since the code on the box is often what's
 * to hand.
 */
function productLookup(products, onSelect, onClear) {
  const input = field({ label: 'Product', hint: 'Type a name or SKU', dense: true });
  const list = h('div', { class: 'ac-list hidden' });
  const wrap = h('div', { class: 'ac' }, input.el, list);
  const clear = iconButton({ name: 'clear', title: 'Clear', size: 16, compact: true, onclick: () => { input.value = ''; onClear(); show(); input.input.focus(); } });
  const searchIcon = h('span', { class: 'affix', style: { top: '10px', right: '10px', pointerEvents: 'none', color: 'var(--muted)' } }, icon('search', { size: 18 }));
  input.el.append(searchIcon, clear);
  clear.classList.add('affix', 'hidden');

  let active = 0;
  let options = [];

  function show() {
    const query = input.value.trim().toLowerCase();
    options = (query === '' ? products : products.filter((p) => haystackMatches(query, p.name, p.sku, p.barcode))).slice(0, 12);
    clear.classList.toggle('hidden', input.value === '');
    searchIcon.classList.toggle('hidden', input.value !== '');
    active = 0;
    if (options.length === 0) { list.classList.add('hidden'); return; }
    list.classList.remove('hidden');
    list.replaceChildren(
      ...options.map((p, i) =>
        h('div', { class: `ac-item${i === active ? ' active' : ''}`, onmousedown: (e) => { e.preventDefault(); choose(p); } },
          h('div', { class: 't' }, p.name),
          h('div', { class: 's' }, `${p.sku ?? 'no SKU'} · ${Number(p.stock).toFixed(0)} ${p.unit} on hand`)),
      ),
    );
  }

  function choose(product) {
    input.value = product.name;
    list.classList.add('hidden');
    clear.classList.remove('hidden');
    searchIcon.classList.add('hidden');
    onSelect(product);
  }

  input.input.addEventListener('focus', show);
  input.input.addEventListener('input', show);
  input.input.addEventListener('blur', () => list.classList.add('hidden'));
  input.input.addEventListener('keydown', (e) => {
    if (list.classList.contains('hidden')) return;
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      active = (active + (e.key === 'ArrowDown' ? 1 : -1) + options.length) % options.length;
      [...list.children].forEach((c, i) => c.classList.toggle('active', i === active));
    } else if (e.key === 'Enter') {
      e.preventDefault();
      choose(options[active]);
    }
  });
  return wrap;
}

export async function receiveStockScreen() {
  const sc = scaffold({ title: 'Receive stock', backTo: '/purchases' });

  let suppliers = [];
  let products = [];
  try {
    [suppliers, products] = await Promise.all([
      api.get('/api/suppliers').then((r) => r.suppliers),
      api.get('/api/products').then((r) => r.products),
    ]);
  } catch (e) {
    sc.content.append(emptyNote(`Could not load suppliers and products: ${e.message}`));
    return { el: sc.el };
  }

  let supplierId = null;
  let paymentStatus = 'paid';
  let lineSeq = 0;
  const lines = [];
  let busy = false;

  const totalEl = h('div', { style: { textAlign: 'right', fontSize: '16px', fontWeight: 700 } });
  const linesBox = h('div');
  const error = h('div', { class: 'error-text hidden', style: { marginTop: '16px' } });
  const paid = field({ label: 'Amount paid', inputmode: 'decimal' });
  paid.el.classList.add('hidden');

  const total = () => lines.reduce((sum, l) => sum + l.quantity() * l.unitCost(), 0);
  const refreshTotal = () => { totalEl.textContent = `Total: ${amount(total())}`; };

  function addLine() {
    const line = { id: ++lineSeq, productId: null };
    const qty = field({ label: 'Qty', value: '1', dense: true, inputmode: 'decimal', onInput: update });
    const cost = field({ label: 'Unit cost', dense: true, inputmode: 'decimal', onInput: update });
    const lineTotal = h('div', { style: { textAlign: 'right', fontWeight: 600, paddingTop: '8px' } });
    line.quantity = () => parseNumber(qty.value) || 0;
    line.unitCost = () => parseNumber(cost.value) || 0;
    const lookup = productLookup(
      products,
      (product) => {
        line.productId = product.id;
        // A starting point, not a lock-in: this purchase's actual unit cost can
        // differ from the product's last-known one, so the field stays editable.
        cost.value = plain(product.costPrice);
        update();
      },
      () => { line.productId = null; },
    );
    const removeButton = iconButton({
      name: 'close', title: 'Remove line', size: 18,
      onclick: () => { lines.splice(lines.indexOf(line), 1); line.row.remove(); syncRemovable(); refreshTotal(); },
    });
    line.removeButton = removeButton;
    function update() { lineTotal.textContent = amount(line.quantity() * line.unitCost()); refreshTotal(); }
    update();
    line.row = h('div', { style: { display: 'flex', gap: '10px', alignItems: 'flex-start', marginBottom: '10px' } },
      h('div', { style: { flex: 4, minWidth: 0 } }, lookup),
      h('div', { style: { flex: 2, minWidth: 0 } }, qty.el),
      h('div', { style: { flex: 2, minWidth: 0 } }, cost.el),
      h('div', { style: { flex: 2, minWidth: 0 } }, lineTotal),
      removeButton);
    lines.push(line);
    linesBox.append(line.row);
    syncRemovable();
  }
  function syncRemovable() { lines.forEach((l) => { l.removeButton.disabled = lines.length === 1; }); }

  let supplierControl;
  if (suppliers.length === 0) {
    supplierControl = h('div', { class: 'field' },
      h('input', { disabled: true, value: '—' }),
      h('label', { style: { top: '-9px', fontSize: '12px', background: 'var(--field-fill)' } }, 'Supplier'),
      h('div', { class: 'help' }, 'No suppliers yet — add one before receiving stock.'));
  } else {
    supplierControl = selectField({
      label: 'Supplier',
      options: [{ value: null, label: '' }, ...suppliers.map((s) => ({ value: s.id, label: s.name }))],
      onChange: (v) => { supplierId = v; },
    }).el;
  }

  const statusSelect = selectField({
    label: 'Payment status',
    options: [{ value: 'paid', label: 'Paid' }, { value: 'partial', label: 'Partially paid' }, { value: 'unpaid', label: 'Credit' }],
    value: 'paid',
    onChange: (v) => { paymentStatus = v; paid.el.classList.toggle('hidden', v !== 'partial'); },
  });

  const submitButton = button({ label: 'Receive stock', variant: 'filled', block: true, onclick: () => submit() });
  const fail = (text) => { error.textContent = text; error.classList.remove('hidden'); };

  async function submit() {
    if (busy) return;
    const valid = lines.filter((l) => l.productId !== null && l.quantity() > 0);
    if (supplierId === null) return fail('Select a supplier.');
    if (valid.length === 0) return fail('Add at least one line item with a product and quantity.');

    const orderTotal = valid.reduce((sum, l) => sum + l.quantity() * l.unitCost(), 0);
    const amountPaid = paymentStatus === 'paid' ? orderTotal : paymentStatus === 'unpaid' ? 0 : parseNumber(paid.value) || 0;

    busy = true;
    error.classList.add('hidden');
    submitButton.disabled = true;
    try {
      await api.post('/api/purchases', {
        supplierId,
        items: valid.map((l) => ({ productId: l.productId, quantity: l.quantity(), unitCost: l.unitCost() })),
        paymentStatus,
        amountPaid,
      });
      snackbar('Stock received.');
      goBack('/purchases');
    } catch (e) {
      fail(e.code === 'unauthorized' ? "You don't have permission to receive stock." : `Could not save this receipt: ${e.message}`);
    } finally {
      busy = false;
      submitButton.disabled = false;
    }
  }

  addLine();
  refreshTotal();
  sc.content.append(
    h('div', { style: { maxWidth: '760px', margin: '0 auto' } },
      supplierControl,
      h('div', { style: { fontSize: '16px', fontWeight: 500, margin: '20px 0 8px' } }, 'Line items'),
      linesBox,
      button({ label: 'Add line', icon: 'add', outlinedIcon: false, variant: 'text', onclick: addLine }),
      h('div', { style: { margin: '12px 0 20px' } }, totalEl),
      h('div', { class: 'row' }, statusSelect.el, paid.el),
      error,
      h('div', { style: { marginTop: '24px' } }, submitButton)),
  );
  return { el: sc.el };
}
