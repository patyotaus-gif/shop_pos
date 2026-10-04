import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

String operationError(Object error) {
  if (error is StateError) return error.message;
  if (error is FirebaseFunctionsException &&
      ['failed-precondition', 'invalid-argument', 'already-exists', 'not-found']
          .contains(error.code) &&
      error.message?.isNotEmpty == true) {
    return error.message!;
  }
  if (error is FirebaseException) {
    if (error.code == 'permission-denied' || error.code == 'unauthenticated') {
      return 'ไม่มีสิทธิ์ทำรายการ กรุณาตรวจสอบบัญชีที่เข้าสู่ระบบ';
    }
    if (['unavailable', 'deadline-exceeded', 'aborted'].contains(error.code)) {
      return 'ยังยืนยันการบันทึกไม่ได้ ตรวจอินเทอร์เน็ตแล้วลองรายการเดิมอีกครั้ง';
    }
  }
  return 'ทำรายการไม่สำเร็จ กรุณาลองอีกครั้ง หากยังมีปัญหาให้ติดต่อทีมงาน';
}
