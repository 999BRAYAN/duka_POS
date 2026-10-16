// Customers, their credit statement, and taking a payment against their tab.

import { api } from '../api.js';
import { goBack, navigate } from '../router.js';
import { scaffold } from '../scaffold.js';
import { state } from '../store.js';
import {
  button, dataTable, emptyNote, field, iconButton, loading, selectField, snackbar, tableCard,
} from '../ui.js';
import { amount, fmtDate, h, haystackMatches, parseNumber } from '../util.js';

// --- list ------------------------------------------------------------------------------

export async function customerListScreen() {
  const sc = scaffold({
    title: 'Customers',
    destination: 'customers',
    noScroll: true,
    actions: [button({ label: 'Add customer', icon: 'person_add_alt_1', outlinedIcon: false, onclick: () => navigate('/customers/new') })],
  });

  let customers = [];
  const f = state.filters;
  const search = field({
    placeholder: 'Search by name or phone', dense: true, leadIcon: 'search', value: f.customerSearch,
    onInput: (v) => { f.customerSearch = v; paint(); },
  });
  search.el.style.width = '320px';
  const results = h('div', { style: { flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' } });
  sc.content.append(h('div', { class: 'fill-col', style: { gap: '16px' } }, search.el, results));
  results.append(loading());

  function paint() {
    const rows = customers.filter((c) => haystackMatches(f.customerSearch, c.name, c.phone));
    if (rows.length === 0) {
      results.replaceChildren(emptyNote('No customers match your search.'));
      return;
    }
    results.replaceChildren(
      tableCard(
        dataTable({
          columns: [
            { label: 'Name' }, { label: 'Phone' }, { label: 'Credit Limit', num: true }, { label: 'Balance', num: true }, { label: '' },
          ],
          rows: rows.map((c) => {
            const owes = c.currentBalance > 0;
            return {
              tint: owes ? 'debt' : undefined,
              cells: [
                h('span', { class: 'cell-row' }, c.name, c.isWalkIn && h('span', { class: 'tag' }, 'Walk-in')),
                c.phone ?? '—',
                amount(c.creditLimit),
                h('span', { style: owes ? { color: 'var(--debt)', fontWeight: 600 } : undefined }, amount(c.currentBalance)),
                h('span', { class: 'cell-row' },
                  iconButton({ name: 'receipt_long', outlined: true, title: 'Statement', size: 20, onclick: () => navigate(`/customers/${c.id}/statement`) }),
                  iconButton({
                    name: 'payments', outlined: true, size: 20,
                    title: c.isWalkIn ? 'The walk-in customer never carries a balance to pay down.' : 'Receive payment',
                    disabled: c.isWalkIn,
                    onclick: () => navigate(`/customers/${c.id}/payment`),
                  })),
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
      customers = (await api.get('/api/customers')).customers;
    } catch (e) {
      results.replaceChildren(emptyNote(`Failed to load customers: ${e.message}`));
      return;
    }
    paint();
  }
  await load();
  return { el: sc.el, refresh: load };
}

// --- add customer ------------------------------------------------------------------------------

export async function customerFormScreen() {
  const sc = scaffold({ title: 'Add customer', backTo: '/customers' });
  const name = field({ label: 'Name' });
  const phone = field({ label: 'Phone', type: 'tel' });
  const email = field({ label: 'Email', type: 'email' });
  const address = field({ label: 'Address' });
  const limit = field({ label: 'Credit limit', value: '0', inputmode: 'decimal', helper: 'How much unpaid balance this customer may carry.' });
  const error = h('div', { class: 'error-text hidden', style: { marginTop: '16px' } });
  const submitButton = button({ label: 'Add customer', variant: 'filled', block: true, onclick: () => submit() });
  let busy = false;
  const fail = (text) => { error.textContent = text; error.classList.remove('hidden'); };

  async function submit() {
    if (busy) return;
    if (!name.value.trim()) return fail('Enter a name.');
    busy = true;
    error.classList.add('hidden');
    submitButton.disabled = true;
    try {
      await api.post('/api/customers', {
        name: name.value.trim(),
        phone: phone.value.trim() || null,
        email: email.value.trim() || null,
        address: address.value.trim() || null,
        creditLimit: parseNumber(limit.value) || 0,
      });
      snackbar(`${name.value.trim()} added.`);
      goBack('/customers');
    } catch (e) {
      fail(e.code === 'unauthorized' || e.code === 'walk_in_not_editable' ? e.message : `Could not save this customer: ${e.message}`);
    } finally {
      busy = false;
      submitButton.disabled = false;
    }
  }

  sc.content.append(
    h('div', { style: { maxWidth: '480px', margin: '0 auto' } },
      h('div', { class: 'stack-12' }, name.el, phone.el, email.el, address.el, limit.el),
      error,
      h('div', { style: { marginTop: '24px' } }, submitButton)),
  );
  return { el: sc.el };
}

// --- receive a payment ----------------------------------------------------------------------------

export async function receivePaymentScreen({ id }) {
  const sc = scaffold({ title: 'Receive payment', backTo: '/customers' });

  let customer;
  try {
    customer = (await api.get('/api/customers')).customers.find((c) => c.id === Number(id));
  } catch (e) {
    sc.content.append(emptyNote(`Could not load the customer: ${e.message}`));
    return { el: sc.el };
  }
  if (!customer) {
    sc.content.append(emptyNote('That customer could not be found.'));
    return { el: sc.el };
  }

  let method = 'cash';
  const amountField = field({ label: 'Amount', inputmode: 'decimal' });
  const methodSelect = selectField({
    label: 'Payment method',
    options: [{ value: 'cash', label: 'Cash' }, { value: 'mpesa', label: 'M-Pesa' }, { value: 'card', label: 'Card' }],
    value: 'cash',
    onChange: (v) => { method = v ?? 'cash'; },
  });
  const notes = field({ label: 'Notes (optional)' });
  const error = h('div', { class: 'error-text hidden', style: { marginTop: '16px' } });
  const submitButton = button({ label: 'Record payment', variant: 'filled', block: true, onclick: () => submit() });
  let busy = false;
  const fail = (text) => { error.textContent = text; error.classList.remove('hidden'); };

  async function submit() {
    if (busy) return;
    const value = parseNumber(amountField.value) || 0;
    if (value <= 0) return fail('Enter an amount greater than zero.');
    busy = true;
    error.classList.add('hidden');
    submitButton.disabled = true;
    try {
      await api.post(`/api/customers/${customer.id}/payments`, { amount: value, method, notes: notes.value.trim() || null });
      snackbar(`Payment of ${amount(value)} recorded.`);
      goBack('/customers');
    } catch (e) {
      fail(e.code === 'unauthorized' ? "You don't have permission to record a payment." : `Could not record this payment: ${e.message}`);
    } finally {
      busy = false;
      submitButton.disabled = false;
    }
  }

  sc.content.append(
    h('div', { style: { maxWidth: '480px', margin: '0 auto' } },
      h('div', { style: { fontSize: '16px', fontWeight: 500 } }, customer.name),
      h('div', { class: 'muted', style: { margin: '4px 0 20px' } }, `Current balance: ${amount(customer.currentBalance)}`),
      h('div', { class: 'stack-12' }, amountField.el, methodSelect.el, notes.el),
      error,
      h('div', { style: { marginTop: '24px' } }, submitButton)),
  );
  return { el: sc.el };
}

// --- statement ----------------------------------------------------------------------------------------

const LEDGER_LABELS = { creditSale: 'Credit sale', payment: 'Payment', reversal: 'Sale voided' };

export async function customerStatementScreen({ id }) {
  const sc = scaffold({ title: 'Statement', backTo: '/customers' });

  let customer;
  let entries;
  try {
    ({ customer, entries } = await api.get(`/api/customers/${id}/ledger`));
  } catch (e) {
    sc.content.append(emptyNote(`Failed to load statement: ${e.message}`));
    return { el: sc.el };
  }
  sc.setTitle(`${customer.name} — statement`);

  const tile = (labelText, value, emphasize = false) =>
    h('div', {},
      h('div', { class: 'muted', style: { fontSize: '12px' } }, labelText),
      h('div', { style: { marginTop: '4px', fontSize: '22px', fontWeight: 700, color: emphasize ? 'var(--debt)' : undefined } }, amount(value)));

  sc.content.append(
    h('div', { class: 'card card-pad', style: { display: 'flex', gap: '32px', marginBottom: '16px' } },
      tile('Credit limit', customer.creditLimit),
      tile('Current balance', customer.currentBalance, customer.currentBalance > 0)),
    entries.length === 0
      ? emptyNote('No credit activity yet.')
      : tableCard(
          dataTable({
            columns: [{ label: 'Date' }, { label: 'Type' }, { label: 'Reference' }, { label: 'Amount', num: true }, { label: 'Balance', num: true }],
            rows: entries.map((entry) => {
              const isCharge = entry.type === 'creditSale';
              return {
                cells: [
                  fmtDate(entry.date),
                  h('span', { style: { fontWeight: 600, color: isCharge ? 'var(--debt)' : 'var(--positive)' } }, LEDGER_LABELS[entry.type]),
                  entry.reference,
                  `${isCharge ? '+' : '-'}${amount(entry.amount)}`,
                  amount(entry.runningBalance),
                ],
              };
            }),
          }),
        ),
  );
  return { el: sc.el };
}
