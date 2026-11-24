import 'package:flutter/foundation.dart';

import '../api/api_exception.dart';
import '../collector/collector_api.dart';
import '../outbox/outbox_store.dart';

/// Tells the collector that the backend refused payments, through a phone
/// notification, so they report it to the admin.
abstract interface class RefusalNotifier {
  /// [payments] were refused for the first time in this sync.
  Future<void> refused(List<OutboxPayment> payments);
}

/// What one sync did.
@immutable
class SyncReport {
  const SyncReport({
    this.sent = 0,
    this.newlyRefused = 0,
    this.stillRefused = 0,
    this.offline = false,
  });

  static const nothing = SyncReport();

  /// Payments the backend saved.
  final int sent;

  /// Payments refused for the first time.
  final int newlyRefused;

  /// Payments refused before and refused again.
  final int stillRefused;

  /// The sync stopped early because the backend couldn't be reached (or the
  /// session had ended); what's left goes next time.
  final bool offline;
}

/// Sends the outbox to the backend (owner decisions 2026-11-15 and
/// 2026-11-23).
///
/// - A payment goes only after its 5 minutes on the phone, with its phone
///   `createdAt` and `updatedAt`; the backend applies it on arrival. Before
///   submitting, [run] with `includeHeld` sends the held ones early too, as
///   the backend asks (2026-11-23).
/// - Each payment is sent on its own. One the backend refuses never holds
///   up the others: it stays on the phone with the backend's reason, the
///   collector is notified once, and every later sync tries it again.
/// - A payment that didn't get through (no connection, timeout, server
///   fault) just waits for the next sync, without a notification.
/// - Every attempt uses the payment's own idempotency key, so nothing is
///   recorded twice, even when an earlier attempt reached the backend but
///   its answer was lost.
///
/// The app and the background sync can run at the same time (in separate
/// isolates); [OutboxStore.claim] keeps them off the same payment.
class PaymentSync {
  PaymentSync({
    required OutboxStore store,
    required CollectorApi api,
    required String? Function() staffId,
    required RefusalNotifier notifier,
    DateTime Function()? now,
  })  : _store = store,
        _api = api,
        _staffId = staffId,
        _notifier = notifier,
        _now = now ?? DateTime.now;

  final OutboxStore _store;
  final CollectorApi _api;
  final String? Function() _staffId;
  final RefusalNotifier _notifier;
  final DateTime Function() _now;

  /// Longer than one request can take (the API times out at 20 seconds),
  /// short enough that a crash mid-send doesn't hold a payment for long.
  static const claimFor = Duration(minutes: 2);

  static const fallbackReason = "The server didn't accept this payment.";

  Future<SyncReport>? _running;

  /// Runs one sync, or joins the one already running. With [includeHeld],
  /// payments still in their 5 minutes are sent too (before submitting the
  /// day); a sync already running is waited for first, then this one runs.
  Future<SyncReport> run({bool includeHeld = false}) async {
    if (!includeHeld) {
      return _running ??= _run(false).whenComplete(() => _running = null);
    }
    final running = _running;
    if (running != null) await running;
    return _running ??= _run(true).whenComplete(() => _running = null);
  }

  Future<SyncReport> _run(bool includeHeld) async {
    final staffId = _staffId();
    if (staffId == null) return SyncReport.nothing;

    var sent = 0;
    var stillRefused = 0;
    var offline = false;
    final newlyRefused = <OutboxPayment>[];

    final payments = await _store.list(staffId);
    for (final payment in payments) {
      final now = _now();
      // Refused payments are tried again on every sync (owner decision
      // 2026-11-15); the rest only once their 5 minutes are up, unless the
      // day is being submitted.
      if (!includeHeld && !payment.isRefused && !payment.isDue(now)) continue;
      // The session may have ended part way through.
      if (_staffId() != staffId) break;
      if (!await _store.claim(payment.idempotencyKey, now, now.add(claimFor))) {
        continue;
      }

      try {
        await _api.recordPayment(
          idempotencyKey: payment.idempotencyKey,
          type: payment.type,
          accountNumber: payment.accountNumber,
          amount: payment.amount,
          description: payment.note,
          createdAt: payment.createdAt,
          updatedAt: payment.updatedAt,
        );
        await _store.remove(payment.idempotencyKey);
        sent++;
      } catch (error) {
        if (isRefusal(error)) {
          final reason = (error as ApiException).message ?? fallbackReason;
          final firstTime =
              await _store.markRefused(payment.idempotencyKey, reason, _now());
          if (firstTime) {
            newlyRefused.add(payment);
          } else {
            stillRefused++;
          }
          continue;
        }
        await _store.markTried(payment.idempotencyKey, _now());
        // Without a connection or a session, the rest would fail the same
        // way. A server fault might be about this payment only, so carry on.
        if (_stopsTheSync(error)) {
          offline = true;
          break;
        }
      }
    }

    if (newlyRefused.isNotEmpty) {
      try {
        await _notifier.refused(newlyRefused);
      } catch (_) {
        // The Outbox still shows them; a missed notification loses nothing.
      }
    }
    return SyncReport(
      sent: sent,
      newlyRefused: newlyRefused.length,
      stillRefused: stillRefused,
      offline: offline,
    );
  }

  static bool _stopsTheSync(Object error) =>
      error is ApiException &&
      (error.failure == ApiFailure.network ||
          error.failure == ApiFailure.unauthorized ||
          error.failure == ApiFailure.notConfigured);
}
