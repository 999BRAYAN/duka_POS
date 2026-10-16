// Staff logins: who can sign in, and what they may do. Manager-only.

import { api } from '../api.js';
import { goBack, navigate } from '../router.js';
import { scaffold } from '../scaffold.js';
import { can, state } from '../store.js';
import { button, confirmDialog, dataTable, emptyNote, field, loading, selectField, snackbar, tableCard } from '../ui.js';
import { h } from '../util.js';
import { showChangePasswordDialog } from './auth.js';

export async function staffListScreen() {
  const canManage = can('manageStaff');
  const sc = scaffold({
    title: 'Staff logins',
    destination: 'staff',
    actions: [canManage && button({ label: 'Add staff', icon: 'person_add', variant: 'filled', onclick: () => navigate('/staff/new') })].filter(Boolean),
  });

  if (!canManage) {
    sc.content.append(emptyNote('Only a manager can manage staff logins.'));
    return { el: sc.el };
  }

  const results = h('div');
  sc.content.append(results);
  results.append(loading());

  async function load() {
    let users;
    try {
      users = (await api.get('/api/users')).users;
    } catch (e) {
      results.replaceChildren(emptyNote(`Could not load staff: ${e.message}`));
      return;
    }
    if (users.length === 0) {
      results.replaceChildren(emptyNote('No staff logins yet.'));
      return;
    }
    results.replaceChildren(
      tableCard(
        dataTable({
          columns: [{ label: 'Name' }, { label: 'Username' }, { label: 'Role' }, { label: 'Status' }, { label: '' }],
          rows: users.map((user) => ({
            tint: user.isActive ? undefined : 'off',
            cells: [
              user.fullName,
              user.username,
              user.role,
              user.isActive ? 'Active' : h('span', { class: 'muted' }, 'Disabled'),
              h('span', { class: 'cell-row' },
                button({ label: 'Reset password', variant: 'text', onclick: () => showChangePasswordDialog(user) }),
                // Signing yourself out of your own shop by disabling your own
                // account would leave nobody able to sign in — the manager role
                // is unique, so there is no second manager to undo it.
                user.isActive && user.id !== state.user?.id
                  ? h('button', { class: 'btn btn-text btn-danger', type: 'button', onclick: () => deactivate(user) }, 'Disable')
                  : null),
            ],
          })),
        }),
      ),
    );
  }

  async function deactivate(user) {
    const confirmed = await confirmDialog({
      title: `Disable ${user.fullName}?`,
      message: 'They will no longer be able to sign in. Their past sales stay on record.',
      confirmLabel: 'Disable',
    });
    if (!confirmed) return;
    try {
      await api.post(`/api/users/${user.uuid}/deactivate`);
      await load();
    } catch (e) {
      snackbar(e.code === 'unauthorized' ? e.message : `Could not disable: ${e.message}`);
    }
  }

  await load();
  return { el: sc.el, refresh: load };
}

/**
 * Creates a staff login. Cashier is the default and the common case; the
 * manager role is offered only because the schema allows exactly one and a
 * shop may need to hand over.
 */
export async function staffFormScreen() {
  const sc = scaffold({ title: 'Add staff login', backTo: '/staff' });
  let role = 'cashier';

  const fullName = field({ label: 'Full name', autofocus: true });
  const username = field({ label: 'Username' });
  const password = field({ label: 'Password', type: 'password', helper: 'At least 6 characters. They can change it after signing in.' });
  const roleSelect = selectField({
    label: 'Role',
    options: [
      { value: 'cashier', label: 'Cashier — can only ring up sales' },
      { value: 'manager', label: 'Manager — full access' },
    ],
    value: 'cashier',
    onChange: (v) => { role = v ?? 'cashier'; },
  });
  const error = h('div', { class: 'error-text hidden', style: { marginTop: '12px' } });
  const submitButton = button({ label: 'Create login', variant: 'filled', block: true, onclick: () => submit() });
  let busy = false;
  const fail = (text) => { error.textContent = text; error.classList.remove('hidden'); };

  async function submit() {
    if (busy) return;
    if (!fullName.value.trim() || !username.value.trim()) return fail('Enter a name and a username.');
    busy = true;
    error.classList.add('hidden');
    submitButton.disabled = true;
    submitButton.setLabel('Creating…');
    try {
      await api.post('/api/users', { fullName: fullName.value, username: username.value, password: password.value, role });
      goBack('/staff');
    } catch (e) {
      if (e.code === 'weak_password') fail(`Password too short. ${e.message}`);
      else if (['unauthorized', 'manager_exists', 'username_taken'].includes(e.code)) fail(e.message);
      else fail(`Could not create the login: ${e.message}`);
    } finally {
      busy = false;
      submitButton.disabled = false;
      submitButton.setLabel('Create login');
    }
  }

  sc.content.append(
    h('div', { class: 'card card-pad', style: { maxWidth: '460px', margin: '0 auto' } },
      h('div', { class: 'stack-12' }, fullName.el, username.el, password.el, roleSelect.el),
      error,
      h('div', { style: { marginTop: '20px' } }, submitButton)),
  );
  return { el: sc.el };
}
