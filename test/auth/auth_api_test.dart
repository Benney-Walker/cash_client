import 'dart:async';
import 'dart:convert';

import 'package:cash_client/api/api_exception.dart';
import 'package:cash_client/auth/auth_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fakes.dart';

Matcher failsWith(ApiFailure failure) => throwsA(
      isA<ApiException>().having((e) => e.failure, 'failure', failure),
    );

void main() {
  group('AuthApi.login', () {
    test('posts the staff ID and password as JSON to the login endpoint',
        () async {
      final requests = <http.Request>[];
      final api = fakeAuthApi(200, loginBody(), requests: requests);

      await api.login(staffId: 'STF001', password: 'secret pass');

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), '$testBaseUrl/api/auth/v1/login');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(request.body), {
        'staffId': 'STF001',
        'password': 'secret pass',
      });
    });

    test('returns the session from a successful response', () async {
      final api = fakeAuthApi(200, loginBody());

      final session = await api.login(staffId: 'STF001', password: 'x');

      expect(session.staffId, 'STF001');
      expect(session.staffName, 'KOFI MENSAH');
      expect(session.roles, ['COLLECTOR']);
      expect(session.accessToken, 'access-token');
      expect(session.refreshToken, 'refresh-token');
      expect(session.isCollector, isTrue);
    });

    test('works with a trailing slash or a path prefix on the base URL',
        () async {
      for (final (base, expected) in [
        ('https://api.example.test/', 'https://api.example.test/api/auth/v1/login'),
        ('https://example.test/bank', 'https://example.test/bank/api/auth/v1/login'),
      ]) {
        Uri? called;
        final api = AuthApi(
          baseUrl: base,
          client: MockClient((request) async {
            called = request.url;
            return http.Response(loginBody(), 200);
          }),
        );
        await api.login(staffId: 'a', password: 'b');
        expect(called.toString(), expected);
      }
    });

    test('401 means invalid credentials', () {
      final api = fakeAuthApi(401, errorBody(401, 'Invalid ID or password'));
      expect(api.login(staffId: 'a', password: 'b'),
          failsWith(ApiFailure.invalidCredentials));
    });

    test('400 carries the field errors from the backend', () async {
      final api = fakeAuthApi(
        400,
        errorBody(400, 'Validation failed',
            errors: {'staffId': 'Staff Id cannot be null'}),
      );
      try {
        await api.login(staffId: '', password: 'b');
        fail('expected an ApiException');
      } on ApiException catch (e) {
        expect(e.failure, ApiFailure.validation);
        expect(e.message, 'Staff Id cannot be null');
      }
    });

    test('5xx is a server failure', () {
      final api = fakeAuthApi(500, errorBody(500, 'Unexpected error'));
      expect(api.login(staffId: 'a', password: 'b'),
          failsWith(ApiFailure.server));
    });

    test('a 200 without tokens is an unexpected response', () {
      final api = fakeAuthApi(200, jsonEncode({'staffName': 'X', 'roles': []}));
      expect(api.login(staffId: 'a', password: 'b'),
          failsWith(ApiFailure.unexpectedResponse));
    });

    test('a 200 that is not JSON is an unexpected response', () {
      final api = fakeAuthApi(200, '<html>proxy page</html>');
      expect(api.login(staffId: 'a', password: 'b'),
          failsWith(ApiFailure.unexpectedResponse));
    });

    test('a connection error is a network failure', () {
      final api = AuthApi(
        baseUrl: testBaseUrl,
        client: MockClient((_) async => throw http.ClientException('no route')),
      );
      expect(api.login(staffId: 'a', password: 'b'),
          failsWith(ApiFailure.network));
    });

    test('a timeout is a network failure', () {
      final api = AuthApi(
        baseUrl: testBaseUrl,
        timeout: const Duration(milliseconds: 10),
        client: MockClient((_) => Completer<http.Response>().future),
      );
      expect(api.login(staffId: 'a', password: 'b'),
          failsWith(ApiFailure.network));
    });

    test('a missing or invalid base URL is reported, not sent', () {
      for (final base in ['', '   ', 'not a url']) {
        final api = AuthApi(
          baseUrl: base,
          client: MockClient((_) async => fail('should not send')),
        );
        expect(api.login(staffId: 'a', password: 'b'),
            failsWith(ApiFailure.notConfigured));
      }
    });
  });
}
