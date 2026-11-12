import 'package:flutter/material.dart';

import '../theme/app_gradients.dart';
import '../theme/app_theme.dart';

/// The primary button: a [FilledButton] drawn on the theme's button
/// gradient.
///
/// Owner decision: every primary action uses this, in this app as in the
/// desktop app, so keep to one per screen. Secondary actions stay outlined or text buttons.
/// It keeps FilledButton's shape, size, font, focus and keyboard handling;
/// only the background is replaced.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.padding,
  });

  /// Null while busy or unavailable. The button is then dimmed and ignores
  /// presses.
  final VoidCallback? onPressed;
  final Widget child;

  /// Overrides the theme's side padding, for a button that shares a row
  /// with another. (The one addition to the desktop app's copy.)
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);
    final enabled = onPressed != null;

    return Opacity(
      opacity: enabled ? 1 : 0.75,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradients.button,
          borderRadius: BorderRadius.circular(AppTheme.controlRadius),
        ),
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            foregroundColor: gradients.onButton,
            disabledForegroundColor: gradients.onButton,
            shadowColor: Colors.transparent,
            padding: padding,
          ),
          child: child,
        ),
      ),
    );
  }
}
