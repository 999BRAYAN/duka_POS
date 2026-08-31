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
