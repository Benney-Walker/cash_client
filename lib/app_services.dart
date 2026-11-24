import 'package:flutter/foundation.dart';

import 'collector/collector_api.dart';
import 'collector/member_directory.dart';
import 'home/today.dart';
import 'location/location_tracker.dart';
import 'outbox/outbox.dart';
import 'submission/day_closure.dart';
import 'sync/sync_scheduler.dart';

/// The backend-facing services the signed-in screens use, created once in
/// `main` and handed down, so tests can swap in fakes.
class AppServices {
  AppServices({
    required this.collectorApi,
    required this.members,
    required this.outbox,
    required this.sync,
    required this.dayClosure,
    required this.location,
    required this.today,
    ValueNotifier<bool>? openOutboxRequest,
  }) : openOutboxRequest = openOutboxRequest ?? ValueNotifier<bool>(false);

  final CollectorApi collectorApi;
  final MemberDirectory members;

  /// Payments saved on the phone that the backend doesn't have yet.
  final Outbox outbox;
  final SyncScheduler sync;

  /// Whether the collector's submitted day is waiting for approval, when
  /// no more payments can be recorded.
  final DayClosure dayClosure;

  /// Location tracking and the point taken with each payment (D34).
  final LocationTracker location;

  /// Home's live totals and recent payments.
  final TodayController today;

  /// Set when the collector taps a refused-payment notification; the
  /// signed-in app opens the Outbox and clears it.
  final ValueNotifier<bool> openOutboxRequest;
}
