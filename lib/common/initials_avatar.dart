import 'package:flutter/material.dart';

import '../theme/app_gradients.dart';
import 'names.dart';

/// The collector's initials on a rounded tile, like the desktop app's "CC"
/// brand mark.
///
/// It sits on the button gradient with the button's text colour (white in
/// light mode, dark indigo in dark mode), a pairing the contrast tests
/// already cover. White letters on the dark-mode gradient would be too
/// faint.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 48});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);

    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: gradients.button,
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Text(
          initials(name),
          style: TextStyle(
            color: gradients.onButton,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.36,
          ),
        ),
      ),
    );
  }
}
