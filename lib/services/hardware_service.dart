import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/hardware_request.dart';
import '../models/shop.dart';
import 'auth_service.dart';

/// Hardware shipments for the current shop. Lives under
/// `shops/{shopId}/hardware`. The founder/sales agent advances statuses
/// from an admin surface (separate build); the owner sees a read-only
/// tracker in Settings via [watchActive].
class HardwareService {
  static CollectionReference<Map<String, dynamic>> _col() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId)
          .collection('hardware');

  /// The shop's most recent non-returned request, or null. Used by the
  /// Settings tracker — a shop normally has one active kit at a time.
  static Stream<HardwareRequest?> watchActive() => _col()
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) {
        final active = s.docs
            .map((d) => HardwareRequest.fromFirestore(d.data(), d.id))
            .where((r) => r.status != HardwareStatus.returned)
            .toList();
        return active.isEmpty ? null : active.first;
      });

  /// Create the signup hardware request for a paying-intent tier.
  /// No-op for Solo (BYOD) — returns null without writing anything.
  ///
  /// Deposit/upfront defaults follow the GTM pricing:
  ///   - Lite: ฿4,000 peripheral up-front (financed handled later)
  ///   - Full: ฿1,000 refundable deposit
  ///   - Restaurant: ฿2,000 deposit per location
  static Future<String?> createForSignup({
    required ShopTier tier,
    int locations = 1,
  }) async {
    final kit = HardwareKitX.forTier(tier);
    if (kit == HardwareKit.none) return null; // Solo — nothing to ship

    final (deposit, upfront) = switch (tier) {
      ShopTier.lite => (0.0, 4000.0),
      ShopTier.full => (1000.0, 0.0),
      ShopTier.restaurant => (2000.0 * locations, 0.0),
      ShopTier.solo => (0.0, 0.0),
    };

    final ref = _col().doc();
    final request = HardwareRequest(
      id: ref.id,
      kit: kit,
      deposit: deposit,
      upfront: upfront,
      createdAt: DateTime.now(),
    );
    await ref.set(request.toFirestore());
    return ref.id;
  }
}
