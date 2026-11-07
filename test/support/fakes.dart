import 'dart:convert';

import 'package:cash_client/auth/auth_api.dart';
import 'package:cash_client/auth/auth_session.dart';
import 'package:cash_client/auth/session_store.dart';
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
