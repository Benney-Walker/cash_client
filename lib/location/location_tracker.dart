import 'dart:async';

import 'package:flutter/widgets.dart';

import 'location_platform.dart';
import 'location_point.dart';
import 'location_store.dart';

/// Why a payment can't be recorded without a location.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message);

  /// For the collector, as it's shown on the confirm screen.
  final String message;

  static const off = LocationUnavailable(
    'Location is off. Turn it on to record payments.',
  );

  static const noFix = LocationUnavailable(
    "Can't find your location. Step outside and try again.",
  );

  @override
  String toString() => message;
}

/// Location tracking for the collector (owner decisions 2026-11-23 and
/// 2026-11-24, D34):
///
/// - a point every 5 minutes while the collector is signed in and their day
///   isn't submitted, even with the app closed (a foreground service shows
///   a notification while it runs);
/// - a point with each payment, carrying the payment's key
///   ([paymentPoint]);
/// - points are kept on the phone and sent before payments
///   (`LocationSync`), because the backend refuses a payment without a
///   point within 15 minutes of it;
/// - no recording while location is off or not allowed (owner decision
///   2026-11-24): there'd be no point, so the backend would refuse it.
///
/// The app tells it when tracking is wanted ([track]); it runs whenever
/// that's so and location is [isReady].
class LocationTracker extends ChangeNotifier with WidgetsBindingObserver {
  LocationTracker({
    required LocationPlatform platform,
    required LocationStore store,
    required String? Function() staffId,
    DateTime Function()? now,
  })  : _platform = platform,
        _store = store,
        _staffId = staffId,
        _now = now ?? DateTime.now;

  final LocationPlatform _platform;
  final LocationStore _store;
  final String? Function() _staffId;
  final DateTime Function() _now;

  /// How often the regular point is taken.
  static const every = Duration(minutes: 5);

  /// Android may deliver readings early (when another app asks for its
  /// location); closer than this to the last point, a reading is skipped.
  static const minGap = Duration(minutes: 4, seconds: 30);

  /// How long a payment waits for a fresh reading.
  static const fixTimeLimit = Duration(seconds: 20);

  /// Without a fresh reading, a point this recent is enough for a payment
  /// (owner decision 2026-11-24). Well inside the backend's 15 minutes.
  static const recentEnough = Duration(minutes: 10);

  /// Runs after each regular point is saved, so it can be sent straight
  /// away. Set by the app once the sync exists.
  VoidCallback? onPoint;

  LocationAccess _access = LocationAccess.denied;
  bool _checked = false;
  bool _wanted = false;
  bool _watching = false;
  StreamSubscription<LocationFix>? _tracking;
  StreamSubscription<bool>? _service;
  DateTime? _lastTracked;

  LocationAccess get access => _access;

  /// Location is allowed and turned on.
  bool get isReady => _access == LocationAccess.ready;

  /// Location is known to be off or not allowed, so payments can't be
  /// recorded. False until the first check, so home doesn't flash "Turn on
  /// location" before it.
  bool get isOff => _checked && !isReady;

  /// The collector hasn't allowed location (or said no for good). False
  /// until the first check, so nothing flashes up before it.
  bool get needsPermission =>
      _checked &&
      (_access == LocationAccess.denied ||
          _access == LocationAccess.deniedForever);

  bool get isTracking => _tracking != null;

  /// Starts following the app's lifecycle and the phone's location switch,
  /// so [access] stays current when the collector comes back from Settings.
  void startWatching() {
    if (_watching) return;
    _watching = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      _service = _platform.serviceChanges().listen(
            (_) => checkAccess(),
            onError: (Object _) {},
          );
    } catch (_) {
      // Resuming the app still re-checks.
    }
  }

  void stopWatching() {
    if (!_watching) return;
    _watching = false;
    WidgetsBinding.instance.removeObserver(this);
    _service?.cancel();
    _service = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) checkAccess();
  }

  Future<LocationAccess> checkAccess() async {
    try {
      _setAccess(await _platform.access());
    } catch (_) {
      // Keep what we knew.
    }
    return _access;
  }

  /// Shows Android's location prompt (the disclosure screen's "Turn on
  /// location").
  Future<LocationAccess> requestAccess() async {
    try {
      _setAccess(await _platform.requestAccess());
    } catch (_) {
      await checkAccess();
    }
    return _access;
  }

  /// Does what it takes to get location working: Android's prompt if it can
  /// still ask, otherwise the app's settings, or the phone's location
  /// switch when it's only turned off.
  Future<void> fixAccess() async {
    final access = await checkAccess();
    try {
      switch (access) {
        case LocationAccess.ready:
          return;
        case LocationAccess.denied:
          await requestAccess();
        case LocationAccess.deniedForever:
          await _platform.openAppSettings();
        case LocationAccess.serviceOff:
          await _platform.openLocationSettings();
      }
    } catch (_) {
      // Nothing more the app can do; the button stays.
    }
  }

  /// Whether the app wants tracking: a collector is signed in and their day
  /// isn't submitted. Safe to call as often as that might have changed.
  void track(bool wanted) {
    _wanted = wanted;
    _apply();
  }

  /// Takes the point that goes with a payment, before it's saved, under the
  /// payment's idempotency key.
  ///
  /// Throws [LocationUnavailable] when location is off or not allowed, or
  /// when no reading comes and the last point is older than
  /// [recentEnough]: the backend would refuse that payment, so it isn't
  /// saved.
  Future<void> paymentPoint(String paymentKey) async {
    final staffId = _staffId();
    if (staffId == null) return;
    if (!isReady && await checkAccess() != LocationAccess.ready) {
      throw LocationUnavailable.off;
    }

    LocationFix? fix;
    try {
      fix = await _platform
          .currentFix(fixTimeLimit)
          .timeout(fixTimeLimit + const Duration(seconds: 5));
    } catch (_) {
      fix = null;
    }
    if (fix != null) {
      await _save(staffId, fix, LocationTrigger.payment, paymentKey);
      return;
    }

    // Indoors, say. A recent regular point still covers the payment.
    final now = _now();
    final latest = await _store.latestRecordedAt(staffId);
    if (latest != null &&
        now.difference(latest) <= recentEnough &&
        !latest.isAfter(now.add(const Duration(minutes: 1)))) {
      return;
    }
    throw LocationUnavailable.noFix;
  }

  void _setAccess(LocationAccess access) {
    final changed = !_checked || access != _access;
    _checked = true;
    _access = access;
    if (!changed) return;
    _apply();
    notifyListeners();
  }

  void _apply() {
    if (_wanted && isReady && _staffId() != null) {
      _startTracking();
    } else {
      _stopTracking();
    }
  }

  void _startTracking() {
    if (_tracking != null) return;
    try {
      _tracking = _platform.trackEvery(every).listen(
            _onFix,
            // Permission taken away or location switched off: stop, and
            // start again once it's back.
            onError: (Object _) {
              _stopTracking();
              checkAccess();
            },
            onDone: _stopTracking,
          );
    } catch (_) {
      _tracking = null;
    }
  }

  void _stopTracking() {
    final tracking = _tracking;
    _tracking = null;
    tracking?.cancel();
  }

  Future<void> _onFix(LocationFix fix) async {
    final staffId = _staffId();
    if (staffId == null) return;
    final now = _now();
    final last = _lastTracked;
    if (last != null && now.difference(last).abs() < minGap) return;
    _lastTracked = now;
    try {
      await _save(staffId, fix, LocationTrigger.every5Min, null);
    } catch (_) {
      return;
    }
    onPoint?.call();
  }

  Future<void> _save(
    String staffId,
    LocationFix fix,
    LocationTrigger trigger,
    String? paymentKey,
  ) async {
    int? battery;
    try {
      battery = await _platform.batteryPercent();
    } catch (_) {
      battery = null;
    }
    await _store.add(
      staffId,
      LocationPoint(
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracyMeters: fix.accuracyMeters,
        batteryPercent: battery,
        trigger: trigger,
        paymentKey: paymentKey,
        // The phone's clock, like the payment's createdAt it's checked
        // against.
        recordedAt: _now().toUtc(),
      ),
    );
  }

  @override
  void dispose() {
    _stopTracking();
    stopWatching();
    super.dispose();
  }
}
