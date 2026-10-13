num stockRound(num value) {
  final scaled = (value * 1000).round();
  return scaled % 1000 == 0 ? scaled ~/ 1000 : scaled / 1000;
}

String stockText(num value) => value == 0
    ? '0'
    : value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
bool validLot(Map lot) {
  final date = lot['expiresOn'];
  return lot['id'] is String &&
      (lot['id'] as String).isNotEmpty &&
      lot['number'] is String &&
      (lot['number'] as String).trim().isNotEmpty &&
      date is String &&
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) &&
      DateTime.tryParse(date)?.toIso8601String().startsWith(date) == true &&
      lot['quantity'] is num &&
      validStockQuantity(lot['quantity'], weight: true, zero: true);
}

bool validStockQuantity(num value, {bool weight = false, bool zero = false}) =>
    value.isFinite &&
    value >= (zero ? 0 : 0.001) &&
    value <= 100000000 &&
    (weight
        ? (value * 1000 - (value * 1000).round()).abs() < 0.000001
        : value == value.round());

String stockToday() => DateTime.now()
    .toUtc()
    .add(const Duration(hours: 7))
    .toIso8601String()
    .substring(0, 10);

class StockAllocation {
  final List<Map<String, dynamic>> lots;
  final List<Map<String, dynamic>> used;
  StockAllocation(this.lots, this.used);
}

List<Map<String, dynamic>> stockLots(Map<String, dynamic> product) {
  final lots = (product['stockLots'] as List? ?? [])
      .map((l) => Map<String, dynamic>.from(l as Map))
      .toList();
  if (lots.any((l) => !validLot(l)) ||
      lots.map((l) => l['id']).toSet().length != lots.length ||
      (lots.fold<num>(0, (s, l) => s + (l['quantity'] as num)) -
                  (product['stock'] as num? ?? 0))
              .abs() >
          0.000001) {
    throw StateError('จำนวนล็อตไม่ตรงกับสต๊อก กรุณาตรวจสอบ');
  }
  return lots;
}

num saleableStock(Map<String, dynamic> product, {String? today}) {
  if (product['trackLots'] != true) return product['stock'] as num? ?? 0;
  final day = today ?? stockToday();
  return stockRound(stockLots(product).fold<num>(0, (sum, raw) {
    final lot = raw as Map;
    return sum +
        ((lot['expiresOn'] as String? ?? '').compareTo(day) >= 0
            ? (lot['quantity'] as num? ?? 0)
            : 0);
  }));
}

StockAllocation allocateStock(Map<String, dynamic> product, num quantity,
    {String? today}) {
  if (!validStockQuantity(quantity, weight: product['isWeighed'] == true)) {
    throw StateError('จำนวนสินค้าไม่ถูกต้อง');
  }
  if (product['trackLots'] != true) return StockAllocation([], []);
  final lots = stockLots(product);
  final day = today ?? stockToday();
  if (saleableStock(product, today: day) + 1e-9 < quantity) {
    throw StateError('ล็อตที่ยังไม่หมดอายุมีไม่พอ กรุณาตรวจสต๊อก');
  }
  lots.sort((a, b) =>
      '${a['expiresOn']}:${a['id']}'.compareTo('${b['expiresOn']}:${b['id']}'));
  num remaining = quantity;
  final used = <Map<String, dynamic>>[];
  for (final lot in lots) {
    if (remaining <= 0 || (lot['expiresOn'] as String).compareTo(day) < 0) {
      continue;
    }
    final available = lot['quantity'] as num;
    final take = available < remaining ? available : remaining;
    if (take <= 0) continue;
    used.add({...lot, 'quantity': take});
    lot['quantity'] = stockRound(available - take);
    remaining = stockRound(remaining - take);
  }
  return StockAllocation(lots, used);
}
