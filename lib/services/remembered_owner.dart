import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device preference only; Firebase still authenticates and authorizes the user.
class RememberedOwner {
  RememberedOwner({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'remembered_owner_uid';

  Future<bool> matches(String uid, {required bool isStaff}) async {
    if (isStaff) return false;
    try {
      return await _storage.read(key: _key) == uid;
    } catch (_) {
      return false; // Locked when secure storage is unavailable.
    }
  }

  Future<void> save(String uid) => _storage.write(key: _key, value: uid);
  Future<void> clear() => _storage.delete(key: _key);
}
