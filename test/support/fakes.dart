import 'dart:async';
import 'dart:convert';

import 'package:cash_client/app_services.dart';
import 'package:cash_client/auth/auth_api.dart';
import 'package:cash_client/auth/auth_session.dart';
import 'package:cash_client/auth/device_id.dart';
import 'package:cash_client/auth/session_store.dart';
import 'package:cash_client/collector/collector_api.dart';
import 'package:cash_client/collector/collector_models.dart';
import 'package:cash_client/collector/member_cache.dart';
import 'package:cash_client/collector/member_directory.dart';
import 'package:cash_client/common/money.dart';
import 'package:cash_client/home/today.dart';
import 'package:cash_client/location/location_platform.dart';
import 'package:cash_client/location/location_point.dart';
import 'package:cash_client/location/location_store.dart';
import 'package:cash_client/location/location_sync.dart';
import 'package:cash_client/location/location_tracker.dart';
import 'package:cash_client/outbox/outbox.dart';
import 'package:cash_client/outbox/outbox_store.dart';
import 'package:cash_client/settings/app_info.dart';
import 'package:cash_client/settings/theme_mode_store.dart';
import 'package:cash_client/submission/day_closure.dart';
import 'package:cash_client/sync/payment_sync.dart';
import 'package:cash_client/sync/sync_platform.dart';
import 'package:cash_client/sync/sync_scheduler.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory [SessionStore] for tests.
class MemorySessionStore implements SessionStore {
  MemorySessionStore([this.session]);

  AuthSession? session;
  int saves = 0;

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> save(AuthSession session) async {
    saves++;
    this.session = session;
  }

  @override
  Future<void> clear() async => session = null;
}

const testBaseUrl = 'https://api.example.test';

const testAppInfo = AppInfo(
  version: '1.0.0',
  buildNumber: '1',
  apiBaseUrl: testBaseUrl,
);

/// A login response body in the backend's shape.
String loginBody({List<String> roles = const ['COLLECTOR']}) => jsonEncode({
      'staffName': 'KOFI MENSAH',
      'roles': roles,
      'authToken': 'access-token',
      'refreshToken': 'refresh-token',
    });

/// The backend's standard error body.
String errorBody(int status, String message,
        {Map<String, String>? errors}) =>
    jsonEncode({
      'timestamp': '2026-11-07T17:00:00Z',
      'status': status,
      'error': 'Error',
      'message': message,
      'path': '/api/auth/v1/collector-login',
      if (errors != null) 'errors': errors,
    });

/// An [AuthApi] whose login endpoint always answers with [status] and
/// [body]. [requests] collects what the app sent.
AuthApi fakeAuthApi(
  int status,
  String body, {
  List<http.Request>? requests,
}) {
  return AuthApi(
    baseUrl: testBaseUrl,
    client: MockClient((request) async {
      requests?.add(request);
      return http.Response(body, status,
          headers: {'content-type': 'application/json'});
    }),
  );
}

const collectorSession = AuthSession(
  staffId: 'STF001',
  staffName: 'KOFI MENSAH',
  roles: ['COLLECTOR'],
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
);

/// An [AuthApi] whose refresh endpoint answers with [refresh] each time it's
/// called. [calls] counts the refresh calls. [delay] holds each answer back,
/// so tests can make requests overlap.
class FakeRefreshApi {
  FakeRefreshApi(this.refresh, {this.delay = Duration.zero});

  /// Status and body to answer with. Change it between calls if needed.
  (int, String) refresh;
  final Duration delay;
  int calls = 0;

  /// When true, the refresh call fails as if the phone had no connection.
  bool offline = false;

  /// Refresh tokens the app sent, in order.
  final sentRefreshTokens = <String>[];

  /// Device IDs sent with each refresh (null when none was sent).
  final sentDeviceIds = <String?>[];

  /// Refresh tokens the app sent to `logout`.
  final loggedOut = <String>[];

  late final AuthApi api = AuthApi(
    baseUrl: testBaseUrl,
    client: MockClient((request) async {
      if (request.url.path.endsWith('/logout')) {
        loggedOut.add(
            (jsonDecode(request.body) as Map)['refreshToken'] as String);
        return http.Response('', 204);
      }
      if (request.url.path.endsWith('/refresh-collector-token')) {
        calls++;
        final body = jsonDecode(request.body) as Map;
        sentRefreshTokens.add(body['refreshToken'] as String);
        sentDeviceIds.add(body['deviceId'] as String?);
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        if (offline) throw http.ClientException('no connection');
        final (status, body) = refresh;
        return http.Response(body, status);
      }
      return http.Response(loginBody(), 200);
    }),
  );

  /// Refresh tokens rotate: the backend sends a new access token and a new
  /// refresh token (15 Nov 2026).
  static (int, String) issues(
    String token, {
    String refreshToken = 'next-refresh-token',
  }) =>
      (200, jsonEncode({'authToken': token, 'refreshToken': refreshToken}));

  static (int, String) refuses() =>
      (401, errorBody(401, 'Invalid refresh token'));
}

/// In-memory [ThemeModeStore] for tests. Set [failSaves] to make every save
/// throw.
class MemoryThemeModeStore implements ThemeModeStore {
  MemoryThemeModeStore([this.mode]);

  ThemeMode? mode;
  bool failSaves = false;

  @override
  Future<ThemeMode?> read() async => mode;

  @override
  Future<void> save(ThemeMode mode) async {
    if (failSaves) throw StateError('disk full');
    this.mode = mode;
  }
}

/// In-memory [MemberCache] for tests.
class MemoryMemberCache implements MemberCache {
  MemoryMemberCache([this.saved]);

  SavedMembers? saved;
  int clears = 0;

  @override
  Future<SavedMembers?> read() async => saved;

  @override
  Future<void> save(List<CollectorMember> members, DateTime savedAt) async =>
      saved = SavedMembers(members: members, savedAt: savedAt);

  @override
  Future<void> clear() async {
    clears++;
    saved = null;
  }
}

const amaOwusu = CollectorMember(
  name: 'Ama Owusu',
  accounts: [
    MemberAccount(accountNumber: '1002345678', type: PaymentType.savings),
    MemberAccount(accountNumber: '3002345678', type: PaymentType.shares),
  ],
);

const yawBoateng = CollectorMember(
  name: 'Yaw Boateng',
  accounts: [
    MemberAccount(accountNumber: '1002349911', type: PaymentType.savings),
  ],
);

/// A members response in the backend's shape.
String membersBody(List<CollectorMember> members) => jsonEncode([
      for (final m in members)
        {
          'memberName': m.name,
          'accounts': [
            for (final a in m.accounts)
              {'accountNumber': a.accountNumber, 'accountType': a.type.wireName},
          ],
        },
    ]);

/// A payment response in the backend's shape: saved PENDING at 10:00 with
/// a window until 10:10.
String paymentBody({
  required String idempotencyKey,
  String type = 'SAVINGS',
  String accountNumber = '1002345678',
  num amount = 50.0,
  String status = 'COMPLETED',
}) =>
    jsonEncode({
      'transactionId': '6f1c1a2e-0000-4000-8000-000000000001',
      'idempotencyKey': idempotencyKey,
      'type': type,
      'accountNumber': accountNumber,
      'memberName': 'Ama Owusu',
      'amount': amount,
      'status': status,
      'failureReason': null,
      'createdAt': '2026-11-15T10:00:00',
      'updatedAt': '2026-11-15T10:00:00',
      'receivedAt': '2026-11-15T10:05:30',
      'postedAt': '2026-11-15T10:05:30',
    });

/// A day summary from `GET /api/collector/v1/payments`, with [payments]
/// payment bodies listed.
String daySummaryBody({
  num savingsTotal = 1040.0,
  num sharesTotal = 200.0,
  int count = 18,
  int payments = 0,
}) =>
    jsonEncode({
      'date': '2026-11-15',
      'count': count,
      'savingsTotal': savingsTotal,
      'sharesTotal': sharesTotal,
      'total': savingsTotal + sharesTotal,
      'payments': [
        for (var i = 0; i < payments; i++)
          jsonDecode(paymentBody(idempotencyKey: 'day-$i')),
      ],
    });

/// A submission from `/api/collector/v1/submissions`.
Map<String, Object?> submissionJson({
  String status = 'SUBMITTED',
  num expectedAmount = 1240.0,
  int paymentCount = 18,
  int failedCount = 0,
}) =>
    {
      'submissionId': '9a1c1a2e-0000-4000-8000-000000000009',
      'collectorStaffId': 'STF001',
      'collectorName': 'Kofi Mensah',
      'branchName': 'Tarkwa',
      'status': status,
      'submittedAt': '2026-11-15T17:42:00',
      'paymentCount': paymentCount,
      'expectedAmount': expectedAmount,
      'failedCount': failedCount,
      'failedAmount': 0.0,
      'countedAmount': null,
      'shortageAmount': null,
      'overageAmount': null,
      'approvedByStaffId': null,
      'approvedAt': null,
      'payments': null,
    };

/// A page of submissions, newest first, as Spring's PagedModel sends it.
String submissionsPage([List<Map<String, Object?>> content = const []]) =>
    jsonEncode({
      'content': content,
      'page': {
        'size': 1,
        'number': 0,
        'totalElements': content.length,
        'totalPages': content.isEmpty ? 0 : 1,
      },
    });

extension SessionWithDevice on AuthSession {
  /// This session as if signed in on the phone [deviceId].
  AuthSession withDevice(String deviceId) => AuthSession(
        staffId: staffId,
        staffName: staffName,
        roles: roles,
        accessToken: accessToken,
        refreshToken: refreshToken,
        deviceId: deviceId,
      );
}

/// The phone's device ID, without the Android platform channel.
class FakeDeviceId implements DeviceIdSource {
  const FakeDeviceId([this.id = 'test-phone-1']);

  /// Null makes [read] fail as a phone without an ID would.
  final String? id;

  @override
  Future<String> read() async {
    final id = this.id;
    if (id == null) throw const DeviceIdUnavailable();
    return id;
  }
}

/// A scripted collector backend. [handler] answers each request; [requests]
/// collects what the app sent.
class FakeCollectorBackend {
  FakeCollectorBackend(this.handler);

  http.Response Function(http.Request request) handler;
  final requests = <http.Request>[];

  late final CollectorApi api = CollectorApi(
    baseUrl: testBaseUrl,
    client: MockClient((request) async {
      requests.add(request);
      return handler(request);
    }),
  );

  /// Answers the members list with [members] and records payments as
  /// PENDING, echoing the key it was sent.
  static FakeCollectorBackend working({
    List<CollectorMember> members = const [amaOwusu, yawBoateng],
  }) =>
      FakeCollectorBackend((request) {
        if (request.method == 'GET' &&
            request.url.path.endsWith('/collector/v1/members')) {
          return http.Response(membersBody(members), 200);
        }
        if (request.method == 'POST' &&
            request.url.path.endsWith('/collector/v1/payments')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            paymentBody(idempotencyKey: body['idempotencyKey'] as String),
            200,
          );
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/collector/v1/payments')) {
          return http.Response(daySummaryBody(), 200);
        }
        if (request.method == 'POST' &&
            request.url.path.endsWith('/collector/v1/locations')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'stored': (body['points'] as List).length,
              'duplicates': 0,
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/collector/v1/submissions')) {
          return request.method == 'POST'
              ? http.Response(jsonEncode(submissionJson()), 200)
              : http.Response(submissionsPage(), 200);
        }
        return http.Response(errorBody(404, 'Not found'), 404);
      });

  /// Payments sent (`POST /api/collector/v1/payments`).
  List<http.Request> get paymentRequests => [
        for (final r in requests)
          if (r.method == 'POST' &&
              r.url.path.endsWith('/collector/v1/payments'))
            r,
      ];

  /// Location batches sent (`POST /api/collector/v1/locations`).
  List<http.Request> get locationRequests => [
        for (final r in requests)
          if (r.method == 'POST' &&
              r.url.path.endsWith('/collector/v1/locations'))
            r,
      ];

  /// Submissions sent (`POST /api/collector/v1/submissions`).
  List<http.Request> get submitRequests => [
        for (final r in requests)
          if (r.method == 'POST' &&
              r.url.path.endsWith('/collector/v1/submissions'))
            r,
      ];
}

/// In-memory [OutboxStore] for tests, with the same rules as the SQLite
/// one: claims, notify-once refusals.
class MemoryOutboxStore implements OutboxStore {
  MemoryOutboxStore([List<OutboxPayment> payments = const []]) {
    for (final p in payments) {
      rows[p.idempotencyKey] = _Row(p);
    }
  }

  final rows = <String, _Row>{};

  List<OutboxPayment> get all => [for (final r in rows.values) r.payment];

  @override
  Future<void> add(OutboxPayment payment) async {
    rows.putIfAbsent(payment.idempotencyKey, () => _Row(payment));
  }

  @override
  Future<List<OutboxPayment>> list(String staffId) async {
    final mine = [
      for (final r in rows.values)
        if (r.payment.staffId == staffId) r.payment,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return mine;
  }

  @override
  Future<bool> claim(String key, DateTime now, DateTime until) async {
    final row = rows[key];
    if (row == null) return false;
    final held = row.claimedUntil;
    if (held != null && !held.isBefore(now)) return false;
    row.claimedUntil = until;
    return true;
  }

  @override
  Future<void> remove(String key) async {
    rows.remove(key);
  }

  @override
  Future<bool> correct(
    String key, {
    required PaymentType type,
    required String accountNumber,
    required Cedis amount,
    required DateTime updatedAt,
  }) async {
    final row = rows[key];
    if (row == null || row.payment.isRefused) return false;
    final held = row.claimedUntil;
    if (held != null && !held.isBefore(updatedAt)) return false;
    if (!row.payment.isCorrectable(updatedAt)) return false;
    final p = row.payment;
    row.payment = OutboxPayment(
      idempotencyKey: p.idempotencyKey,
      staffId: p.staffId,
      memberName: p.memberName,
      accountNumber: accountNumber,
      type: type,
      amount: amount,
      note: p.note,
      createdAt: p.createdAt,
      updatedAt: updatedAt,
    );
    return true;
  }

  @override
  Future<void> markTried(String key, DateTime at) async {
    final row = rows[key];
    if (row == null) return;
    row.payment = _copy(row.payment, lastTriedAt: at);
    row.claimedUntil = null;
  }

  @override
  Future<bool> markRefused(String key, String reason, DateTime at) async {
    final row = rows[key];
    if (row == null) return false;
    final firstTime = !row.notified;
    row.notified = true;
    row.claimedUntil = null;
    row.payment = _copy(
      row.payment,
      refusalReason: reason,
      refusedAt: row.payment.refusedAt ?? at,
      lastTriedAt: at,
    );
    return firstTime;
  }

  static OutboxPayment _copy(
    OutboxPayment p, {
    String? refusalReason,
    DateTime? refusedAt,
    DateTime? lastTriedAt,
  }) =>
      OutboxPayment(
        idempotencyKey: p.idempotencyKey,
        staffId: p.staffId,
        memberName: p.memberName,
        accountNumber: p.accountNumber,
        type: p.type,
        amount: p.amount,
        note: p.note,
        createdAt: p.createdAt,
        updatedAt: p.updatedAt,
        refusalReason: refusalReason ?? p.refusalReason,
        refusedAt: refusedAt ?? p.refusedAt,
        lastTriedAt: lastTriedAt ?? p.lastTriedAt,
      );
}

class _Row {
  _Row(this.payment);

  OutboxPayment payment;
  DateTime? claimedUntil;
  bool notified = false;
}

/// An outbox payment recorded by STF001 at [createdAt].
OutboxPayment queuedPayment({
  String key = 'key-1',
  String staffId = 'STF001',
  required DateTime createdAt,
  String memberName = 'Ama Owusu',
  String accountNumber = '1002345678',
  PaymentType type = PaymentType.savings,
  int pesewas = 5000,
  String? refusalReason,
}) =>
    OutboxPayment(
      idempotencyKey: key,
      staffId: staffId,
      memberName: memberName,
      accountNumber: accountNumber,
      type: type,
      amount: Cedis.pesewas(pesewas),
      createdAt: createdAt.toUtc(),
      refusalReason: refusalReason,
      refusedAt: refusalReason == null ? null : createdAt.toUtc(),
    );

class MemorySubmittedDayStore implements SubmittedDayStore {
  SubmittedDay? day;

  @override
  Future<SubmittedDay?> read() async => day;

  @override
  Future<void> save(SubmittedDay day) async {
    this.day = day;
  }

  @override
  Future<void> clear() async {
    day = null;
  }
}

/// Records the refused-payment notifications and permission requests.
class FakeNotifications implements AppNotifications {
  final shown = <List<OutboxPayment>>[];
  int permissionRequests = 0;

  @override
  Future<void> refused(List<OutboxPayment> payments) async {
    shown.add(List.of(payments));
  }

  @override
  Future<void> requestPermission() async {
    permissionRequests++;
  }
}

class FakeConnectivity implements ConnectivityWatcher {
  final controller = StreamController<bool>.broadcast();

  @override
  Stream<bool> get changes => controller.stream;
}

class FakeBackgroundScheduler implements BackgroundScheduler {
  int periodic = 0;
  final once = <String, Duration>{};

  @override
  Future<void> ensurePeriodic() async {
    periodic++;
  }

  @override
  Future<void> scheduleOnce(String key, Duration delay) async {
    once[key] = delay;
  }
}

/// Services for app-level tests. [staffId] is who the outbox belongs to;
/// app-level tests pass the session manager's.
AppServices testServices({
  FakeCollectorBackend? backend,
  MemoryMemberCache? cache,
  MemoryOutboxStore? outboxStore,
  FakeNotifications? notifications,
  FakeConnectivity? connectivity,
  FakeBackgroundScheduler? background,
  String? Function()? staffId,
  DateTime Function()? now,
  MemorySubmittedDayStore? dayStore,
  FakeLocationPlatform? locationPlatform,
  MemoryLocationStore? locationStore,
  MemoryDaySummaryStore? daySummaryStore,
}) {
  final collector = backend ?? FakeCollectorBackend.working();
  final points = locationStore ?? MemoryLocationStore();
  final store = outboxStore ?? MemoryOutboxStore();
  final who = staffId ?? () => collectorSession.staffId;
  final notify = notifications ?? FakeNotifications();
  final outbox = Outbox(store: store, staffId: who, now: now);
  final today = TodayController(
    api: collector.api,
    outbox: outbox,
    store: daySummaryStore ?? MemoryDaySummaryStore(),
    staffId: who,
    now: now,
  );
  return AppServices(
    collectorApi: collector.api,
    members: MemberDirectory(
      api: collector.api,
      cache: cache ?? MemoryMemberCache(),
      now: () => DateTime(2026, 11, 15, 8, 12),
    ),
    outbox: outbox,
    sync: SyncScheduler(
      sync: PaymentSync(
        store: store,
        api: collector.api,
        staffId: who,
        notifier: notify,
        locations: LocationSync(store: points, api: collector.api, now: now),
        now: now,
      ),
      outbox: outbox,
      connectivity: connectivity ?? FakeConnectivity(),
      background: background ?? FakeBackgroundScheduler(),
      notifications: notify,
    )..onSynced = today.synced,
    dayClosure: DayClosure(
      store: dayStore ?? MemorySubmittedDayStore(),
      staffId: who,
    ),
    location: LocationTracker(
      platform: locationPlatform ?? FakeLocationPlatform(),
      store: points,
      staffId: who,
      now: now,
    ),
    today: today,
  );
}

/// In-memory [LocationStore] for tests.
class MemoryLocationStore implements LocationStore {
  final rows = <({String staffId, LocationPoint point, DateTime? sentAt})>[];
  int _nextId = 1;

  /// Makes [add] fail, as a full disk would.
  bool failAdds = false;

  List<LocationPoint> get points => [for (final r in rows) r.point];

  @override
  Future<void> add(String staffId, LocationPoint point) async {
    if (failAdds) throw StateError('disk full');
    rows.add((
      staffId: staffId,
      point: LocationPoint(
        id: _nextId++,
        latitude: point.latitude,
        longitude: point.longitude,
        accuracyMeters: point.accuracyMeters,
        batteryPercent: point.batteryPercent,
        trigger: point.trigger,
        paymentKey: point.paymentKey,
        recordedAt: point.recordedAt,
      ),
      sentAt: null,
    ));
  }

  @override
  Future<List<LocationPoint>> unsent(String staffId, {int limit = 500}) async {
    final unsent = [
      for (final r in rows)
        if (r.staffId == staffId && r.sentAt == null) r.point,
    ]..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    return unsent.take(limit).toList();
  }

  @override
  Future<void> markSent(List<int> ids, DateTime at) async {
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (ids.contains(r.point.id)) {
        rows[i] = (staffId: r.staffId, point: r.point, sentAt: at);
      }
    }
  }

  @override
  Future<void> remove(List<int> ids) async {
    rows.removeWhere((r) => ids.contains(r.point.id));
  }

  @override
  Future<DateTime?> latestRecordedAt(String staffId) async {
    DateTime? latest;
    for (final r in rows) {
      if (r.staffId != staffId) continue;
      if (latest == null || r.point.recordedAt.isAfter(latest)) {
        latest = r.point.recordedAt;
      }
    }
    return latest;
  }

  @override
  Future<void> pruneSent(DateTime before) async {
    rows.removeWhere((r) => r.sentAt != null && r.sentAt!.isBefore(before));
  }
}

/// A scripted [LocationPlatform]: location allowed and on by default, with a
/// fix in Accra.
class FakeLocationPlatform implements LocationPlatform {
  FakeLocationPlatform({
    this.accessNow = LocationAccess.ready,
    this.afterRequest,
    this.fix = accraFix,
    this.battery = 80,
  });

  static const accraFix =
      LocationFix(latitude: 5.6037, longitude: -0.187, accuracyMeters: 12);

  LocationAccess accessNow;

  /// What Android's prompt leads to; null leaves [accessNow] as it is.
  LocationAccess? afterRequest;

  /// The next [currentFix]; null means no reading comes (indoors).
  LocationFix? fix;
  int? battery;

  int requests = 0;
  int appSettingsOpened = 0;
  int locationSettingsOpened = 0;
  final tracking = <StreamController<LocationFix>>[];
  final service = StreamController<bool>.broadcast();

  /// The live tracking stream, if one is listened to.
  StreamController<LocationFix>? get activeTracking {
    for (final c in tracking.reversed) {
      if (c.hasListener) return c;
    }
    return null;
  }

  @override
  Future<LocationAccess> access() async => accessNow;

  @override
  Future<LocationAccess> requestAccess() async {
    requests++;
    if (afterRequest != null) accessNow = afterRequest!;
    return accessNow;
  }

  @override
  Stream<LocationFix> trackEvery(Duration interval) {
    final controller = StreamController<LocationFix>();
    tracking.add(controller);
    return controller.stream;
  }

  @override
  Future<LocationFix> currentFix(Duration timeLimit) async {
    final fix = this.fix;
    if (fix == null) throw TimeoutException('no fix', timeLimit);
    return fix;
  }

  @override
  Stream<bool> serviceChanges() => service.stream;

  @override
  Future<int?> batteryPercent() async => battery;

  @override
  Future<void> openAppSettings() async {
    appSettingsOpened++;
  }

  @override
  Future<void> openLocationSettings() async {
    locationSettingsOpened++;
  }
}

/// In-memory [DaySummaryStore] for tests.
class MemoryDaySummaryStore implements DaySummaryStore {
  MemoryDaySummaryStore([this.saved]);

  SavedDaySummary? saved;

  @override
  Future<SavedDaySummary?> read() async => saved;

  @override
  Future<void> save(SavedDaySummary saved) async {
    this.saved = saved;
  }

  @override
  Future<void> clear() async {
    saved = null;
  }
}
