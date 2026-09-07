import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/operation_error.dart';

/// Blocks navigation and repeated taps only while a confirmed write is running.
Future<T> runShopOperation<T>(BuildContext context, Future<T> Function() action,
    {String message = 'กำลังบันทึก กรุณารอสักครู่'}) async {
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
    return await action();
  } finally {
    if (route.isActive) navigator.removeRoute(route);
  }
}

Future<bool> performShopOperation(
    BuildContext context, Future<void> Function() action,
    {String success = 'บันทึกแล้ว'}) async {
  try {
    await runShopOperation(context, action);
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
