import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../collector/collector_models.dart';
import '../common/money.dart';
import '../storage/app_database.dart';

/// A payment recorded without a connection, kept on the phone until the
/// backend has it (app spec 2.3 and 2.4a).
@immutable
class OutboxPayment {
  const OutboxPayment({
    required this.idempotencyKey,
    required this.staffId,
    required this.memberName,
    required this.accountNumber,
    required this.type,
    required this.amount,
    required this.recordedAt,
    this.note,
    this.refusalReason,
    this.refusedAt,
    this.lastTriedAt,
  });

  /// Made on the confirm screen and sent with every attempt, so the backend
  /// never records it twice, even if an earlier attempt did get through.
  final String idempotencyKey;

  /// The collector who recorded it. Only their session sends it.
  final String staffId;
  final String memberName;
  final String accountNumber;
  final PaymentType type;
  final Cedis amount;
  final String? note;

  /// Phone time when the collector recorded it, in UTC. Sent to the backend
  /// as `recordedAt`.
  final DateTime recordedAt;

  /// The backend's reason, once it has refused the payment.
  final String? refusalReason;
  final DateTime? refusedAt;

  /// The last time the app tried to send it, whatever the outcome.
  final DateTime? lastTriedAt;

  bool get isRefused => refusalReason != null;

  /// When its 10 minutes are up and it can be sent (decision D40: offline
  /// payments arrive at the backend final).
  DateTime get dueAt => recordedAt.add(correctionWindow);

  bool isDue(DateTime now) => !now.isBefore(dueAt);

  /// Time left in its 10 minutes, never negative.
  Duration timeLeft(DateTime now) {
    final left = dueAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

/// Where outbox payments live. Every call is safe to make from the app and
/// from the background sync at the same time.
abstract interface class OutboxStore {
  Future<void> add(OutboxPayment payment);

  /// [staffId]'s payments, oldest first.
  Future<List<OutboxPayment>> list(String staffId);

  /// Takes [idempotencyKey] for sending until [until], unless someone else
  /// (the other of app and background sync) holds it. Returns false when
  /// it's taken or gone. Holding it stops the two from sending the same
  /// payment at the same moment; a crash just lets the hold run out.
  Future<bool> claim(String idempotencyKey, DateTime now, DateTime until);

  /// The backend has it: forget it.
  Future<void> remove(String idempotencyKey);

  /// It didn't get through (no connection, timeout, server fault). Keeps
  /// any earlier refusal.
  Future<void> markTried(String idempotencyKey, DateTime at);

  /// The backend refused it. Returns true the first time this payment is
  /// refused, so the collector is notified once, not on every retry.
  Future<bool> markRefused(String idempotencyKey, String reason, DateTime at);
}

/// [OutboxStore] in the app's SQLite database.
class SqliteOutboxStore implements OutboxStore {
  SqliteOutboxStore(this._db);

  final AppDatabase _db;

  static const _table = 'outbox';

  @override
  Future<void> add(OutboxPayment payment) async {
    final db = await _db.database;
    await db.insert(
      _table,
      {
        'idempotency_key': payment.idempotencyKey,
        'staff_id': payment.staffId,
        'member_name': payment.memberName,
        'account_number': payment.accountNumber,
        'payment_type': payment.type.wireName,
        'amount_pesewas': payment.amount.pesewas,
        'description': payment.note,
        'recorded_at': _text(payment.recordedAt),
      },
      // The same key twice is the same payment; keep the first copy.
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<List<OutboxPayment>> list(String staffId) async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where: 'staff_id = ?',
      whereArgs: [staffId],
      orderBy: 'recorded_at, idempotency_key',
    );
    return [
      for (final row in rows)
        if (_fromRow(row) case final payment?) payment,
    ];
  }

  @override
  Future<bool> claim(String idempotencyKey, DateTime now, DateTime until) async {
    final db = await _db.database;
    // One statement, so SQLite decides atomically which caller gets it.
    final changed = await db.rawUpdate(
      'UPDATE $_table SET claimed_until = ? '
      'WHERE idempotency_key = ? '
      'AND (claimed_until IS NULL OR claimed_until < ?)',
      [_text(until), idempotencyKey, _text(now)],
    );
    return changed == 1;
  }

  @override
  Future<void> remove(String idempotencyKey) async {
    final db = await _db.database;
    await db.delete(
      _table,
      where: 'idempotency_key = ?',
      whereArgs: [idempotencyKey],
    );
  }

  @override
  Future<void> markTried(String idempotencyKey, DateTime at) async {
    final db = await _db.database;
    await db.update(
      _table,
      {'last_tried_at': _text(at), 'claimed_until': null},
      where: 'idempotency_key = ?',
      whereArgs: [idempotencyKey],
    );
  }

  @override
  Future<bool> markRefused(
    String idempotencyKey,
    String reason,
    DateTime at,
  ) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        _table,
        columns: ['notified', 'refused_at'],
        where: 'idempotency_key = ?',
        whereArgs: [idempotencyKey],
      );
      if (rows.isEmpty) return false;
      final firstTime = rows.first['notified'] == 0;
      await txn.update(
        _table,
        {
          'refusal_reason': reason,
          'refused_at': rows.first['refused_at'] ?? _text(at),
          'last_tried_at': _text(at),
          'notified': 1,
          'claimed_until': null,
        },
        where: 'idempotency_key = ?',
        whereArgs: [idempotencyKey],
      );
      return firstTime;
    });
  }

  static String _text(DateTime time) => time.toUtc().toIso8601String();

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  static OutboxPayment? _fromRow(Map<String, Object?> row) {
    final type = PaymentType.fromWire(row['payment_type']);
    final recordedAt = _time(row['recorded_at']);
    final pesewas = row['amount_pesewas'];
    if (type == null || recordedAt == null || pesewas is! int) return null;
    return OutboxPayment(
      idempotencyKey: row['idempotency_key'] as String,
      staffId: row['staff_id'] as String,
      memberName: row['member_name'] as String,
      accountNumber: row['account_number'] as String,
      type: type,
      amount: Cedis.pesewas(pesewas),
      note: row['description'] as String?,
      recordedAt: recordedAt,
      refusalReason: row['refusal_reason'] as String?,
      refusedAt: _time(row['refused_at']),
      lastTriedAt: _time(row['last_tried_at']),
    );
  }
}
