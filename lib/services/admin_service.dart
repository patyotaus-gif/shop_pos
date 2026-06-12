import 'package:cloud_functions/cloud_functions.dart';

/// Client wrapper for the founder-only admin Cloud Functions. Every call
/// hits a callable that re-checks the founder allowlist server-side, so
/// this service is safe to expose behind the (also founder-gated) console
/// UI — the gating here is convenience, not the security boundary.
class AdminService {
  static HttpsCallable _fn(String name) =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable(name);

  /// All shops with subscription state + their hardware requests.
  static Future<List<Map<String, dynamic>>> listShops() async {
    final res = await _fn('adminListShops').call();
    final data = Map<String, dynamic>.from(res.data as Map);
    final raw = (data['shops'] as List?) ?? const [];
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  static Future<void> extendTrial(String shopId, int days) =>
      _fn('adminSetSubscription')
          .call({'shopId': shopId, 'op': 'extendTrial', 'days': days});

  static Future<void> activate(
    String shopId, {
    required int days,
    String? tier,
    String? billingCycle,
    int? locations,
  }) =>
      _fn('adminSetSubscription').call({
        'shopId': shopId,
        'op': 'activate',
        'days': days,
        if (tier != null) 'tier': tier,
        if (billingCycle != null) 'billingCycle': billingCycle,
        if (locations != null) 'locations': locations,
      });

  static Future<void> expire(String shopId) =>
      _fn('adminSetSubscription').call({'shopId': shopId, 'op': 'expire'});

  /// Grant or revoke the founder custom claim for the account with [email].
  /// Takes effect on that user's next token refresh / re-login.
  static Future<void> setFounder(String email, bool founder) =>
      _fn('adminSetFounder').call({'email': email, 'founder': founder});

  static Future<void> setHardwareStatus(
    String shopId,
    String requestId, {
    String? status,
    String? note,
    String? serialNumber,
  }) =>
      _fn('adminSetHardwareStatus').call({
        'shopId': shopId,
        'requestId': requestId,
        if (status != null) 'status': status,
        if (note != null) 'note': note,
        if (serialNumber != null) 'serialNumber': serialNumber,
      });

  /// Create (supplierId == null) or update a supplier. Returns its id.
  static Future<String> upsertSupplier({
    String? supplierId,
    required String name,
    String category = '',
    String area = '',
    String deliveryDays = '',
    double minOrder = 0,
    bool active = true,
  }) async {
    final res = await _fn('adminUpsertSupplier').call({
      if (supplierId != null) 'supplierId': supplierId,
      'name': name,
      'category': category,
      'area': area,
      'deliveryDays': deliveryDays,
      'minOrder': minOrder,
      'active': active,
    });
    return Map<String, dynamic>.from(res.data as Map)['supplierId'] as String;
  }

  /// Create a login-enabled supplier (Firebase Auth account + supplier doc
  /// whose id is that account's uid). Returns the supplier id. Throws
  /// 'already-exists' if the email is taken.
  static Future<String> createSupplierAccount({
    required String email,
    required String password,
    required String name,
    String category = '',
    String area = '',
    String deliveryDays = '',
    double minOrder = 0,
  }) async {
    final res = await _fn('adminCreateSupplierAccount').call({
      'email': email,
      'password': password,
      'name': name,
      'category': category,
      'area': area,
      'deliveryDays': deliveryDays,
      'minOrder': minOrder,
    });
    return Map<String, dynamic>.from(res.data as Map)['supplierId'] as String;
  }

  /// Create (productId == null) or update one catalog line. Returns its id.
  static Future<String> upsertSupplierProduct({
    required String supplierId,
    String? productId,
    required String name,
    String unit = 'ชิ้น',
    double price = 0,
    int moq = 1,
    bool available = true,
  }) async {
    final res = await _fn('adminUpsertSupplierProduct').call({
      'supplierId': supplierId,
      if (productId != null) 'productId': productId,
      'name': name,
      'unit': unit,
      'price': price,
      'moq': moq,
      'available': available,
    });
    return Map<String, dynamic>.from(res.data as Map)['productId'] as String;
  }
}
