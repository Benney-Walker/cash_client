import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../collector/idempotency.dart';
import '../storage/app_database.dart';

/// Lets only one part of the app refresh the session at a time.
///
/// Refresh tokens are single use (backend, 15 Nov 2026), and spending one
/// twice ends the whole session. The open app and the background sync run
/// in separate isolates with their own session managers, so they agree
/// through the shared database.
abstract interface class RefreshLock {
  /// Runs [action] while holding the lock.
  Future<T> run<T>(Future<T> Function() action);
}

/// No locking, for tests and for code that has only one session manager.
class NoRefreshLock implements RefreshLock {
  const NoRefreshLock();

  @override
  Future<T> run<T>(Future<T> Function() action) => action();
}

/// [RefreshLock] held as a row in the app's SQLite database.
///
/// The row carries a lease, so a holder that crashes mid-refresh blocks the
/// other for at most [lease]. If the database itself fails, the refresh runs
/// without the lock rather than not at all.
class SqliteRefreshLock implements RefreshLock {
  SqliteRefreshLock(
    this._db, {
    this.lease = const Duration(seconds: 40),
    this.poll = const Duration(milliseconds: 250),
  });

  final AppDatabase _db;

  /// Longer than a refresh can take, including its one retry (two 10-second
  /// timeouts).
  final Duration lease;
  final Duration poll;

  static const _name = 'session_refresh';

  @override
  Future<T> run<T>(Future<T> Function() action) async {
    final owner = newIdempotencyKey();
    var held = false;
    try {
      held = await _acquire(owner);
    } catch (_) {
      held = false;
    }
    try {
      return await action();
    } finally {
      if (held) {
        try {
          final db = await _db.database;
          await db.delete(
            'app_locks',
            where: 'name = ? AND owner = ?',
            whereArgs: [_name, owner],
          );
        } catch (_) {
          // The lease runs out on its own.
        }
      }
    }
  }

  /// Waits for the lock, for a little longer than one lease. Returns false
  /// if it never came free, and the caller goes ahead anyway: a stuck lock
  /// must not stop the collector working.
  Future<bool> _acquire(String owner) async {
    final db = await _db.database;
    final giveUpAt = DateTime.now().add(lease + const Duration(seconds: 5));
    while (true) {
      final now = DateTime.now().toUtc();
      // EXCLUSIVE, so two connections can't both see the lock free.
      final got = await db.transaction((txn) async {
        final rows = await txn.query(
          'app_locks',
          columns: ['held_until'],
          where: 'name = ?',
          whereArgs: [_name],
        );
        final heldUntil = rows.isEmpty
            ? null
            : DateTime.tryParse(rows.first['held_until'] as String? ?? '');
        if (heldUntil != null && heldUntil.isAfter(now)) return false;
        await txn.insert(
          'app_locks',
          {
            'name': _name,
            'owner': owner,
            'held_until': now.add(lease).toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return true;
      }, exclusive: true);
      if (got) return true;
      if (DateTime.now().isAfter(giveUpAt)) return false;
      await Future<void>.delayed(poll);
    }
  }
}
