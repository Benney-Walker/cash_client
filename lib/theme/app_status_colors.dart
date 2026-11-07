import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Colours Material's [ColorScheme] has no slot for: transaction and sync
/// statuses, and the hero gradient.
///
/// Read it with `AppStatusColors.of(context)`. The light and dark instances
/// are registered on the matching [ThemeData], so a widget never has to check
/// the brightness itself.
///
/// Statuses must always be shown with an icon and a label as well as colour.
/// Colour alone doesn't work for colour-blind collectors or in glare.
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.neutral,
    required this.neutralContainer,
    required this.heroGradient,
    required this.onHero,
    required this.onHeroSecondary,
  });

  /// COMPLETED transactions, "SMS sent" and other confirmed outcomes.
  final Color success;
  final Color successContainer;

  /// PENDING transactions and records not yet synced to the backend.
  final Color warning;
  final Color warningContainer;

  /// FAILED transactions and rejected submissions.
  final Color danger;
  final Color dangerContainer;

  /// REVERSED and other inactive states.
  final Color neutral;
  final Color neutralContainer;

  /// Only for hero surfaces: today's collections card, the login header and
  /// the receipt banner. Buttons, inputs and chips stay solid.
  final LinearGradient heroGradient;

  /// Text and icons placed on [heroGradient].
  final Color onHero;
  final Color onHeroSecondary;

  static const light = AppStatusColors(
    success: AppColors.lightSuccess,
    successContainer: AppColors.lightSuccessContainer,
    warning: AppColors.lightWarning,
    warningContainer: AppColors.lightWarningContainer,
    danger: AppColors.lightError,
    dangerContainer: AppColors.lightErrorContainer,
    neutral: AppColors.lightNeutral,
    neutralContainer: AppColors.lightNeutralContainer,
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: AppColors.lightHeroStops,
      stops: [0.0, 0.55, 1.0],
    ),
    onHero: AppColors.onHero,
    onHeroSecondary: AppColors.lightOnHeroSecondary,
  );

  static const dark = AppStatusColors(
    success: AppColors.darkSuccess,
    successContainer: AppColors.darkSuccessContainer,
    warning: AppColors.darkWarning,
    warningContainer: AppColors.darkWarningContainer,
    danger: AppColors.darkError,
    dangerContainer: AppColors.darkErrorContainer,
    neutral: AppColors.darkNeutral,
    neutralContainer: AppColors.darkNeutralContainer,
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: AppColors.darkHeroStops,
      stops: [0.0, 0.55, 1.0],
    ),
    onHero: AppColors.onHero,
    onHeroSecondary: AppColors.darkOnHeroSecondary,
  );

  static AppStatusColors of(BuildContext context) =>
      Theme.of(context).extension<AppStatusColors>()!;

  @override
  AppStatusColors copyWith({
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? danger,
    Color? dangerContainer,
    Color? neutral,
    Color? neutralContainer,
    LinearGradient? heroGradient,
    Color? onHero,
    Color? onHeroSecondary,
  }) {
    return AppStatusColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      neutral: neutral ?? this.neutral,
      neutralContainer: neutralContainer ?? this.neutralContainer,
      heroGradient: heroGradient ?? this.heroGradient,
      onHero: onHero ?? this.onHero,
      onHeroSecondary: onHeroSecondary ?? this.onHeroSecondary,
    );
  }

  // Lets the colours animate smoothly when the app switches theme mode.
  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) return this;
    return AppStatusColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      neutralContainer: Color.lerp(neutralContainer, other.neutralContainer, t)!,
      heroGradient: LinearGradient.lerp(heroGradient, other.heroGradient, t)!,
      onHero: Color.lerp(onHero, other.onHero, t)!,
      onHeroSecondary: Color.lerp(onHeroSecondary, other.onHeroSecondary, t)!,
    );
  }
}
