import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SaleDisplayMode { photos, names }

/// Presentation only. No prices, product records or permissions live here.
class SaleDisplaySettings {
  const SaleDisplaySettings({
    this.mode = SaleDisplayMode.photos,
    this.categoryColors = const {},
    this.catalogTab = 'all',
  });

  final SaleDisplayMode mode;
  final Map<String, String> categoryColors;
  final String catalogTab;
  static const colorNames = ['wine', 'blue', 'teal', 'amber', 'purple'];

  factory SaleDisplaySettings.decode(String? raw) {
    if (raw == null) return const SaleDisplaySettings();
    final data = jsonDecode(raw);
    if (data is! Map) throw const FormatException('Invalid display settings');
    final colors = data['categoryColors'];
    return SaleDisplaySettings(
      mode: data['mode'] == 'names'
          ? SaleDisplayMode.names
          : SaleDisplayMode.photos,
      catalogTab:
          data['catalogTab'] is String ? data['catalogTab'] as String : 'all',
      categoryColors: Map.unmodifiable({
        if (colors is Map)
          for (final entry in colors.entries)
            if (entry.key is String && colorNames.contains(entry.value))
              entry.key as String: entry.value as String,
      }),
    );
  }

  String encode() => jsonEncode({
        'mode': mode.name,
        'categoryColors': categoryColors,
        'catalogTab': catalogTab
      });

  SaleDisplaySettings withMode(SaleDisplayMode mode) => SaleDisplaySettings(
      mode: mode, categoryColors: categoryColors, catalogTab: catalogTab);

  SaleDisplaySettings withCatalogTab(String tab) => SaleDisplaySettings(
      mode: mode, categoryColors: categoryColors, catalogTab: tab);

  SaleDisplaySettings withColor(String category, String? color) {
    final next = Map<String, String>.of(categoryColors)..remove(category);
    if (colorNames.contains(color)) next[category] = color!;
    return SaleDisplaySettings(
        mode: mode,
        categoryColors: Map.unmodifiable(next),
        catalogTab: catalogTab);
  }
}

/// One shared controller per shop on this device, including owner/staff views.
/// Settings are deliberately local, just like the app's theme preference.
class SaleDisplayController extends ChangeNotifier {
  SaleDisplayController(this.shopId);
  final String shopId;
  SaleDisplaySettings value = const SaleDisplaySettings();
  bool loaded = false;
  bool busy = false;
  bool loadFailed = false;
  String get storageKey => 'saleDisplay.v1.${Uri.encodeComponent(shopId)}';

  Future<void> load() async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      value = SaleDisplaySettings.decode(prefs.getString(storageKey));
      loadFailed = false;
    } catch (_) {
      loadFailed = true;
    } finally {
      loaded = true;
      busy = false;
      notifyListeners();
    }
  }

  Future<void> save(SaleDisplaySettings next) async {
    if (busy || !loaded) return;
    busy = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(storageKey, next.encode())) {
        throw StateError('Could not save display settings');
      }
      value = next;
      loadFailed = false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

abstract final class SaleDisplayService {
  static final _controllers = <String, SaleDisplayController>{};

  static SaleDisplayController? forShop(String? shopId) {
    if (shopId == null || shopId.isEmpty) return null;
    return _controllers.putIfAbsent(
        shopId, () => SaleDisplayController(shopId)..load());
  }
}
