import 'package:cash_client/theme/app_status_colors.dart';
import 'package:cash_client/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

// AA for normal-size text. Collectors read these screens outdoors, so every
// text pairing is held to the text standard, not the 3:1 allowed for large
// text.
const double minTextContrast = 4.5;
// AA for non-text UI such as input outlines.
const double minUiContrast = 3.0;

void main() {
  for (final entry in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    final mode = entry.key;
    final theme = entry.value;
    final s = theme.colorScheme;
    final status = theme.extension<AppStatusColors>();

    group('$mode theme', () {
      test('has the expected brightness and status colours', () {
        expect(
          s.brightness,
          mode == 'light' ? Brightness.light : Brightness.dark,
        );
        expect(status, isNotNull);
      });

      final textPairs = <String, (Color, Color)>{
        'text on page': (s.onSurface, s.surface),
        'text on card': (s.onSurface, s.surfaceContainerLow),
        'secondary text on page': (s.onSurfaceVariant, s.surface),
        'secondary text on card': (s.onSurfaceVariant, s.surfaceContainerLow),
        'secondary text on raised': (s.onSurfaceVariant, s.surfaceContainerHigh),
        'secondary text on highest': (
          s.onSurfaceVariant,
          s.surfaceContainerHighest,
        ),
        'on primary': (s.onPrimary, s.primary),
        'on primary container': (s.onPrimaryContainer, s.primaryContainer),
        'primary on card': (s.primary, s.surfaceContainerLow),
        'on secondary': (s.onSecondary, s.secondary),
        'on secondary container': (
          s.onSecondaryContainer,
          s.secondaryContainer,
        ),
        'on error': (s.onError, s.error),
        'on error container': (s.onErrorContainer, s.errorContainer),
        'success chip': (status!.success, status.successContainer),
        'warning chip': (status.warning, status.warningContainer),
        'danger chip': (status.danger, status.dangerContainer),
        'neutral chip': (status.neutral, status.neutralContainer),
      };

      for (final pair in textPairs.entries) {
        test('${pair.key} meets $minTextContrast:1', () {
          final (fg, bg) = pair.value;
          expect(contrastRatio(fg, bg), greaterThanOrEqualTo(minTextContrast));
        });
      }

      // Text sits on every part of the hero gradient, so check each stop.
      test('hero text is readable across the whole gradient', () {
        for (final stop in status!.heroGradient.colors) {
          expect(
            contrastRatio(status.onHero, stop),
            greaterThanOrEqualTo(minTextContrast),
          );
          expect(
            contrastRatio(status.onHeroSecondary, stop),
            greaterThanOrEqualTo(minTextContrast),
          );
        }
      });

      test('input outline is visible on a card', () {
        expect(
          contrastRatio(s.outline, s.surfaceContainerLow),
          greaterThanOrEqualTo(minUiContrast),
        );
      });

      test('buttons meet the 48dp touch target', () {
        for (final style in [
          theme.filledButtonTheme.style,
          theme.outlinedButtonTheme.style,
          theme.textButtonTheme.style,
          theme.segmentedButtonTheme.style,
        ]) {
          final size = style!.minimumSize!.resolve(<WidgetState>{});
          expect(size!.height, greaterThanOrEqualTo(AppTheme.minTouchTarget));
        }
      });
    });
  }
}
