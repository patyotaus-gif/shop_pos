import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

import '../models/order.dart';
import '../utils/bank_notification_parser.dart';
import '../utils/bank_payment_match.dart';
import 'auth_service.dart';

/// Bridges Android's NotificationListenerService with our PromptPay order
/// pipeline. When a banking app posts an incoming-funds notification, we:
///   1. parse the amount + sender out of the notification text,
///   2. look for a pendingPayment order whose finalAmount matches,
///   3. attach an unverified matching hint for the owner's bank check.
///
/// iOS is silently a no-op — Apple doesn't expose other apps' notifications.
class BankNotificationService {
  static bool _initialized = false;
  static Stream<dynamic>? _eventStream;

  /// Hook the OS notification stream once per process. Safe to call from
  /// main() on every platform — no-ops everywhere except Android.
  static Future<void> init() async {
    if (_initialized) return;
    if (!Platform.isAndroid) {
      _initialized = true;
      return;
    }
    try {
      _eventStream = NotificationListenerService.notificationsStream;
      _eventStream!.listen((event) async {
        try {
          await _onNotification(event);
        } catch (_) {
          debugPrint('[BankNotificationService] review hint unavailable');
        }
      }, onError: (Object e, StackTrace st) {
        debugPrint('[BankNotificationService] stream error: $e');
      });
    } catch (e) {
      debugPrint('[BankNotificationService] init failed: $e');
    }
    _initialized = true;
  }

  /// True if the user has already granted Notification Access. On iOS this
  /// always returns false.
  static Future<bool> isPermissionGranted() async {
    if (!Platform.isAndroid) return false;
    try {
      return await NotificationListenerService.isPermissionGranted();
    } catch (_) {
      return false;
    }
  }

  /// Opens the system Notification Access settings page so the user can
  /// flip the toggle for Pokpok POS. Returns whether permission ended up
  /// granted after the user came back.
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      return await NotificationListenerService.requestPermission();
    } catch (e) {
      debugPrint('[BankNotificationService] requestPermission: $e');
      return false;
    }
  }

  static Future<void> _onNotification(dynamic event) async {
    if (event is! ServiceNotificationEvent) return;

    final pkg = event.packageName ?? '';
    if (!BankNotificationParser.supportedPackages.contains(pkg)) return;

    final title = event.title ?? '';
    final text = event.content ?? '';
    final parsed = BankNotificationParser.parse(
      packageName: pkg,
      title: title,
      text: text,
    );
    if (parsed == null) {
      return;
    }

    await _suggestForReview(parsed);
  }

  static Future<void> _suggestForReview(BankIncomingTransfer transfer) async {
    final shopId = AuthService.shopId;
    if (shopId == null || AuthService.isStaff) return;

    final col = FirebaseFirestore.instance
        .collection('shops')
        .doc(shopId)
        .collection('orders');

    final observedAt = DateTime.now();
    final snap = await col
        .where('status', isEqualTo: OrderStatus.pendingPayment.name)
        .get();

    // Include older pending bills: a delayed transfer must not be silently
    // assigned to a newer same-amount bill. Every suggestion requires review.
    final matches = snap.docs.where((d) {
      final amt = (d.data()['finalAmount'] as num?)?.toDouble() ??
          (d.data()['total'] as num?)?.toDouble() ??
          0;
      final data = d.data();
      if (data['paymentMethod'] == 'stripe' ||
          data['paymentMethod'] == 'omise') {
        return false;
      }
      return bankPaymentCandidate(
          expected: amt,
          received: transfer.amount,
          createdAt: (data['createdAt'] as Timestamp?)?.toDate() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          observedAt: observedAt,
          transferredAt: transfer.transferredAt);
    }).toList();

    if (matches.isEmpty) {
      debugPrint(
          '[BankNotificationService] no pending order at ${transfer.amount}');
      return;
    }
    // Each transaction rechecks state so late hints cannot modify paid bills.
    for (final match in matches) {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final latest = (await tx.get(match.reference)).data();
        if (latest == null ||
            latest['status'] != 'pendingPayment' ||
            latest['paidAt'] != null ||
            latest['saleId'] != null) {
          return;
        }
        tx.update(match.reference, {
          'bankMatchStatus':
              matches.length > 1 || latest['bankMatchStatus'] == 'ambiguous'
                  ? 'ambiguous'
                  : 'awaitingOwner',
          'bankMatchAt': FieldValue.serverTimestamp(),
          'bankMatchRef': 'notification:${transfer.bankCode}',
          'paymentSender': transfer.sender,
          'autoConfirmed': false,
        });
      });
    }
  }
}
