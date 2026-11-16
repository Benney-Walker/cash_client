import 'package:flutter/material.dart';

import '../theme/app_gradients.dart';

/// The pale gradient wash with soft glows: behind the sign-in screen and
/// across the top of the home screen.
///
/// Same colours as the desktop app's sign-in panel. Text on it uses
/// `AppGradients.panelText` and `panelTextSecondary`, which are checked for
/// contrast against every part of the wash, glows included.
///
/// It takes the size of [child], so it works both as a full-screen
/// background and as a header inside a list.
class GradientWash extends StatelessWidget {
  const GradientWash({super.key, required this.child, this.borderRadius});

  final Widget child;

  /// Rounds the wash's corners, for example the bottom of a header.
  final BorderRadius? borderRadius;

  // Where the glows sit; matched to the colours by index.
  static const _glowCentres = [
    Alignment(-0.8, -0.75),
    Alignment(0.9, -0.2),
    Alignment(-0.5, 0.9),
  ];

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);
    final radius = borderRadius ?? BorderRadius.zero;

    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: gradients.panel),
        child: Stack(
          children: [
            for (var i = 0; i < gradients.panelGlows.length; i++)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: _glowCentres[i % _glowCentres.length],
                      radius: 0.8,
                      colors: [
                        gradients.panelGlows[i],
                        gradients.panelGlows[i].withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            // Not positioned, so the stack (and the wash) takes its size.
            child,
          ],
        ),
      ),
    );
  }
}
