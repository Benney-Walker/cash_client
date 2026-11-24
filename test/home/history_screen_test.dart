import 'dart:convert';

import 'package:cash_client/common/glass_card.dart';
import 'package:cash_client/common/gradient_wash.dart';
import 'package:cash_client/home/history_screen.dart';
import 'package:cash_client/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fakes.dart';

void main() {
  // Tuesday 24 November 2026, midday in Accra (UTC).
  final now = DateTime.utc(2026, 11, 24, 12);

  /// Payments by date (`yyyy-mm-dd`), as the server would list them.
  late Map<String, List<Map<String, Object?>>> days;
  late List<Map<String, Object?>> submissions;
  late bool online;
  late FakeCollectorBackend backend;

  Map<String, Object?> payment(
    String key, {
    String type = 'SAVINGS',
    num amount = 50,
    String status = 'COMPLETED',
    String? failureReason,
    String createdAt = '2026-11-24T10:00:00',
  }) =>
      {
        ...jsonDecode(paymentBody(
          idempotencyKey: key,
          type: type,
          amount: amount,
          status: status,
        )) as Map<String, Object?>,
        'failureReason': failureReason,
        'createdAt': createdAt,
      };

  setUp(() {
    days = {};
    submissions = [];
    online = true;
    backend = FakeCollectorBackend((request) {
      if (!online) throw http.ClientException('offline');
      if (request.url.path.endsWith('/collector/v1/submissions')) {
        return http.Response(submissionsPage(submissions), 200);
      }
      final date = request.url.queryParameters['date']!;
      final payments = days[date] ?? const [];
      num total(String type) => payments
          .where((p) => p['type'] == type && p['status'] != 'FAILED')
          .fold<num>(0, (sum, p) => sum + (p['amount'] as num));
      return http.Response(
        jsonEncode({
          'date': date,
          'count': payments.length,
          'savingsTotal': total('SAVINGS'),
          'sharesTotal': total('SHARES'),
          'total': total('SAVINGS') + total('SHARES'),
          'payments': payments,
        }),
        200,
      );
    });
  });

  Future<void> pumpHistory(
    WidgetTester tester, {
    ThemeData? theme,
    bool active = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: HistoryScreen(api: backend.api, active: active, now: () => now),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String?> datesAsked() => [
        for (final r in backend.requests)
          if (r.url.path.endsWith('/payments')) r.url.queryParameters['date'],
      ];

  ChoiceChip chip(WidgetTester tester, HistoryFilter filter) =>
      tester.widget(find.byKey(Key('history.filter.${filter.name}')));

  testWidgets("the day, its count and total sit on a glass strip in the wash",
      (tester) async {
    days['2026-11-24'] = [payment('a'), payment('b', amount: 20.5)];
    await pumpHistory(tester);

    for (final key in ['history.day', 'history.count', 'history.total']) {
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
    expect(find.text('Today · Tue 24 Nov'), findsOneWidget);
    expect(find.text('2 payments'), findsOneWidget);
    expect(find.text('GH₵ 70.50'), findsOneWidget);
    expect(datesAsked(), ['2026-11-24']);
  });

  testWidgets("lists the day's payments, failed ones with the reason",
      (tester) async {
    days['2026-11-24'] = [
      payment('a'),
      payment(
        'b',
        status: 'FAILED',
        failureReason: 'The account was frozen',
      ),
    ];
    await pumpHistory(tester);

    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('The account was frozen'), findsOneWidget);
    // Failed payments count, but their money doesn't.
    expect(find.text('2 payments'), findsOneWidget);
    expect(find.text('GH₵ 50.00'), findsWidgets);
  });

  testWidgets('a filter narrows the list, the count and the total',
      (tester) async {
    days['2026-11-24'] = [
      payment('a', amount: 30),
      payment('b', type: 'SHARES', amount: 20),
    ];
    await pumpHistory(tester);

    await tester.tap(find.byKey(const Key('history.filter.shares')));
    await tester.pump();

    expect(chip(tester, HistoryFilter.shares).selected, isTrue);
    expect(find.byKey(const Key('history.payment.0')), findsOneWidget);
    expect(find.byKey(const Key('history.payment.1')), findsNothing);
    expect(find.text('1 payment'), findsOneWidget);
    expect(find.byKey(const Key('history.total')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('history.total'))).data,
      'GH₵ 20.00',
    );
  });

  testWidgets('an empty day, named by the filter', (tester) async {
    await pumpHistory(tester);

    expect(chip(tester, HistoryFilter.all).selected, isTrue);
    expect(find.text('No payments yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('history.filter.shares')));
    await tester.pump();
    expect(find.text('No share payments yet'), findsOneWidget);
  });

  testWidgets('steps back through the last 7 days, and no further',
      (tester) async {
    days['2026-11-23'] = [payment('y', createdAt: '2026-11-23T09:00:00')];
    await pumpHistory(tester);
    final next = find.byKey(const Key('history.nextDay'));
    final previous = find.byKey(const Key('history.previousDay'));
    expect(tester.widget<IconButton>(next).onPressed, isNull);

    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(find.text('Yesterday · Mon 23 Nov'), findsOneWidget);
    expect(find.text('1 payment'), findsOneWidget);

    for (var i = 0; i < 5; i++) {
      await tester.tap(previous);
      await tester.pumpAndSettle();
    }
    expect(find.text('Wed 18 Nov'), findsOneWidget);
    expect(tester.widget<IconButton>(previous).onPressed, isNull);

    // Days already seen aren't downloaded again.
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(datesAsked(), [
      '2026-11-24',
      '2026-11-23',
      '2026-11-22',
      '2026-11-21',
      '2026-11-20',
      '2026-11-19',
      '2026-11-18',
    ]);
  });

  testWidgets("shows the day's submission", (tester) async {
    submissions = [
      {
        ...submissionJson(status: 'APPROVED', expectedAmount: 1105),
        'submittedAt': '2026-11-23T17:05:00',
        'countedAmount': 1105,
        'approvedAt': '2026-11-23T17:40:00',
      },
    ];
    await pumpHistory(tester);
    expect(find.byKey(const Key('history.submission')), findsNothing);

    await tester.tap(find.byKey(const Key('history.previousDay')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history.submission')), findsOneWidget);
    expect(find.textContaining('Approved'), findsOneWidget);
    expect(find.textContaining('Counted GH₵ 1,105.00'), findsOneWidget);
  });

  testWidgets('a submission waiting today shows the cash to hand in',
      (tester) async {
    submissions = [
      {
        ...submissionJson(expectedAmount: 1240),
        'submittedAt': '2026-11-24T11:30:00',
      },
    ];
    await pumpHistory(tester);

    expect(find.text('Waiting for approval'), findsOneWidget);
    expect(find.textContaining('GH₵ 1,240.00 to hand in'), findsOneWidget);
  });

  testWidgets('offline: says so, and Try again downloads it', (tester) async {
    online = false;
    days['2026-11-24'] = [payment('a')];
    await pumpHistory(tester);

    expect(find.text("Couldn't load this day. Check your connection."),
        findsOneWidget);

    online = true;
    await tester.tap(find.byKey(const Key('history.retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history.error')), findsNothing);
    expect(find.text('1 payment'), findsOneWidget);
  });

  testWidgets('downloads only once its tab is showing', (tester) async {
    await pumpHistory(tester, active: false);
    expect(backend.requests, isEmpty);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HistoryScreen(api: backend.api, now: () => now),
      ),
    );
    await tester.pumpAndSettle();

    expect(datesAsked(), ['2026-11-24']);
  });

  testWidgets('fits a 360dp phone without overflow, in both themes',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    days['2026-11-24'] = [
      for (var i = 0; i < 8; i++)
        payment('p$i', amount: 999999.99, failureReason: 'A long reason'),
    ];
    submissions = [
      {...submissionJson(), 'submittedAt': '2026-11-24T11:30:00'},
    ];

    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await pumpHistory(tester, theme: theme);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('there is no Withdrawals filter', (tester) async {
    await pumpHistory(tester);
    expect(find.text('Withdrawals'), findsNothing);
    expect(HistoryFilter.values.map((f) => f.label),
        ['All', 'Deposits', 'Shares']);
  });

  test('day labels', () {
    expect(historyDayLabel(DateTime.utc(2026, 11, 24), 0), 'Today · Tue 24 Nov');
    expect(historyDayLabel(DateTime.utc(2026, 11, 23), 1),
        'Yesterday · Mon 23 Nov');
    expect(historyDayLabel(DateTime.utc(2026, 11, 1), 23), 'Sun 1 Nov');
    expect(paymentCountLabel(0), 'No payments');
    expect(paymentCountLabel(1), '1 payment');
  });
}
