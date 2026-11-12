import 'dart:convert';

import 'package:cash_client/auth/auth_api.dart';
import 'package:cash_client/auth/auth_session.dart';
import 'package:cash_client/auth/session_store.dart';
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
      'path': '/api/auth/v1/login',
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
      if (request.url.path.endsWith('/refresh-token')) {
        calls++;
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        if (offline) throw http.ClientException('no connection');
        final (status, body) = refresh;
        return http.Response(body, status);
      }
      return http.Response(loginBody(), 200);
    }),
  );

  static (int, String) issues(String token) =>
      (200, jsonEncode({'authToken': token}));

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
