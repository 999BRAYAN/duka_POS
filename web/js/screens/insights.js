// Stock health: which products sell, which lag, and what to buy.

import { api } from '../api.js';
import { scaffold } from '../scaffold.js';
import { chip, dataTable, emptyNote, loading, tableCard } from '../ui.js';
import { amount, h, quantity } from '../util.js';

const STATUS = {
  out: ['Out of stock', 'var(--debt)'],
  reorder: ['Reorder', 'var(--debt)'],
  fast: ['Fast mover', 'var(--green-700)'],
  steady: ['Steady', 'var(--ink-2)'],
  slow: ['Slow', 'var(--amber-700)'],
  overstocked: ['Too much stock', 'var(--amber-700)'],
  dead: ['Not selling', 'var(--debt)'],
  new: ['Too new to judge', 'var(--muted)'],
  supply: ['Ingredient / supply', 'var(--muted)'],
};
const FILTERS = [
  ['all', 'All'], ['reorder', 'Reorder'], ['fast', 'Fast'], ['slow', 'Slow'], ['overstocked', 'Too much stock'], ['dead', 'Not selling'], ['out', 'Out of stock'],
];
const ORDER = { out: 0, reorder: 1, dead: 2, overstocked: 3, slow: 4, fast: 5, steady: 6, new: 7, supply: 8 };

export async function insightsScreen() {
  const sc = scaffold({ title: 'Stock health', destination: 'insights' });
  const kpis = h('div', { class: 'kpi-row', style: { flexWrap: 'wrap' } });
  const note = h('div', { style: { margin: '12px 0', color: 'var(--muted)' } });
  const chips = h('div', { style: { display: 'flex', gap: '8px', flexWrap: 'wrap', margin: '8px 0 12px' } });
  const results = h('div', {}, loading());
  sc.content.append(kpis, note, chips, results);

  let data;
  try {
    data = await api.get('/api/insights');
  } catch (e) {
    results.replaceChildren(emptyNote(`Could not load: ${e.message}`));
    return { el: sc.el };
  }
  let filter = 'all';
  const { summary } = data;
  const kpi = (label, value, color) => h('div', { class: 'card kpi' }, h('div', { class: 'l' }, label), h('div', { class: 'v', style: color ? { color } : undefined }, value));
  kpis.append(
    kpi('Stock value (at cost)', amount(summary.stockValue)),
    kpi('Money tied up in excess', amount(summary.excessValue), summary.excessValue > 0 ? 'var(--debt)' : undefined),
    kpi('Need reordering', String(summary.counts.reorder + summary.counts.out)),
    kpi('Not selling / too much', String(summary.counts.dead + summary.counts.overstocked)),
  );
  note.textContent = !data.historyDays
    ? 'No completed sales yet - make some sales and this page will start telling you what moves.'
    : data.enoughHistory
      ? `Based on ${data.historyDays.toFixed(0)} days of sales. "Days left" is how long today's stock lasts at the recent selling pace; reorder amounts bring each product up to 14 days.`
      : `Only ${data.historyDays.toFixed(0)} days of sales so far - slow and over-stocked calls become reliable after about 7 days.`;

  function paint() {
    const rows = data.products
      .filter((p) => filter === 'all' || p.status === filter)
      .sort((a, b) => (ORDER[a.status] - ORDER[b.status]) || (b.revenue - a.revenue));
    if (rows.length === 0) { results.replaceChildren(emptyNote('Nothing in this group.')); return; }
    results.replaceChildren(tableCard(dataTable({
      columns: [
        { label: 'Product' }, { label: 'Status' }, { label: 'Sold', num: true }, { label: 'Per day', num: true },
        { label: 'In stock', num: true }, { label: 'Days left', num: true }, { label: 'Class' },
        { label: 'Suggested order', num: true }, { label: 'Money in excess', num: true },
      ],
      rows: rows.map((p) => ({
        tint: ['out', 'reorder', 'dead'].includes(p.status) ? 'debt' : ['overstocked', 'slow'].includes(p.status) ? 'warn' : undefined,
        cells: [
          p.name,
          h('b', { style: { color: STATUS[p.status][1] } }, STATUS[p.status][0]),
          quantity(p.sold), p.dailyRate ? p.dailyRate.toFixed(1) : '-', quantity(p.stock),
          p.coverDays == null ? '-' : p.coverDays.toFixed(0), p.abc,
          p.suggestedOrder ? quantity(p.suggestedOrder) : '-', p.excessValue ? amount(p.excessValue) : '-',
        ],
      })),
    })));
  }

  const chipEls = FILTERS.map(([id, label]) => [id, chip({
    label,
    selected: id === filter,
    onclick: () => { filter = id; chipEls.forEach(([i, el]) => el.setSelected(i === id)); paint(); },
  })]);
  chips.append(...chipEls.map(([, el]) => el));
  paint();
  return { el: sc.el };
}
