import '../api/api_exception.dart';
import '../collector/collector_api.dart';
import 'location_point.dart';
import 'location_store.dart';

/// Sends the location points kept on the phone (owner decisions 2026-11-23,
/// D34), in batches of up to 500.
///
/// The backend refuses a payment unless a point taken within 15 minutes of
/// it arrived first, so the payment sync runs this before sending any
/// payment.
class LocationSync {
  LocationSync({
    required LocationStore store,
    required CollectorApi api,
    DateTime Function()? now,
  })  : _store = store,
        _api = api,
        _now = now ?? DateTime.now;

  final LocationStore _store;
  final CollectorApi _api;
  final DateTime Function() _now;

  /// The backend takes at most this many points a call.
  static const batchSize = 500;

  /// Sent points are kept this long, only so the app knows when it last had
  /// a location (see `LocationTracker.paymentPoint`).
  static const keepSentFor = Duration(days: 1);

  /// Sends all of [staffId]'s unsent points. True when none are left, false
  /// when some didn't get through (no connection, ended session, server
  /// fault); they go next time.
  ///
  /// A point the backend rejects (400, such as a phone time in the future)
  /// fails its whole batch, so that batch is sent again one point at a time
  /// and only the rejected point is dropped: it would never be accepted, and
  /// keeping it would block every point after it. Any other refusal (403,
  /// for example) is about the account, not the points, so they're kept.
  Future<bool> flush(String staffId) async {
    while (true) {
      final batch = await _store.unsent(staffId, limit: batchSize);
      if (batch.isEmpty) break;
      try {
        await _api.sendLocations(batch);
        await _store.markSent(_ids(batch), _now());
      } catch (error) {
        if (!_rejectsPoints(error)) return false;
        if (!await _oneByOne(batch)) return false;
      }
      if (batch.length < batchSize) break;
    }
    try {
      await _store.pruneSent(_now().subtract(keepSentFor));
    } catch (_) {
      // Housekeeping only; next time.
    }
    return true;
  }

  Future<bool> _oneByOne(List<LocationPoint> batch) async {
    for (final point in batch) {
      final ids = _ids([point]);
      try {
        await _api.sendLocations([point]);
        await _store.markSent(ids, _now());
      } catch (error) {
        if (!_rejectsPoints(error)) return false;
        await _store.remove(ids);
      }
    }
    return true;
  }

  static bool _rejectsPoints(Object error) =>
      error is ApiException && error.failure == ApiFailure.validation;

  static List<int> _ids(List<LocationPoint> points) => [
        for (final point in points)
          if (point.id != null) point.id!,
      ];
}
