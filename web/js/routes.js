// Every screen and the path it lives at.

import { salesHistoryScreen } from './screens/history.js';
import { stockAdjustmentScreen } from './screens/adjust.js';
import { customerFormScreen, customerListScreen, customerStatementScreen, receivePaymentScreen } from './screens/customers.js';
import { dashboardScreen } from './screens/dashboard.js';
import { expensesScreen } from './screens/expenses.js';
import { productFormScreen, productListScreen } from './screens/products.js';
import { purchaseListScreen, receiveStockScreen } from './screens/purchases.js';
import { reportsScreen } from './screens/reports.js';
import { importScreen } from './screens/import.js';
import { checkoutScreen, saleScreen } from './screens/sales.js';
import { staffFormScreen, staffListScreen } from './screens/staff.js';
import { supplierFormScreen, supplierListScreen } from './screens/suppliers.js';

export const routes = [
  ['/products', () => productListScreen()],
  ['/products/new', () => productFormScreen()],
  ['/products/:uuid/edit', (p) => productFormScreen(p)],
  ['/sell', () => saleScreen()],
  ['/sell/checkout', () => checkoutScreen()],
  ['/sales', () => salesHistoryScreen()],
  ['/adjust', () => stockAdjustmentScreen()],
  ['/purchases', () => purchaseListScreen()],
  ['/purchases/receive', () => receiveStockScreen()],
  ['/suppliers', () => supplierListScreen()],
  ['/suppliers/new', () => supplierFormScreen()],
  ['/suppliers/:uuid/edit', (p) => supplierFormScreen(p)],
  ['/customers', () => customerListScreen()],
  ['/customers/new', () => customerFormScreen()],
  ['/customers/:id/payment', (p) => receivePaymentScreen(p)],
  ['/customers/:id/statement', (p) => customerStatementScreen(p)],
  ['/staff', () => staffListScreen()],
  ['/staff/new', () => staffFormScreen()],
  ['/expenses', () => expensesScreen()],
  ['/dashboard', () => dashboardScreen()],
  ['/import', () => importScreen()],
  ['/reports', () => reportsScreen()],
];
