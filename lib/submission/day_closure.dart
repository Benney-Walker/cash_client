import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../collector/collector_api.dart';
import '../collector/collector_models.dart';
import '../storage/app_database.dart';

/// Whether the signed-in collector has submitted their day and is waiting
/// for approval (decision D35: submitting closes the day, so no more
/// payments until it's approved).
///
/// The backend refuses payments after a submission, but the app keeps its
/// own note too, so that a payment taken offline after submitting isn't
/// saved on the phone only to be refused at the next sync. The note is
/// cleared when the session ends: approval signs the collector out.
class DayClosure extends ChangeNotifier {
  DayClosure({
    required SubmittedDayStore store,
    required String? Function() staffId,
  })  : _store = store,
        _staffId = staffId;

  final SubmittedDayStore _store;
  final String? Function() _staffId;

  SubmittedDay? _day;

  /// True while the signed-in collector's submission waits for approval.
  bool get isClosed {
    final day = _day;
    return day != null && day.staffId == _staffId();
  }

  /// Reads the note kept on the phone.
  Future<void> load() async {
    try {
      _day = await _store.read();
    } catch (_) {
      _day = null;
    }
    notifyListeners();
  }

  /// Asks the backend for the collector's latest submission and updates
  /// the note. Leaves it alone when the backend can't be reached.
  Future<void> refresh(CollectorApi api) async {
    try {
      update(await api.fetchLatestSubmission());
    } catch (_) {
      // Offline: keep what the phone knows.
    }
  }

  /// Records what the backend said about the latest submission.
  void update(DaySubmission? latest) {
    final staffId = _staffId();
    if (staffId == null) return;
    if (latest != null && latest.isWaiting) {
      _set(SubmittedDay(staffId: staffId, submissionId: latest.id));
    } else {
      _set(null);
    }
  }

  /// The session ended or the collector signed out.
  void clear() => _set(null);

  void _set(SubmittedDay? day) {
    if (day == _day) return;
    _day = day;
    notifyListeners();
    // Best effort; the backend still refuses payments after a submission.
    (day == null ? _store.clear() : _store.save(day))
        .catchError((Object _) {});
  }
}

@immutable
class SubmittedDay {
  const SubmittedDay({required this.staffId, required this.submissionId});

  final String staffId;
  final String submissionId;

  @override
  bool operator ==(Object other) =>
      other is SubmittedDay &&
      other.staffId == staffId &&
      other.submissionId == submissionId;

  @override
  int get hashCode => Object.hash(staffId, submissionId);
}

abstract interface class SubmittedDayStore {
  Future<SubmittedDay?> read();
  Future<void> save(SubmittedDay day);
  Future<void> clear();
}

/// [SubmittedDayStore] as a row in the database's `sync_meta` table.
class SqliteSubmittedDayStore implements SubmittedDayStore {
  SqliteSubmittedDayStore(this._db);

  final AppDatabase _db;

  static const _key = 'day_submitted';

  @override
  Future<SubmittedDay?> read() async {
    final db = await _db.database;
    final rows = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: [_key],
    );
    if (rows.isEmpty) return null;
    try {
      final json = jsonDecode(rows.first['value'] as String);
      final staffId = json is Map ? json['staffId'] : null;
      final submissionId = json is Map ? json['submissionId'] : null;
      if (staffId is! String || submissionId is! String) return null;
      return SubmittedDay(staffId: staffId, submissionId: submissionId);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(SubmittedDay day) async {
    final db = await _db.database;
    await db.insert(
      'sync_meta',
      {
        'key': _key,
        'value': jsonEncode(
          {'staffId': day.staffId, 'submissionId': day.submissionId},
        ),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> clear() async {
    final db = await _db.database;
    await db.delete('sync_meta', where: 'key = ?', whereArgs: [_key]);
  }
}
