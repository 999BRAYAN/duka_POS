// The frame every screen sits in: an app bar, and — on destination screens —
// the navigation (a permanent rail on wide windows, a slide-over drawer on
// narrow ones). Screens Version 1 pushed carry a back arrow instead.

import { buildDrawer } from './nav.js';
import { goBack } from './router.js';
import { h } from './util.js';
import { iconButton } from './ui.js';

/**
 * @param {object} o
 * @param {string} o.title
 * @param {string} [o.destination]  drawer id — makes this a destination screen
 * @param {string} [o.backTo]       fallback route for the back arrow on pushed screens
 * @param {Node[]} [o.actions]      app bar buttons
 * @param {Node} [o.tabs]           a tab bar under the app bar
 * @param {boolean} [o.noScroll]    the screen manages its own scrolling
 */
export function scaffold({ title, destination, backTo = '/products', actions = [], tabs, noScroll = false, padded = true }) {
  const content = h('div', { class: `page-content${padded ? ' pad' : ''}`, style: noScroll ? { overflow: 'hidden', display: 'flex', flexDirection: 'column' } : undefined });
  const titleEl = h('div', { class: 'title' }, title);
  const actionsEl = h('div', { class: 'actions' }, actions);

  let drawerWrap = null;
  let scrim = null;
  const closeDrawer = () => { drawerWrap?.classList.remove('open'); scrim?.classList.remove('open'); };

  const leading = destination
    ? iconButton({
        name: 'menu',
        title: 'Open navigation',
        onclick: () => { drawerWrap.classList.add('open'); scrim.classList.add('open'); },
      })
    : iconButton({ name: 'arrow_back', title: 'Back', onclick: () => goBack(backTo) });
  leading.classList.toggle('menu-btn', !!destination);

  const bar = h('header', { class: 'appbar' }, leading, titleEl, actionsEl);

  const main = h('div', { class: 'page-main' }, bar, tabs, content);
  const page = h('div', { class: 'page' });

  if (destination) {
    page.append(h('aside', { class: 'rail' }, buildDrawer(destination, { persistent: true })));
    scrim = h('div', { class: 'drawer-scrim', onclick: closeDrawer });
    drawerWrap = h('div', { class: 'drawer-wrap' }, buildDrawer(destination, { persistent: false, onNavigate: closeDrawer }));
    page.append(scrim, drawerWrap);
  }
  page.append(main);

  return {
    el: page,
    content,
    setTitle(text) { titleEl.textContent = text; },
    setActions(nodes) { actionsEl.replaceChildren(...nodes); },
  };
}
