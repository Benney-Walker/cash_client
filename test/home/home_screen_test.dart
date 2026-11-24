import 'package:cash_client/collector/collector_models.dart';
import 'package:cash_client/common/glass_card.dart';
import 'package:cash_client/common/gradient_button.dart';
import 'package:cash_client/common/gradient_wash.dart';
import 'package:cash_client/common/names.dart';
import 'package:cash_client/common/money.dart';
import 'package:cash_client/home/home_screen.dart';
import 'package:cash_client/home/today.dart';
import 'package:cash_client/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late int seeAllTaps;
  late int recordTaps;
  late int outboxTaps;
  late int submitTaps;
  late int locationTaps;

  Future<void> pumpHome(
    WidgetTester tester, {
    ThemeData? theme,
    DateTime? now,
    int outboxWaiting = 0,
    int outboxRefused = 0,
    bool locationOff = false,
    TodayView today = TodayView.empty,
  }) async {
    locationTaps = 0;
    seeAllTaps = 0;
    recordTaps = 0;
    outboxTaps = 0;
    submitTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: HomeScreen(
          staffName: 'KOFI MENSAH',
          onSeeAll: () => seeAllTaps++,
          onRecordDeposit: () => recordTaps++,
          onSubmitDay: () => submitTaps++,
          outboxWaiting: outboxWaiting,
          outboxRefused: outboxRefused,
          onOpenOutbox: () => outboxTaps++,
          locationOff: locationOff,
          onTurnOnLocation: () => locationTaps++,
          today: today,
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

  test('initials use the first and last names', () {
    expect(initials('KOFI MENSAH'), 'KM');
    expect(initials('AMA SERWAA OWUSU'), 'AO');
    expect(initials('efua'), 'E');
    expect(initials('  '), '?');
  });

  testWidgets('greets the collector and shows an empty day', (tester) async {
    await pumpHome(tester, now: DateTime(2026, 11, 10, 14));

    expect(find.text('Good afternoon'), findsOneWidget);
    expect(find.text('Kofi Mensah'), findsOneWidget);
    expect(find.text('GH₵ 0.00'), findsOneWidget);
    expect(find.text('No records yet today'), findsOneWidget);
    expect(find.byKey(const Key('home.recentEmpty')), findsOneWidget);
  });

  testWidgets('Record deposit opens the payment flow', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home.recordDeposit')));
    await tester.pump();

    expect(recordTaps, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets("Submit today's collections opens the submit screen",
      (tester) async {
    await pumpHome(tester);

    final button = find.byKey(const Key('home.submitDay'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(submitTaps, 1);
  });

  testWidgets('there is no withdrawal button', (tester) async {
    await pumpHome(tester);
    expect(find.byKey(const Key('home.withdrawal')), findsNothing);
    expect(find.textContaining('Withdrawal'), findsNothing);
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

  group('outbox row', () {
    testWidgets('is hidden when nothing is waiting', (tester) async {
      await pumpHome(tester);
      expect(find.byKey(const Key('home.outbox')), findsNothing);
    });

    testWidgets('shows waiting and refused counts and opens the Outbox',
        (tester) async {
      await pumpHome(tester, outboxWaiting: 3, outboxRefused: 1);

      expect(find.text('Outbox'), findsOneWidget);
      final summary = tester.widget<Text>(
        find.byKey(const Key('home.outboxSummary')),
      );
      expect(summary.textSpan!.toPlainText(), contains('3 waiting'));
      expect(summary.textSpan!.toPlainText(), contains('1 refused'));

      await tester.tap(find.byKey(const Key('home.outbox')));
      expect(outboxTaps, 1);
    });

    testWidgets('sits above Record deposit', (tester) async {
      await pumpHome(tester, outboxRefused: 1);
      expect(
        tester.getTopLeft(find.byKey(const Key('home.outbox'))).dy,
        lessThan(
            tester.getTopLeft(find.byKey(const Key('home.recordDeposit'))).dy),
      );
    });
  });

  group('location off (design H-B)', () {
    testWidgets('Record deposit becomes Turn on location to record',
        (tester) async {
      await pumpHome(tester, locationOff: true);

      expect(find.byKey(const Key('home.recordDeposit')), findsNothing);
      expect(find.text('Turn on location to record'), findsOneWidget);
      expect(find.text("Location is off. Payments can't be recorded."),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('home.turnOnLocation')));
      expect(locationTaps, 1);
      expect(recordTaps, 0);
    });

    testWidgets('with location on, Record deposit is back', (tester) async {
      await pumpHome(tester);

      expect(find.byKey(const Key('home.recordDeposit')), findsOneWidget);
      expect(find.byKey(const Key('home.locationOff')), findsNothing);
    });

    testWidgets('fits a small phone', (tester) async {
      useSmallPhone(tester);
      await pumpHome(tester, locationOff: true, outboxRefused: 1);

      expect(tester.takeException(), isNull);
    });
  });

  group("today's figures and recent payments (design T1)", () {
    final at = DateTime.utc(2026, 11, 10, 10, 42);

    RecentPayment server(String name, RecentState state, int pesewas) =>
        RecentPayment(
          idempotencyKey: name,
          memberName: name,
          type: PaymentType.savings,
          accountNumber: '1002345678',
          amount: Cedis.pesewas(pesewas),
          createdAt: at,
          state: state,
        );

    TodayView view({
      List<RecentPayment> recent = const [],
      TodayProblem problem = TodayProblem.none,
      DateTime? updatedAt,
      int onPhone = 2,
    }) =>
        TodayView(
          savings: const Cedis.pesewas(98050),
          shares: const Cedis.pesewas(26000),
          count: 14,
          onPhone: onPhone,
          hasServerFigures: updatedAt != null || problem == TodayProblem.none,
          updatedAt: updatedAt,
          problem: problem,
          recent: recent,
        );

    testWidgets('the card shows the total, savings, shares and counts',
        (tester) async {
      await pumpHome(tester, today: view());

      expect(find.text('GH₵ 1,240.50'), findsOneWidget);
      expect(find.text('Savings GH₵ 980.50'), findsOneWidget);
      expect(find.text('Shares GH₵ 260.00'), findsOneWidget);
      expect(find.text('14 payments · 2 on this phone'), findsOneWidget);
      expect(find.byKey(const Key('home.todayUpdated')), findsNothing);
    });

    testWidgets('offline, it says when the figures are from', (tester) async {
      await pumpHome(
        tester,
        today: view(problem: TodayProblem.offline, updatedAt: at),
      );

      expect(find.text('Updated ${clockTime(at)} · offline'), findsOneWidget);
    });

    test('labels for the count and the update line', () {
      expect(todayCountLabel(TodayView.empty), 'No records yet today');
      expect(todayCountLabel(view(onPhone: 0)), '14 payments');
      expect(
        todayUpdatedLabel(view(problem: TodayProblem.failed, updatedAt: at)),
        "Updated ${clockTime(at)} · couldn't update",
      );
      expect(
        todayUpdatedLabel(view(problem: TodayProblem.offline)),
        'Only payments on this phone · offline',
      );
    });

    testWidgets('recent payments with where each stands', (tester) async {
      final held = queuedPayment(
        key: 'held',
        // A minute before home's clock (pumpHome's 09:00).
        createdAt: DateTime(2026, 11, 10, 8, 59),
        memberName: 'AMA OWUSU',
      );
      await pumpHome(
        tester,
        today: view(recent: [
          RecentPayment.onPhone(held),
          server('YAW BOATENG', RecentState.completed, 2000),
          server('ESI ASANTE', RecentState.failed, 10000),
        ]),
      );

      expect(find.byKey(const Key('home.recentEmpty')), findsNothing);
      expect(find.text('Ama Owusu'), findsOneWidget);
      expect(find.textContaining('Can correct'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Savings · 1002345678 · ${clockTime(at)}'),
          findsNWidgets(2));

      // A payment on the phone opens the Outbox.
      await tester.tap(find.byKey(const Key('home.recent.0')));
      expect(outboxTaps, 1);
      await tester.tap(find.byKey(const Key('home.recent.1')));
      expect(outboxTaps, 1);
    });

    testWidgets('five rows fit a small phone', (tester) async {
      useSmallPhone(tester);
      await pumpHome(
        tester,
        today: view(recent: [
          for (var i = 0; i < 5; i++)
            server('MEMBER WITH A VERY LONG NAME $i', RecentState.completed,
                99999999),
        ]),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
