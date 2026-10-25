import '../services/auth_service.dart';
import '../services/staff_access_service.dart';
import 'package:flutter/material.dart';
import '../models/sale.dart';
import '../services/shop_database.dart';
import 'sale_receipt_screen.dart';

class OrderSaleScreen extends StatelessWidget {
  const OrderSaleScreen({super.key, required this.orderId});
  final String orderId;
  Future<Sale> _load() async {
    if (AuthService.isStaff) {
      final order = await StaffAccessService.read('orders', orderId);
      final id = order['saleId'] as String?;
      if (id == null) throw StateError('ยังไม่มีใบเสร็จ');
      return Sale.fromFirestore(await StaffAccessService.read('sales', id), id);
    }
    final result = await ShopDatabase.shop
        .collection('sales')
        .where('orderId', isEqualTo: orderId)
        .limit(2)
        .get();
    if (result.docs.length != 1) {
      throw StateError('ไม่พบบิลที่เชื่อมโยงเพียงบิลเดียว');
    }
    final doc = result.docs.single;
    return Sale.fromFirestore(doc.data(), doc.id);
  }

  @override
  Widget build(BuildContext context) =>
      SaleReceiptScreen(loadSale: _load, allowRefund: true);
}
