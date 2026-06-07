import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's theme choice across launches. Defaults to **light**
/// — the Pokpok brand is a light design, so the app does NOT follow the
/// device's system dark setting; dark is opt-in from Settings.
class ThemeService {
  static const _key = 'themeMode';

  static Future<ThemeMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  static Future<void> save(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode == ThemeMode.dark ? 'dark' : 'light');
  }
}
