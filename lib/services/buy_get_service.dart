import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/cart_item.dart';
import '../models/sale.dart';
import 'staff_access_service.dart';

class BuyGetService {
  static Future<Map<String, dynamic>> preview(List<CartItem> cart) async {
    final result = await StaffAccessService.call('quoteCounterGifts', {
      'items': cart
          .map((i) => {
                'productId': i.product.id,
                'quantity': i.quantity,
                'optionIds': i.modifiers.map((m) => m.optionId).toList()
              })
          .toList(),
    });
    return {
      for (final key in ['buyGet', 'bundles'])
        key: ((result[key] as List?) ?? [])
            .map((g) => Map<String, dynamic>.from(g as Map))
            .toList()
    };
  }

  // Owner checkout uses the same config and rechecks it inside the stock/sale
  // transaction. Staff checkout performs this check on the server.
  static Future<List<Map<String, dynamic>>> quote(Transaction tx,
      DocumentReference<Map<String, dynamic>> shop, List<SaleItem> items,
      {DateTime? now}) async {
    final counts = <String, num>{};
    for (final item in items.where((i) => !i.isGift)) {
      counts.update(item.productId, (n) => n + item.quantity,
          ifAbsent: () => item.quantity);
    }
    final gifts = <Map<String, dynamic>>[];
    for (final id in counts.keys) {
      final c =
          (await tx.get(shop.collection('buyGetPromotions').doc(id))).data();
      if (c == null ||
          c['active'] != true ||
          !(c['endsAt'] as Timestamp).toDate().isAfter(now ?? DateTime.now())) {
        continue;
      }
      final sets = (counts[id]! ~/ (c['buyQuantity'] as int))
          .clamp(0, c['maxSets'] as int);
      if (sets == 0) continue;
      final product = (await tx.get(
              shop.collection('products').doc(c['giftProductId'] as String)))
          .data();
      if (product == null ||
          product['isWeighed'] == true ||
          ((product['modifierGroupIds'] as List?)?.isNotEmpty ?? false)) {
        throw StateError('สินค้าแถมเปลี่ยนไป กรุณาตรวจโปรโมชั่นใหม่');
      }
      gifts.add({
        'promotionId': id,
        'revision': c['revision'],
        'productId': c['giftProductId'],
        'productName': product['name'] ?? '',
        'quantity': sets * (c['giftQuantity'] as int)
      });
    }
    return gifts;
  }

  static String fingerprint(List<Map<String, dynamic>> gifts) {
    final rows = gifts
        .map((g) => [
              g['promotionId'],
              g['revision'],
              g['productId'],
              g['productName'],
              g['quantity']
            ])
        .toList();
    rows.sort((a, b) => (a.first as String).compareTo(b.first as String));
    return jsonEncode(rows);
  }

  static Future<void> validate(Transaction tx,
      DocumentReference<Map<String, dynamic>> shop, Sale draft) async {
    final current = await quote(tx, shop, draft.items);
    if (fingerprint(current) != fingerprint(draft.buyGet)) {
      throw StateError('โปรซื้อแถมเปลี่ยนแล้ว กรุณาตรวจของแถมก่อนรับเงิน');
    }
    final free = draft.items.where((i) => i.isGift).toList();
    if (free.length != draft.buyGet.length) {
      throw StateError('รายการของแถมไม่ตรงกับโปรโมชั่น');
    }
    for (var n = 0; n < free.length; n++) {
      final i = free[n], g = draft.buyGet[n];
      if (i.productId != g['productId'] ||
          i.quantity != g['quantity'] ||
          i.price != 0 ||
          i.subtotal != 0 ||
          i.modifiers.isNotEmpty) {
        throw StateError('รายการของแถมไม่ตรงกับโปรโมชั่น');
      }
    }
  }
}
