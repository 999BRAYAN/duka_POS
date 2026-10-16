// Sales, profit & loss, and inventory reports, all reading from the one period
// a shared selector controls — pick a period once and every tab's numbers
// agree on the same window.

import { api, download } from '../api.js';
import { barChart } from '../charts.js';
import { scaffold } from '../scaffold.js';
import { state } from '../store.js';
import { button, chip, dataTable, emptyNote, loading, snackbar, tableCard } from '../ui.js';
import { amount, h } from '../util.js';

const PERIODS = [
  ['today', 'Today'],
  ['week', 'This week'],
  ['month', 'This month'],
  ['year', 'This year'],
];
const MOVEMENT_ORDER = ['PURCHASE', 'SALE', 'RETURN', 'ADJUSTMENT'];
const MOVEMENT_LABELS = { PURCHASE: 'Received', SALE: 'Sold', RETURN: 'Returned', ADJUSTMENT: 'Adjusted' };

export async function reportsScreen() {
  const tabs = [
    ['sales', 'Sales'],
    ['pnl', 'Profit & loss'],
    ['inventory', 'Inventory'],
  ];
  let active = 'sales';
  let disconnectChart = null;

  const tabButtons = tabs.map(([id, text]) =>
    h('button', { class: 'tab', type: 'button', role: 'tab', 'aria-selected': String(id === active), onclick: () => select(id) }, text));
  const sc = scaffold({
    title: 'Reports',
    destination: 'reports',
    tabs: h('div', { class: 'tabbar', role: 'tablist' }, tabButtons),
    noScroll: true,
  });

  const chips = PERIODS.map(([id, text]) =>
    chip({
      label: text, selected: state.filters.reportPeriod === id,
      onclick: () => { state.filters.reportPeriod = id; chips.forEach((c, i) => c.setSelected(PERIODS[i][0] === id)); load(); },
    }));
  const panel = h('div', { class: 'grow', style: { minHeight: 0, overflow: 'auto', marginTop: '16px' } });
  sc.content.append(h('div', { class: 'period-chips' }, chips), panel);

  function select(id) {
    active = id;
    tabButtons.forEach((b, i) => b.setAttribute('aria-selected', String(tabs[i][0] === id)));
    load();
  }

  const exportRow = (kind, period) =>
    h('div', { class: 'export-row', style: { marginBottom: '12px' } },
      button({ label: 'PDF', icon: 'picture_as_pdf', variant: 'outlined', onclick: () => exportReport(kind, period, 'pdf') }),
      button({ label: 'CSV (Excel)', icon: 'table_chart', variant: 'outlined', onclick: () => exportReport(kind, period, 'csv') }));

  async function exportReport(kind, period, format) {
    try {
      await download(`/api/reports/${kind}`, { period, format });
    } catch (e) {
      snackbar(`Could not export: ${e.message}`);
    }
  }

  const stat = (labelText, value) =>
    h('div', { class: 'card kpi' }, h('div', { class: 'l' }, labelText), h('div', { class: 'v' }, value));

  function salesTab(report, period) {
    return h('div', {},
      exportRow('sales', period),
      h('div', { class: 'kpi-row' },
        stat('Total revenue', amount(report.totalRevenue)),
        stat('Sales', String(report.saleCount)),
        stat('Average sale', amount(report.averageSaleValue))),
      h('div', { class: 'section-h', style: { margin: '24px 0 8px' } }, 'Revenue by product'),
      report.productBreakdown.length === 0
        ? emptyNote('No sales in this period.')
        : tableCard(dataTable({
            columns: [{ label: 'Product' }, { label: 'Quantity sold', num: true }, { label: 'Revenue', num: true }],
            rows: report.productBreakdown.map((r) => ({ cells: [r.productName, amount(r.quantitySold), amount(r.revenue)] })),
          })),
    );
  }

  function pnlTab(report, period) {
    const row = (labelText, value, { em = false, color } = {}) =>
      h('div', { class: `pnl-row${em ? ' em' : ''}`, style: color ? { color } : undefined }, h('span', {}, labelText), h('span', {}, amount(value)));
    return h('div', {},
      exportRow('pnl', period),
      h('div', { class: 'card pnl-card' },
        row('Subtotal', report.subtotal),
        row('Discount', -report.discount),
        h('hr'),
        row('Net revenue', report.netRevenue, { em: true }),
        row('Cost of goods sold', -report.cogs),
        h('hr'),
        row('Gross profit', report.grossProfit, { em: true }),
        row('Expenses', -report.expenses),
        h('hr'),
        row('Net profit', report.netProfit, { em: true, color: report.netProfit < 0 ? 'var(--debt)' : 'var(--positive)' })),
    );
  }

  function inventoryTab(report, period) {
    const byType = new Map(report.movementSummary.map((m) => [m.type, m.totalQuantity]));
    const bars = MOVEMENT_ORDER.map((t) => ({ label: MOVEMENT_LABELS[t], value: byType.get(t) ?? 0 }));
    const chartHost = h('div', { style: { height: '300px', minWidth: 0 } });
    const chartCard = h('div', { class: 'card', style: { padding: '24px 16px 12px 8px' } }, chartHost);

    const levels = report.stockLevels.length === 0
      ? emptyNote('No products yet.')
      : tableCard(dataTable({
          columns: [{ label: 'Product' }, { label: 'Stock', num: true }, { label: 'Avg cost', num: true }, { label: 'Stock value', num: true }],
          rows: report.stockLevels.map((l) => ({
            tint: l.isLowStock ? 'warn' : undefined,
            cells: [l.name, amount(l.stock), amount(l.averageCost), amount(l.stockValue)],
          })),
        }));

    const root = h('div', {},
      exportRow('inventory', period),
      h('div', { class: 'report-split' },
        h('div', {}, h('div', { class: 'section-h' }, 'Stock levels'), levels),
        h('div', {}, h('div', { class: 'section-h' }, 'Stock movement'),
          report.movementSummary.length === 0 ? emptyNote('No stock movement in this period.') : chartCard)));
    if (report.movementSummary.length > 0) {
      queueMicrotask(() => { disconnectChart = barChart(chartHost, bars); });
    }
    return root;
  }

  async function load() {
    const kind = active;
    const period = state.filters.reportPeriod;
    disconnectChart?.();
    disconnectChart = null;
    panel.replaceChildren(loading());
    let data;
    try {
      data = await api.get(`/api/reports/${kind}`, { period });
    } catch (e) {
      if (kind === active && period === state.filters.reportPeriod) {
        panel.replaceChildren(emptyNote(`Failed to load report: ${e.message}`));
      }
      return;
    }
    // A newer tab or period choice is already loading; don't paint over it.
    if (kind !== active || period !== state.filters.reportPeriod) return;
    panel.replaceChildren(
      kind === 'sales' ? salesTab(data.report, period) : kind === 'pnl' ? pnlTab(data.report, period) : inventoryTab(data.report, period),
    );
  }

  await load();
  return { el: sc.el, destroy: () => disconnectChart?.() };
}
