// Sales history — every sale the shop has rung up, and the only place a sale
// can be reversed. Voiding lives here rather than on the checkout screen
// because it is a correction made after the fact, usually by someone other
// than whoever rang it up.

import { api, download } from '../api.js';
import { scaffold } from '../scaffold.js';
import { can } from '../store.js';
import { dataTable, emptyNote, field, iconButton, loading, openDialog, snackbar, tableCard } from '../ui.js';
import { amount, fmtDateTime, h } from '../util.js';

export async function salesHistoryScreen() {
  const canVoid = can('voidSale');
  const pdfButton = iconButton({ name: 'picture_as_pdf', outlined: true, title: 'Download as PDF', onclick: () => exportSales('pdf'), disabled: true });
  const csvButton = iconButton({ name: 'table_chart', outlined: true, title: 'Download as CSV (Excel)', onclick: () => exportSales('csv'), disabled: true });
  const sc = scaffold({ title: 'Sales history', destination: 'sales', actions: [pdfButton, csvButton] });

  let sales = [];
  let customerById = new Map();
  const results = h('div');
  sc.content.append(results);
  results.append(loading());

  async function exportSales(format) {
    try {
      await download(`/api/sales/export.${format}`);
    } catch (e) {
      snackbar(`Could not export: ${e.message}`);
    }
  }

  function paint() {
    const hasSales = sales.length > 0;
    pdfButton.disabled = !hasSales;
    csvButton.disabled = !hasSales;
    if (!hasSales) {
      results.replaceChildren(emptyNote('No sales yet.'));
      return;
    }
    results.replaceChildren(
      tableCard(
        dataTable({
          tall: true,
          columns: [
            { label: 'Receipt' }, { label: 'When' }, { label: 'Customer' }, { label: 'Total', num: true },
            { label: 'Paid', num: true }, { label: 'Status' }, { label: '' },
          ],
          rows: sales.map((sale) => {
            const isVoid = sale.status === 'void';
            const owing = sale.total - sale.amountPaid > 0.00005;
            return {
              cells: [
                h('span', { style: isVoid ? { textDecoration: 'line-through', color: 'var(--muted)' } : undefined }, sale.invoiceNumber),
                fmtDateTime(sale.createdAt),
                sale.customerId === null ? 'Walk-in' : customerById.get(sale.customerId)?.name ?? '—',
                amount(sale.total),
                amount(sale.amountPaid),
                isVoid
                  ? h('span', { title: sale.voidReason || 'No reason recorded' }, 'Void')
                  : owing
                    ? h('span', { style: { color: 'var(--debt)' } }, 'On account')
                    : h('span', { style: { color: 'var(--positive)' } }, 'Paid'),
                isVoid
                  ? ''
                  : canVoid
                    ? h('button', { class: 'btn btn-text btn-danger', type: 'button', onclick: () => voidSale(sale) }, 'Void')
                    : h('span', { class: 'muted', style: { fontSize: '11px' } }, 'manager only'),
              ],
            };
          }),
        }),
      ),
    );
  }

  async function load() {
    try {
      const [s, c] = await Promise.all([api.get('/api/sales'), api.get('/api/customers')]);
      sales = s.sales;
      customerById = new Map(c.customers.map((x) => [x.id, x]));
    } catch (e) {
      results.replaceChildren(emptyNote(`Could not load sales: ${e.message}`));
      return;
    }
    paint();
  }

  async function voidSale(sale) {
    const reason = field({
      label: 'Reason', hint: 'e.g. wrong item rung up', autofocus: true, onEnter: () => confirm(),
    });
    const dialog = openDialog({
      title: `Void ${sale.invoiceNumber}?`,
      width: 420,
      body: h('div', {},
        h('p', { style: { marginBottom: '12px' } },
          "The goods go back into stock and any unpaid balance comes off the customer's account. Both are recorded."),
        reason.el),
      actions: [
        { label: 'Cancel', variant: 'text' },
        { label: 'Void sale', variant: 'filled', onclick: () => { confirm(); return false; } },
      ],
    });
    function confirm() {
      if (!reason.value.trim()) { reason.setError('Say why this sale is being voided.'); return; }
      dialog.close(reason.value.trim());
    }
    const text = await dialog.result;
    if (!text) return;

    try {
      await api.post(`/api/sales/${sale.uuid}/void`, { reason: text });
      snackbar(`${sale.invoiceNumber} voided. Stock and balance reversed.`);
      await load();
    } catch (e) {
      const known = ['unauthorized', 'already_void', 'missing_void_reason'];
      snackbar(known.includes(e.code) ? e.message : `Could not void the sale: ${e.message}`);
    }
  }

  await load();
  return { el: sc.el, refresh: load };
}
