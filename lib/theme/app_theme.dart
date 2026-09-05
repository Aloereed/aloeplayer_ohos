import 'package:flutter/material.dart';

ThemeData buildAloeTheme(Brightness brightness, {bool desktop = false, String? fontFamily}) {
  final dark = brightness == Brightness.dark;
  final colors = ColorScheme.fromSeed(seedColor: const Color(0xFF1687B8), brightness: brightness).copyWith(
    surface: dark ? const Color(0xFF111820) : const Color(0xFFF9FBFE),
    surfaceContainerLowest: dark ? const Color(0xFF0C1219) : Colors.white,
    surfaceContainerLow: dark ? const Color(0xFF18222D) : const Color(0xFFF0F5FA),
    surfaceContainer: dark ? const Color(0xFF1D2935) : const Color(0xFFEBF1F7),
    surfaceContainerHigh: dark ? const Color(0xFF24323F) : const Color(0xFFE5EDF5),
    surfaceContainerHighest: dark ? const Color(0xFF2C3B49) : const Color(0xFFDDE7F0),
    outlineVariant: dark ? const Color(0xFF354554) : const Color(0xFFD6E1EB),
  );
  final base = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: colors,
    fontFamily: fontFamily, scaffoldBackgroundColor: colors.surface,
    visualDensity: VisualDensity.standard);
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.4),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
      bodySmall: base.textTheme.bodySmall?.copyWith(height: 1.45),
    ),
    appBarTheme: AppBarTheme(backgroundColor: colors.surface, foregroundColor: colors.onSurface,
      elevation: 0, scrolledUnderElevation: 0, centerTitle: false, toolbarHeight: desktop ? 68 : 60,
      titleSpacing: 20, titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
    cardTheme: CardThemeData(elevation: 0, color: colors.surfaceContainerLowest, clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: colors.outlineVariant))),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: colors.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: colors.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: colors.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: colors.primary, width: 1.5))),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: rounded,
      minimumSize: const Size(44, 46), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12))),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(shape: rounded, elevation: 0,
      minimumSize: const Size(44, 46), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: rounded,
      minimumSize: const Size(44, 46), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: rounded, minimumSize: const Size(44, 44))),
    listTileTheme: ListTileThemeData(iconColor: colors.onSurfaceVariant, contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      minVerticalPadding: 10, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    dialogTheme: DialogThemeData(backgroundColor: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: colors.surface, modalBackgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))), clipBehavior: Clip.antiAlias),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(elevation: 2, highlightElevation: 3,
      backgroundColor: colors.primaryContainer, foregroundColor: colors.onPrimaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
    navigationBarTheme: NavigationBarThemeData(indicatorColor: colors.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => base.textTheme.labelMedium?.copyWith(
        fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        color: states.contains(WidgetState.selected) ? colors.onSurface : colors.onSurfaceVariant))),
    dividerTheme: DividerThemeData(color: colors.outlineVariant.withValues(alpha: .7), thickness: .7, space: 1),
  );
}
