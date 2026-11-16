import 'package:cash_client/auth/login_screen.dart';
import 'package:cash_client/theme/app_gradients.dart';
import 'package:cash_client/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contrast.dart';

/// Every colour a gradient passes through at its stops and halfway between
/// neighbouring stops. Text sits on all of them somewhere.
List<Color> samples(LinearGradient gradient) {
  final colors = gradient.colors;
  return [
    for (var i = 0; i < colors.length; i++) ...[
      colors[i],
      if (i + 1 < colors.length) Color.lerp(colors[i], colors[i + 1], 0.5)!,
    ],
  ];
}

/// The wash's possible backgrounds: its base colours, with each glow laid
/// over them at full strength (the glow's centre).
List<Color> washBackgrounds(AppGradients g) => [
      for (final base in samples(g.panel)) ...[
        base,
        for (final glow in g.panelGlows) Color.alphaBlend(glow, base),
      ],
    ];

/// The glass card laid over every part of the wash.
List<Color> glassBackgrounds(AppGradients g) => [
      for (final background in washBackgrounds(g))
        Color.alphaBlend(g.glassFill, background),
    ];

void main() {
  for (final entry in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    final theme = entry.value;
    final g = theme.extension<AppGradients>();

    group('${entry.key} gradients', () {
      test('are registered on the theme', () {
        expect(g, isNotNull);
      });

      test('button text is readable across the whole button', () {
        for (final colour in samples(g!.button)) {
          expect(
            contrastRatio(g.onButton, colour),
            greaterThanOrEqualTo(minTextContrast),
            reason: 'on $colour',
          );
        }
      });

      test('title and footer text are readable anywhere on the wash', () {
        for (final background in washBackgrounds(g!)) {
          for (final text in [g.panelText, g.panelTextSecondary]) {
            expect(
              contrastRatio(text, background),
              greaterThanOrEqualTo(minTextContrast),
              reason: '$text on $background',
            );
          }
        }
      });

      // The card's text all uses panelText: panelTextSecondary drops to
      // about 4.0:1 on dark-mode glass over the teal glow.
      test('card heading, hint and labels are readable on the glass', () {
        for (final glass in glassBackgrounds(g!)) {
          expect(
            contrastRatio(g.panelText, glass),
            greaterThanOrEqualTo(minTextContrast),
            reason: 'on $glass',
          );
        }
      });

      test('field error messages are readable on the glass', () {
        final error = LoginScreen.fieldErrorColor(theme);
        for (final glass in glassBackgrounds(g!)) {
          expect(
            contrastRatio(error, glass),
            greaterThanOrEqualTo(minTextContrast),
            reason: 'on $glass',
          );
        }
      });

      test('form text is readable on the page glows', () {
        final scheme = theme.colorScheme;
        for (final glow in g!.pageGlows) {
          final background = Color.alphaBlend(glow, scheme.surface);
          expect(
            contrastRatio(scheme.onSurfaceVariant, background),
            greaterThanOrEqualTo(minTextContrast),
          );
        }
      });
    });
  }

  test('switching theme mode blends without errors', () {
    final mid = AppGradients.light.lerp(AppGradients.dark, 0.5);
    expect(mid.panelGlows, isNotEmpty);
    expect(AppGradients.light.lerp(AppGradients.dark, 1).onButton,
        AppGradients.dark.onButton);
  });

  test('the theme uses the bundled Inter font', () {
    expect(AppTheme.light.textTheme.bodyMedium?.fontFamily, AppTheme.fontFamily);
    expect(AppTheme.dark.textTheme.bodyMedium?.fontFamily, AppTheme.fontFamily);
  });
}
