// Product catalog (list) and the add / edit form.

import { api } from '../api.js';
import { goBack, navigate } from '../router.js';
import { scaffold } from '../scaffold.js';
import { can, state } from '../store.js';
import {
  button, chip, dataTable, emptyNote, field, icon, iconButton, loading, openDialog, selectField, snackbar, tableCard,
} from '../ui.js';
import { amount, h, haystackMatches, parseNumber, plain } from '../util.js';

// --- list ------------------------------------------------------------------------------

export async function productListScreen() {
  const canManage = can('manageProducts');
  const sc = scaffold({
    title: 'Products',
    destination: 'products',
    actions: [
      canManage && iconButton({ name: 'add_box', outlined: true, title: 'Add product', onclick: () => navigate('/products/new') }),
      button({ label: 'New sale', icon: 'point_of_sale', outlinedIcon: false, onclick: () => navigate('/sell') }),
    ].filter(Boolean),
    noScroll: true,
  });

  let products = [];
  let categories = [];
  const f = state.filters;

  const search = field({
    placeholder: 'Search by name, SKU or barcode', dense: true, leadIcon: 'search', value: f.productSearch,
    onInput: (v) => { f.productSearch = v; paint(); },
  });
  search.el.style.width = '320px';

  const categorySelect = selectField({
    dense: true,
    options: [{ value: null, label: 'All categories' }],
    value: f.productCategory,
    onChange: (v) => { f.productCategory = v; paint(); },
  });
  categorySelect.el.style.width = '220px';

  const lowChip = chip({
    label: 'Low stock only', selected: f.productLowOnly, check: true,
    onclick: () => { f.productLowOnly = !f.productLowOnly; lowChip.setSelected(f.productLowOnly); paint(); },
  });

  const results = h('div', { class: 'grow', style: { display: 'flex', flexDirection: 'column', minHeight: 0 } });
  sc.content.append(
    h('div', { class: 'fill-col', style: { gap: '16px' } },
      h('div', { class: 'wrap' }, search.el, categorySelect.el, lowChip),
      results),
  );
  results.append(loading());

  const categoryName = (id) => categories.find((c) => c.id === id)?.name;

  function filtered() {
    return products.filter((p) => {
      if (f.productCategory !== null && p.categoryId !== f.productCategory) return false;
      if (f.productLowOnly && p.stock > p.reorderLevel) return false;
      return haystackMatches(f.productSearch, p.name, p.sku, p.barcode);
    });
  }

  function paint() {
    const rows = filtered();
    if (rows.length === 0) {
      results.replaceChildren(emptyNote('No products match your filters.'));
      return;
    }
    const columns = [
      { label: 'Name' }, { label: 'SKU' }, { label: 'Category' },
      { label: 'Stock', num: true }, { label: 'Cost', num: true }, { label: 'Price', num: true },
      ...(canManage ? [{ label: '' }] : []),
    ];
    const table = dataTable({
      columns,
      rows: rows.map((p) => {
        const low = p.stock <= p.reorderLevel;
        return {
          tint: low ? 'warn' : undefined,
          cells: [
            p.name,
            p.sku ?? '—',
            categoryName(p.categoryId) ?? '—',
            h('span', { class: 'cell-row' }, amount(p.stock), low && icon('warning_amber', { outlined: true, size: 16, color: 'var(--warning)' })),
            amount(p.costPrice),
            amount(p.sellingPrice),
            ...(canManage ? [button({ label: 'Edit', variant: 'text', onclick: () => navigate(`/products/${p.uuid}/edit`) })] : []),
          ],
        };
      }),
    });
    results.replaceChildren(tableCard(table, { fill: true }));
  }

  async function load() {
    try {
      [products, categories] = await Promise.all([
        api.get('/api/products').then((r) => r.products),
        api.get('/api/categories').then((r) => r.categories),
      ]);
    } catch (e) {
      results.replaceChildren(emptyNote(`Failed to load products: ${e.message}`));
      return;
    }
    categorySelect.setOptions(
      [{ value: null, label: 'All categories' }, ...categories.map((c) => ({ value: c.id, label: c.name }))],
      categories.some((c) => c.id === f.productCategory) ? f.productCategory : null,
    );
    paint();
  }

  await load();
  return { el: sc.el, refresh: load };
}

// --- form ---------------------------------------------------------------------------------

const NUMERIC = /[0-9.]/;

/**
 * Adds a product, or edits one when `uuid` is given.
 *
 * Opening stock is only offered when adding: after that, stock moves only
 * through stock movements so every change keeps an audit row, and this form
 * must not become a second writer of it.
 */
export async function productFormScreen({ uuid } = {}) {
  const editing = !!uuid;
  const sc = scaffold({ title: editing ? 'Edit product' : 'Add product', backTo: '/products' });

  let product = null;
  let categories = [];
  try {
    const [productsResponse, categoriesResponse] = await Promise.all([
      editing ? api.get('/api/products') : null,
      api.get('/api/categories'),
    ]);
    categories = categoriesResponse.categories;
    if (editing) product = productsResponse.products.find((p) => p.uuid === uuid);
  } catch (e) {
    sc.content.append(emptyNote(`Could not load the product: ${e.message}`));
    return { el: sc.el };
  }
  if (editing && !product) {
    sc.content.append(emptyNote('That product could not be found.'));
    return { el: sc.el };
  }

  const p = product;
  const name = field({ label: 'Product name', value: p?.name ?? '', autofocus: true });
  const sku = field({ label: 'SKU (optional)', value: p?.sku ?? '' });
  const barcode = field({ label: 'Barcode (optional)', value: p?.barcode ?? '' });
  const unit = field({ label: 'Unit', value: p?.unit ?? 'pcs' });
  unit.el.style.width = '120px';
  const cost = field({ label: 'Cost price', value: p ? plain(p.costPrice) : '', inputmode: 'decimal', restrict: NUMERIC });
  const selling = field({ label: 'Selling price', value: p ? plain(p.sellingPrice) : '', inputmode: 'decimal', restrict: NUMERIC });
  const minimum = field({
    label: 'Lowest price you will accept', value: p ? plain(p.minSellingPrice) : '', inputmode: 'decimal', restrict: NUMERIC,
    helper: 'Leave blank to refuse any discount below the selling price.',
  });
  const opening = field({ label: 'Opening stock', value: '0', inputmode: 'decimal', restrict: NUMERIC });
  const reorder = field({
    label: 'Warn me below', value: p ? plain(p.reorderLevel) : '0', inputmode: 'decimal', restrict: NUMERIC,
    helper: 'Shows the product as low stock.',
  });

  let categoryId = p?.categoryId ?? null;
  const categoryPicker = buildCategoryPicker(categories, categoryId, (id) => { categoryId = id; });

  const error = h('div', { class: 'error-text hidden', style: { marginTop: '12px' } });
  const submitButton = button({
    label: editing ? 'Save changes' : 'Add product', variant: 'filled', block: true, onclick: () => submit(),
  });
  let busy = false;
  const fail = (text) => { error.textContent = text; error.classList.remove('hidden'); };

  const number = (input) => {
    const text = input.value.trim();
    return text === '' ? 0 : parseNumber(text);
  };

  async function submit() {
    if (busy) return;
    const productName = name.value.trim();
    if (!productName) return fail('Give the product a name.');
    const costValue = number(cost);
    const sellingValue = number(selling);
    const reorderValue = number(reorder);
    const openingValue = number(opening);
    if ([costValue, sellingValue, reorderValue, openingValue].some(Number.isNaN)) return fail('Prices and quantities must be numbers.');
    if ([costValue, sellingValue, reorderValue, openingValue].some((n) => n < 0)) return fail("Prices and quantities can't be negative.");
    // Left blank, the floor is the selling price: the common case is a shop
    // that does not haggle, and defaulting to 0 would silently allow giving
    // stock away.
    const minimumValue = minimum.value.trim() === '' ? sellingValue : parseNumber(minimum.value);
    if (Number.isNaN(minimumValue)) return fail('The minimum selling price must be a number.');

    busy = true;
    error.classList.add('hidden');
    submitButton.disabled = true;
    submitButton.setLabel('Saving…');

    const payload = {
      name: productName,
      sku: sku.value.trim() || null,
      barcode: barcode.value.trim() || null,
      categoryId,
      unit: unit.value.trim() || 'pcs',
      costPrice: costValue,
      sellingPrice: sellingValue,
      minSellingPrice: minimumValue,
      reorderLevel: reorderValue,
      ...(editing ? {} : { stock: openingValue }),
    };
    const save = (confirmPriceBelowCost) =>
      editing
        ? api.put(`/api/products/${uuid}`, { ...payload, confirmPriceBelowCost })
        : api.post('/api/products', { ...payload, confirmPriceBelowCost });

    try {
      let saved = false;
      try {
        await save(false);
        saved = true;
      } catch (e) {
        if (e.code !== 'price_below_cost') throw e;
        const confirmed = await confirmPriceBelowCost(e.data.costPrice, e.data.minSellingPrice);
        if (confirmed) { await save(true); saved = true; }
      }
      // Declining the confirmation leaves the form open with the values intact.
      if (saved) goBack('/products');
    } catch (e) {
      fail(e.code === 'unauthorized' ? e.message : `Could not save the product: ${e.message}`);
    } finally {
      busy = false;
      submitButton.disabled = false;
      submitButton.setLabel(editing ? 'Save changes' : 'Add product');
    }
  }

  sc.content.append(
    h('div', { class: 'card card-pad form-card' },
      name.el,
      h('div', { class: 'row', style: { marginTop: '12px' } }, sku.el, barcode.el),
      h('div', { class: 'row', style: { marginTop: '12px' } }, categoryPicker.el, h('div', { class: 'fixed' }, unit.el)),
      h('div', { class: 'sec-title' }, 'Pricing'),
      h('div', { class: 'row' }, cost.el, selling.el),
      h('div', { style: { marginTop: '12px' } }, minimum.el),
      h('div', { class: 'sec-title' }, 'Stock'),
      h('div', { class: 'row' }, !editing && opening.el, reorder.el),
      editing && h('div', { class: 'muted', style: { fontSize: '12px', marginTop: '8px' } },
        'Stock is changed by sales, goods received and stock adjustments, so that every change keeps a record.'),
      error,
      h('div', { style: { marginTop: '20px' } }, submitButton),
    ),
  );
  return { el: sc.el };
}

/** "Selling below cost" — resolves true if they chose to save anyway. */
async function confirmPriceBelowCost(costPrice, minSellingPrice) {
  const d = openDialog({
    title: 'Selling below cost',
    body: h('p', {},
      `The minimum selling price (${Number(minSellingPrice).toFixed(2)}) is below the cost price ` +
      `(${Number(costPrice).toFixed(2)}). Save anyway?`),
    actions: [
      { label: 'Cancel', variant: 'text', value: false },
      { label: 'Save anyway', variant: 'filled', value: true },
    ],
  });
  return (await d.result) === true;
}

// --- category picker -------------------------------------------------------------------------

const NEW_CATEGORY = '__new__';

/** Picks a category, and can create one without leaving the form. */
function buildCategoryPicker(categories, selectedId, onChange) {
  const optionsFor = (list) => [
    { value: null, label: 'No category' },
    ...list.map((c) => ({ value: c.id, label: c.name })),
    { value: NEW_CATEGORY, label: 'New category…' },
  ];
  let list = categories;
  let selected = list.some((c) => c.id === selectedId) ? selectedId : null;

  const picker = selectField({
    label: 'Category',
    options: optionsFor(list),
    value: selected,
    onChange: async (value) => {
      if (value !== NEW_CATEGORY) {
        selected = value;
        onChange(value);
        return;
      }
      const created = await createCategory();
      if (created) {
        list = [...list, created].sort((a, b) => a.name.localeCompare(b.name));
        selected = created.id;
        picker.setOptions(optionsFor(list), selected);
        onChange(selected);
      } else {
        picker.value = selected; // back to what was chosen before
      }
    },
  });
  return picker;
}

async function createCategory() {
  const name = field({ label: 'Name', autofocus: true, onEnter: () => dialog.close(name.value.trim()) });
  const dialog = openDialog({
    title: 'New category',
    body: name.el,
    actions: [
      { label: 'Cancel', variant: 'text' },
      { label: 'Create', variant: 'filled', onclick: () => { dialog.close(name.value.trim()); return false; } },
    ],
  });
  const value = await dialog.result;
  if (!value) return null;
  try {
    return (await api.post('/api/categories', { name: value })).category;
  } catch (e) {
    snackbar(e.code === 'unauthorized' ? e.message : `Could not add the category: ${e.message}`);
    return null;
  }
}
