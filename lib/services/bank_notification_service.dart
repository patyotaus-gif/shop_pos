import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

import '../models/order.dart';
import '../utils/bank_notification_parser.dart';
import 'auth_service.dart';

/// Bridges Android's NotificationListenerService with our PromptPay order
/// pipeline. When a banking app posts an incoming-funds notification, we:
///   1. parse the amount + sender out of the notification text,
///   2. look for a pendingPayment order whose finalAmount matches,
///   3. flip that order to 'paid' and stamp the bank ref.
///
/// iOS is silently a no-op — Apple doesn't expose other apps' notifications.
class BankNotificationService {
  static bool _initialized = false;
  static Stream<dynamic>? _eventStream;

  /// Window we'll consider a banking notification "fresh enough" to match
  /// against a pending order. Longer than this and we assume it's history
  /// being replayed.
  static const Duration _matchWindow = Duration(minutes: 30);

  /// Tolerance when matching amounts. Banking apps sometimes round to two
  /// decimals differently (29.95 vs 29.96), so allow 1 satang either way.
  static const double _amountTolerance = 0.01;

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
      _eventStream!.listen(_onNotification, onError: (Object e, StackTrace st) {
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
      debugPrint('[BankNotificationService] no match for $pkg: $title / $text');
      return;
    }

    debugPrint('[BankNotificationService] parsed: $parsed');
    await _matchAndConfirm(parsed);
  }

  static Future<void> _matchAndConfirm(BankIncomingTransfer transfer) async {
    final shopId = AuthService.shopId;
    if (shopId == null) return;

    final col = FirebaseFirestore.instance
        .collection('shops')
        .doc(shopId)
        .collection('orders');

    final since = DateTime.now().subtract(_matchWindow);
    final snap = await col
        .where('status', isEqualTo: OrderStatus.pendingPayment.name)
        .where('createdAt', isGreaterThan: Timestamp.fromDate(since))
        .get();

    // Match by finalAmount within tolerance. We allow only a single
    // unambiguous match — if two orders coincidentally land on the exact
    // same final amount (collision in our cents hash), fall back to manual
    // confirm so the shop owner picks the right one.
    final matches = snap.docs.where((d) {
      final amt = (d.data()['finalAmount'] as num?)?.toDouble() ??
          (d.data()['total'] as num?)?.toDouble() ??
          0;
      return (amt - transfer.amount).abs() <= _amountTolerance;
    }).toList();

    if (matches.isEmpty) {
      debugPrint('[BankNotificationService] no pending order at ${transfer.amount}');
      return;
    }
    if (matches.length > 1) {
      debugPrint(
        '[BankNotificationService] ambiguous: ${matches.length} orders at ${transfer.amount} — '
        'leaving for manual confirm',
      );
      return;
    }

    final orderRef = matches.single.reference;
    await orderRef.update({
      'status': OrderStatus.paid.name,
      'paidAt': FieldValue.serverTimestamp(),
      'paymentRef': 'auto:${transfer.bankCode}',
      'paymentSender': transfer.sender,
      'autoConfirmed': true,
    });
    debugPrint(
      '[BankNotificationService] auto-confirmed ${orderRef.id} via ${transfer.bankCode}',
    );
  }
}
