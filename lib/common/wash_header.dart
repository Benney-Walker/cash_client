import 'package:flutter/material.dart';

import 'gradient_wash.dart';

/// The pale wash across the top of a tab screen (home and history), with
/// rounded bottom corners. It runs under the status bar, so it pads its
/// content below it; the screen sets the status bar icon colour with an
/// `AnnotatedRegion`.
class WashHeader extends StatelessWidget {
  const WashHeader({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return GradientWash(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, topInset + 12, 16, 16),
        child: child,
      ),
    );
  }
}
