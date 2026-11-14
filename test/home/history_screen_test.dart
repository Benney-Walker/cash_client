import 'package:cash_client/common/glass_card.dart';
import 'package:cash_client/common/gradient_wash.dart';
import 'package:cash_client/home/history_screen.dart';
import 'package:cash_client/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpHistory(WidgetTester tester, {ThemeData? theme}) =>
      tester.pumpWidget(
        MaterialApp(theme: theme ?? AppTheme.light, home: const HistoryScreen()),
      );

  ChoiceChip chip(WidgetTester tester, HistoryFilter filter) =>
      tester.widget(find.byKey(Key('history.filter.${filter.name}')));

  testWidgets("today's count and total sit on a glass strip in the wash",
      (tester) async {
    await pumpHistory(tester);

    for (final key in ['history.todayCount', 'history.todayTotal']) {
      expect(
        find.descendant(
          of: find.byType(GlassCard),
          matching: find.byKey(Key(key)),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: find.byType(GradientWash),
        matching: find.text('History'),
      ),
      findsOneWidget,
    );
    expect(find.text('GH₵ 0.00'), findsOneWidget);
  });

  testWidgets('starts on All with an empty day', (tester) async {
    await pumpHistory(tester);

    expect(chip(tester, HistoryFilter.all).selected, isTrue);
    expect(find.text('No records yet'), findsOneWidget);
  });

  testWidgets('choosing a filter selects it and names it in the empty state',
      (tester) async {
    await pumpHistory(tester);

    await tester.tap(find.byKey(const Key('history.filter.shares')));
    await tester.pump();

    expect(chip(tester, HistoryFilter.shares).selected, isTrue);
    expect(chip(tester, HistoryFilter.all).selected, isFalse);
    expect(find.text('No share payments yet'), findsOneWidget);
  });

  testWidgets('fits a 360dp phone without overflow, in both themes',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await pumpHistory(tester, theme: theme);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
