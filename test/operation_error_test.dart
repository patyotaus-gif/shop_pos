import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/utils/operation_error.dart';

void main() {
  test('authentication or attestation failure is not a missing permission', () {
    final message = operationError(FirebaseFunctionsException(
        code: 'unauthenticated', message: 'Unauthenticated'));
    expect(message, contains('ยืนยันบัญชีหรือแอพไม่สำเร็จ'));
    expect(message, isNot(contains('ไม่มีสิทธิ์')));
    expect(
        operationError(FirebaseFunctionsException(
            code: 'permission-denied', message: 'Permission denied')),
        contains('ไม่มีสิทธิ์'));
  });

  test('business rejection and uncertain completion remain distinct', () {
    expect(
        operationError(FirebaseFunctionsException(
            code: 'failed-precondition', message: 'กรุณาเปิดรอบก่อน')),
        'กรุณาเปิดรอบก่อน');
    expect(operationError(TimeoutException('timeout')),
        contains('สถานะรายการก่อนลองซ้ำ'));
  });
}
