import 'dart:convert';

import 'package:cash_client/collector/collector_models.dart';
import 'package:cash_client/common/money.dart';
import 'package:cash_client/home/today.dart';
import 'package:cash_client/outbox/outbox.dart';
import 'package:cash_client/sync/payment_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fakes.dart';

void main() {
  // The fake summary's payments are dated 15 Nov 2026 at 10:00.
  final now = DateTime.utc(2026, 11, 15, 11);

  late MemoryOutboxStore outboxStore;
  late Outbox outbox;
  late MemoryDaySummaryStore saved;
  String? staffId;

  setUp(() {
    outboxStore = MemoryOutboxStore();
    saved = MemoryDaySummaryStore();
    staffId = 'STF001';
    outbox = Outbox(store: outboxStore, staffId: () => staffId, now: () => now);
  });

  TodayController controller(FakeCollectorBackend backend) => TodayController(
        api: backend.api,
        outbox: outbox,
        store: saved,
        staffId: () => staffId,
        now: () => now,
      );

  FakeCollectorBackend summary({
    num savings = 1040,
    num shares = 200,
    int count = 18,
    int payments = 0,
  }) =>
      FakeCollectorBackend(
        (_) => http.Response(
          daySummaryBody(
            savingsTotal: savings,
            sharesTotal: shares,
            count: count,
            payments: payments,
          ),
          200,
        ),
      );

  FakeCollectorBackend offline() =>
      FakeCollectorBackend((_) => throw http.ClientException('offline'));

  test("the server's figures plus the payments on the phone", () async {
    await outboxStore.add(queuedPayment(
      key: 'p1',
      createdAt: now.subtract(const Duration(minutes: 2)),
      pesewas: 5000,
    ));
    await outboxStore.add(queuedPayment(
      key: 'p2',
      createdAt: now.subtract(const Duration(minutes: 1)),
      type: PaymentType.shares,
      pesewas: 2050,
    ));
    await outbox.refresh();
    final today = controller(summary());

    await today.refresh();
    final view = today.view;

    expect(view.savings, const Cedis.pesewas(104000 + 5000));
    expect(view.shares, const Cedis.pesewas(20000 + 2050));
    expect(view.total, const Cedis.pesewas(124000 + 7050));
    expect(view.count, 20);
    expect(view.onPhone, 2);
    expect(view.problem, TodayProblem.none);
  });

  test('refused payments are listed but not counted', () async {
    await outboxStore.add(queuedPayment(
      key: 'r1',
      createdAt: now.subtract(const Duration(minutes: 30)),
      refusalReason: 'Account not active',
    ));
    await outbox.refresh();
    final today = controller(summary());

    await today.refresh();
    final view = today.view;

    expect(view.total, const Cedis.pesewas(124000));
    expect(view.onPhone, 0);
    expect(view.recent.first.state, RecentState.refused);
  });

  test('a payment the server already lists is counted once', () async {
    await outboxStore.add(queuedPayment(
      key: 'day-0',
      createdAt: now.subtract(const Duration(minutes: 1)),
    ));
    await outbox.refresh();
    final today = controller(summary(payments: 1));

    await today.refresh();

    expect(today.view.total, const Cedis.pesewas(124000));
    expect(today.view.recent, hasLength(1));
    expect(today.view.recent.single.state, RecentState.completed);
  });

  test("an earlier day's payment on the phone isn't today's", () async {
    await outboxStore.add(queuedPayment(
      key: 'old',
      createdAt: now.subtract(const Duration(days: 1)),
    ));
    await outbox.refresh();
    final today = controller(summary());

    await today.refresh();

    expect(today.view.onPhone, 0);
    expect(today.view.recent, isEmpty);
  });

  test('lists the 5 latest, newest first, phone and server together',
      () async {
    for (var i = 0; i < 3; i++) {
      await outboxStore.add(queuedPayment(
        key: 'p$i',
        createdAt: now.subtract(Duration(minutes: 10 - i)),
      ));
    }
    await outbox.refresh();
    final today = controller(summary(payments: 4));

    await today.refresh();
    final recent = today.view.recent;

    expect(recent, hasLength(5));
    // The phone's are newer than the server's (10:00).
    expect(recent.take(3).map((p) => p.idempotencyKey), ['p2', 'p1', 'p0']);
    expect(recent.first.state, RecentState.onPhone);
    expect(recent.last.state, RecentState.completed);
  });

  test('failed payments are listed as failed', () async {
    final today = controller(FakeCollectorBackend(
      (_) => http.Response(
        jsonEncode({
          'date': '2026-11-15',
          'count': 1,
          'savingsTotal': 0,
          'sharesTotal': 0,
          'total': 0,
          'payments': [
            jsonDecode(paymentBody(idempotencyKey: 'f', status: 'FAILED')),
          ],
        }),
        200,
      ),
    ));

    await today.refresh();

    expect(today.view.count, 1);
    expect(today.view.total, Cedis.zero);
    expect(today.view.recent.single.state, RecentState.failed);
  });

  group('offline', () {
    test('uses the figures saved today, with when', () async {
      await controller(summary()).refresh();
      final fetched = saved.saved!.fetchedAt;

      final later = controller(offline());
      await later.refresh();

      expect(later.view.total, const Cedis.pesewas(124000));
      expect(later.view.updatedAt, fetched);
      expect(later.view.problem, TodayProblem.offline);
    });

    test("yesterday's figures aren't used", () async {
      saved.saved = SavedDaySummary(
        staffId: 'STF001',
        fetchedAt: now.subtract(const Duration(days: 1)),
        summary: CollectorDaySummary.fromJson(
          jsonDecode(daySummaryBody()),
        )!,
      );
      final today = controller(offline());

      await today.refresh();

      expect(today.view.hasServerFigures, isFalse);
      expect(today.view.total, Cedis.zero);
    });

    test("another collector's figures aren't used", () async {
      await controller(summary()).refresh();
      staffId = 'STF002';

      final today = controller(offline());
      await today.refresh();

      expect(today.view.hasServerFigures, isFalse);
    });

    test('a server error is told apart from no connection', () async {
      final today = controller(FakeCollectorBackend(
        (_) => http.Response(errorBody(500, 'Server error'), 500),
      ));

      await today.refresh();

      expect(today.view.problem, TodayProblem.failed);
    });
  });

  group('after a sync', () {
    test('payments that reached the server: downloads again', () async {
      final backend = summary();
      final today = controller(backend);
      await today.refresh();

      today.synced(const SyncReport(sent: 1));
      await pumpEventQueue();

      expect(backend.requests, hasLength(2));
    });

    test('nothing sent and nothing wrong: no download', () async {
      final backend = summary();
      final today = controller(backend);
      await today.refresh();

      today.synced(SyncReport.nothing);
      await pumpEventQueue();

      expect(backend.requests, hasLength(1));
    });

    test('back online after a failed download: tries again', () async {
      var online = false;
      final backend = FakeCollectorBackend((_) {
        if (!online) throw http.ClientException('offline');
        return http.Response(daySummaryBody(), 200);
      });
      final today = controller(backend);
      await today.refresh();
      expect(today.view.problem, TodayProblem.offline);

      online = true;
      today.synced(SyncReport.nothing);
      await pumpEventQueue();

      expect(today.view.problem, TodayProblem.none);
      expect(today.view.total, const Cedis.pesewas(124000));
    });
  });

  test('signing out clears the figures and the saved copy', () async {
    final today = controller(summary());
    await today.refresh();

    today.clear();
    await pumpEventQueue();

    expect(today.view.hasServerFigures, isFalse);
    expect(saved.saved, isNull);
  });

  test('the saved copy survives the trip through JSON', () {
    final summary =
        CollectorDaySummary.fromJson(jsonDecode(daySummaryBody(payments: 2)))!;

    final again = CollectorDaySummary.fromJson(
      jsonDecode(jsonEncode(summary.toJson())),
    )!;

    expect(again.total, summary.total);
    expect(again.count, summary.count);
    expect(again.payments.map((p) => p.idempotencyKey), ['day-0', 'day-1']);
    expect(again.payments.first.createdAt, summary.payments.first.createdAt);
    expect(again.payments.first.status, PaymentStatus.completed);
  });
}
