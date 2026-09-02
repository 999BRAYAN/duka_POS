import 'package:flutter/material.dart';

/// Stone/amber earthy palette — same reference used for the product's
/// earlier browser-based UI mockup. Named after the Tailwind CSS scales
/// they come from, since that's the palette's mental model.
abstract final class AppColors {
  static const stone50 = Color(0xFFFAFAF9);
  static const stone100 = Color(0xFFF5F5F4);
  static const stone200 = Color(0xFFE7E5E4);
  static const stone300 = Color(0xFFD6D3D1);
  static const stone400 = Color(0xFFA8A29E);
  static const stone500 = Color(0xFF78716C);
  static const stone600 = Color(0xFF57534E);
  static const stone700 = Color(0xFF44403C);
  static const stone800 = Color(0xFF292524);
  static const stone900 = Color(0xFF1C1917);

  static const amber50 = Color(0xFFFFFBEB);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber200 = Color(0xFFFDE68A);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);
  static const amber800 = Color(0xFF92400E);

  // Semantic status colors — separate from the amber accent, used only for
  // state (e.g. payment status chips), not for branding.
  static const green50 = Color(0xFFF0FDF4);
  static const green200 = Color(0xFFBBF7D0);
  static const green700 = Color(0xFF15803D);

  static const rust50 = Color(0xFFFDF2EE);
  static const rust200 = Color(0xFFE9BBA9);
  static const rust700 = Color(0xFF9F3A22);
}

/// The dark palette is a designed second set, not an inversion: surfaces
/// stay warm (a shop screen at night should not glare blue), and the amber
/// accent lifts several steps so it still reads as the action colour against
/// a dark ground.
abstract final class AppDarkColors {
  static const bg = Color(0xFF1A1816);
  static const surface = Color(0xFF232120);
  static const surfaceHigh = Color(0xFF2C2927);
  static const line = Color(0xFF383431);
  static const lineStrong = Color(0xFF4A4541);
  static const ink = Color(0xFFF5F5F4);
  static const ink2 = Color(0xFFC8C3BE);
  static const ink3 = Color(0xFF8B837C);
  static const amber = Color(0xFFE9A23B);
  static const amberInk = Color(0xFFF3C177);
  static const amberSoft = Color(0xFF2E2418);
  static const green = Color(0xFF5FC98A);
  static const greenSoft = Color(0xFF16281D);
  static const rust = Color(0xFFE8836A);
  static const rustSoft = Color(0xFF2E1A15);
}

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.amber700,
    brightness: Brightness.light,
    surface: AppColors.stone50,
    surfaceContainerHighest: AppColors.stone100,
    outline: AppColors.stone300,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.stone50,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.stone50,
      foregroundColor: AppColors.stone900,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: const TextStyle(
        color: AppColors.stone900,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(AppColors.stone100),
      headingTextStyle: const TextStyle(
        color: AppColors.stone700,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      dataTextStyle: const TextStyle(color: AppColors.stone800, fontSize: 13),
      dividerThickness: 1,
    ),
    dividerColor: AppColors.stone200,
    cardTheme: const CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: AppColors.stone200),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.stone300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.stone300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.amber700, width: 1.5),
      ),
    ),
  );
}

ThemeData buildAppDarkTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppDarkColors.amber,
    brightness: Brightness.dark,
    surface: AppDarkColors.surface,
    surfaceContainerHighest: AppDarkColors.surfaceHigh,
    outline: AppDarkColors.lineStrong,
    primary: AppDarkColors.amber,
    error: AppDarkColors.rust,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppDarkColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppDarkColors.surface,
      foregroundColor: AppDarkColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: AppDarkColors.ink,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    dataTableTheme: const DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(AppDarkColors.surfaceHigh),
      headingTextStyle: TextStyle(
        color: AppDarkColors.ink2,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      dataTextStyle: TextStyle(color: AppDarkColors.ink, fontSize: 13),
      dividerThickness: 1,
    ),
    dividerColor: AppDarkColors.line,
    cardTheme: const CardThemeData(
      color: AppDarkColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: AppDarkColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppDarkColors.surfaceHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppDarkColors.lineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppDarkColors.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppDarkColors.amber, width: 1.5),
      ),
    ),
  );
}

/// Colours that carry meaning rather than decoration — low stock, money
/// owed, profit — resolved for whichever theme is showing. Screens read
/// these instead of AppColors directly so a figure stays legible in both.
abstract final class SemanticColors {
  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color warning(BuildContext context) =>
      _isDark(context) ? AppDarkColors.amber : AppColors.amber800;

  static Color warningSurface(BuildContext context) =>
      _isDark(context) ? AppDarkColors.amberSoft : AppColors.amber50;

  static Color debt(BuildContext context) =>
      _isDark(context) ? AppDarkColors.rust : AppColors.rust700;

  static Color debtSurface(BuildContext context) =>
      _isDark(context) ? AppDarkColors.rustSoft : AppColors.rust50;

  static Color positive(BuildContext context) =>
      _isDark(context) ? AppDarkColors.green : AppColors.green700;

  static Color muted(BuildContext context) =>
      _isDark(context) ? AppDarkColors.ink3 : AppColors.stone500;
}
