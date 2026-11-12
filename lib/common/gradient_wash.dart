import 'package:flutter/material.dart';

import '../theme/app_gradients.dart';

/// The pale gradient wash with soft glows, behind the sign-in screen.
///
/// Same colours as the desktop app's sign-in panel. Text on it uses
/// `AppGradients.panelText` and `panelTextSecondary`, which are checked for
/// contrast against every part of the wash, glows included.
class GradientWash extends StatelessWidget {
  const GradientWash({super.key, required this.child});

  final Widget child;

  // Where the glows sit on a tall phone screen; matched to the colours by
  // index.
  static const _glowCentres = [
    Alignment(-0.8, -0.75),
    Alignment(0.9, -0.2),
    Alignment(-0.5, 0.9),
  ];

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);

    return DecoratedBox(
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
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}
