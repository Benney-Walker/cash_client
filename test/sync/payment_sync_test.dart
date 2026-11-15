import 'dart:convert';

import 'package:cash_client/sync/payment_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fakes.dart';

void main() {
  // 10:30 UTC on the day; payments recorded before 10:20 are due.
  final now = DateTime.utc(2026, 11, 15, 10, 30);
  final due = now.subtract(const Duration(minutes: 15));
  final notDue = now.subtract(const Duration(minutes: 4));

  late MemoryOutboxStore store;
  late FakeNotifications notifications;

  setUp(() {
    store = MemoryOutboxStore();
    notifications = FakeNotifications();
  });

  PaymentSync syncWith(
    FakeCollectorBackend backend, {
    String? Function()? staffId,
  }) =>
      PaymentSync(
        store: store,
        api: backend.api,
        staffId: staffId ?? () => 'STF001',
        notifier: notifications,
        now: () => now,
      );

  String keyOf(http.Request r) =>
      (jsonDecode(r.body) as Map<String, dynamic>)['idempotencyKey'] as String;

  /// Saves every payment except the ones in [refuse], which get a 409 with
  /// the backend's message.
  FakeCollectorBackend backendRefusing(Set<String> refuse) =>
      FakeCollectorBackend((request) {
        final key = keyOf(request);
        if (refuse.contains(key)) {
          return http.Response(
            errorBody(409, "This member's first deposit must be made at the office"),
            409,
          );
        }
        return http.Response(paymentBody(idempotencyKey: key), 200);
      });

  test('sends a payment once its 10 minutes are up, with recordedAt',
      () async {
    await store.add(queuedPayment(key: 'a', recordedAt: due));
    final backend = FakeCollectorBackend.working();

    final report = await syncWith(backend).run();

    expect(report.sent, 1);
    expect(store.all, isEmpty);
    final body = jsonDecode(backend.paymentRequests.single.body) as Map;
    expect(body['idempotencyKey'], 'a');
    expect(body['recordedAt'], '2026-11-15T10:15:00');
  });

  test('a payment still inside its 10 minutes waits', () async {
    await store.add(queuedPayment(key: 'a', recordedAt: notDue));
    final backend = FakeCollectorBackend.working();

    final report = await syncWith(backend).run();

    expect(report.sent, 0);
    expect(backend.requests, isEmpty);
    expect(store.all, hasLength(1));
  });

  test('a refused payment does not stop the others, and is kept with the '
      "backend's reason", () async {
    await store.add(queuedPayment(key: 'a', recordedAt: due));
    await store.add(queuedPayment(
        key: 'b', recordedAt: due.add(const Duration(seconds: 1))));
    await store.add(queuedPayment(
        key: 'c', recordedAt: due.add(const Duration(seconds: 2))));
    final backend = backendRefusing({'b'});

    final report = await syncWith(backend).run();

    expect(report.sent, 2);
    expect(report.newlyRefused, 1);
    expect(backend.paymentRequests.map(keyOf), ['a', 'b', 'c']);
    final left = store.all.single;
    expect(left.idempotencyKey, 'b');
    expect(left.isRefused, isTrue);
    expect(left.refusalReason,
        "This member's first deposit must be made at the office");
    expect(notifications.shown.single.single.idempotencyKey, 'b');
  });

  test('refused payments are retried on every sync but notified only once',
      () async {
    await store.add(queuedPayment(key: 'a', recordedAt: due));
    final refusing = backendRefusing({'a'});
    final sync = syncWith(refusing);

    await sync.run();
    final second = await sync.run();

    expect(refusing.paymentRequests, hasLength(2));
    expect(second.stillRefused, 1);
    expect(second.newlyRefused, 0);
    expect(notifications.shown, hasLength(1));
  });

  test('a refused payment goes through once the office fixes the cause',
      () async {
    await store.add(queuedPayment(key: 'a', recordedAt: due));
    await syncWith(backendRefusing({'a'})).run();
    expect(store.all.single.isRefused, isTrue);

    final report = await syncWith(FakeCollectorBackend.working()).run();

    expect(report.sent, 1);
    expect(store.all, isEmpty);
  });

  test('no connection stops the sync, keeps everything and notifies nobody',
      () async {
    await store.add(queuedPayment(key: 'a', recordedAt: due));
    await store.add(queuedPayment(
        key: 'b', recordedAt: due.add(const Duration(seconds: 1))));
    final backend = FakeCollectorBackend(
      (_) => throw http.ClientException('no connection'),
    );

    final report = await syncWith(backend).run();

    expect(report.offline, isTrue);
    // It gave up after the first attempt rather than trying every payment.
    expect(backend.requests, hasLength(1));
    expect(store.all, hasLength(2));
    expect(store.all.every((p) => !p.isRefused), isTrue);
    expect(store.all.first.lastTriedAt, now);
    expect(notifications.shown, isEmpty);
  });

  test('a server fault on one payment is not a refusal and the rest still go',
      () async {
    await store.add(queuedPayment(key: 'a', recordedAt: due));
    await store.add(queuedPayment(
        key: 'b', recordedAt: due.add(const Duration(seconds: 1))));
    final backend = FakeCollectorBackend((request) {
      final key = keyOf(request);
      if (key == 'a') return http.Response(errorBody(500, 'Oops'), 500);
      return http.Response(paymentBody(idempotencyKey: key), 200);
    });

    final report = await syncWith(backend).run();

    expect(report.sent, 1);
    expect(report.newlyRefused, 0);
    expect(store.all.single.idempotencyKey, 'a');
    expect(store.all.single.isRefused, isFalse);
    expect(notifications.shown, isEmpty);
  });

  test('a payment the other sync is sending is left alone', () async {
    await store.add(queuedPayment(key: 'a', recordedAt: due));
    // The background sync holds it.
    await store.claim('a', now, now.add(const Duration(minutes: 2)));
    final backend = FakeCollectorBackend.working();

    await syncWith(backend).run();

    expect(backend.requests, isEmpty);
    expect(store.all, hasLength(1));
  });

  test("only the signed-in collector's payments are sent", () async {
    await store.add(queuedPayment(key: 'mine', recordedAt: due));
    await store.add(
        queuedPayment(key: 'theirs', staffId: 'STF002', recordedAt: due));
    final backend = FakeCollectorBackend.working();

    await syncWith(backend).run();

    expect(backend.paymentRequests.map(keyOf), ['mine']);
    expect(store.all.single.idempotencyKey, 'theirs');
  });

  test('nobody signed in: nothing is sent', () async {
    await store.add(queuedPayment(key: 'a', recordedAt: due));
    final backend = FakeCollectorBackend.working();

    final report = await syncWith(backend, staffId: () => null).run();

    expect(report.sent, 0);
    expect(backend.requests, isEmpty);
  });

  test('two syncs started together share one run', () async {
    await store.add(queuedPayment(key: 'a', recordedAt: due));
    final backend = FakeCollectorBackend.working();
    final sync = syncWith(backend);

    await Future.wait([sync.run(), sync.run()]);

    expect(backend.paymentRequests, hasLength(1));
  });
}
