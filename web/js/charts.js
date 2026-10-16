// Two small hand-drawn SVG charts (no library, so the till works offline):
// the dashboard's 7-day revenue line and the inventory report's movement bars.
// Conventions follow Version 1: a 2px line with ringed dots, hairline
// horizontal gridlines only, round-number axis steps, values lead in the tooltip.

import { amount, compact, fmtDayMonth, fmtWeekday } from './util.js';

const NS = 'http://www.w3.org/2000/svg';

function svg(tag, attrs = {}, ...children) {
  const el = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v);
  el.append(...children.filter(Boolean));
  return el;
}

/** A theme colour as a concrete value (SVG attributes can't resolve var()). */
function css(name) {
  const probe = document.createElement('span');
  probe.style.color = `var(${name})`;
  document.body.append(probe);
  const value = getComputedStyle(probe).color;
  probe.remove();
  return value;
}

/** A "nice" gridline step for `maxValue` — 100/200/500/1000 rather than an
 *  arbitrary maxValue/4 that would land ticks on values like 137.5. */
export function niceInterval(maxValue) {
  if (maxValue <= 0) return 100;
  const rough = maxValue / 4;
  const magnitude = 10 ** Math.floor(Math.log10(rough));
  const residual = rough / magnitude;
  const nice = residual < 1.5 ? 1 : residual < 3 ? 2 : residual < 7 ? 5 : 10;
  return nice * magnitude;
}

let tip;
function showTip(html, x, y) {
  if (!tip) { tip = document.createElement('div'); tip.className = 'chart-tip'; document.body.append(tip); }
  tip.innerHTML = html;
  tip.style.left = `${x + 12}px`;
  tip.style.top = `${y - 48}px`;
  tip.style.display = 'block';
}
function hideTip() { if (tip) tip.style.display = 'none'; }

/** Redraws `container` with `draw(width, height)` now and whenever it resizes. */
function responsive(container, draw) {
  const paint = () => {
    const { width, height } = container.getBoundingClientRect();
    if (width < 40 || height < 40) return;
    container.replaceChildren(draw(width, height));
  };
  const observer = new ResizeObserver(paint);
  observer.observe(container);
  paint();
  return () => observer.disconnect();
}

/** points: [{ date: 'YYYY-MM-DD', revenue }] */
export function lineChart(container, points) {
  return responsive(container, (width, height) => {
    const m = { left: 56, right: 24, top: 24, bottom: 36 };
    const w = width - m.left - m.right;
    const hgt = height - m.top - m.bottom;
    const max = points.reduce((a, p) => Math.max(a, p.revenue), 0);
    const interval = niceInterval(max);
    const maxY = max === 0 ? interval : Math.ceil(max / interval) * interval;
    const x = (i) => m.left + (points.length === 1 ? w / 2 : (i / (points.length - 1)) * w);
    const y = (v) => m.top + hgt - (v / maxY) * hgt;
    const muted = css('--muted');
    const line = css('--chart-line');

    const root = svg('svg', { viewBox: `0 0 ${width} ${height}`, width, height });
    for (let v = 0; v <= maxY + 1e-9; v += interval) {
      root.append(
        svg('line', { x1: m.left, x2: m.left + w, y1: y(v), y2: y(v), stroke: css('--chart-grid'), 'stroke-width': 1 }),
        svg('text', { x: m.left - 8, y: y(v) + 4, 'text-anchor': 'end', 'font-size': 11, fill: muted }, compact(v)),
      );
    }
    const coords = points.map((p, i) => [x(i), y(p.revenue)]);
    const path = coords.map(([cx, cy], i) => `${i ? 'L' : 'M'}${cx},${cy}`).join(' ');
    root.append(
      svg('path', { d: `${path} L${coords.at(-1)[0]},${y(0)} L${coords[0][0]},${y(0)} Z`, fill: line, opacity: 0.1 }),
      svg('path', { d: path, fill: 'none', stroke: line, 'stroke-width': 2, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' }),
    );
    points.forEach((p, i) => {
      root.append(svg('text', { x: x(i), y: height - 12, 'text-anchor': 'middle', 'font-size': 11, fill: muted }, fmtWeekday(p.date)));
    });
    coords.forEach(([cx, cy], i) => {
      const dot = svg('circle', { cx, cy, r: 4, fill: line, stroke: '#fff', 'stroke-width': 2 });
      const hit = svg('circle', { cx, cy, r: 18, fill: 'transparent' });
      hit.addEventListener('mousemove', (e) =>
        showTip(`${amount(points[i].revenue)}<small>${fmtDayMonth(points[i].date)}</small>`, e.clientX, e.clientY));
      hit.addEventListener('mouseleave', hideTip);
      root.append(dot, hit);
    });
    return root;
  });
}

/** bars: [{ label, value }] — drawn above/below zero, coloured by sign. */
export function barChart(container, bars) {
  return responsive(container, (width, height) => {
    const m = { left: 48, right: 16, top: 24, bottom: 36 };
    const w = width - m.left - m.right;
    const hgt = height - m.top - m.bottom;
    const maxAbs = bars.reduce((a, b) => Math.max(a, Math.abs(b.value)), 0);
    const bound = maxAbs === 0 ? 1 : maxAbs * 1.2;
    const y = (v) => m.top + hgt / 2 - (v / bound) * (hgt / 2);
    const muted = css('--muted');
    const root = svg('svg', { viewBox: `0 0 ${width} ${height}`, width, height });

    // Gridlines at round numbers either side of zero, as the line chart does.
    const step = niceInterval(bound);
    const ticks = [];
    for (let v = 0; v <= bound + 1e-9; v += step) { ticks.push(v); if (v) ticks.unshift(-v); }
    for (const v of ticks) {
      root.append(
        svg('line', { x1: m.left, x2: m.left + w, y1: y(v), y2: y(v), stroke: css('--chart-grid'), 'stroke-width': 1 }),
        svg('text', { x: m.left - 8, y: y(v) + 4, 'text-anchor': 'end', 'font-size': 11, fill: muted }, v.toFixed(0)),
      );
    }
    const slot = w / bars.length;
    bars.forEach((bar, i) => {
      const cx = m.left + slot * (i + 0.5);
      const top = Math.min(y(bar.value), y(0));
      const barHeight = Math.max(Math.abs(y(bar.value) - y(0)), 0);
      const rect = svg('rect', {
        x: cx - 12, y: top, width: 24, height: barHeight, rx: 4,
        fill: bar.value < 0 ? css('--debt') : css('--positive'),
      });
      const hit = svg('rect', { x: cx - slot / 2, y: m.top, width: slot, height: hgt, fill: 'transparent' });
      hit.addEventListener('mousemove', (e) => showTip(amount(bar.value), e.clientX, e.clientY));
      hit.addEventListener('mouseleave', hideTip);
      root.append(rect, hit, svg('text', { x: cx, y: height - 12, 'text-anchor': 'middle', 'font-size': 11, fill: muted }, bar.label));
    });
    return root;
  });
}
