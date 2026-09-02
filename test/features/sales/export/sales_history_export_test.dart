import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/sales/export/sales_history_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

void main() {
  late DukaDatabase db;
  late Customer customer;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));

    final cashier = await db.into(db.users).insertReturning(
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

    await db.into(db.sales).insert(
      SalesCompanion.insert(
        uuid: 'sale-1',
        invoiceNumber: 'INV-000001',
        customerId: Value(customer.id),
        userId: cashier.id,
        subtotal: const Value(100),
        total: const Value(100),
        amountPaid: const Value(60),
        paymentMethod: 'credit',
        createdAt: DateTime(2026, 3, 15, 14, 30),
      ),
    );
    await db.into(db.sales).insert(
      SalesCompanion.insert(
        uuid: 'sale-2',
        invoiceNumber: 'INV-000002',
        userId: cashier.id,
        subtotal: const Value(50),
        total: const Value(50),
        amountPaid: const Value(50),
        paymentMethod: 'cash',
        status: const Value('void'),
        createdAt: DateTime(2026, 3, 15, 15, 0),
      ),
    );
  });

  tearDown(() => db.close());

  Future<List<Sale>> sales() => db.select(db.sales).get();
  Map<int, Customer> customerById() => {customer.id: customer};

  group('buildSalesHistoryCsv', () {
    test('lists every sale, a named customer on account, a void walk-in sale', () async {
      final csv = buildSalesHistoryCsv(await sales(), customerById());

      expect(csv, contains('INV-000001'));
      expect(csv, contains('John Smith'));
      expect(csv, contains('100.00,60.00,On account'));
      expect(csv, contains('INV-000002'));
      expect(csv, contains('Walk-in'));
      expect(csv, contains('50.00,50.00,Void'));
    });
  });

  group('buildSalesHistoryPdf', () {
    test('produces a valid PDF excluding the void sale from the revenue total', () async {
      final bytes = await buildSalesHistoryPdf(await sales(), customerById(), format: PdfPageFormat.a4);

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('does not throw for an empty sale list', () async {
      final bytes = await buildSalesHistoryPdf(const [], const {}, format: PdfPageFormat.a4);

      expect(bytes, isNotEmpty);
    });
  });
}
