import 'package:flutter/foundation.dart';

import '../collector/collector_models.dart';
import '../collector/record_payment_screen.dart';
import '../common/money.dart';
import 'outbox_store.dart';

/// The signed-in collector's outbox, for the screens: payments on the phone
/// that the backend doesn't have yet. Every payment starts here and is held
/// for its 5 minutes (owner decision 2026-11-23).
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

  /// Not refused: inside their 5 minutes, or due and waiting for a
  /// connection.
  List<OutboxPayment> get waiting => [
        for (final p in _items)
          if (!p.isRefused) p,
      ];

  bool get isEmpty => _items.isEmpty;

  DateTime now() => _now();

  /// The payment with [idempotencyKey], or null once it's been sent.
  OutboxPayment? find(String idempotencyKey) {
    for (final p in _items) {
      if (p.idempotencyKey == idempotencyKey) return p;
    }
    return null;
  }

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

  /// Keeps a newly confirmed payment for its 5 minutes. [idempotencyKey]
  /// was made by the confirm screen and goes with every send.
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
      createdAt: _now().toUtc(),
    );
    await _store.add(payment);
    await refresh();
    return payment;
  }

  /// A correction inside the 5 minutes: [account] (one of the same member's
  /// accounts) and [amount]. Returns false when it's too late, because the
  /// 5 minutes are up or the payment is already being sent.
  Future<bool> correct(
    String idempotencyKey, {
    required MemberAccount account,
    required Cedis amount,
  }) async {
    final bool changed;
    try {
      changed = await _store.correct(
        idempotencyKey,
        type: account.type,
        accountNumber: account.accountNumber,
        amount: amount,
        updatedAt: _now().toUtc(),
      );
    } finally {
      await refresh();
    }
    return changed;
  }
}
