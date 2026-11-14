import 'package:flutter/material.dart';

import '../theme/app_gradients.dart';

/// A frosted card for content on the gradient wash: the sign-in form and
/// today's total on the home screen.
///
/// Text on it should use `AppGradients.panelText`. The lighter
/// `panelTextSecondary` and the error reds fall below 4.5:1 on dark-mode
/// glass where it crosses the teal glow (see app_gradients_test.dart).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradients.glassFill,
        border: Border.all(color: gradients.glassBorder),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}
