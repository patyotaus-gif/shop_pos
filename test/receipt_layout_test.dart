import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/receipt_profile.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/utils/receipt_generator.dart';

final settings = <String, dynamic>{
  'name': 'ร้านตัวอย่าง Pokpok',
  'address': '21/922 หมู่ 12 แขวงบางนา เขตบางนา กรุงเทพมหานคร 10260',
  'taxId': '9100192800912',
  'branch': 'สำนักงานใหญ่',
  'phone': '02-123-4567',
  'website': 'example.com',
  'receiptVatEnabled': true,
  'receiptVatRate': 7
};

Sale sample(
        {ReceiptProfile? profile,
        bool debt = false,
        bool refunded = false,
        PaymentMethod method = PaymentMethod.cash,
        String? receiptNo = '691010-001',
        bool longName = false}) =>
    Sale(
        id: 'legacy-document-123',
        receiptNo: receiptNo,
        createdAt: DateTime(2026, 10, 10, 14, 36, 54),
        items: [
          SaleItem(
              productId: 'p',
              productName: longName
                  ? 'ชาไทยสูตรเข้มข้นหวานน้อย เพิ่มไข่มุกและครีมชีส บรรจุในแก้วขนาดใหญ่พิเศษ'
                  : 'ชาไทยเย็น ขนาดใหญ่',
              price: 50,
              quantity: 2,
              subtotal: 100),
          const SaleItem(
              productId: 'c',
              productName: 'บราวนี่ช็อกโกแลต',
              price: 25,
              quantity: 1,
              subtotal: 25,
              notes: 'แยกถุงกลับบ้าน')
        ],
        total: 107,
        discount: 23,
        serviceCharge: 5,
        paid: debt
            ? 0
            : method == PaymentMethod.cash
                ? 120
                : 107,
        change: debt || method != PaymentMethod.cash ? 0 : 13,
        paymentMethod: method,
        isDebt: debt,
        customerName: debt ? 'ลูกค้าทดสอบ' : null,
        isRefunded: refunded,
        staffName: 'พนักงานทดสอบ',
        tableName: '1',
        receiptProfile: profile);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('VAT is opt-in, requires issuer details, and legacy stays a receipt',
      () {
    expect(ReceiptProfile.fromSettings({}).vatEnabled, false);
    expect(
        ReceiptProfile.fromSettings({...settings, 'receiptVatEnabled': false})
            .vatEnabled,
        false);
    expect(
        ReceiptProfile.fromSettings({...settings, 'taxId': '123'}).vatEnabled,
        false);
    expect(ReceiptProfile.fromSettings({...settings, 'address': ''}).vatEnabled,
        false);
    expect(
        ReceiptProfile.fromSettings({...settings, 'receiptVatRate': double.nan})
            .vatEnabled,
        false);
    expect(ReceiptProfile.fromSettings(settings, allowVat: false).vatEnabled,
        false);
    expect(ReceiptProfile.fromSettings(settings).vatEnabled, true);
    expect(
        ReceiptProfile.fromSettings({...settings, 'receiptVatRate': '7'})
            .vatEnabled,
        false);
  });
  test('included VAT reconciles exactly to total after discount and service',
      () {
    final p = ReceiptProfile.fromSettings(settings);
    expect(p.includedVat(sample().total), (netMinor: 10000, vatMinor: 700));
    expect(p.includedVat(109889), (netMinor: 10270000, vatMinor: 718900));
    for (final total in [0.0, 0.01, 20.02, 75.91, 110.30, 999999.99]) {
      final amount = p.includedVat(total);
      expect(amount.netMinor + amount.vatMinor, (total * 100).round());
    }
    expect(ReceiptProfile.fromSettings({}).includedVat(107),
        (netMinor: 10700, vatMinor: 0));
  });
  test('sale round trip freezes receipt profile and original document/date',
      () {
    final p = ReceiptProfile.fromSettings(settings);
    final sale = sample(profile: p);
    final saved = Sale.fromFirestore(sale.toFirestore(), sale.id);
    expect(saved.receiptProfile!.toMap(), p.toMap());
    final changed = ReceiptProfile.fromSettings(
        {...settings, 'name': 'New shop', 'receiptVatRate': 10});
    expect(saved.receiptProfile!.name, isNot(changed.name));
    expect(saved.receiptProfile!.vatRate, 7);
    expect(ReceiptGenerator.saleDate(saved.createdAt), '10/10/2569 14:36:54');
    expect(ReceiptGenerator.documentNumber(sample(receiptNo: null)),
        'legacy-document-123');
  });
  test(
      'receipt PDF builds with Thai text, long names, tax, credit and refund states',
      () async {
    final directory = Directory('.remember/tmp/receipt-preview')
      ..createSync(recursive: true);
    final tax = ReceiptProfile.fromSettings(settings);
    final general = ReceiptProfile.fromSettings(settings, allowVat: false);
    final cases = {
      'vat': sample(profile: tax, longName: true),
      'general': sample(profile: general),
      'transfer': sample(profile: tax, method: PaymentMethod.transfer),
      'credit': sample(profile: tax, debt: true),
      'refunded': sample(profile: tax, refunded: true),
      'legacy': sample(receiptNo: null)
    };
    for (final entry in cases.entries) {
      final bytes = await ReceiptGenerator.buildDocument(entry.value,
          profile: entry.value.receiptProfile ?? general);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(5000));
      await File('${directory.path}/${entry.key}.pdf').writeAsBytes(bytes);
    }
    await File('${directory.path}/vat80.pdf').writeAsBytes(
        await ReceiptGenerator.buildDocument(sample(profile: tax),
            profile: tax, paperWidthMm: 80));
  });
}
