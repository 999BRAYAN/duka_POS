// The navigation drawer — every screen in the app, in one place.
//
// An item the signed-in user can't reach is shown disabled rather than
// hidden, so a cashier can see the shop has a Reports screen and knows to
// ask, instead of wondering whether the software has one at all.

import { replace } from './router.js';
import { signOut } from './session.js';
import { getThemeMode, setThemeMode, can, state } from './store.js';
import { showChangePasswordDialog, showSwitchUserDialog } from './screens/auth.js';
import { icon } from './ui.js';
import { h } from './util.js';

const GROUPS = [
  ['Selling', [
    ['sell', 'New sale', 'point_of_sale', false, 'processSale', '/sell'],
    ['sales', 'Sales history', 'receipt_long', true, null, '/sales'],
  ]],
  ['Stock', [
    ['products', 'Products', 'inventory_2', true, null, '/products'],
    ['adjust', 'Stock adjustments', 'tune', false, 'adjustStock', '/adjust'],
    ['purchases', 'Receive stock', 'local_shipping', true, 'receiveStock', '/purchases'],
    ['suppliers', 'Suppliers', 'store', true, 'manageProducts', '/suppliers'],
    ['import', 'Import from Excel', 'upload_file', true, 'manageProducts', '/import'],
  ]],
  ['People', [
    ['customers', 'Customers', 'people_outline', false, null, '/customers'],
    ['staff', 'Staff logins', 'badge', true, 'manageStaff', '/staff'],
  ]],
  ['Money', [
    ['expenses', 'Expenses', 'payments', true, 'manageExpenses', '/expenses'],
    ['dashboard', 'Dashboard', 'dashboard', true, 'manageProducts', '/dashboard'],
    ['reports', 'Reports', 'bar_chart', true, 'manageProducts', '/reports'],
    ['insights', 'Stock health', 'monitor_heart', true, 'manageProducts', '/insights'],
  ]],
];

const THEMES = [
  ['light', 'light_mode', 'Light'],
  ['system', 'brightness_auto', 'Match the device'],
  ['dark', 'dark_mode', 'Dark'],
];

export function buildDrawer(current, { persistent, onNavigate = () => {} }) {
  const user = state.user;

  const items = GROUPS.flatMap(([label, destinations]) => [
    h('div', { class: 'drawer-group' }, label),
    ...destinations.map(([id, text, iconName, outlined, permission, path]) => {
      const allowed = !permission || can(permission);
      const selected = id === current;
      const item = h(
        'button',
        {
          class: `nav-item${selected ? ' selected' : ''}`,
          type: 'button',
          disabled: !allowed,
          title: allowed ? undefined : 'Only a manager can open this',
          onclick: () => {
            onNavigate();
            // Replace rather than push: the drawer is the navigation, so the
            // back stack should not fill with every screen visited.
            if (!selected) replace(path);
          },
        },
        icon(iconName, { outlined }),
        h('span', { class: 'label' }, text),
        // A small lock rather than the word "manager": the longest labels plus
        // a word of explanation do not fit the rail's width.
        !allowed && h('span', { class: 'lock' }, icon('lock_outline', { size: 14 })),
      );
      return item;
    }),
  ]);

  const mode = getThemeMode();
  const themeSwitch = h(
    'div',
    { class: 'segmented' },
    THEMES.map(([value, iconName, title]) =>
      h(
        'button',
        {
          type: 'button',
          title,
          'aria-label': title,
          'aria-pressed': String(mode === value),
          onclick: (e) => {
            setThemeMode(value);
            e.currentTarget.parentElement.querySelectorAll('button').forEach((b) => b.setAttribute('aria-pressed', 'false'));
            e.currentTarget.setAttribute('aria-pressed', 'true');
          },
        },
        icon(iconName, { outlined: true }),
      ),
    ),
  );

  const footItem = (iconName, text, onclick) =>
    h('button', { class: 'nav-item', type: 'button', style: { minHeight: '36px' }, onclick: () => { onNavigate(); onclick(); } },
      icon(iconName, { outlined: true }), h('span', { class: 'label' }, text));

  return h(
    'nav',
    { class: 'drawer' },
    h('div', { class: 'drawer-head' },
      h('div', { class: 'name' }, user?.fullName ?? 'Duka POS'),
      user && h('div', { class: 'role' }, user.role)),
    h('hr'),
    h('div', { class: 'drawer-list' }, items),
    h('hr'),
    h('div', { class: 'drawer-foot' },
      themeSwitch,
      user && footItem('password', 'Change my password', () => showChangePasswordDialog(user)),
      user && footItem('switch_account', 'Switch user', () => showSwitchUserDialog()),
      footItem('logout', 'Sign out', () => signOut())),
  );
}
