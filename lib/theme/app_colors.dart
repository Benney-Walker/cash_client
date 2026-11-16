import 'package:flutter/material.dart';

/// The "Indigo Aurora" palette agreed for the collector app.
///
/// Every text/background pairing here was checked against WCAG AA (4.5:1);
/// `test/theme/app_theme_test.dart` keeps it that way. Collectors work
/// outdoors in strong sunlight, so treat contrast as a requirement, not polish.
///
/// Widgets should read colours from `Theme.of(context)` and [AppStatusColors]
/// rather than from this class, so light and dark mode both work.
abstract final class AppColors {
  // Light mode
  static const lightPrimary = Color(0xFF4F46E5);
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightPrimaryContainer = Color(0xFFE0E7FF);
  static const lightOnPrimaryContainer = Color(0xFF312E81);
  static const lightSecondary = Color(0xFF0E7490);
  static const lightOnSecondary = Color(0xFFFFFFFF);
  static const lightSecondaryContainer = Color(0xFFCFFAFE);
  static const lightOnSecondaryContainer = Color(0xFF164E63);
  static const lightBackground = Color(0xFFF6F7FB);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightContainer = Color(0xFFF1F3F9);
  static const lightRaised = Color(0xFFEEF0F7);
  static const lightRaisedHighest = Color(0xFFE6E9F2);
  static const lightBorder = Color(0xFFE2E8F0);
  // Darker than the border so input outlines stay visible on white cards.
  static const lightOutline = Color(0xFF64748B);
  static const lightText = Color(0xFF0F172A);
  static const lightTextSecondary = Color(0xFF475569);
  static const lightError = Color(0xFFB91C1C);
  static const lightOnError = Color(0xFFFFFFFF);
  static const lightErrorContainer = Color(0xFFFEE2E2);
  static const lightOnErrorContainer = Color(0xFF7F1D1D);

  // Dark mode. Surfaces are blue-tinted rather than pure black so they sit in
  // the same family as the hero gradient.
  static const darkPrimary = Color(0xFFA5B4FC);
  static const darkOnPrimary = Color(0xFF1E1B4B);
  static const darkPrimaryContainer = Color(0xFF3730A3);
  static const darkOnPrimaryContainer = Color(0xFFE0E7FF);
  static const darkSecondary = Color(0xFF67E8F9);
  static const darkOnSecondary = Color(0xFF083344);
  static const darkSecondaryContainer = Color(0xFF155E75);
  static const darkOnSecondaryContainer = Color(0xFFCFFAFE);
  static const darkBackground = Color(0xFF0B0F1A);
  static const darkLowest = Color(0xFF0F1422);
  static const darkCard = Color(0xFF141A2A);
  static const darkContainer = Color(0xFF182033);
  static const darkRaised = Color(0xFF1C2438);
  static const darkRaisedHighest = Color(0xFF232C42);
  static const darkBorder = Color(0xFF263048);
  static const darkOutline = Color(0xFF8590A8);
  static const darkText = Color(0xFFE6E9F2);
  static const darkTextSecondary = Color(0xFFA3ACC2);
  static const darkError = Color(0xFFF87171);
  static const darkOnError = Color(0xFF450A0A);
  static const darkErrorContainer = Color(0xFF3A1414);
  static const darkOnErrorContainer = Color(0xFFFECACA);

  // Status colours: a foreground for icon and label, on a matching tint.
  // Green is reserved for success and never used as a brand colour, so a
  // "completed" chip always means the backend confirmed it.
  static const lightSuccess = Color(0xFF15803D);
  static const lightSuccessContainer = Color(0xFFDCFCE7);
  static const lightWarning = Color(0xFFB45309);
  static const lightWarningContainer = Color(0xFFFEF3C7);
  static const lightNeutral = Color(0xFF475569);
  static const lightNeutralContainer = Color(0xFFF1F5F9);

  static const darkSuccess = Color(0xFF4ADE80);
  static const darkSuccessContainer = Color(0xFF0F2E1C);
  static const darkWarning = Color(0xFFFBBF24);
  static const darkWarningContainer = Color(0xFF2E2410);
  static const darkNeutral = Color(0xFF94A3B8);
  static const darkNeutralContainer = Color(0xFF1E293B);

  // Hero gradient stops. The cyan end is deliberately the darker 700/800
  // shade: a bright cyan looks nicer but white text on it fails contrast.
  static const lightHeroStops = [
    Color(0xFF312E81),
    Color(0xFF4F46E5),
    Color(0xFF0E7490),
  ];
  static const darkHeroStops = [
    Color(0xFF1E1B4B),
    Color(0xFF3730A3),
    Color(0xFF155E75),
  ];
  static const onHero = Color(0xFFFFFFFF);
  static const lightOnHeroSecondary = Color(0xFFEEF2FF);
  static const darkOnHeroSecondary = Color(0xFFC7D2FE);

  // Lighter gradient tints, added 12 November 2026 in the desktop app and
  // shared by both apps (owner decision). Keep these identical to the
  // desktop app's lib/theme/app_colors.dart; change both or neither. Text
  // pairings are checked in test/theme/app_gradients_test.dart.

  // Light mode. The panel is a pale indigo-to-sky wash with soft glows.
  static const lightPanelStops = [Color(0xFFEEF2FF), Color(0xFFE0F2FE)];
  static const lightPanelGlows = [
    Color(0xFFC7D2FE), // indigo
    Color(0xFFA5F3FC), // cyan
    Color(0xFFDDD6FE), // lavender
  ];
  static const lightPanelText = Color(0xFF312E81);
  static const lightPanelTextSecondary = Color(0xFF4338CA);
  static const lightIllustrationStops = [Color(0xFF818CF8), Color(0xFF22D3EE)];
  // Two stops only: a brighter indigo in the middle would drop white text
  // below 4.5:1.
  static const lightButtonStops = [Color(0xFF4F46E5), Color(0xFF0E7490)];
  static const lightOnButton = Color(0xFFFFFFFF);
  static const lightPageGlows = [
    Color(0x59A5F3FC), // cyan at 35%
    Color(0x73C7D2FE), // indigo at 45%
  ];
  static const lightGlassFill = Color(0x8CFFFFFF);
  static const lightGlassBorder = Color(0xE6FFFFFF);

  // Dark mode. Deep navy to teal, with translucent glows.
  static const darkPanelStops = [
    Color(0xFF1E1B4B),
    Color(0xFF172554),
    Color(0xFF164E63),
  ];
  static const darkPanelGlows = [
    Color(0x8C6366F1), // indigo at 55%
    Color(0x990E7490), // teal at 60%
  ];
  static const darkPanelText = Color(0xFFFFFFFF);
  static const darkPanelTextSecondary = Color(0xFFE0E7FF);
  static const darkIllustrationStops = [Color(0xFFA5B4FC), Color(0xFF67E8F9)];
  static const darkButtonStops = [
    Color(0xFFA5B4FC),
    Color(0xFFC4B5FD),
    Color(0xFF67E8F9),
  ];
  static const darkOnButton = Color(0xFF1E1B4B);
  static const darkPageGlows = [
    Color(0x59155E75), // teal at 35%
    Color(0x593730A3), // indigo at 35%
  ];
  static const darkGlassFill = Color(0x1AFFFFFF);
  static const darkGlassBorder = Color(0x47FFFFFF);
}
