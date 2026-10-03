import 'dart:async';

/// One registration per active shop, even when snapshots rebuild the UI.
class NotificationRegistration {
  String? _shopId;
  String? _savedToken;
  int _generation = 0;
  Future<void>? _starting;
  StreamSubscription<String>? _subscription;

  Future<void> start(
    String shopId, {
    required Future<String?> Function() getToken,
    required Stream<String> tokenChanges,
    required Future<void> Function(String shopId, String token) save,
  }) {
    if (_shopId == shopId) return _starting ?? Future.value();
    stop();
    _shopId = shopId;
    final generation = _generation;
    Future<void> persist(String token) async {
      if (generation != _generation || token == _savedToken) return;
      // Mark before the write so a snapshot/duplicate refresh cannot loop.
      _savedToken = token;
      try {
        await save(shopId, token);
      } catch (_) {
        if (generation == _generation && _savedToken == token) {
          _savedToken = null;
        }
      }
    }

    _subscription = tokenChanges.listen((token) {
      persist(token);
    }, onError: (Object _) {});
    return _starting = () async {
      try {
        final token = await getToken();
        if (generation == _generation && _savedToken == null && token != null) {
          await persist(token);
        }
      } catch (_) {
        // Notifications must not disrupt selling or retry on every snapshot.
      }
    }();
  }

  void stop() {
    _generation++;
    _subscription?.cancel();
    _subscription = null;
    _shopId = null;
    _savedToken = null;
    _starting = null;
  }
}
