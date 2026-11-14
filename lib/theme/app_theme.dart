import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xffc45100);
  static const accent = Color(0xffef8028);
  static const background = Color(0xfffff8f0);
  static const surface = Color(0xfffffdf9);
  static const softSurface = Color(0xfffff0e0);
  static const soft = Color(0xffffdfc3);
  static const ink = Color(0xff35271e);
  static const muted = Color(0xff7c6858);
  static const border = Color(0xffead9c9);
}

ThemeData buildAppTheme() {
  final colors = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.soft,
    onPrimaryContainer: const Color(0xff713100),
    secondary: const Color(0xff9b6031),
    tertiary: const Color(0xffa66c15),
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    outlineVariant: AppColors.border,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'NotoSansJP',
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: colors,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'NotoSansJP',
        fontSize: 26,
        fontWeight: FontWeight.bold,
        color: AppColors.ink,
      ),
      backgroundColor: AppColors.background,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.soft,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'NotoSansJP',
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.muted,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 50)),
    ),
  );
}
