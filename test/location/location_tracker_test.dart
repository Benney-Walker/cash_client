import 'package:cash_client/location/location_platform.dart';
import 'package:cash_client/location/location_point.dart';
import 'package:cash_client/location/location_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeLocationPlatform platform;
  late MemoryLocationStore store;
  late DateTime now;
  String? staffId;

  LocationTracker tracker() => LocationTracker(
        platform: platform,
        store: store,
        staffId: () => staffId,
        now: () => now,
      );

  setUp(() {
    platform = FakeLocationPlatform();
    store = MemoryLocationStore();
    now = DateTime.utc(2026, 11, 24, 9);
    staffId = 'STF001';
  });

  group('the point with each payment', () {
    test('takes a fresh reading under the payment key, with battery',
        () async {
      final location = tracker();
      await location.checkAccess();

      await location.paymentPoint('pay-1');

      final point = store.points.single;
      expect(point.trigger, LocationTrigger.payment);
      expect(point.paymentKey, 'pay-1');
      expect(point.latitude, FakeLocationPlatform.accraFix.latitude);
      expect(point.accuracyMeters, 12);
      expect(point.batteryPercent, 80);
      expect(point.recordedAt, now);
    });

    test('no reading (indoors): a point from the last 10 minutes is enough',
        () async {
      final location = tracker();
      await location.checkAccess();
      await location.paymentPoint('pay-1');
      platform.fix = null;
      now = now.add(const Duration(minutes: 9));

      await location.paymentPoint('pay-2');

      expect(store.points, hasLength(1));
    });

    test('no reading and nothing recent: not saved, and says why', () async {
      final location = tracker();
      await location.checkAccess();
      await location.paymentPoint('pay-1');
      platform.fix = null;
      now = now.add(const Duration(minutes: 11));

      await expectLater(
        location.paymentPoint('pay-2'),
        throwsA(same(LocationUnavailable.noFix)),
      );
      expect(LocationUnavailable.noFix.message,
          "Can't find your location. Step outside and try again.");
    });

    test('location off or not allowed: refused before any reading', () async {
      platform.accessNow = LocationAccess.serviceOff;
      final location = tracker();

      await expectLater(
        location.paymentPoint('pay-1'),
        throwsA(same(LocationUnavailable.off)),
      );
      expect(store.points, isEmpty);
    });

    test('a location turned back on is noticed at the payment', () async {
      platform.accessNow = LocationAccess.serviceOff;
      final location = tracker();
      await location.checkAccess();
      platform.accessNow = LocationAccess.ready;

      await location.paymentPoint('pay-1');

      expect(store.points, hasLength(1));
    });
  });

  group('every 5 minutes', () {
    test('tracks while wanted and allowed, and saves each reading', () async {
      final location = tracker();
      await location.checkAccess();
      var sent = 0;
      location.onPoint = () => sent++;

      location.track(true);
      expect(location.isTracking, isTrue);
      platform.activeTracking!.add(FakeLocationPlatform.accraFix);
      await pumpEventQueue();

      expect(store.points.single.trigger, LocationTrigger.every5Min);
      expect(store.points.single.paymentKey, isNull);
      expect(sent, 1);
    });

    test('a reading that comes early is skipped', () async {
      final location = tracker();
      await location.checkAccess();
      location.track(true);
      final stream = platform.activeTracking!;

      stream.add(FakeLocationPlatform.accraFix);
      await pumpEventQueue();
      now = now.add(const Duration(minutes: 1));
      stream.add(FakeLocationPlatform.accraFix);
      await pumpEventQueue();
      now = now.add(const Duration(minutes: 4));
      stream.add(FakeLocationPlatform.accraFix);
      await pumpEventQueue();

      expect(store.points, hasLength(2));
    });

    test('stops when no longer wanted (submitted, signed out)', () async {
      final location = tracker();
      await location.checkAccess();
      location.track(true);
      final stream = platform.activeTracking!;

      location.track(false);

      expect(location.isTracking, isFalse);
      expect(stream.hasListener, isFalse);
    });

    test("doesn't start until location is allowed, then starts by itself",
        () async {
      platform
        ..accessNow = LocationAccess.denied
        ..afterRequest = LocationAccess.ready;
      final location = tracker();
      await location.checkAccess();
      location.track(true);
      expect(location.isTracking, isFalse);
      expect(location.needsPermission, isTrue);

      await location.requestAccess();

      expect(location.isTracking, isTrue);
      expect(location.needsPermission, isFalse);
    });

    test('not without a signed-in collector', () async {
      staffId = null;
      final location = tracker();
      await location.checkAccess();

      location.track(true);

      expect(location.isTracking, isFalse);
    });

    test('location switched off mid-tracking: stops, then resumes', () async {
      final location = tracker();
      await location.checkAccess();
      location.track(true);

      platform.accessNow = LocationAccess.serviceOff;
      platform.activeTracking!.addError(Exception('location off'));
      await pumpEventQueue();
      expect(location.isTracking, isFalse);
      expect(location.isOff, isTrue);

      platform.accessNow = LocationAccess.ready;
      await location.checkAccess();
      expect(location.isTracking, isTrue);
    });
  });

  group('getting location working', () {
    test('nothing is off before the first check', () {
      final location = tracker();
      expect(location.isOff, isFalse);
      expect(location.needsPermission, isFalse);
    });

    test('asks Android while it still can', () async {
      platform.accessNow = LocationAccess.denied;
      final location = tracker();

      await location.fixAccess();

      expect(platform.requests, 1);
    });

    test('said no for good: opens the app settings', () async {
      platform.accessNow = LocationAccess.deniedForever;
      final location = tracker();

      await location.fixAccess();

      expect(platform.requests, 0);
      expect(platform.appSettingsOpened, 1);
    });

    test("allowed but switched off: opens the phone's location settings",
        () async {
      platform.accessNow = LocationAccess.serviceOff;
      final location = tracker();

      await location.fixAccess();

      expect(platform.locationSettingsOpened, 1);
    });
  });
}
