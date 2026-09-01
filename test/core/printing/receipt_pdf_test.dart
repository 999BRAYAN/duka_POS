import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/printing/receipt_pdf.dart';
import 'package:pdf/pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late User cashier;
  late Customer customer;
  late Product productA;
  late Product productB;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));

    cashier = await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-1',
        username: 'jane',
        passwordHash: 'hash',
        fullName: 'Jane Doe',
        role: 'cashier',
        createdAt: DateTime.now(),
      ),
    );
    customer = await db.into(db.customers).insertReturning(
      CustomersCompanion.insert(uuid: 'cust-1', name: 'John Smith', createdAt: DateTime.now()),
    );
    productA = await db.into(db.products).insertReturning(
      ProductsCompanion.insert(uuid: 'prod-a', name: 'Soda', createdAt: DateTime.now()),
    );
    productB = await db.into(db.products).insertReturning(
      ProductsCompanion.insert(uuid: 'prod-b', name: 'Bread', createdAt: DateTime.now()),
    );
  });

  tearDown(() => db.close());

  Future<Sale> insertSale({
    int? customerId,
    double discount = 0,
    double amountPaid = 200,
  }) {
    return db.into(db.sales).insertReturning(
      SalesCompanion.insert(
        uuid: 'sale-1',
        invoiceNumber: 'INV-000001',
        customerId: Value(customerId),
        userId: cashier.id,
        subtotal: const Value(210),
        discount: Value(discount),
        total: Value(210 - discount),
        amountPaid: Value(amountPaid),
        paymentMethod: 'credit',
        createdAt: DateTime(2026, 3, 15, 14, 30),
      ),
    );
  }

  Future<List<SaleItem>> insertItems(int saleId) async {
    final item1 = await db.into(db.saleItems).insertReturning(
      SaleItemsCompanion.insert(
        uuid: 'item-1',
        saleId: saleId,
        productId: productA.id,
        quantity: 2,
        unitPrice: 70,
        total: 140,
        createdAt: DateTime(2026, 3, 15, 14, 30),
      ),
    );
    final item2 = await db.into(db.saleItems).insertReturning(
      SaleItemsCompanion.insert(
        uuid: 'item-2',
        saleId: saleId,
        productId: productB.id,
        quantity: 1,
        unitPrice: 70,
        total: 70,
        createdAt: DateTime(2026, 3, 15, 14, 30),
      ),
    );
    return [item1, item2];
  }

  Map<int, Product> productsById() => {productA.id: productA, productB.id: productB};

  test('produces a valid, non-empty PDF for a credit sale left with a balance', () async {
    final sale = await insertSale(customerId: customer.id, amountPaid: 150);
    final items = await insertItems(sale.id);

    final bytes = await buildReceiptPdf(
      sale: sale,
      items: items,
      productsById: productsById(),
      cashier: cashier,
      customer: customer,
      format: PdfPageFormat.a4,
    );

    expect(bytes, isNotEmpty);
    // The PDF file-format magic header — proof this is a real PDF, not
    // just arbitrary bytes.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('does not throw for a walk-in sale (no customer) paid in full', () async {
    final sale = await insertSale(); // no customerId, amountPaid defaults to the full total
    final items = await insertItems(sale.id);

    final bytes = await buildReceiptPdf(
      sale: sale,
      items: items,
      productsById: productsById(),
      cashier: cashier,
      customer: null,
      format: PdfPageFormat.a4,
    );

    expect(bytes, isNotEmpty);
  });

  test('does not throw when the cashier is unknown or a line references an unmapped product', () async {
    final sale = await insertSale();
    final items = await insertItems(sale.id);

    final bytes = await buildReceiptPdf(
      sale: sale,
      items: items,
      productsById: const {}, // deliberately missing both products
      cashier: null,
      customer: null,
      format: PdfPageFormat.a4,
    );

    expect(bytes, isNotEmpty);
  });

  test('more line items produce a larger document', () async {
    final sale = await insertSale();
    final items = await insertItems(sale.id);

    final smaller = await buildReceiptPdf(
      sale: sale,
      items: [items.first],
      productsById: productsById(),
      cashier: cashier,
      customer: null,
      format: PdfPageFormat.a4,
    );
    final larger = await buildReceiptPdf(
      sale: sale,
      items: items,
      productsById: productsById(),
      cashier: cashier,
      customer: null,
      format: PdfPageFormat.a4,
    );

    expect(larger.length, greaterThan(smaller.length));
  });
}
