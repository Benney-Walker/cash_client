import '../storage/app_database.dart';
import 'location_point.dart';

/// Location points kept on the phone until the backend has them, and for a
/// day after, so the app knows when it last had a location.
///
/// Points belong to the collector who was signed in when they were taken.
/// Like payments, unsent points stay on the phone through a sign-out and go
/// after the same collector signs in again.
abstract interface class LocationStore {
  /// Keeps [point] for [staffId].
  Future<void> add(String staffId, LocationPoint point);

  /// [staffId]'s points the backend doesn't have yet, oldest first.
  Future<List<LocationPoint>> unsent(String staffId, {int limit});

  /// The backend has these points.
  Future<void> markSent(List<int> ids, DateTime at);

  /// Drops points the backend will never take (it refused them).
  Future<void> remove(List<int> ids);

  /// When [staffId]'s latest point was taken, sent or not.
  Future<DateTime?> latestRecordedAt(String staffId);

  /// Deletes points sent before [before]; they're only kept for
  /// [latestRecordedAt].
  Future<void> pruneSent(DateTime before);
}

/// [LocationStore] as the database's `location_points` table.
class SqliteLocationStore implements LocationStore {
  SqliteLocationStore(this._db);

  final AppDatabase _db;

  @override
  Future<void> add(String staffId, LocationPoint point) async {
    final db = await _db.database;
    await db.insert('location_points', {
      'staff_id': staffId,
      'latitude': point.latitude,
      'longitude': point.longitude,
      'accuracy_meters': point.accuracyMeters,
      'battery_percent': point.batteryPercent,
      'point_trigger': point.trigger.wireName,
      'payment_key': point.paymentKey,
      'recorded_at': _text(point.recordedAt),
    });
  }

  @override
  Future<List<LocationPoint>> unsent(String staffId, {int limit = 500}) async {
    final db = await _db.database;
    final rows = await db.query(
      'location_points',
      where: 'staff_id = ? AND sent_at IS NULL',
      whereArgs: [staffId],
      orderBy: 'recorded_at, id',
      limit: limit,
    );
    return [
      for (final row in rows)
        if (_point(row) case final point?) point,
    ];
  }

  @override
  Future<void> markSent(List<int> ids, DateTime at) async {
    if (ids.isEmpty) return;
    final db = await _db.database;
    await db.update(
      'location_points',
      {'sent_at': _text(at)},
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  @override
  Future<void> remove(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _db.database;
    await db.delete(
      'location_points',
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  @override
  Future<DateTime?> latestRecordedAt(String staffId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT MAX(recorded_at) AS latest FROM location_points '
      'WHERE staff_id = ?',
      [staffId],
    );
    return _time(rows.isEmpty ? null : rows.first['latest']);
  }

  @override
  Future<void> pruneSent(DateTime before) async {
    final db = await _db.database;
    await db.delete(
      'location_points',
      where: 'sent_at IS NOT NULL AND sent_at < ?',
      whereArgs: [_text(before)],
    );
  }

  // UTC ISO-8601 text sorts in time order, which MAX and ORDER BY rely on.
  static String _text(DateTime time) => time.toUtc().toIso8601String();

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  static LocationPoint? _point(Map<String, Object?> row) {
    final trigger = LocationTrigger.fromWire(row['point_trigger']);
    final recordedAt = _time(row['recorded_at']);
    final latitude = row['latitude'];
    final longitude = row['longitude'];
    final accuracy = row['accuracy_meters'];
    final key = row['payment_key'] as String?;
    if (trigger == null ||
        recordedAt == null ||
        latitude is! num ||
        longitude is! num ||
        accuracy is! num ||
        (trigger == LocationTrigger.payment) != (key != null)) {
      return null;
    }
    return LocationPoint(
      id: row['id'] as int?,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      accuracyMeters: accuracy.toDouble(),
      batteryPercent: row['battery_percent'] as int?,
      trigger: trigger,
      paymentKey: key,
      recordedAt: recordedAt,
    );
  }
}
