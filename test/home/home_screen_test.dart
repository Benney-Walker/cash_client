import 'package:cash_client/common/glass_card.dart';
import 'package:cash_client/common/gradient_button.dart';
import 'package:cash_client/common/gradient_wash.dart';
import 'package:cash_client/common/names.dart';
import 'package:cash_client/home/home_screen.dart';
import 'package:cash_client/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int seeAllTaps;

  Future<void> pumpHome(
    WidgetTester tester, {
    ThemeData? theme,
    DateTime? now,
  }) async {
    seeAllTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: HomeScreen(
          staffName: 'KOFI MENSAH',
          onSeeAll: () => seeAllTaps++,
          now: () => now ?? DateTime(2026, 11, 10, 9),
        ),
      ),
    );
  }

  /// A 360 x 780 dp phone, a common small Android size.
  void useSmallPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  test('greeting follows the time of day', () {
    expect(greetingFor(DateTime(2026, 1, 1, 6)), 'Good morning');
    expect(greetingFor(DateTime(2026, 1, 1, 11, 59)), 'Good morning');
    expect(greetingFor(DateTime(2026, 1, 1, 12)), 'Good afternoon');
    expect(greetingFor(DateTime(2026, 1, 1, 16, 59)), 'Good afternoon');
    expect(greetingFor(DateTime(2026, 1, 1, 17)), 'Good evening');
  });

  test('names from the backend are shown in normal case', () {
    expect(displayName('KOFI MENSAH'), 'Kofi Mensah');
    expect(displayName('  AMA   OWUSU '), 'Ama Owusu');
    expect(displayName('EFUA'), 'Efua');
    expect(displayName(''), '');
  });

  testWidgets('greets the collector and shows an empty day', (tester) async {
    await pumpHome(tester, now: DateTime(2026, 11, 10, 14));

    expect(find.text('Good afternoon'), findsOneWidget);
    expect(find.text('Kofi Mensah'), findsOneWidget);
    expect(find.text('GH₵ 0.00'), findsOneWidget);
    expect(find.text('No records yet today'), findsOneWidget);
    expect(find.byKey(const Key('home.recentEmpty')), findsOneWidget);
  });

  testWidgets('the actions explain they are not available yet',
      (tester) async {
    await pumpHome(tester);

    for (final (key, words) in [
      ('home.recordDeposit', 'Recording deposits'),
      ('home.withdrawal', 'Withdrawal requests'),
      ('home.submitDay', "Submitting the day's collections"),
    ]) {
      final button = find.byKey(Key(key));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(find.textContaining(words), findsOneWidget, reason: key);
    }
  });

  testWidgets('See all opens the history', (tester) async {
    await pumpHome(tester);

    final seeAll = find.byKey(const Key('home.seeAll'));
    await tester.ensureVisible(seeAll);
    await tester.tap(seeAll);

    expect(seeAllTaps, 1);
  });

  testWidgets('fits a 360dp phone without overflow, in both themes',
      (tester) async {
    useSmallPhone(tester);
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await pumpHome(tester, theme: theme);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the action buttons are at least 48dp tall', (tester) async {
    await pumpHome(tester);

    for (final key in [
      'home.recordDeposit',
      'home.withdrawal',
      'home.submitDay',
    ]) {
      expect(tester.getSize(find.byKey(Key(key))).height,
          greaterThanOrEqualTo(AppTheme.minTouchTarget),
          reason: key);
    }
  });

  testWidgets("the greeting and today's total sit on the wash header, "
      'with the total on a glass card', (tester) async {
    await pumpHome(tester);

    expect(
      find.descendant(
        of: find.byType(GradientWash),
        matching: find.byKey(const Key('home.staffName')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(GlassCard),
        matching: find.byKey(const Key('home.todayTotal')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Record deposit is the one gradient button', (tester) async {
    await pumpHome(tester);

    expect(find.byType(GradientButton), findsOneWidget);
    expect(tester.widget(find.byKey(const Key('home.recordDeposit'))),
        isA<GradientButton>());
  });
}
