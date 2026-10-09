import 'package:flutter/material.dart';

/// Shared visual language: warm neutral work surfaces and a wine accent.
/// Keep operational status colors separate from the brand accent.
abstract final class PokpokTheme {
  static const wine = Color(0xFF7A1F2B);
  static const paper = Color(0xFFF7F5F1);
  static const ink = Color(0xFF302526);
  static const fontFamily = 'IBM Plex Sans Thai';

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final cs =
        ColorScheme.fromSeed(seedColor: wine, brightness: brightness).copyWith(
      primary: dark ? const Color(0xFFF2ADB7) : wine,
      onPrimary: dark ? const Color(0xFF48101A) : Colors.white,
      primaryContainer:
          dark ? const Color(0xFF50232B) : const Color(0xFFF5E8EA),
      onPrimaryContainer:
          dark ? const Color(0xFFFFD9DF) : const Color(0xFF601623),
      surface: dark ? const Color(0xFF211E1D) : Colors.white,
      onSurface: dark ? const Color(0xFFF0E9E4) : ink,
      onSurfaceVariant:
          dark ? const Color(0xFFCCC1BA) : const Color(0xFF685E59),
      surfaceContainerLowest: dark ? const Color(0xFF191716) : Colors.white,
      surfaceContainerLow: dark ? const Color(0xFF272322) : paper,
      surfaceContainer:
          dark ? const Color(0xFF2D2927) : const Color(0xFFF1EDE7),
      surfaceContainerHigh:
          dark ? const Color(0xFF342F2D) : const Color(0xFFECE6DF),
      surfaceContainerHighest:
          dark ? const Color(0xFF3B3533) : const Color(0xFFE5DED5),
      outline: dark ? const Color(0xFF9B8D84) : const Color(0xFF85776E),
      outlineVariant: dark ? const Color(0xFF514841) : const Color(0xFFE0D9D1),
    );
    final base =
        ThemeData(useMaterial3: true, colorScheme: cs, fontFamily: fontFamily);
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outline));
    return base.copyWith(
      scaffoldBackgroundColor: dark ? const Color(0xFF191716) : paper,
      textTheme: base.textTheme.copyWith(
        titleLarge:
            base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        titleMedium:
            base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.45),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF191716) : paper,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
            color: cs.onSurface, fontWeight: FontWeight.w600, fontSize: 20),
      ),
      cardTheme: CardThemeData(
        color: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: shape.copyWith(side: BorderSide(color: cs.outlineVariant)),
      ),
      dividerTheme: DividerThemeData(color: cs.outlineVariant, thickness: 1),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
        textStyle: const TextStyle(
            fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
        side: BorderSide(color: cs.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      )),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
      )),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
            borderSide: BorderSide(color: cs.primary, width: 2)),
        hintStyle: TextStyle(color: cs.onSurfaceVariant),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: cs.outlineVariant),
        backgroundColor: cs.surface,
        selectedColor: cs.primaryContainer,
        labelStyle: TextStyle(fontFamily: fontFamily, color: cs.onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cs.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: cs.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontFamily: fontFamily,
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w400,
              color: states.contains(WidgetState.selected)
                  ? cs.primary
                  : cs.onSurfaceVariant,
            )),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
    );
  }
}
