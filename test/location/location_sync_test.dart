import 'dart:convert';

import 'package:cash_client/location/location_point.dart';
import 'package:cash_client/location/location_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fakes.dart';

void main() {
  final now = DateTime.utc(2026, 11, 24, 10, 30);
  late MemoryLocationStore store;

  setUp(() => store = MemoryLocationStore());

  LocationPoint point(int minutesAgo, {String? key, double lat = 5.6}) =>
      LocationPoint(
        latitude: lat,
        longitude: -0.18,
        accuracyMeters: 10,
        batteryPercent: 70,
        trigger: key == null ? LocationTrigger.every5Min : LocationTrigger.payment,
        paymentKey: key,
        recordedAt: now.subtract(Duration(minutes: minutesAgo)),
      );

  LocationSync syncWith(FakeCollectorBackend backend) =>
      LocationSync(store: store, api: backend.api, now: () => now);

  List<Map<String, dynamic>> pointsIn(http.Request request) => [
        for (final p in (jsonDecode(request.body) as Map)['points'] as List)
          p as Map<String, dynamic>,
      ];

  test('sends the unsent points, oldest first, and marks them sent', () async {
    await store.add('STF001', point(5));
    await store.add('STF001', point(10, key: 'pay-1'));
    final backend = FakeCollectorBackend.working();

    final delivered = await syncWith(backend).flush('STF001');

    expect(delivered, isTrue);
    final sent = pointsIn(backend.locationRequests.single);
    expect(sent.first, {
      'latitude': 5.6,
      'longitude': -0.18,
      'accuracyMeters': 10.0,
      'batteryPercent': 70,
      'trigger': 'PAYMENT',
      'paymentIdempotencyKey': 'pay-1',
      'recordedAt': '2026-11-24T10:20:00',
    });
    expect(sent.last['trigger'], 'EVERY_5_MIN');
    expect(sent.last.containsKey('paymentIdempotencyKey'), isFalse);
    expect(await store.unsent('STF001'), isEmpty);
    // Kept a while, so the app knows when it last had a location.
    expect(await store.latestRecordedAt('STF001'), now.subtract(const Duration(minutes: 5)));
  });

  test('nothing to send: no request', () async {
    final backend = FakeCollectorBackend.working();

    expect(await syncWith(backend).flush('STF001'), isTrue);
    expect(backend.requests, isEmpty);
  });

  test("only the signed-in collector's points go", () async {
    await store.add('STF001', point(5));
    await store.add('STF002', point(6));
    final backend = FakeCollectorBackend.working();

    await syncWith(backend).flush('STF001');

    expect(pointsIn(backend.locationRequests.single), hasLength(1));
    expect(await store.unsent('STF002'), hasLength(1));
  });

  test('sends at most 500 a call', () async {
    for (var i = 0; i < 501; i++) {
      await store.add('STF001', point(600 - i));
    }
    final backend = FakeCollectorBackend.working();

    expect(await syncWith(backend).flush('STF001'), isTrue);

    expect(backend.locationRequests, hasLength(2));
    expect(pointsIn(backend.locationRequests.first), hasLength(500));
    expect(pointsIn(backend.locationRequests.last), hasLength(1));
  });

  test('without a connection the points stay for next time', () async {
    await store.add('STF001', point(5));
    final backend = FakeCollectorBackend(
      (_) => throw http.ClientException('offline'),
    );

    expect(await syncWith(backend).flush('STF001'), isFalse);
    expect(await store.unsent('STF001'), hasLength(1));
  });

  test('a rejected point is dropped; the others still go', () async {
    await store.add('STF001', point(5, lat: 1));
    await store.add('STF001', point(4, lat: 2));
    final backend = FakeCollectorBackend((request) {
      final points = pointsIn(request);
      if (points.any((p) => p['latitude'] == 1)) {
        return http.Response(
          errorBody(400, "recordedAt can't be in the future"),
          400,
        );
      }
      return http.Response(
        jsonEncode({'stored': points.length, 'duplicates': 0}),
        200,
      );
    });

    expect(await syncWith(backend).flush('STF001'), isTrue);

    // The batch, then each point on its own.
    expect(backend.locationRequests, hasLength(3));
    expect(await store.unsent('STF001'), isEmpty);
    expect(store.points.map((p) => p.latitude), [2]);
  });

  test('a refusal about the account keeps every point', () async {
    await store.add('STF001', point(5));
    final backend = FakeCollectorBackend(
      (_) => http.Response(errorBody(403, 'Collectors only'), 403),
    );

    expect(await syncWith(backend).flush('STF001'), isFalse);
    expect(await store.unsent('STF001'), hasLength(1));
  });

  test('points sent over a day ago are deleted', () async {
    await store.add('STF001', point(5));
    await store.markSent([1], now.subtract(const Duration(days: 2)));
    await store.add('STF001', point(4));
    await store.markSent([2], now.subtract(const Duration(hours: 1)));

    await syncWith(FakeCollectorBackend.working()).flush('STF001');

    expect(store.points.map((p) => p.id), [2]);
  });
}
