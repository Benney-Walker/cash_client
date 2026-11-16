import 'package:flutter/foundation.dart';

import '../collector/record_payment_screen.dart';
import 'outbox_store.dart';

/// The signed-in collector's outbox, for the screens: payments recorded
/// offline that the backend doesn't have yet.
///
/// The background sync changes the same table from another isolate, so the
/// list is re-read with [refresh] after every sync and when the app comes
/// back to the foreground.
class Outbox extends ChangeNotifier {
  Outbox({
    required OutboxStore store,
    required String? Function() staffId,
    DateTime Function()? now,
  })  : _store = store,
        _staffId = staffId,
        _now = now ?? DateTime.now;

  final OutboxStore _store;
  final String? Function() _staffId;
  final DateTime Function() _now;

  List<OutboxPayment> _items = const [];

  /// Oldest first.
  List<OutboxPayment> get items => _items;

  List<OutboxPayment> get refused => [
        for (final p in _items)
          if (p.isRefused) p,
      ];

  /// Not refused: inside their 10 minutes, or due and waiting for a
  /// connection.
  List<OutboxPayment> get waiting => [
        for (final p in _items)
          if (!p.isRefused) p,
      ];

  bool get isEmpty => _items.isEmpty;

  DateTime now() => _now();

  Future<void> refresh() async {
    final staffId = _staffId();
    final List<OutboxPayment> items;
    try {
      items = staffId == null ? const [] : await _store.list(staffId);
    } catch (_) {
      // Keep showing what was there; the next refresh tries again.
      return;
    }
    _items = List.unmodifiable(items);
    notifyListeners();
  }

  /// Keeps a payment that couldn't be sent. [idempotencyKey] is the one the
  /// confirm screen already tried with, so if that attempt did reach the
  /// backend, the sync gets the saved payment back rather than a second one.
  Future<OutboxPayment> add(
    PaymentDraft draft, {
    required String idempotencyKey,
  }) async {
    final staffId = _staffId();
    if (staffId == null) throw StateError('No collector is signed in');
    final payment = OutboxPayment(
      idempotencyKey: idempotencyKey,
      staffId: staffId,
      memberName: draft.member.name,
      accountNumber: draft.account.accountNumber,
      type: draft.type,
      amount: draft.amount,
      note: draft.note,
      recordedAt: _now().toUtc(),
    );
    await _store.add(payment);
    await refresh();
    return payment;
  }
}
