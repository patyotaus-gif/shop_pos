/// Frozen with a sale so later shop/tax edits do not rewrite old receipts.
class ReceiptProfile {
  final String name, address, taxId, branch, phone, website, logoUrl;
  final bool vatEnabled;
  final double vatRate;

  const ReceiptProfile(
      {required this.name,
      this.address = '',
      this.taxId = '',
      this.branch = '',
      this.phone = '',
      this.website = '',
      this.logoUrl = '',
      this.vatEnabled = false,
      this.vatRate = 7});

  static String _text(dynamic value) => value is String ? value.trim() : '';

  factory ReceiptProfile.fromSettings(Map<String, dynamic> data,
          {bool allowVat = true}) =>
      ReceiptProfile.fromMap({
        ...data,
        'vatEnabled': allowVat && data['receiptVatEnabled'] == true,
        'vatRate': data['receiptVatRate'] ?? 7,
      });

  factory ReceiptProfile.fromMap(Map<String, dynamic> data) {
    final name = _text(data['name']);
    final taxId = _text(data['taxId']);
    final address = _text(data['address']);
    final rate =
        data['vatRate'] is num ? (data['vatRate'] as num).toDouble() : 7.0;
    final validRate = (data['vatRate'] == null || data['vatRate'] is num) &&
        rate.isFinite &&
        rate > 0 &&
        rate <= 100 &&
        (rate * 100 - (rate * 100).round()).abs() < 0.000001;
    return ReceiptProfile(
        name: name.isEmpty ? 'ร้านของชำ' : name,
        address: address,
        taxId: taxId,
        branch: _text(data['branch']),
        phone: _text(data['phone']),
        website: _text(data['website']),
        logoUrl: _text(data['logoUrl']),
        vatRate: validRate ? rate : 7,
        vatEnabled: data['vatEnabled'] == true &&
            name.isNotEmpty &&
            address.isNotEmpty &&
            RegExp(r'^\d{13}$').hasMatch(taxId) &&
            validRate);
  }

  /// VAT is extracted from the paid total, never added to the customer's bill.
  ({int netMinor, int vatMinor}) includedVat(double total) {
    final gross = (total * 100).round();
    final rate = (vatRate * 100).round();
    final tax = vatEnabled ? (gross * rate / (10000 + rate)).round() : 0;
    return (netMinor: gross - tax, vatMinor: tax);
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'address': address,
        'taxId': taxId,
        'branch': branch,
        'phone': phone,
        'website': website,
        'logoUrl': logoUrl,
        'vatEnabled': vatEnabled,
        'vatRate': vatRate
      };
}
