import 'package:cash_client/common/gradient_button.dart';
import 'package:cash_client/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpButton(WidgetTester tester, VoidCallback? onPressed) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: GradientButton(
                onPressed: onPressed,
                child: const Text('Sign in'),
              ),
            ),
          ),
        ),
      );

  testWidgets('calls onPressed when tapped', (tester) async {
    var taps = 0;
    await pumpButton(tester, () => taps++);

    await tester.tap(find.text('Sign in'));

    expect(taps, 1);
  });

  testWidgets('ignores taps and is dimmed while unavailable', (tester) async {
    await pumpButton(tester, null);

    await tester.tap(find.text('Sign in'), warnIfMissed: false);

    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('Sign in'), matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, lessThan(1));
  });

  testWidgets('keeps the 48dp minimum height', (tester) async {
    await pumpButton(tester, () {});

    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(AppTheme.minTouchTarget),
    );
  });

  testWidgets('draws the theme gradient behind the label', (tester) async {
    await pumpButton(tester, () {});

    final box = tester.widget<DecoratedBox>(
      find.ancestor(
        of: find.byType(FilledButton),
        matching: find.byType(DecoratedBox),
      ).first,
    );
    expect((box.decoration as BoxDecoration).gradient, isA<LinearGradient>());
  });
}
