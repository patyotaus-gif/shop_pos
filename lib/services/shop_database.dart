import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';

class ShopDatabase {
  @visibleForTesting
  static DocumentReference<Map<String, dynamic>>? overrideShop;

  static DocumentReference<Map<String, dynamic>> get shop =>
      overrideShop ??
      FirebaseFirestore.instance.collection('shops').doc(AuthService.shopId);
}
