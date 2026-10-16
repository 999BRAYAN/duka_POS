// What the shop spends that isn't stock: rent, transport, power, licences.
// Without this the profit & loss report's Expenses line is always zero and net
// profit is overstated by the shop's entire cost base.

import { api } from '../api.js';
import { scaffold } from '../scaffold.js';
import { can } from '../store.js';
import { button, dataTable, emptyNote, field, loading, selectField, snackbar } from '../ui.js';
import { amount, fmtDate, h, parseNumber } from '../util.js';

// The recurring costs of a small shop. Free text is still allowed elsewhere,
// since no fixed list survives contact with a real business.
const COMMON_CATEGORIES = ['Rent', 'Transport', 'Utilities', 'Wages', 'Licences', 'Repairs', 'Other'];

export async function expensesScreen() {
  const canManage = can('manageExpenses');
  const sc = scaffold({ title: 'Expenses', destination: 'expenses' });

  if (!canManage) {
    sc.content.append(emptyNote('Only a manager can record shop expenses.'));
    return { el: sc.el };
  }

  let category = 'Rent';
  const amountField = field({ label: 'Amount', inputmode: 'decimal', restrict: /[0-9.]/ });
  const description = field({
    label: 'What was it for?', hint: 'e.g. matatu fare to the wholesaler', onEnter: () => submit(),
  });
  const categorySelect = selectField({
    label: 'Category',
    options: COMMON_CATEGORIES.map((c) => ({ value: c, label: c })),
    value: 'Rent',
    onChange: (v) => { category = v ?? 'Other'; },
  });
  const error = h('div', { class: 'error-text hidden', style: { marginTop: '12px' } });
  const submitButton = button({ label: 'Record expense', variant: 'filled', block: true, onclick: () => submit() });
  let busy = false;
  const fail = (text) => { error.textContent = text; error.classList.remove('hidden'); };

  const form = h('div', { class: 'card card-pad' },
    h('div', { style: { fontSize: '16px', fontWeight: 500, marginBottom: '16px' } }, 'Record an expense'),
    h('div', { class: 'stack-12' }, categorySelect.el, amountField.el, description.el),
    error,
    h('div', { style: { marginTop: '16px' } }, submitButton));

  const list = h('div');
  list.append(loading());
  sc.content.append(h('div', { class: 'split-900' }, form, list));

  async function load() {
    let expenses;
    try {
      expenses = (await api.get('/api/expenses')).expenses;
    } catch (e) {
      list.replaceChildren(emptyNote(`Could not load expenses: ${e.message}`));
      return;
    }
    if (expenses.length === 0) {
      list.replaceChildren(
        h('div', { class: 'card empty', style: { whiteSpace: 'pre-line' } },
          'No expenses recorded yet.\nRent, transport and power belong here — they come off your profit.'),
      );
      return;
    }
    const total = expenses.reduce((sum, e) => sum + e.amount, 0);
    list.replaceChildren(
      h('div', { class: 'card clip' },
        h('div', { style: { display: 'flex', justifyContent: 'space-between', padding: '12px 16px' } },
          h('span', { style: { fontWeight: 600 } }, 'All expenses'),
          h('span', { style: { fontWeight: 700 } }, amount(total))),
        h('div', { class: 'table-scroll', style: { borderTop: '1px solid var(--line)' } },
          dataTable({
            columns: [{ label: 'Date' }, { label: 'Category' }, { label: 'Description' }, { label: 'Amount', num: true }],
            rows: expenses.map((e) => ({ cells: [fmtDate(e.createdAt), e.category, e.description, amount(e.amount)] })),
          }))),
    );
  }

  async function submit() {
    if (busy) return;
    const value = parseNumber(amountField.value);
    if (Number.isNaN(value) || value <= 0) return fail('Enter how much was spent.');
    if (!description.value.trim()) return fail('Say what the money was for.');
    busy = true;
    error.classList.add('hidden');
    submitButton.disabled = true;
    submitButton.setLabel('Saving…');
    try {
      await api.post('/api/expenses', { category, description: description.value.trim(), amount: value });
      description.value = '';
      amountField.value = '';
      snackbar('Expense recorded.');
      await load();
    } catch (e) {
      fail(e.code === 'unauthorized' ? e.message : `Could not record the expense: ${e.message}`);
    } finally {
      busy = false;
      submitButton.disabled = false;
      submitButton.setLabel('Record expense');
    }
  }

  await load();
  return { el: sc.el, refresh: load };
}
