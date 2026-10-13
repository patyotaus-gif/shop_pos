import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/operation_error.dart';

/// Blocks navigation and repeated taps only while a confirmed write is running.
/// [timeout] only releases the UI; it cannot cancel a remote write. Use it for
/// idempotent actions whose uncertain result can be checked before retrying.
Future<T> runShopOperation<T>(BuildContext context, Future<T> Function() action,
    {String message = 'กำลังบันทึก กรุณารอสักครู่', Duration? timeout}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(message, textAlign: TextAlign.center),
        ]),
      ),
    ),
  );
  unawaited(navigator.push(route));
  try {
    final pending = action();
    return await (timeout == null ? pending : pending.timeout(timeout));
  } finally {
    if (route.isActive) navigator.removeRoute(route);
  }
}

Future<bool> performShopOperation(
    BuildContext context, Future<void> Function() action,
    {String success = 'บันทึกแล้ว',
    String message = 'กำลังบันทึก กรุณารอสักครู่',
    Duration? timeout}) async {
  try {
    await runShopOperation(context, action, message: message, timeout: timeout);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(operationError(error))));
    }
    return false;
  }
}
