// Suppliers: who the shop buys from, and what it still owes them.

import { api } from '../api.js';
import { goBack, navigate } from '../router.js';
import { scaffold } from '../scaffold.js';
import { can } from '../store.js';
import { button, dataTable, emptyNote, field, loading, tableCard } from '../ui.js';
import { amount, h } from '../util.js';

export async function supplierListScreen() {
  const canManage = can('manageProducts');
  const sc = scaffold({
    title: 'Suppliers',
    destination: 'suppliers',
    actions: [canManage && button({ label: 'Add supplier', icon: 'add', outlinedIcon: false, onclick: () => navigate('/suppliers/new') })].filter(Boolean),
  });
  const results = h('div');
  sc.content.append(results);
  results.append(loading());

  async function load() {
    let suppliers;
    try {
      suppliers = (await api.get('/api/suppliers')).suppliers;
    } catch (e) {
      results.replaceChildren(emptyNote(`Could not load suppliers: ${e.message}`));
      return;
    }
    if (suppliers.length === 0) {
      results.replaceChildren(emptyNote('No suppliers yet. Add the shops you buy stock from.'));
      return;
    }
    results.replaceChildren(
      tableCard(
        dataTable({
          columns: [{ label: 'Supplier' }, { label: 'Phone' }, { label: 'Owed to them', num: true }, ...(canManage ? [{ label: '' }] : [])],
          rows: suppliers.map((s) => ({
            tint: s.balance > 0 ? 'debt' : undefined,
            cells: [
              s.name,
              s.phone ?? '—',
              h('span', { style: s.balance > 0 ? { fontWeight: 700, color: 'var(--debt)' } : undefined }, amount(s.balance)),
              ...(canManage ? [button({ label: 'Edit', variant: 'text', onclick: () => navigate(`/suppliers/${s.uuid}/edit`) })] : []),
            ],
          })),
        }),
      ),
    );
  }
  await load();
  return { el: sc.el, refresh: load };
}

export async function supplierFormScreen({ uuid } = {}) {
  const editing = !!uuid;
  const sc = scaffold({ title: editing ? 'Edit supplier' : 'Add supplier', backTo: '/suppliers' });

  let supplier = null;
  if (editing) {
    try {
      supplier = (await api.get('/api/suppliers')).suppliers.find((s) => s.uuid === uuid);
    } catch (e) {
      sc.content.append(emptyNote(`Could not load the supplier: ${e.message}`));
      return { el: sc.el };
    }
    if (!supplier) {
      sc.content.append(emptyNote('That supplier could not be found.'));
      return { el: sc.el };
    }
  }

  const name = field({ label: 'Supplier name', value: supplier?.name ?? '', autofocus: true });
  const phone = field({ label: 'Phone (optional)', value: supplier?.phone ?? '', type: 'tel' });
  const email = field({ label: 'Email (optional)', value: supplier?.email ?? '', type: 'email' });
  const address = field({ label: 'Address (optional)', value: supplier?.address ?? '', multiline: true, rows: 2 });
  const error = h('div', { class: 'error-text hidden', style: { marginTop: '12px' } });
  const submitButton = button({ label: editing ? 'Save changes' : 'Add supplier', variant: 'filled', block: true, onclick: () => submit() });
  let busy = false;
  const fail = (text) => { error.textContent = text; error.classList.remove('hidden'); };

  async function submit() {
    if (busy) return;
    if (!name.value.trim()) return fail('Give the supplier a name.');
    busy = true;
    error.classList.add('hidden');
    submitButton.disabled = true;
    submitButton.setLabel('Saving…');
    const payload = { name: name.value.trim(), phone: phone.value.trim() || null, email: email.value.trim() || null, address: address.value.trim() || null };
    try {
      if (editing) await api.put(`/api/suppliers/${uuid}`, payload);
      else await api.post('/api/suppliers', payload);
      goBack('/suppliers');
    } catch (e) {
      fail(e.code === 'unauthorized' ? e.message : `Could not save the supplier: ${e.message}`);
    } finally {
      busy = false;
      submitButton.disabled = false;
      submitButton.setLabel(editing ? 'Save changes' : 'Add supplier');
    }
  }

  sc.content.append(
    h('div', { class: 'card card-pad', style: { maxWidth: '460px', margin: '0 auto' } },
      h('div', { class: 'stack-12' }, name.el, phone.el, email.el, address.el),
      error,
      h('div', { style: { marginTop: '20px' } }, submitButton)),
  );
  return { el: sc.el };
}
