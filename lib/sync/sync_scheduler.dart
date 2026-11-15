import 'dart:async';

import 'package:flutter/widgets.dart';

import '../outbox/outbox.dart';
import '../outbox/outbox_store.dart';
import 'payment_sync.dart';
import 'sync_platform.dart';

/// Decides when the app syncs while a collector is signed in:
///
/// - when they sign in or the app opens,
/// - when the app comes back to the foreground,
/// - when the phone gets a connection,
/// - when a waiting payment's 10 minutes are up,
/// - when they tap Retry in the Outbox.
///
/// While the app is closed, Android's WorkManager runs the same sync (see
/// `background_sync.dart`).
class SyncScheduler with WidgetsBindingObserver {
  SyncScheduler({
    required PaymentSync sync,
    required Outbox outbox,
    required ConnectivityWatcher connectivity,
    required BackgroundScheduler background,
    required AppNotifications notifications,
  })  : _sync = sync,
        _outbox = outbox,
        _connectivity = connectivity,
        _background = background,
        _notifications = notifications;

  final PaymentSync _sync;
  final Outbox _outbox;
  final ConnectivityWatcher _connectivity;
  final BackgroundScheduler _background;
  final AppNotifications _notifications;

  StreamSubscription<bool>? _connection;
  Timer? _nextDue;
  bool _started = false;

  /// The scheduler of the running app, if a collector is signed in. When
  /// WorkManager runs a task inside the running app, it uses this rather
  /// than building a second set of services.
  static SyncScheduler? active;

  bool get isStarted => _started;

  /// A collector is signed in. Safe to call more than once.
  void start() {
    if (_started) return;
    _started = true;
    active = this;
    WidgetsBinding.instance.addObserver(this);
    _connection = _connectivity.changes.listen((online) {
      if (online) syncNow();
    });
    unawaited(_background.ensurePeriodic().catchError((Object _) {}));
    syncNow();
  }

  /// The collector signed out or the session ended. Their outbox stays on
  /// the phone and is sent after they sign in again.
  void stop() {
    if (!_started) return;
    _started = false;
    if (identical(active, this)) active = null;
    WidgetsBinding.instance.removeObserver(this);
    _connection?.cancel();
    _connection = null;
    _nextDue?.cancel();
    _nextDue = null;
    _outbox.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) syncNow();
  }

  /// Syncs, then re-reads the outbox and arranges the next due time.
  Future<SyncReport> syncNow() async {
    if (!_started) return SyncReport.nothing;
    // Show what's on the phone straight away; a slow connection can hold
    // the sync for up to the request timeout.
    await _outbox.refresh();
    SyncReport report;
    try {
      report = await _sync.run();
    } catch (_) {
      // The store couldn't be read, for example. Try again next time.
      report = const SyncReport(offline: true);
    }
    await _outbox.refresh();
    _scheduleNextDue();
    return report;
  }

  /// A payment was just saved on the phone.
  Future<void> paymentQueued(OutboxPayment payment) async {
    final delay = payment.timeLeft(_outbox.now());
    _scheduleNextDue();
    try {
      await _background.scheduleOnce(payment.idempotencyKey, delay);
    } catch (_) {
      // The periodic task still picks it up.
    }
    try {
      await _notifications.requestPermission();
    } catch (_) {
      // Refused payments still show in the Outbox.
    }
  }

  void _scheduleNextDue() {
    _nextDue?.cancel();
    _nextDue = null;
    if (!_started) return;
    final now = _outbox.now();
    DateTime? next;
    for (final p in _outbox.waiting) {
      if (p.isDue(now)) continue;
      if (next == null || p.dueAt.isBefore(next)) next = p.dueAt;
    }
    if (next == null) return;
    // A second late, so the payment is surely due when the timer fires.
    _nextDue = Timer(next.difference(now) + const Duration(seconds: 1), () {
      syncNow();
    });
  }
}
