// The shop's at-a-glance status: today's headline numbers alongside a 7-day
// revenue trend, so a manager can see both "how's today going" and "is that
// normal" in one screen — plus backup and restore.

import { api, download } from '../api.js';
import { barChart, lineChart } from '../charts.js';
import { scaffold } from '../scaffold.js';
import { lastBackupAt, markBackedUp } from '../store.js';
import { button, icon, iconButton, loading, openDialog, snackbar } from '../ui.js';
import { amount, h } from '../util.js';

export async function dashboardScreen() {
  const sc = scaffold({
    title: 'Dashboard',
    destination: 'dashboard',
    noScroll: true,
    actions: [
      iconButton({ name: 'backup', outlined: true, title: 'Backup now', onclick: () => backupNow() }),
      iconButton({ name: 'restore_page', outlined: true, title: 'Restore from backup', onclick: () => restoreFromBackup() }),
    ],
  });

  const kpis = h('div', { class: 'kpi-row' });
  const reminder = h('div', { style: { marginTop: '16px' } });
  const chartBox = h('div', { class: 'card chart-card' }, loading());
  const chartHost = h('div', { style: { flex: 1, minWidth: 0, minHeight: 0 } });
  let disconnect = null;

  sc.content.append(
    kpis,
    reminder,
    h('div', { class: 'section-h', style: { margin: '24px 0 8px' } }, 'Revenue, last 7 days'),
    h('div', { class: 'grow', style: { display: 'flex', flexDirection: 'column' } }, chartBox),
  );

  const kpi = (labelText, value, color) =>
    h('div', { class: 'card kpi' }, h('div', { class: 'l' }, labelText), h('div', { class: 'v', style: color ? { color } : undefined }, value));

  function paintReminder() {
    const last = lastBackupAt();
    const daysAgo = last ? Math.floor((Date.now() - last.getTime()) / 86_400_000) : null;
    const stale = daysAgo === null || daysAgo >= 7;
    const message =
      daysAgo === null ? 'This shop has never been backed up on this device.'
        : daysAgo === 0 ? 'Backed up today.'
          : daysAgo === 1 ? 'Last backup was yesterday.'
            : `Last backup was ${daysAgo} days ago.`;
    reminder.replaceChildren(
      h('div', { class: `banner ${stale ? 'stale' : 'fresh'}` },
        icon(stale ? 'warning_amber' : 'check_circle_outline', { outlined: true }),
        h('div', {}, stale
          ? `${message} Your sales, stock and customer balances live in the till's database — keep a copy somewhere safe.`
          : message)),
    );
  }

  async function load() {
    let data;
    try {
      data = await api.get('/api/dashboard');
    } catch (e) {
      kpis.replaceChildren(h('div', { class: 'empty' }, `Failed to load the dashboard: ${e.message}`));
      chartBox.replaceChildren();
      return;
    }
    kpis.replaceChildren(
      kpi("Today's revenue", amount(data.todayRevenue)),
      kpi("Today's net profit", amount(data.todayNetProfit), data.todayNetProfit < 0 ? 'var(--debt)' : undefined),
      kpi('Low stock', String(data.lowStockCount), data.lowStockCount > 0 ? 'var(--warning)' : undefined),
      kpi('Credit outstanding', amount(data.creditOutstanding), data.creditOutstanding > 0 ? 'var(--debt)' : undefined),
    );
    disconnect?.();
    chartBox.replaceChildren(chartHost);
    disconnect = lineChart(chartHost, data.revenueTrend);
  }

  async function backupNow() {
    try {
      await download('/api/backup');
      markBackedUp();
      paintReminder();
      snackbar('Backup downloaded.');
    } catch (e) {
      snackbar(`Backup failed: ${e.message}`);
    }
  }

  async function restoreFromBackup() {
    const picker = h('input', { type: 'file', accept: '.json,application/json', style: { display: 'none' } });
    document.body.append(picker);

    const dialog = openDialog({
      title: 'Restore from backup?',
      body: h('p', {}, 'This will replace all current data with the backup file. A safety copy of your current data will be downloaded first.'),
      actions: [
        { label: 'Cancel', variant: 'text', value: false },
        // The file picker must open straight from this click.
        { label: 'Choose backup file', variant: 'filled', value: true, onclick: () => { picker.click(); } },
      ],
    });
    const confirmed = await dialog.result;
    if (confirmed !== true) { picker.remove(); return; }

    picker.addEventListener('change', async () => {
      const file = picker.files[0];
      picker.remove();
      if (!file) return;
      try {
        await download('/api/backup'); // the safety copy
        const form = new FormData();
        form.append('file', file);
        await api.upload('/api/restore', form);
        markBackedUp();
        location.reload(); // everything on screen is now stale
      } catch (e) {
        snackbar(e.code === 'invalid_backup' ? e.message : `Restore failed: ${e.message}`);
      }
    });
    picker.addEventListener('cancel', () => picker.remove());
  }

  paintReminder();
  await load();
  return { el: sc.el, refresh: load, destroy: () => disconnect?.() };
}
