// Import: fill products, customers, suppliers or expenses from an Excel or
// CSV sheet. The sheet is always previewed first (the server runs the whole
// import and rolls it back), then imported for real on confirmation.

import { api, download } from '../api.js';
import { scaffold } from '../scaffold.js';
import { button, card, chip, dataTable, errorBox, loading, snackbar, tableCard } from '../ui.js';
import { h } from '../util.js';

const KINDS = [
  ['products', 'Products', 'Name, SKU, barcode, category, unit, cost, selling price, stock, reorder level.'],
  ['customers', 'Customers', 'Name, phone, email, address, credit limit.'],
  ['suppliers', 'Suppliers', 'Name, phone, email, address.'],
  ['expenses', 'Expenses', 'Description, amount, category, date.'],
];

const STATUS = {
  created: ['New', 'var(--ok, #2e7d32)'],
  updated: ['Updated', 'var(--accent, #b45309)'],
  unchanged: ['No change', 'var(--muted, #78716c)'],
  error: ['Skipped', 'var(--debt, #b91c1c)'],
};

export async function importScreen() {
  const sc = scaffold({ title: 'Import from Excel', destination: 'import' });
  let kind = 'products';
  let pending = null; // { file, kind } waiting for the user to confirm

  const chips = h('div', { class: 'chip-row', style: { display: 'flex', gap: '8px', flexWrap: 'wrap' } });
  const blurb = h('p', { style: { margin: '12px 0 4px', opacity: 0.8 } });
  const actions = h('div', { style: { display: 'flex', gap: '12px', flexWrap: 'wrap', margin: '12px 0' } });
  const output = h('div');

  const picker = h('input', { type: 'file', accept: '.xlsx,.xlsm,.csv', style: { display: 'none' } });
  sc.el.append(picker);

  function paintKinds() {
    chips.replaceChildren(...KINDS.map(([id, label]) => chip({
      label, selected: id === kind,
      onclick: () => { kind = id; pending = null; output.replaceChildren(); paintKinds(); },
    })));
    blurb.textContent = `Columns understood: ${KINDS.find(([id]) => id === kind)[2]} Only the Name/Description and Amount columns are required; headings can be in any order.`;
  }

  async function send(file, commit) {
    const form = new FormData();
    form.append('file', file);
    form.append('commit', commit ? '1' : '0');
    return api.upload(`/api/import/${kind}`, form);
  }

  async function preview(file) {
    output.replaceChildren(loading());
    try {
      const result = await send(file, false);
      pending = { file, kind };
      paintReport(result);
    } catch (e) {
      pending = null;
      output.replaceChildren(errorBox(e.message));
    }
  }

  async function confirm() {
    if (!pending) return;
    const { file } = pending;
    output.replaceChildren(loading());
    try {
      const result = await send(file, true);
      pending = null;
      paintReport(result);
      const c = result.counts;
      snackbar(`Imported: ${c.created} new, ${c.updated} updated.`);
    } catch (e) {
      output.replaceChildren(errorBox(`Import failed: ${e.message}`));
    }
  }

  function paintReport(result) {
    const c = result.counts;
    const applies = c.created + c.updated;
    const parts = [];

    const summary = h('div', { style: { display: 'flex', gap: '24px', flexWrap: 'wrap', marginBottom: '8px' } },
      ...Object.entries(STATUS).map(([key, [label, color]]) =>
        h('div', {}, h('div', { style: { fontSize: '24px', fontWeight: 700, color } }, String(c[key])), h('div', { style: { opacity: 0.75 } }, label))));
    const heading = result.committed
      ? h('h3', { style: { margin: '0 0 8px' } }, 'Import finished')
      : h('h3', { style: { margin: '0 0 8px' } }, `Preview of ${result.total} rows - nothing has been saved yet`);
    parts.push(card({ style: { padding: '16px', marginBottom: '16px' } }, heading, summary));

    if (result.ignoredColumns.length) {
      parts.push(h('p', { style: { opacity: 0.75 } }, `Columns not recognised and ignored: ${result.ignoredColumns.join(', ')}.`));
    }
    if (!result.committed) {
      parts.push(h('div', { style: { display: 'flex', gap: '12px', margin: '0 0 16px' } },
        button({
          label: applies ? `Import ${applies} row${applies === 1 ? '' : 's'}${c.error ? ` (skip ${c.error})` : ''}` : 'Nothing to import',
          icon: 'check', outlinedIcon: false, disabled: applies === 0, onclick: confirm,
        }),
        button({ label: 'Cancel', variant: 'text', onclick: () => { pending = null; output.replaceChildren(); picker.value = ''; } })));
    }

    parts.push(tableCard(dataTable({
      columns: [{ label: 'Row', num: true }, { label: 'Result' }, { label: kind === 'expenses' ? 'Description' : 'Name' }, { label: 'Details' }],
      rows: result.rows.map((r) => ({
        tint: r.status === 'error' ? 'debt' : r.status === 'unchanged' ? 'off' : undefined,
        cells: [String(r.row), h('b', { style: { color: STATUS[r.status][1] } }, STATUS[r.status][0]), r.name, r.note ?? ''],
      })),
    })));
    output.replaceChildren(...parts);
  }

  picker.addEventListener('change', () => {
    const file = picker.files[0];
    picker.value = '';
    if (file) preview(file);
  });

  actions.append(
    button({ label: 'Choose Excel / CSV file', icon: 'upload_file', outlinedIcon: false, onclick: () => picker.click() }),
    button({
      label: 'Download template', icon: 'download', variant: 'outlined',
      onclick: async () => {
        try { await download(`/api/import/${kind}/template`); } catch (e) { snackbar(`Could not download: ${e.message}`); }
      },
    }),
  );

  sc.content.append(
    h('p', { style: { margin: '0 0 12px', opacity: 0.8 } },
      'Pick what the sheet holds, upload it, and check the preview. Rows that match something already in the system (same SKU, barcode, phone or name) update it instead of adding a duplicate.'),
    chips, blurb, actions, output,
  );
  paintKinds();
  return { el: sc.el };
}
