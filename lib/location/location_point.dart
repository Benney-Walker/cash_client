import 'package:flutter/foundation.dart';

/// Why a location point was taken (backend `LocationTrigger`).
enum LocationTrigger {
  /// The regular point, every 5 minutes while the collector is signed in.
  every5Min('EVERY_5_MIN'),

  /// Taken when a payment is recorded; carries the payment's key.
  payment('PAYMENT');

  const LocationTrigger(this.wireName);

  final String wireName;

  static LocationTrigger? fromWire(Object? value) {
    for (final trigger in values) {
      if (trigger.wireName == value) return trigger;
    }
    return null;
  }
}

/// One reading of where the phone was (owner decisions 2026-11-23, D34),
/// as it's kept on the phone and sent to `POST /api/collector/v1/locations`.
@immutable
class LocationPoint {
  const LocationPoint({
    this.id,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    this.batteryPercent,
    required this.trigger,
    this.paymentKey,
    required this.recordedAt,
  }) : assert(
          (trigger == LocationTrigger.payment) == (paymentKey != null),
          'Only a PAYMENT point carries a payment key, and it always does',
        );

  /// The row's id on the phone; null until it's stored.
  final int? id;

  final double latitude;
  final double longitude;

  /// How far off the reading may be, in metres, as the phone reports it.
  final double accuracyMeters;

  /// 0–100, when the phone can tell.
  final int? batteryPercent;

  final LocationTrigger trigger;

  /// The payment's idempotency key, for a [LocationTrigger.payment] point.
  final String? paymentKey;

  /// The phone's clock when the reading arrived, in UTC. The backend
  /// compares it with the payment's `createdAt`, which comes from the same
  /// clock.
  final DateTime recordedAt;
}

/// What the backend did with a batch of points.
@immutable
class LocationBatchResult {
  const LocationBatchResult({required this.stored, required this.duplicates});

  /// New points saved.
  final int stored;

  /// Points it already had (a batch sent again), stored once.
  final int duplicates;
}
