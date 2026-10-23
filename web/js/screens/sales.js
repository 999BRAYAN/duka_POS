// The two-step sale: build the order (New sale), then confirm it and take the
// money (Confirm & pay). Payment is deliberately not on the first screen —
// the goods are gathered and agreed first, then a total is named and paid,
// and splitting them means the payment screen shows the order as a settled
// list rather than a cart still being edited underneath the person paying.

import { api } from '../api.js';
import { goBack, navigate } from '../router.js';
import { scaffold } from '../scaffold.js';
import { can, cart, heldOrders, orderTotal, resetOrder, state } from '../store.js';
import {
  button, chip, dataTable, emptyNote, field, icon, iconButton, loading, openDialog, selectField, snackbar, tableCard,
} from '../ui.js';
import { amount, h, haystackMatches, parseNumber, plain, preserveFocus, setChildren } from '../util.js';

// --- step indicators ------------------------------------------------------------------------------------

function stepsFor(active) {
  const step = (index, text) =>
    h('span', { class: `step${index === active ? ' active' : ''}` }, h('span', { class: 'dot' }, String(index)), text);
  return h('div', { class: 'steps' },
    step(1, 'Build the order'),
    h('span', { class: 'arrow' }, icon('arrow_forward', { size: 14 })),
    step(2, 'Confirm & take payment'));
}

function checkoutSteps() {
  return h('div', { class: 'steps' },
    h('span', { class: 'step' }, icon('check_circle'), 'Order built'),
    h('span', { class: 'arrow' }, icon('arrow_forward', { size: 14 })),
    h('span', { class: 'step active' }, h('span', { class: 'dot' }, '2'), 'Confirm & take payment'));
}

// --- step one: New sale ---------------------------------------------------------------------------------------

export async function saleScreen() {
  const heldButton = iconButton({ name: 'pause_circle_outline', title: 'Held orders', onclick: () => showHeldOrders() });
  const sc = scaffold({ title: 'New sale', destination: 'sell', actions: [heldButton], noScroll: true });

  let products = [];
  let categories = [];
  let categoryId = null;
  let searchText = '';

  const paintHeldBadge = () => {
    heldButton.querySelector('.badge')?.remove();
    if (state.held.length > 0) heldButton.append(h('span', { class: 'badge' }, String(state.held.length)));
  };
  paintHeldBadge();

  // --- the product picker ---
  const search = field({
    placeholder: 'Search by name, SKU or barcode', dense: true, leadIcon: 'search',
    onInput: (v) => { searchText = v; clearButton.classList.toggle('hidden', !v); paintGrid(); },
  });
  const clearButton = iconButton({
    name: 'clear', title: 'Clear search', size: 18, compact: true,
    onclick: () => { search.value = ''; searchText = ''; clearButton.classList.add('hidden'); paintGrid(); },
  });
  clearButton.classList.add('hidden', 'affix');
  search.el.append(clearButton);

  const chipRow = h('div', { class: 'chip-scroll' });
  const grid = h('div', { class: 'product-grid' });
  const picker = h('div', { class: 'sale-picker' }, search.el, chipRow, grid);

  function matching() {
    return products.filter((p) => (categoryId === null || p.categoryId === categoryId) && haystackMatches(searchText, p.name, p.sku, p.barcode));
  }

  function paintChips() {
    chipRow.replaceChildren();
    chipRow.classList.toggle('hidden', categories.length === 0);
    if (categories.length === 0) return;
    const countFor = (id) => products.filter((p) => id === null || p.categoryId === id).length;
    const make = (id, label) => {
      const c = chip({
        label: `${label} (${countFor(id)})`, selected: categoryId === id,
        onclick: () => { categoryId = id; paintChips(); paintGrid(); },
      });
      return c;
    };
    chipRow.append(make(null, 'All'), ...categories.map((c) => make(c.id, c.name)));
  }

  function paintGrid() {
    const list = matching();
    if (list.length === 0) {
      grid.replaceChildren(
        h('div', { class: 'empty', style: { gridColumn: '1 / -1' } },
          products.length === 0 ? 'No products yet. Add some from the Products screen.' : 'Nothing matches that search.'),
      );
      return;
    }
    grid.replaceChildren(
      ...list.map((p) => {
        const out = p.stock <= 0;
        const low = !out && p.stock <= p.reorderLevel;
        return h('button', {
            class: 'product-card', type: 'button', disabled: out,
            onclick: () => { cart.addProduct({ productId: p.id, name: p.name, price: p.sellingPrice }); paintLines(); refreshTotals(); },
          },
          h('span', { class: 'pname' }, p.name),
          h('span', { class: 'pprice' }, amount(p.sellingPrice), h('small', {}, ` / ${p.unit}`)),
          h('span', { class: `pstock${out ? ' out' : low ? ' low' : ''}` },
            out ? 'Out of stock' : `${amount(p.stock)} ${p.unit}${low ? ' · low' : ''}`));
      }),
    );
  }

  // --- the order panel ---
  const linesBox = h('div');
  const discountField = field({
    label: 'Discount on the whole order', dense: true, inputmode: 'decimal',
    value: state.order.discount > 0 ? plain(state.order.discount) : '0',
    onInput: (v) => { state.order.discount = parseFloat(v) || 0; refreshTotals(); },
  });
  const totalsBox = h('div');
  const reviewButton = button({ label: 'Review order', icon: 'arrow_forward', outlinedIcon: false, block: true, onclick: () => navigate('/sell/checkout') });
  const holdButton = button({ label: 'Hold order', variant: 'outlined', block: true, onclick: () => hold() });

  const panel = h('div', { class: 'card card-pad order-panel' },
    h('div', { class: 'order-scroll' },
      h('div', { style: { fontSize: '16px', fontWeight: 500, marginBottom: '8px' } }, 'Order'),
      linesBox,
      h('div', { style: { marginTop: '12px' } }, discountField.el)),
    h('hr', { class: 'panel-divider' }),
    totalsBox,
    h('div', { class: 'stack-12' }, reviewButton, holdButton));

  const floorFor = (productId) => products.find((p) => p.id === productId)?.minSellingPrice ?? 0;

  function priceField(line) {
    const floor = floorFor(line.productId);
    const input = field({
      label: 'Unit price', value: line.price.toFixed(2), dense: true, inputmode: 'decimal', key: `price-${line.productId}`,
      className: 'price-field', helper: `Min ${amount(floor)}`,
      onInput: (value) => {
        const parsed = parseNumber(value);
        if (Number.isNaN(parsed)) return;
        cart.setPrice(line.productId, parsed);
        const below = parsed < floor;
        input.setError(below ? `Min ${amount(floor)}` : null);
        input.setHelper(below ? null : `Min ${amount(floor)}`);
        lineTotal.textContent = amount(line.price * line.quantity);
        refreshTotals();
      },
    });
    if (line.price < floor) { input.setError(`Min ${amount(floor)}`); input.setHelper(null); }
    const lineTotal = h('div', { class: 'ltotal' }, amount(line.price * line.quantity));
    return { input, lineTotal };
  }

  function paintLines() {
    preserveFocus(linesBox, () => {
      if (state.cart.length === 0) {
        linesBox.replaceChildren(h('div', { class: 'muted', style: { textAlign: 'center', padding: '24px 0' } }, 'Tap a product to start the order.'));
        return;
      }
      linesBox.replaceChildren(
        ...state.cart.map((line) => {
          const { input, lineTotal } = priceField(line);
          const setQty = (q) => { cart.setQuantity(line.productId, q); paintLines(); refreshTotals(); };
          return h('div', { class: 'order-line' },
            h('div', { class: 'info' },
              h('div', { class: 'lname' }, line.name),
              input.el,
              h('div', { class: 'qty' },
                iconButton({ name: 'remove', title: 'One fewer', compact: true, onclick: () => setQty(line.quantity - 1) }),
                h('div', { class: 'n' }, amount(line.quantity)),
                iconButton({ name: 'add', title: 'One more', compact: true, onclick: () => setQty(line.quantity + 1) }),
                iconButton({ name: 'close', title: 'Remove', compact: true, onclick: () => { cart.removeLine(line.productId); paintLines(); refreshTotals(); } }))),
            lineTotal);
        }),
      );
    });
  }

  function refreshTotals() {
    const subtotal = cart.subtotal();
    const discount = state.order.discount;
    setChildren(
      totalsBox,
      h('div', { class: 'totals-row' }, h('span', { class: 'l' }, 'Subtotal'), h('span', {}, amount(subtotal))),
      discount > 0 && h('div', { class: 'totals-row' }, h('span', { class: 'l' }, 'Discount'), h('span', {}, amount(-discount))),
      h('div', { class: 'order-total' }, h('span', { class: 'l' }, 'Order total'), h('span', { class: 'v' }, amount(orderTotal()))),
    );
    const empty = state.cart.length === 0;
    reviewButton.disabled = empty;
    holdButton.disabled = empty;
  }

  async function hold() {
    if (state.cart.length === 0) return;
    let customerName = null;
    if (state.order.customerId !== null) {
      try {
        const { customers } = await api.get('/api/customers');
        customerName = customers.find((c) => c.id === state.order.customerId)?.name ?? null;
      } catch { /* the name is only a label */ }
    }
    heldOrders.hold({ customerName });
    cart.clear();
    resetOrder();
    discountField.value = '0';
    paintLines();
    refreshTotals();
    paintHeldBadge();
    snackbar('Order held.');
  }

  function resume(id) {
    const held = heldOrders.resume(id);
    if (!held) return;
    cart.replaceAll(held.cart);
    state.order.customerId = held.customerId;
    state.order.paymentMethod = held.paymentMethod;
    state.order.discount = held.discount;
    state.order.amountPaid = held.amountPaid;
    discountField.value = plain(held.discount);
    paintLines();
    refreshTotals();
    paintHeldBadge();
  }

  function showHeldOrders() {
    const list = h('div', { class: 'list-sep', style: { width: '420px', maxWidth: '100%', maxHeight: '320px', overflow: 'auto' } });
    const dialog = openDialog({ title: 'Held orders', body: list, actions: [{ label: 'Close', variant: 'text' }] });
    const paint = () => {
      paintHeldBadge();
      if (state.held.length === 0) {
        list.replaceChildren(h('div', { class: 'empty', style: { height: '200px' } }, 'No held orders.'));
        return;
      }
      list.replaceChildren(
        ...state.held.map((order) =>
          h('div', { class: 'list-tile' },
            h('div', { class: 'grow' },
              h('div', { class: 't' }, order.customerName ?? 'Walk-in customer'),
              h('div', { class: 's' }, `${heldOrders.itemCount(order).toFixed(0)} item(s) · ${amount(heldOrders.subtotal(order))}`)),
            iconButton({ name: 'delete_outline', title: 'Discard', size: 20, onclick: () => { heldOrders.discard(order.id); paint(); } }),
            button({ label: 'Resume', variant: 'text', onclick: () => { dialog.close(); resume(order.id); } }))),
      );
    };
    paint();
  }

  const layout = h('div', { class: 'sale-layout' }, picker, panel);
  sc.content.append(stepsFor(1), layout);
  paintLines();
  refreshTotals();
  grid.append(loading());

  async function load() {
    try {
      [products, categories] = await Promise.all([
        api.get('/api/products').then((r) => r.products),
        api.get('/api/categories').then((r) => r.categories),
      ]);
    } catch (e) {
      grid.replaceChildren(emptyNote(`Failed to load products: ${e.message}`));
      return;
    }
    if (categoryId !== null && !categories.some((c) => c.id === categoryId)) categoryId = null;
    paintChips();
    paintGrid();
  }
  await load();
  return { el: sc.el, refresh: load };
}

// --- step two: Confirm & pay -----------------------------------------------------------------------------------------

const PAYMENT_METHODS = [
  { value: 'cash', label: 'Cash' },
  { value: 'mpesa', label: 'M-Pesa' },
  { value: 'card', label: 'Card' },
  { value: 'credit', label: 'Credit' },
];

export async function checkoutScreen() {
  const sc = scaffold({ title: 'Confirm & pay', backTo: '/sell' });

  if (state.cart.length === 0) {
    sc.content.append(
      h('div', { class: 'center-screen', style: { flexDirection: 'column', gap: '12px' } },
        h('div', {}, 'The order is empty.'),
        button({ label: 'Back to the order', variant: 'filled', onclick: () => goBack('/sell') })));
    return { el: sc.el };
  }

  let customers = [];
  try {
    customers = (await api.get('/api/customers')).customers.filter((c) => !c.isWalkIn);
  } catch (e) {
    sc.content.append(emptyNote(`Could not load customers: ${e.message}`));
    return { el: sc.el };
  }

  let amountPaidText = '';
  let submitting = false;
  let error = null;
  // Set when the last attempt was refused for breaching a credit limit, so the
  // override is offered against that specific refusal rather than standing
  // permanently on the screen as a way to skip the check.
  let creditLimitRefused = false;

  const subtotal = cart.subtotal();
  const discount = state.order.discount;
  const total = orderTotal();
  const canOverride = can('overrideCreditLimit');

  const orderCard = h('div', { class: 'card clip' },
    h('div', { class: 'table-scroll' },
      dataTable({
        tall: true,
        columns: [{ label: 'Item' }, { label: 'Qty', num: true }, { label: 'Price', num: true }, { label: 'Total', num: true }],
        rows: state.cart.map((line) => ({
          cells: [line.name, amount(line.quantity), amount(line.price), amount(line.price * line.quantity)],
        })),
      })),
    h('div', { class: 'card-pad', style: { borderTop: '1px solid var(--line)' } },
      h('div', { class: 'totals-row' }, h('span', { class: 'l' }, 'Subtotal'), h('span', {}, amount(subtotal))),
      discount > 0 && h('div', { class: 'totals-row' }, h('span', { class: 'l' }, 'Discount'), h('span', {}, amount(-discount))),
      h('div', { class: 'order-total', style: { marginTop: '6px', marginBottom: 0 } },
        h('span', { class: 'l' }, 'Total'), h('span', { class: 'big-total' }, amount(total)))));

  const paymentCard = h('div', { class: 'card card-pad' });
  sc.content.append(checkoutSteps(), h('div', { class: 'checkout-layout' }, orderCard, paymentCard));
  sc.content.querySelector('.steps').style.marginBottom = '16px';

  const amountPaid = () => (state.order.customerId === null ? total : parseNumber(amountPaidText) || 0);
  const balanceDue = () => Math.max(total - amountPaid(), 0);
  const selectedCustomer = () => customers.find((c) => c.id === state.order.customerId);

  function paintPayment() {
    preserveFocus(paymentCard, () => {
      const customerId = state.order.customerId;
      const method = state.order.paymentMethod;

      const customerSelect = selectField({
        label: 'Customer', dense: true, key: 'customer', value: customerId,
        options: [
          { value: null, label: 'Walk-in customer' },
          ...customers.map((c) => ({ value: c.id, label: `${c.name} · owes ${amount(c.currentBalance)}` })),
        ],
        onChange: (value) => {
          // A newly-picked customer defaults to paying in full: leaving a
          // balance should be a deliberate act, not what happens by forgetting
          // to type anything. Except when "Credit" is already the payment
          // method — then paid-in-full would silently discard the credit sale,
          // so it defaults to unpaid instead.
          const wasWalkIn = state.order.customerId === null;
          state.order.customerId = value;
          if (value !== null && wasWalkIn) amountPaidText = method === 'credit' ? '0' : total.toFixed(2);
          creditLimitRefused = false;
          paintPayment();
        },
      });

      const methodSelect = selectField({
        label: 'Payment method', dense: true, key: 'method', options: PAYMENT_METHODS, value: method,
        onChange: (value) => {
          const next = value ?? 'cash';
          const wasCredit = state.order.paymentMethod === 'credit';
          state.order.paymentMethod = next;
          // Credit means nothing is taken now: it forces the amount to 0 rather
          // than leaving whatever was last typed (often the auto-filled total).
          if (state.order.customerId !== null) {
            if (next === 'credit') amountPaidText = '0';
            else if (wasCredit) amountPaidText = total.toFixed(2);
          }
          creditLimitRefused = false;
          paintPayment();
        },
      });

      const customer = selectedCustomer();
      const due = balanceDue();

      let paidField = null;
      if (customerId !== null && method !== 'credit') {
        paidField = field({
          label: 'Amount paid now', dense: true, inputmode: 'decimal', key: 'paid', value: amountPaidText,
          onInput: (v) => { amountPaidText = v; refreshWarning(); },
        });
      }

      const warning = h('div', { class: 'notice notice-warn' });
      const refreshWarning = () => {
        const c = selectedCustomer();
        const d = balanceDue();
        warning.classList.toggle('hidden', !c);
        if (c && d > 0) {
          warning.textContent =
            `Remaining ${amount(d)} goes on ${c.name}'s account — now ${amount(c.currentBalance)} of ${amount(c.creditLimit)}.`;
        } else if (c) {
          // Picking a customer alone is not a credit sale: say so, so it isn't a surprise afterwards.
          warning.textContent =
            `Paid in full now, so nothing goes on ${c.name}'s account. To sell on credit, choose Credit as the payment method (or lower the amount paid).`;
        }
      };
      refreshWarning();

      const errorBox = error
        ? h('div', { class: 'notice notice-bad' },
            h('div', {}, error),
            creditLimitRefused && (canOverride
              ? h('div', { style: { marginTop: '10px' } },
                  button({ label: 'Override and complete', variant: 'outlined', disabled: submitting, onclick: () => complete(true) }))
              : h('div', { style: { marginTop: '10px', fontSize: '12px' } }, 'A manager can approve this.')))
        : null;

      setChildren(
        paymentCard,
        h('div', { style: { fontSize: '16px', fontWeight: 500, marginBottom: '16px' } }, 'Payment'),
        h('div', { class: 'stack-12' },
          customerSelect.el,
          methodSelect.el,
          paidField?.el,
          warning,
          errorBox),
        h('div', { style: { marginTop: '16px' } },
          button({
            label: submitting ? 'Saving…' : `Complete sale · ${amount(total)}`, variant: 'filled', block: true, tall: true,
            disabled: submitting, onclick: () => complete(false),
          })),
        h('div', { style: { marginTop: '8px' } },
          button({ label: 'Back to the order', icon: 'arrow_back', outlinedIcon: false, variant: 'outlined', block: true, onclick: () => goBack('/sell') })),
      );
    });
  }

  async function complete(overrideCreditLimit) {
    if (submitting || state.cart.length === 0) return;
    submitting = true;
    error = null;
    paintPayment();

    try {
      const { sale } = await api.post('/api/sales', {
        cart: state.cart.map((l) => ({ productId: l.productId, price: l.price, quantity: l.quantity })),
        customerId: state.order.customerId,
        paymentMethod: state.order.paymentMethod,
        amountPaid: amountPaid(),
        discount: state.order.discount,
        overrideCreditLimit,
      });
      cart.clear();
      resetOrder();
      submitting = false;
      await showSaleConfirmation(sale);
      goBack('/sell');
    } catch (e) {
      submitting = false;
      creditLimitRefused = e.code === 'credit_limit_exceeded';
      const specific = ['credit_limit_exceeded', 'unauthorized', 'insufficient_stock', 'price_below_floor', 'customer_required'];
      error = specific.includes(e.code) ? e.message : `Could not complete this sale: ${e.message}`;
      paintPayment();
    }
  }

  paintPayment();
  return { el: sc.el };
}

/** The post-payment confirmation: print the receipt, or move on. */
function showSaleConfirmation(sale) {
  const dialog = openDialog({
    iconName: 'check_circle',
    iconColor: '#4caf50',
    title: 'Sale complete',
    centered: true,
    dismissible: false,
    body: h('div', { style: { textAlign: 'center' } }, `Invoice ${sale.invoiceNumber} · ${amount(sale.total)}`),
    actions: [
      {
        label: 'Print receipt', variant: 'outlined', icon: 'print',
        // Opened straight from the click: browsers refuse a print window that
        // isn't a synchronous continuation of a user gesture.
        onclick: () => { window.open(`/api/sales/${sale.uuid}/receipt.pdf`, '_blank'); return false; },
      },
      { label: 'Done', variant: 'filled', value: true },
    ],
  });
  return dialog.result;
}
