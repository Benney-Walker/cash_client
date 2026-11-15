import 'dart:convert';

import 'package:cash_client/app_services.dart';
import 'package:cash_client/auth/auth_api.dart';
import 'package:cash_client/auth/auth_session.dart';
import 'package:cash_client/auth/session_store.dart';
import 'package:cash_client/collector/collector_api.dart';
import 'package:cash_client/collector/collector_models.dart';
import 'package:cash_client/collector/member_cache.dart';
import 'package:cash_client/collector/member_directory.dart';
import 'package:cash_client/settings/app_info.dart';
import 'package:cash_client/settings/theme_mode_store.dart';
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

  late final AuthApi api = AuthApi(
    baseUrl: testBaseUrl,
    client: MockClient((request) async {
      if (request.url.path.endsWith('/refresh-collector-token')) {
        calls++;
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        if (offline) throw http.ClientException('no connection');
        final (status, body) = refresh;
        return http.Response(body, status);
      }
      return http.Response(loginBody(), 200);
    }),
  );

  /// The backend sends the new access token as the bare response body.
  static (int, String) issues(String token) => (200, token);

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
  String status = 'PENDING',
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
      'recordedAt': null,
      'correctableUntil': '2026-11-15T10:10:00',
      'postedAt': null,
    });

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
        return http.Response(errorBody(404, 'Not found'), 404);
      });

  List<http.Request> get paymentRequests => [
        for (final r in requests)
          if (r.method == 'POST') r,
      ];
}

/// Services for app-level tests.
AppServices testServices({
  FakeCollectorBackend? backend,
  MemoryMemberCache? cache,
}) {
  final collector = backend ?? FakeCollectorBackend.working();
  return AppServices(
    collectorApi: collector.api,
    members: MemberDirectory(
      api: collector.api,
      cache: cache ?? MemoryMemberCache(),
      now: () => DateTime(2026, 11, 15, 8, 12),
    ),
  );
}
