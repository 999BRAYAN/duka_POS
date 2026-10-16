// First-run setup, sign-in, switch user, change password.

import { api } from '../api.js';
import { applySession } from '../session.js';
import { state } from '../store.js';
import { button, field, openDialog } from '../ui.js';
import { h } from '../util.js';

const MIN_PASSWORD = 6;

function authFrame(card) {
  return h('div', { class: 'center-screen' }, card);
}

/** Shown when no one is signed in and the shop already has a manager. */
export function signInScreen() {
  const username = field({ label: 'Username', autofocus: true, onEnter: () => password.input.focus() });
  const password = field({ label: 'Password', type: 'password', onEnter: () => submit() });
  const error = h('div', { class: 'error-text hidden', style: { marginTop: '12px' } });
  const submitButton = button({ label: 'Sign in', variant: 'filled', block: true, onclick: () => submit() });
  let busy = false;

  async function submit() {
    if (busy) return;
    busy = true;
    error.classList.add('hidden');
    submitButton.disabled = true;
    submitButton.setLabel('Signing in…');
    try {
      const payload = await api.post('/api/auth/login', { username: username.value.trim(), password: password.value });
      history.replaceState({ depth: 0 }, '', '#/products');
      applySession(payload);
    } catch (e) {
      error.textContent = e.code === 'invalid_credentials' ? e.message : `Could not sign in: ${e.message}`;
      error.classList.remove('hidden');
    } finally {
      busy = false;
      submitButton.disabled = false;
      submitButton.setLabel('Sign in');
    }
  }

  return {
    el: authFrame(
      h('div', { class: 'card auth-card' },
        h('h1', {}, 'Duka POS'),
        h('div', { class: 'sub' }, 'Sign in to open the till'),
        username.el, password.el, error, submitButton),
    ),
  };
}

/** Shown once, on a shop with no accounts at all. */
export function setupScreen() {
  const fullName = field({ label: 'Your name', autofocus: true });
  const username = field({ label: 'Username' });
  const password = field({ label: 'Password', type: 'password', helper: `At least ${MIN_PASSWORD} characters` });
  const confirm = field({ label: 'Confirm password', type: 'password', onEnter: () => submit() });
  const error = h('div', { class: 'error-text hidden', style: { marginTop: '12px' } });
  const submitButton = button({ label: 'Create account', variant: 'filled', block: true, onclick: () => submit() });
  let busy = false;

  const fail = (text) => { error.textContent = text; error.classList.remove('hidden'); };

  async function submit() {
    if (busy) return;
    if (!fullName.value.trim() || !username.value.trim()) return fail('Enter your name and a username.');
    if (password.value !== confirm.value) return fail("Those passwords don't match.");
    busy = true;
    error.classList.add('hidden');
    submitButton.disabled = true;
    submitButton.setLabel('Creating…');
    try {
      const payload = await api.post('/api/auth/setup', {
        fullName: fullName.value,
        username: username.value,
        password: password.value,
      });
      history.replaceState({ depth: 0 }, '', '#/products');
      applySession(payload);
    } catch (e) {
      if (e.code === 'weak_password') fail(`Password too short. ${e.message}`);
      else if (e.code === 'manager_exists') fail(e.message);
      else fail(`Could not create the account: ${e.message}`);
    } finally {
      busy = false;
      submitButton.disabled = false;
      submitButton.setLabel('Create account');
    }
  }

  return {
    el: authFrame(
      h('div', { class: 'card auth-card wide' },
        h('h1', {}, 'Set up this till'),
        h('div', { class: 'sub' },
          "Create the manager account. It's the only account that can add products, see reports and create staff logins."),
        fullName.el, username.el, password.el, confirm.el,
        h('div', { class: 'notice notice-info' },
          'Write this password down somewhere safe. There is no way to recover it from the app — ' +
          'the shop data lives in the database on the till\'s server.'),
        error, submitButton),
    ),
  };
}

/** Sets a new password for `user` — your own, or (as a manager) anyone's. */
export function showChangePasswordDialog(user) {
  const password = field({
    label: 'New password', type: 'password', autofocus: true, helper: `At least ${MIN_PASSWORD} characters`,
  });
  const confirm = field({ label: 'Confirm password', type: 'password', onEnter: () => submit() });
  const error = h('div', { class: 'error-text hidden', style: { fontSize: '12px', marginTop: '12px' } });
  let busy = false;

  const dialog = openDialog({
    title: `New password for ${user.fullName}`,
    width: 400,
    body: h('div', { class: 'stack-12' }, password.el, confirm.el, error),
    actions: [
      { label: 'Cancel', variant: 'text' },
      { label: 'Change password', variant: 'filled', onclick: () => { submit(); return false; } },
    ],
  });

  async function submit() {
    if (busy) return;
    if (password.value !== confirm.value) {
      error.textContent = "Those passwords don't match.";
      error.classList.remove('hidden');
      return;
    }
    busy = true;
    error.classList.add('hidden');
    try {
      await api.post('/api/auth/password', { userUuid: user.uuid, newPassword: password.value });
      dialog.close(true);
    } catch (e) {
      error.textContent = e.code === 'weak_password' ? `Password too short. ${e.message}` : `Could not change the password: ${e.message}`;
      error.classList.remove('hidden');
    } finally {
      busy = false;
    }
  }
  return dialog.result;
}

/**
 * Switches the signed-in user without leaving the app: pick a profile, enter
 * that profile's password, and the till carries on as them — the open order
 * and the current screen stay where they are.
 */
export function showSwitchUserDialog() {
  const body = h('div', { style: { width: '340px', minHeight: '120px' } });
  let dialog;
  let target = null;

  async function showPicker() {
    target = null;
    body.replaceChildren(h('div', { class: 'loading' }, h('div', { class: 'spinner' })));
    let users;
    try {
      users = (await api.get('/api/users')).users.filter((u) => u.isActive && u.id !== state.user?.id);
    } catch (e) {
      body.replaceChildren(h('div', { class: 'empty' }, `Could not load staff: ${e.message}`));
      return;
    }
    dialog.el.querySelector('h2').textContent = 'Switch user';
    setActions([{ label: 'Cancel', variant: 'text', value: undefined }]);
    if (users.length === 0) {
      body.replaceChildren(h('div', { class: 'empty' }, 'No other staff accounts to switch to.'));
      return;
    }
    body.replaceChildren(
      h('div', { class: 'list-sep', style: { maxHeight: '320px', overflow: 'auto' } },
        users.map((u) =>
          h('div', { class: 'list-tile tap', onclick: () => showPassword(u) },
            h('div', { class: 'grow' }, h('div', { class: 't' }, u.fullName), h('div', { class: 's' }, u.role))),
        )),
    );
  }

  function showPassword(user) {
    target = user;
    dialog.el.querySelector('h2').textContent = `Sign in as ${user.fullName}`;
    const password = field({ label: 'Password', type: 'password', autofocus: true, onEnter: () => submit() });
    const error = h('div', { class: 'error-text hidden', style: { fontSize: '12px', marginTop: '12px' } });
    body.replaceChildren(h('div', {}, password.el, error));
    let busy = false;

    async function submit() {
      if (busy) return;
      busy = true;
      error.classList.add('hidden');
      try {
        const payload = await api.post('/api/auth/login', { username: user.username, password: password.value });
        dialog.close(true);
        applySession(payload); // re-renders the same screen, now seen as the new user
      } catch (e) {
        error.textContent = e.code === 'invalid_credentials' ? e.message : `Could not switch users: ${e.message}`;
        error.classList.remove('hidden');
      } finally {
        busy = false;
      }
    }
    setActions([
      { label: 'Back', variant: 'text', onclick: () => { showPicker(); return false; } },
      { label: 'Switch', variant: 'filled', onclick: () => { submit(); return false; } },
    ]);
  }

  function setActions(actions) {
    const bar = dialog.el.querySelector('.d-actions');
    bar.replaceChildren(
      ...actions.map((a) =>
        button({
          label: a.label,
          variant: a.variant,
          onclick: async () => {
            const keep = a.onclick ? await a.onclick() : undefined;
            if (keep !== false) dialog.close(a.value);
          },
        }),
      ),
    );
  }

  dialog = openDialog({
    title: 'Switch user',
    body,
    actions: [{ label: 'Cancel', variant: 'text' }],
  });
  showPicker();
  return dialog.result;
}
