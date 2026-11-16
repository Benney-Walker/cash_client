import 'package:flutter/painting.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// AA for normal-size text.
const double minTextContrast = 4.5;

/// AA for non-text UI such as input outlines.
const double minUiContrast = 3.0;
