import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../api/api_exception.dart';
import '../collector/collector_api.dart';
import '../collector/collector_models.dart';
import '../common/money.dart';
import '../outbox/outbox.dart';
import '../outbox/outbox_store.dart';
import '../storage/app_database.dart';
import '../sync/payment_sync.dart';

/// Home's live figures (Step 1, design T1, owner decisions 2026-11-24):
/// today's total, savings and shares, the number of payments, and the 5
/// latest payments.
///
/// - The server's day summary (`GET /api/collector/v1/payments`) plus the
///   payments still on the phone: the cash is already collected, and it's
///   what Submit hands in. Refused payments are left out of the figures
///   (the server didn't take them) but show in the list.
/// - Offline, the last summary downloaded today is used, saved on the
///   phone, with when it was downloaded.
/// - FAILED payments count in the number but not the money, as on the
///   server.
class TodayController extends ChangeNotifier {
  TodayController({
    required CollectorApi api,
    required Outbox outbox,
    required DaySummaryStore store,
    required String? Function() staffId,
    DateTime Function()? now,
  })  : _api = api,
        _outbox = outbox,
        _store = store,
        _staffId = staffId,
        _now = now ?? DateTime.now {
    _outbox.addListener(notifyListeners);
  }

  final CollectorApi _api;
  final Outbox _outbox;
  final DaySummaryStore _store;
  final String? Function() _staffId;
  final DateTime Function() _now;

  /// How many payments home lists before See all (owner decision).
  static const recentCount = 5;

  SavedDaySummary? _saved;
  TodayProblem _problem = TodayProblem.none;
  bool _refreshing = false;
  Future<void>? _running;

  bool get isRefreshing => _refreshing;

  /// Asks the server for today's summary and keeps it on the phone. Offline,
  /// falls back to the one saved today. Joins a refresh already running.
  Future<void> refresh() => _running ??= _refresh().whenComplete(() {
        _running = null;
      });

  Future<void> _refresh() async {
    final staffId = _staffId();
    if (staffId == null) return;
    _refreshing = true;
    notifyListeners();
    try {
      final summary = await _api.fetchDaySummary();
      if (_staffId() != staffId) return;
      _saved = SavedDaySummary(
        staffId: staffId,
        fetchedAt: _now().toUtc(),
        summary: summary,
      );
      _problem = TodayProblem.none;
      try {
        await _store.save(_saved!);
      } catch (_) {
        // Only the offline fallback is lost.
      }
    } catch (error) {
      _problem = error is ApiException && error.failure == ApiFailure.network
          ? TodayProblem.offline
          : TodayProblem.failed;
      if (_saved == null) {
        try {
          _saved = await _store.read();
        } catch (_) {
          _saved = null;
        }
      }
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  /// A sync finished. Payments that reached the server change its totals;
  /// a sync that got through after a failed download is a chance to try
  /// again.
  void synced(SyncReport report) {
    if (report.sent > 0 || (_problem != TodayProblem.none && !report.offline)) {
      refresh();
    }
  }

  /// The collector signed out or the session ended: nothing of theirs stays
  /// on screen, and the saved summary goes.
  void clear() {
    _saved = null;
    _problem = TodayProblem.none;
    notifyListeners();
    _store.clear().catchError((Object _) {});
  }

  /// What home shows now.
  TodayView get view {
    final now = _now().toUtc();
    final staffId = _staffId();
    final saved = _saved;
    final server = saved != null &&
            saved.staffId == staffId &&
            _sameDay(saved.fetchedAt, now)
        ? saved.summary
        : null;

    final onServer = {
      for (final p in server?.payments ?? const <CollectorPayment>[])
        p.idempotencyKey,
    };
    // Today's payments still on the phone that the server doesn't list yet.
    final onPhone = [
      for (final p in _outbox.items)
        if (_sameDay(p.createdAt, now) && !onServer.contains(p.idempotencyKey))
          p,
    ];
    final counted = [
      for (final p in onPhone)
        if (!p.isRefused) p,
    ];

    var savings = server?.savingsTotal.pesewas ?? 0;
    var shares = server?.sharesTotal.pesewas ?? 0;
    for (final p in counted) {
      if (p.type == PaymentType.shares) {
        shares += p.amount.pesewas;
      } else {
        savings += p.amount.pesewas;
      }
    }

    final recent = <RecentPayment>[
      for (final p in onPhone) RecentPayment.onPhone(p),
      for (final p in server?.payments ?? const <CollectorPayment>[])
        RecentPayment.fromServer(p),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return TodayView(
      savings: Cedis.pesewas(savings),
      shares: Cedis.pesewas(shares),
      count: (server?.count ?? 0) + counted.length,
      onPhone: counted.length,
      hasServerFigures: server != null,
      updatedAt: server == null ? null : saved!.fetchedAt,
      problem: _problem,
      recent: List.unmodifiable(recent.take(recentCount)),
    );
  }

  /// The backend's day is Africa/Accra, which is UTC.
  static bool _sameDay(DateTime a, DateTime b) {
    final x = a.toUtc();
    final y = b.toUtc();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  @override
  void dispose() {
    _outbox.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Home's figures at one moment.
@immutable
class TodayView {
  const TodayView({
    required this.savings,
    required this.shares,
    required this.count,
    required this.onPhone,
    required this.hasServerFigures,
    required this.updatedAt,
    required this.problem,
    required this.recent,
  });

  static const empty = TodayView(
    savings: Cedis.zero,
    shares: Cedis.zero,
    count: 0,
    onPhone: 0,
    hasServerFigures: false,
    updatedAt: null,
    problem: TodayProblem.none,
    recent: [],
  );

  final Cedis savings;
  final Cedis shares;
  Cedis get total => Cedis.pesewas(savings.pesewas + shares.pesewas);

  /// Payments today, failed ones included, as the server counts them.
  final int count;

  /// Of [count], how many are still on the phone (refused ones aren't
  /// counted).
  final int onPhone;

  /// False when the server's summary for today hasn't been seen (offline
  /// since the day began): the figures are the phone's only.
  final bool hasServerFigures;

  /// When the server's figures were downloaded.
  final DateTime? updatedAt;

  /// Why the last attempt to download them failed, if it did.
  final TodayProblem problem;

  /// Newest first, at most [TodayController.recentCount].
  final List<RecentPayment> recent;
}

/// Why the server's figures couldn't be downloaded last time.
enum TodayProblem {
  none,

  /// No connection (or a timeout).
  offline,

  /// The server answered with an error.
  failed,
}

/// Where a payment in home's list stands.
enum RecentState {
  /// On the phone: held for its 5 minutes, or waiting for a connection.
  onPhone,

  /// On the phone, refused by the server.
  refused,

  completed,
  failed,

  /// A status from the server the app doesn't know (or PENDING).
  other,
}

/// One row of home's recent list.
@immutable
class RecentPayment {
  const RecentPayment({
    required this.idempotencyKey,
    required this.memberName,
    required this.type,
    required this.accountNumber,
    required this.amount,
    required this.createdAt,
    required this.state,
    this.phonePayment,
  });

  factory RecentPayment.onPhone(OutboxPayment payment) => RecentPayment(
        idempotencyKey: payment.idempotencyKey,
        memberName: payment.memberName,
        type: payment.type,
        accountNumber: payment.accountNumber,
        amount: payment.amount,
        createdAt: payment.createdAt,
        state: payment.isRefused ? RecentState.refused : RecentState.onPhone,
        phonePayment: payment,
      );

  factory RecentPayment.fromServer(CollectorPayment payment) => RecentPayment(
        idempotencyKey: payment.idempotencyKey,
        memberName: payment.memberName,
        type: payment.type,
        accountNumber: payment.accountNumber,
        amount: payment.amount,
        // Every payment the server lists has its phone time; the receipt
        // time is a stand-in only for a malformed record.
        createdAt: payment.createdAt ??
            payment.receivedAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        state: switch (payment.status) {
          PaymentStatus.completed => RecentState.completed,
          PaymentStatus.failed => RecentState.failed,
          _ => RecentState.other,
        },
      );

  final String idempotencyKey;
  final String memberName;
  final PaymentType type;
  final String accountNumber;
  final Cedis amount;
  final DateTime createdAt;
  final RecentState state;

  /// The phone's copy, for a payment still on the phone (its countdown).
  final OutboxPayment? phonePayment;
}

/// Today's summary as last downloaded, kept for offline.
@immutable
class SavedDaySummary {
  const SavedDaySummary({
    required this.staffId,
    required this.fetchedAt,
    required this.summary,
  });

  final String staffId;
  final DateTime fetchedAt;
  final CollectorDaySummary summary;
}

abstract interface class DaySummaryStore {
  Future<SavedDaySummary?> read();
  Future<void> save(SavedDaySummary saved);
  Future<void> clear();
}

/// [DaySummaryStore] as a row in the database's `sync_meta` table.
class SqliteDaySummaryStore implements DaySummaryStore {
  SqliteDaySummaryStore(this._db);

  final AppDatabase _db;

  static const _key = 'day_summary';

  @override
  Future<SavedDaySummary?> read() async {
    final db = await _db.database;
    final rows =
        await db.query('sync_meta', where: 'key = ?', whereArgs: [_key]);
    if (rows.isEmpty) return null;
    try {
      final json = jsonDecode(rows.first['value'] as String);
      if (json is! Map<String, dynamic>) return null;
      final staffId = json['staffId'];
      final fetchedAt = parseServerTime(json['fetchedAt']);
      final summary = CollectorDaySummary.fromJson(json['summary']);
      if (staffId is! String || fetchedAt == null || summary == null) {
        return null;
      }
      return SavedDaySummary(
        staffId: staffId,
        fetchedAt: fetchedAt,
        summary: summary,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(SavedDaySummary saved) async {
    final db = await _db.database;
    await db.insert(
      'sync_meta',
      {
        'key': _key,
        'value': jsonEncode({
          'staffId': saved.staffId,
          'fetchedAt': saved.fetchedAt.toUtc().toIso8601String(),
          'summary': saved.summary.toJson(),
        }),
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
