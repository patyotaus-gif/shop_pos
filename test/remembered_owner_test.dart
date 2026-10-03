import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/services/remembered_owner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('shared device is locked until explicit owner opt-in', () async {
    expect(await RememberedOwner().matches('owner', isStaff: false), false);
  });
  test('personal device remembers only the same authenticated owner', () async {
    await RememberedOwner().save('owner');
    final restarted = RememberedOwner();
    expect(await restarted.matches('owner', isStaff: false), true);
    expect(await restarted.matches('other', isStaff: false), false);
    expect(await restarted.matches('owner', isStaff: true), false);
  });
  test('sign-out or staff switch removes remembered owner', () async {
    final preference = RememberedOwner();
    await preference.save('owner');
    await preference.clear();
    expect(await RememberedOwner().matches('owner', isStaff: false), false);
  });
}
