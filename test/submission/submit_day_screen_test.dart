import 'dart:convert';

import 'package:cash_client/outbox/outbox.dart';
import 'package:cash_client/submission/day_closure.dart';
import 'package:cash_client/submission/submit_day_screen.dart';
import 'package:cash_client/sync/payment_sync.dart';
import 'package:cash_client/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fakes.dart';

void main() {
  // 17:40 UTC (Accra time) on the day.
  final now = DateTime.utc(2026, 11, 15, 17, 40);

  late DayClosure dayClosure;
  late int syncs;

  Future<void> pumpSubmit(
    WidgetTester tester, {
    FakeCollectorBackend? backend,
    MemoryOutboxStore? outbox,
  }) async {
    syncs = 0;
    dayClosure = DayClosure(
      store: MemorySubmittedDayStore(),
      staffId: () => 'STF001',
    );
    final store = outbox ?? MemoryOutboxStore();
    final box = Outbox(store: store, staffId: () => 'STF001', now: () => now);
    await box.refresh();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: SubmitDayScreen(
        api: (backend ?? FakeCollectorBackend.working()).api,
        outbox: box,
        dayClosure: dayClosure,
        syncOutbox: () async {
          syncs++;
          return SyncReport.nothing;
        },
        now: () => now,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> tapSubmitAndConfirm(WidgetTester tester) async {
    await tapKey(tester, 'submit.button');
    await tapKey(tester, 'submit.confirm');
  }

  testWidgets("shows today's totals with every check passed", (tester) async {
    await pumpSubmit(tester);

    expect(syncs, 1);
    expect(find.text('GH₵ 1,240.00'), findsOneWidget);
    expect(find.text('18 payments'), findsOneWidget);
    expect(find.text('GH₵ 1,040.00'), findsOneWidget);
    expect(find.text('GH₵ 200.00'), findsOneWidget);
    expect(find.text('Nothing waiting on this phone'), findsOneWidget);
    expect(find.text('No payments in their 10 minutes'), findsOneWidget);
  });

  testWidgets('submitting asks first, then shows the submission waiting',
      (tester) async {
    final backend = FakeCollectorBackend.working();
    await pumpSubmit(tester, backend: backend);

    await tapKey(tester, 'submit.button');
    expect(find.byKey(const Key('submit.confirmDialog')), findsOneWidget);
    expect(backend.submitRequests, isEmpty);

    await tapKey(tester, 'submit.confirm');

    expect(backend.submitRequests, hasLength(1));
    expect(find.byKey(const Key('submit.waiting')), findsOneWidget);
    expect(find.text('GH₵ 1,240.00'), findsOneWidget);
    expect(find.text('Cash to hand in'), findsOneWidget);
    expect(dayClosure.isClosed, isTrue);
  });

  testWidgets('cancelling the confirmation sends nothing', (tester) async {
    final backend = FakeCollectorBackend.working();
    await pumpSubmit(tester, backend: backend);

    await tapKey(tester, 'submit.button');
    await tapKey(tester, 'submit.cancel');

    expect(backend.submitRequests, isEmpty);
    expect(dayClosure.isClosed, isFalse);
  });

  testWidgets('a refused payment on the phone blocks Submit', (tester) async {
    final backend = FakeCollectorBackend.working();
    await pumpSubmit(
      tester,
      backend: backend,
      outbox: MemoryOutboxStore([
        queuedPayment(
          recordedAt: now.subtract(const Duration(hours: 2)),
          refusalReason: 'Account 1002345678 is not active',
        ),
      ]),
    );

    expect(find.text('1 payment refused · call your admin'), findsOneWidget);
    await tapKey(tester, 'submit.button');

    expect(find.byKey(const Key('submit.confirmDialog')), findsNothing);
    expect(find.textContaining('Call your admin'), findsOneWidget);
    expect(backend.submitRequests, isEmpty);
  });

  testWidgets('a payment still on the phone blocks Submit', (tester) async {
    final backend = FakeCollectorBackend.working();
    await pumpSubmit(
      tester,
      backend: backend,
      outbox: MemoryOutboxStore([
        queuedPayment(recordedAt: now.subtract(const Duration(minutes: 3))),
      ]),
    );

    expect(find.text('1 payment still on this phone'), findsOneWidget);
    await tapKey(tester, 'submit.button');

    expect(find.textContaining("hasn't reached the server yet"), findsOneWidget);
    expect(backend.submitRequests, isEmpty);
  });

  testWidgets('a payment in its 10 minutes blocks Submit until it closes',
      (tester) async {
    final backend = FakeCollectorBackend.working()
      ..handler = (request) {
        if (request.method == 'GET' &&
            request.url.path.endsWith('/collector/v1/payments')) {
          return http.Response(
            daySummaryBody(correctableUntil: ['2026-11-15T17:46:30']),
            200,
          );
        }
        return http.Response(submissionsPage(), 200);
      };
    await pumpSubmit(tester, backend: backend);

    expect(find.text('1 payment in its 10 minutes · 6:30'), findsOneWidget);
    await tapKey(tester, 'submit.button');

    expect(find.textContaining('You can submit at'), findsOneWidget);
    expect(backend.submitRequests, isEmpty);
  });

  testWidgets("the backend's refusal is shown word for word", (tester) async {
    final backend = FakeCollectorBackend((request) {
      if (request.method == 'POST') {
        return http.Response(
          errorBody(409,
              '1 payment(s) are still in their 10-minute correction window. You can submit after 17:50'),
          409,
        );
      }
      if (request.url.path.endsWith('/collector/v1/payments')) {
        return http.Response(daySummaryBody(), 200);
      }
      return http.Response(submissionsPage(), 200);
    });
    await pumpSubmit(tester, backend: backend);

    await tapSubmitAndConfirm(tester);

    expect(
      find.text('1 payment(s) are still in their 10-minute correction window. '
          'You can submit after 17:50'),
      findsOneWidget,
    );
    expect(dayClosure.isClosed, isFalse);
  });

  testWidgets('a submission already waiting opens in the waiting state',
      (tester) async {
    final backend = FakeCollectorBackend((request) {
      if (request.url.path.endsWith('/collector/v1/submissions')) {
        return http.Response(
            submissionsPage([submissionJson(expectedAmount: 500)]), 200);
      }
      return http.Response(daySummaryBody(), 200);
    });
    await pumpSubmit(tester, backend: backend);

    expect(find.byKey(const Key('submit.waiting')), findsOneWidget);
    expect(find.text('GH₵ 500.00'), findsOneWidget);
    expect(find.byKey(const Key('submit.button')), findsNothing);
    expect(dayClosure.isClosed, isTrue);
  });

  testWidgets('without a connection it says so and offers Try again',
      (tester) async {
    var online = false;
    final backend = FakeCollectorBackend((request) {
      if (!online) throw http.ClientException('no connection');
      if (request.url.path.endsWith('/collector/v1/submissions')) {
        return http.Response(submissionsPage(), 200);
      }
      return http.Response(daySummaryBody(), 200);
    });
    await pumpSubmit(tester, backend: backend);

    expect(find.textContaining('Submitting needs a connection'), findsOneWidget);

    online = true;
    await tapKey(tester, 'submit.retry');

    expect(find.text('GH₵ 1,240.00'), findsOneWidget);
  });

  test('the latest submission is read from the paged list', () async {
    final backend = FakeCollectorBackend(
      (_) => http.Response(
          submissionsPage([submissionJson(status: 'APPROVED')]), 200),
    );

    final latest = await backend.api.fetchLatestSubmission();

    expect(latest?.isWaiting, isFalse);
    expect(backend.requests.single.url.queryParameters,
        {'page': '0', 'size': '1'});
    expect(
      jsonDecode(submissionsPage())['content'],
      isEmpty,
    );
  });
}
