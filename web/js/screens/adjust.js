// Manual stock corrections: breakage, spoilage, theft, and the miscounts that
// turn up when someone actually counts the shelf. Every correction demands a
// reason, because the reason is the only record of what happened to the goods.

import { api } from '../api.js';
import { scaffold } from '../scaffold.js';
import { can } from '../store.js';
import { button, dataTable, emptyNote, field, loading, selectField, snackbar } from '../ui.js';
import { fmtDateTime, h, parseNumber, quantity } from '../util.js';

export async function stockAdjustmentScreen() {
  const sc = scaffold({ title: 'Stock adjustments', destination: 'adjust' });

  if (!can('adjustStock')) {
    sc.content.append(emptyNote('Only a manager can correct stock counts.'));
    return { el: sc.el };
  }

  let products = [];
  let productId = null;

  const productSelect = selectField({ label: 'Product', options: [{ value: null, label: '' }], onChange: (v) => { productId = v; updateHelper(); } });
  const change = field({ label: 'Change', inputmode: 'decimal', restrict: /[0-9.\-]/, helper: 'Negative removes stock, positive adds it.' });
  const reason = field({ label: 'Reason', hint: 'e.g. 3 lengths cracked in the store', onEnter: () => submit() });
  const error = h('div', { class: 'error-text hidden', style: { marginTop: '12px' } });
  const submitButton = button({ label: 'Record correction', variant: 'filled', block: true, onclick: () => submit() });
  let busy = false;
  const fail = (text) => { error.textContent = text; error.classList.remove('hidden'); };

  const selected = () => products.find((p) => p.id === productId);
  function updateHelper() {
    const p = selected();
    change.setHelper(p ? `e.g. -3 for three broken. On hand: ${quantity(p.stock)} ${p.unit}` : 'Negative removes stock, positive adds it.');
  }

  const form = h('div', { class: 'card card-pad' },
    h('div', { style: { fontSize: '16px', fontWeight: 500 } }, 'Correct a stock count'),
    h('div', { class: 'muted', style: { fontSize: '12px', margin: '4px 0 16px' } }, 'For breakage, spoilage, theft or a miscount.'),
    h('div', { class: 'stack-12' }, productSelect.el, change.el, reason.el),
    error,
    h('div', { style: { marginTop: '16px' } }, submitButton));

  const history = h('div');
  history.append(loading());
  sc.content.append(h('div', { class: 'split-900 wide-form' }, form, history));

  async function load() {
    let movements;
    try {
      [products, movements] = await Promise.all([
        api.get('/api/products').then((r) => r.products),
        api.get('/api/stock/movements').then((r) => r.movements),
      ]);
    } catch (e) {
      history.replaceChildren(emptyNote(`Could not load corrections: ${e.message}`));
      return;
    }
    if (!products.some((p) => p.id === productId)) productId = null;
    productSelect.setOptions(
      [{ value: null, label: '' }, ...products.map((p) => ({ value: p.id, label: `${p.name} — ${quantity(p.stock)} ${p.unit}` }))],
      productId,
    );
    updateHelper();

    const adjustments = movements.filter((m) => m.type === 'ADJUSTMENT');
    if (adjustments.length === 0) {
      history.replaceChildren(h('div', { class: 'card empty' }, 'No corrections recorded yet.'));
      return;
    }
    const nameById = new Map(products.map((p) => [p.id, p.name]));
    history.replaceChildren(
      h('div', { class: 'card clip' },
        h('div', { class: 'table-scroll' },
          dataTable({
            columns: [{ label: 'When' }, { label: 'Product' }, { label: 'Change', num: true }, { label: 'Reason' }],
            rows: adjustments.map((m) => ({
              cells: [
                fmtDateTime(m.createdAt),
                nameById.get(m.productId) ?? '—',
                h('span', { style: { fontWeight: 600, color: m.quantity < 0 ? 'var(--debt)' : 'var(--positive)' } },
                  `${m.quantity > 0 ? '+' : ''}${quantity(m.quantity)}`),
                m.notes ?? '—',
              ],
            })),
          }))),
    );
  }

  async function submit() {
    if (busy) return;
    const product = selected();
    if (!product) return fail('Choose the product being corrected.');
    const delta = parseNumber(change.value);
    if (Number.isNaN(delta) || delta === 0) return fail('Enter how much to add or remove.');
    if (product.stock + delta < 0) {
      return fail(`That would take ${product.name} below zero. It has ${quantity(product.stock)} on hand.`);
    }
    busy = true;
    error.classList.add('hidden');
    submitButton.disabled = true;
    submitButton.setLabel('Saving…');
    try {
      await api.post('/api/stock/adjustments', { productId: product.id, quantityChange: delta, reason: reason.value });
      change.value = '';
      reason.value = '';
      snackbar(`${product.name} corrected.`);
      await load();
    } catch (e) {
      fail(['unauthorized', 'missing_adjustment_reason'].includes(e.code) ? e.message : `Could not record the correction: ${e.message}`);
    } finally {
      busy = false;
      submitButton.disabled = false;
      submitButton.setLabel('Record correction');
    }
  }

  await load();
  return { el: sc.el, refresh: load };
}
