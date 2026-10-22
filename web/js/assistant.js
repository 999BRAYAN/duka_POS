// The shop assistant: a chat button on every screen. Answers come from the
// shop's own records (see duka/assistant.py), so nothing here needs internet.

import { api } from './api.js';
import { icon } from './ui.js';
import { h } from './util.js';

const STARTERS = ["What's running low?", 'What should I reorder?', 'Which products are not selling?', 'How are sales today?'];

let root = null;
let greeted = false; // survives closing the panel, not a page reload

export function mountAssistant() {
  if (root) return;
  const log = h('div', { class: 'chat-log' });
  const input = h('input', { class: 'chat-input', type: 'text', placeholder: 'Ask about stock, sales, what to reorder...', maxlength: '500', autocomplete: 'off' });
  const send = h('button', { class: 'chat-send', type: 'button', title: 'Send' }, icon('send'));
  const panel = h('div', { class: 'chat-panel', hidden: true },
    h('div', { class: 'chat-head' }, icon('support_agent'), h('span', {}, 'Shop assistant'),
      h('button', { class: 'chat-close', type: 'button', title: 'Close', onclick: () => toggle(false) }, icon('close'))),
    log,
    h('div', { class: 'chat-bar' }, input, send));
  const fab = h('button', { class: 'chat-fab', type: 'button', title: 'Ask the assistant', onclick: () => toggle(true) }, icon('chat'));
  root = h('div', { id: 'assistant-root' }, panel, fab);
  document.body.append(root);

  function toggle(open) {
    panel.hidden = !open;
    fab.hidden = open;
    if (open) {
      if (!greeted) {
        greeted = true;
        bot({ reply: "Hi! I answer from your shop's own records. Try one of these:", suggestions: STARTERS });
      }
      input.focus();
    }
  }

  function bubble(who, ...children) {
    const el = h('div', { class: `chat-msg ${who}` }, ...children);
    log.append(el);
    log.scrollTop = log.scrollHeight;
    return el;
  }

  function bot(answer) {
    const parts = [h('div', {}, answer.reply)];
    if (answer.table) {
      parts.push(h('div', { class: 'chat-table' }, h('table', { class: 'data' },
        h('thead', {}, h('tr', {}, ...answer.table.columns.map((c) => h('th', {}, c)))),
        h('tbody', {}, ...answer.table.rows.map((r) => h('tr', {}, ...r.map((c) => h('td', {}, c))))))));
    }
    if (answer.suggestions?.length) {
      parts.push(h('div', { class: 'chat-sugg' }, ...answer.suggestions.map((s) => h('button', { type: 'button', onclick: () => ask(s) }, s))));
    }
    bubble('bot', ...parts);
  }

  async function ask(question) {
    question = question.trim();
    if (!question) return;
    input.value = '';
    bubble('me', question);
    const waiting = bubble('bot', '...');
    try {
      bot(await api.post('/api/assistant', { question }));
    } catch (e) {
      bubble('bot', e.message);
    } finally {
      waiting.remove();
    }
  }

  send.addEventListener('click', () => ask(input.value));
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter') ask(input.value); });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !panel.hidden) toggle(false); });
}

export function unmountAssistant() {
  root?.remove();
  root = null;
}
