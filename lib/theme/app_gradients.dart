import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The lighter gradients shared with the desktop app: the pale wash behind
/// the sign-in screen, its illustration and glass labels, the soft page
/// glows, and the gradient primary button.
///
/// Read it with `AppGradients.of(context)`. Light and dark instances are
/// registered on the matching [ThemeData]. Keep this in step with the
/// desktop app's copy.
@immutable
class AppGradients extends ThemeExtension<AppGradients> {
  const AppGradients({
    required this.button,
    required this.onButton,
    required this.panel,
    required this.panelGlows,
    required this.panelText,
    required this.panelTextSecondary,
    required this.illustration,
    required this.glassFill,
    required this.glassBorder,
    required this.pageGlows,
  });

  /// Primary buttons. Owner decision: every primary button uses the
  /// gradient, in this app as in the desktop app (see `GradientButton`).
  final LinearGradient button;
  final Color onButton;

  /// The pale wash behind the sign-in screen; [panelGlows] are drawn over
  /// it as soft radial spots.
  final LinearGradient panel;
  final List<Color> panelGlows;
  final Color panelText;
  final Color panelTextSecondary;

  /// Fill for the shield and other illustrations on the wash.
  final LinearGradient illustration;

  /// Translucent "glass" cards, labels and rings on the wash.
  final Color glassFill;
  final Color glassBorder;

  /// Faint radial spots for plain pages.
  final List<Color> pageGlows;

  static const light = AppGradients(
    button: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: AppColors.lightButtonStops,
    ),
    onButton: AppColors.lightOnButton,
    panel: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: AppColors.lightPanelStops,
    ),
    panelGlows: AppColors.lightPanelGlows,
    panelText: AppColors.lightPanelText,
    panelTextSecondary: AppColors.lightPanelTextSecondary,
    illustration: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: AppColors.lightIllustrationStops,
    ),
    glassFill: AppColors.lightGlassFill,
    glassBorder: AppColors.lightGlassBorder,
    pageGlows: AppColors.lightPageGlows,
  );

  static const dark = AppGradients(
    button: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: AppColors.darkButtonStops,
    ),
    onButton: AppColors.darkOnButton,
    panel: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: AppColors.darkPanelStops,
    ),
    panelGlows: AppColors.darkPanelGlows,
    panelText: AppColors.darkPanelText,
    panelTextSecondary: AppColors.darkPanelTextSecondary,
    illustration: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: AppColors.darkIllustrationStops,
    ),
    glassFill: AppColors.darkGlassFill,
    glassBorder: AppColors.darkGlassBorder,
    pageGlows: AppColors.darkPageGlows,
  );

  static AppGradients of(BuildContext context) =>
      Theme.of(context).extension<AppGradients>()!;

  @override
  AppGradients copyWith({
    LinearGradient? button,
    Color? onButton,
    LinearGradient? panel,
    List<Color>? panelGlows,
    Color? panelText,
    Color? panelTextSecondary,
    LinearGradient? illustration,
    Color? glassFill,
    Color? glassBorder,
    List<Color>? pageGlows,
  }) {
    return AppGradients(
      button: button ?? this.button,
      onButton: onButton ?? this.onButton,
      panel: panel ?? this.panel,
      panelGlows: panelGlows ?? this.panelGlows,
      panelText: panelText ?? this.panelText,
      panelTextSecondary: panelTextSecondary ?? this.panelTextSecondary,
      illustration: illustration ?? this.illustration,
      glassFill: glassFill ?? this.glassFill,
      glassBorder: glassBorder ?? this.glassBorder,
      pageGlows: pageGlows ?? this.pageGlows,
    );
  }

  // Lets the gradients animate when the app switches theme mode. Gradients
  // with different stop counts can't blend, so those switch at the midpoint.
  @override
  AppGradients lerp(ThemeExtension<AppGradients>? other, double t) {
    if (other is! AppGradients) return this;
    return AppGradients(
      button: _lerpGradient(button, other.button, t),
      onButton: Color.lerp(onButton, other.onButton, t)!,
      panel: _lerpGradient(panel, other.panel, t),
      panelGlows: _lerpColors(panelGlows, other.panelGlows, t),
      panelText: Color.lerp(panelText, other.panelText, t)!,
      panelTextSecondary:
          Color.lerp(panelTextSecondary, other.panelTextSecondary, t)!,
      illustration: _lerpGradient(illustration, other.illustration, t),
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      pageGlows: _lerpColors(pageGlows, other.pageGlows, t),
    );
  }

  static LinearGradient _lerpGradient(
    LinearGradient a,
    LinearGradient b,
    double t,
  ) {
    if (a.colors.length != b.colors.length) return t < 0.5 ? a : b;
    return LinearGradient.lerp(a, b, t)!;
  }

  static List<Color> _lerpColors(List<Color> a, List<Color> b, double t) {
    if (a.length != b.length) return t < 0.5 ? a : b;
    return [for (var i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t)!];
  }
}
