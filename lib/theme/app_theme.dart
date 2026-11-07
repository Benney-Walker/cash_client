import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_status_colors.dart';

/// Light and dark [ThemeData] for the collector app.
///
/// The colour schemes are written out in full instead of using
/// `ColorScheme.fromSeed`. A seed would generate its own tones, and the agreed
/// palette (and its contrast checks) would no longer be what ships.
///
/// Surface roles are used consistently in both modes:
/// `surface` is the page, `surfaceContainerLow` is a card,
/// `surfaceContainerHigh` is a raised area such as a sheet, and
/// `outlineVariant` is the hairline border.
abstract final class AppTheme {
  // Field use: thumbs, gloves, a moving tricycle. Material's 48dp minimum is
  // the floor for anything tappable.
  static const double minTouchTarget = 48;
  static const double cardRadius = 16;
  static const double controlRadius = 12;

  static ThemeData get light => _build(
        const ColorScheme(
          brightness: Brightness.light,
          primary: AppColors.lightPrimary,
          onPrimary: AppColors.lightOnPrimary,
          primaryContainer: AppColors.lightPrimaryContainer,
          onPrimaryContainer: AppColors.lightOnPrimaryContainer,
          secondary: AppColors.lightSecondary,
          onSecondary: AppColors.lightOnSecondary,
          secondaryContainer: AppColors.lightSecondaryContainer,
          onSecondaryContainer: AppColors.lightOnSecondaryContainer,
          error: AppColors.lightError,
          onError: AppColors.lightOnError,
          errorContainer: AppColors.lightErrorContainer,
          onErrorContainer: AppColors.lightOnErrorContainer,
          surface: AppColors.lightBackground,
          onSurface: AppColors.lightText,
          onSurfaceVariant: AppColors.lightTextSecondary,
          surfaceContainerLowest: AppColors.lightCard,
          surfaceContainerLow: AppColors.lightCard,
          surfaceContainer: AppColors.lightContainer,
          surfaceContainerHigh: AppColors.lightRaised,
          surfaceContainerHighest: AppColors.lightRaisedHighest,
          outline: AppColors.lightOutline,
          outlineVariant: AppColors.lightBorder,
          inverseSurface: AppColors.lightText,
          onInverseSurface: AppColors.lightBackground,
          inversePrimary: AppColors.darkPrimary,
          surfaceTint: Colors.transparent,
        ),
        AppStatusColors.light,
      );

  static ThemeData get dark => _build(
        const ColorScheme(
          brightness: Brightness.dark,
          primary: AppColors.darkPrimary,
          onPrimary: AppColors.darkOnPrimary,
          primaryContainer: AppColors.darkPrimaryContainer,
          onPrimaryContainer: AppColors.darkOnPrimaryContainer,
          secondary: AppColors.darkSecondary,
          onSecondary: AppColors.darkOnSecondary,
          secondaryContainer: AppColors.darkSecondaryContainer,
          onSecondaryContainer: AppColors.darkOnSecondaryContainer,
          error: AppColors.darkError,
          onError: AppColors.darkOnError,
          errorContainer: AppColors.darkErrorContainer,
          onErrorContainer: AppColors.darkOnErrorContainer,
          surface: AppColors.darkBackground,
          onSurface: AppColors.darkText,
          onSurfaceVariant: AppColors.darkTextSecondary,
          surfaceContainerLowest: AppColors.darkLowest,
          surfaceContainerLow: AppColors.darkCard,
          surfaceContainer: AppColors.darkContainer,
          surfaceContainerHigh: AppColors.darkRaised,
          surfaceContainerHighest: AppColors.darkRaisedHighest,
          outline: AppColors.darkOutline,
          outlineVariant: AppColors.darkBorder,
          inverseSurface: AppColors.darkText,
          onInverseSurface: AppColors.darkBackground,
          inversePrimary: AppColors.lightPrimary,
          surfaceTint: Colors.transparent,
        ),
        AppStatusColors.dark,
      );

  static ThemeData _build(ColorScheme scheme, AppStatusColors status) {
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(controlRadius),
    );
    const buttonMinimumSize = Size(64, minTouchTarget);

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [status],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        // Keep the bar the page colour when content scrolls under it.
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonMinimumSize,
          shape: controlShape,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonMinimumSize,
          shape: controlShape,
          side: BorderSide(color: scheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: buttonMinimumSize,
          shape: controlShape,
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
