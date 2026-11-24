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

      await api.login(staffId: 'STF001', password: 'secret pass', deviceId: 'phone-1');

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), '$testBaseUrl/api/auth/v1/collector-login');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(request.body), {
        'staffId': 'STF001',
        'password': 'secret pass',
        'deviceId': 'phone-1',
      });
    });

    test('returns the session from a successful response', () async {
      final api = fakeAuthApi(200, loginBody());

      final session = await api.login(staffId: 'STF001', password: 'x', deviceId: 'phone-1');

      expect(session.staffId, 'STF001');
      expect(session.staffName, 'KOFI MENSAH');
      expect(session.roles, ['COLLECTOR']);
      expect(session.accessToken, 'access-token');
      expect(session.refreshToken, 'refresh-token');
      expect(session.isCollector, isTrue);
      // Kept with the session, for every refresh.
      expect(session.deviceId, 'phone-1');
    });

    test("another phone's 403 carries the backend's message", () async {
      final api = fakeAuthApi(
        403,
        errorBody(403,
            "This account is registered to another phone. Ask your branch's agent or an administrator to release it"),
      );
      await expectLater(
        api.login(staffId: 'STF001', password: 'x', deviceId: 'phone-2'),
        throwsA(isA<ApiException>()
            .having((e) => e.failure, 'failure', ApiFailure.forbidden)
            .having((e) => e.message, 'message', contains('another phone'))),
      );
    });

    test('works with a trailing slash or a path prefix on the base URL',
        () async {
      for (final (base, expected) in [
        ('https://api.example.test/', 'https://api.example.test/api/auth/v1/collector-login'),
        ('https://example.test/bank', 'https://example.test/bank/api/auth/v1/collector-login'),
      ]) {
        Uri? called;
        final api = AuthApi(
          baseUrl: base,
          client: MockClient((request) async {
            called = request.url;
            return http.Response(loginBody(), 200);
          }),
        );
        await api.login(staffId: 'a', password: 'b', deviceId: 'phone-1');
        expect(called.toString(), expected);
      }
    });

    test("401 means unauthorized (wrong ID or password)", () {
      final api = fakeAuthApi(401, errorBody(401, 'Invalid ID or password'));
      expect(api.login(staffId: 'a', password: 'b', deviceId: 'phone-1'),
          failsWith(ApiFailure.unauthorized));
    });

    test('403 (a valid account that is not a collector) is forbidden', () {
      final api = fakeAuthApi(
        403,
        errorBody(403, 'Only collector accounts can sign in here'),
      );
      expect(api.login(staffId: 'AGT001', password: 'b', deviceId: 'phone-1'),
          failsWith(ApiFailure.forbidden));
    });

    test('400 carries the field errors from the backend', () async {
      final api = fakeAuthApi(
        400,
        errorBody(400, 'Validation failed',
            errors: {'staffId': 'Staff Id cannot be null'}),
      );
      try {
        await api.login(staffId: '', password: 'b', deviceId: 'phone-1');
        fail('expected an ApiException');
      } on ApiException catch (e) {
        expect(e.failure, ApiFailure.validation);
        expect(e.message, 'Staff Id cannot be null');
      }
    });

    test('5xx is a server failure', () {
      final api = fakeAuthApi(500, errorBody(500, 'Unexpected error'));
      expect(api.login(staffId: 'a', password: 'b', deviceId: 'phone-1'),
          failsWith(ApiFailure.server));
    });

    test('a 200 without tokens is an unexpected response', () {
      final api = fakeAuthApi(200, jsonEncode({'staffName': 'X', 'roles': []}));
      expect(api.login(staffId: 'a', password: 'b', deviceId: 'phone-1'),
          failsWith(ApiFailure.unexpectedResponse));
    });

    test('a 200 that is not JSON is an unexpected response', () {
      final api = fakeAuthApi(200, '<html>proxy page</html>');
      expect(api.login(staffId: 'a', password: 'b', deviceId: 'phone-1'),
          failsWith(ApiFailure.unexpectedResponse));
    });

    test('a connection error is a network failure', () {
      final api = AuthApi(
        baseUrl: testBaseUrl,
        client: MockClient((_) async => throw http.ClientException('no route')),
      );
      expect(api.login(staffId: 'a', password: 'b', deviceId: 'phone-1'),
          failsWith(ApiFailure.network));
    });

    test('a timeout is a network failure', () {
      final api = AuthApi(
        baseUrl: testBaseUrl,
        timeout: const Duration(milliseconds: 10),
        client: MockClient((_) => Completer<http.Response>().future),
      );
      expect(api.login(staffId: 'a', password: 'b', deviceId: 'phone-1'),
          failsWith(ApiFailure.network));
    });

    test('a missing or invalid base URL is reported, not sent', () {
      for (final base in ['', '   ', 'not a url']) {
        final api = AuthApi(
          baseUrl: base,
          client: MockClient((_) async => fail('should not send')),
        );
        expect(api.login(staffId: 'a', password: 'b', deviceId: 'phone-1'),
            failsWith(ApiFailure.notConfigured));
      }
    });
  });

  group('AuthApi.refreshTokens', () {
    // A token in the backend's shape: three base64url parts.
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJTVEYwMDEifQ.c2lnbmF0dXJl';
    final rotated =
        jsonEncode({'authToken': jwt, 'refreshToken': 'next-refresh'});

    test('posts the refresh token and returns both new tokens', () async {
      final requests = <http.Request>[];
      final api = fakeAuthApi(200, rotated, requests: requests);

      final tokens = await api.refreshTokens('refresh-token');

      expect(tokens.accessToken, jwt);
      expect(tokens.refreshToken, 'next-refresh');
      expect(requests.single.url.toString(),
          '$testBaseUrl/api/auth/v1/refresh-collector-token');
      expect(jsonDecode(requests.single.body),
          {'refreshToken': 'refresh-token'});
    });

    test("sends the phone's device ID when the session has one", () async {
      final requests = <http.Request>[];
      final api = fakeAuthApi(200, rotated, requests: requests);

      await api.refreshTokens('refresh-token', deviceId: 'phone-1');

      expect(jsonDecode(requests.single.body),
          {'refreshToken': 'refresh-token', 'deviceId': 'phone-1'});
    });

    test('401 (used, revoked or expired refresh token) is unauthorized', () {
      final api = fakeAuthApi(401, errorBody(401, 'Invalid or expired refresh token'));
      expect(api.refreshTokens('old'), failsWith(ApiFailure.unauthorized));
    });

    test('a response without both tokens is unexpected', () {
      for (final body in [
        '',
        '<html>proxy page</html>',
        // The old bare-token reply.
        jwt,
        jsonEncode(jwt),
        jsonEncode({'authToken': jwt}),
        jsonEncode({'authToken': 'not a token', 'refreshToken': 'r'}),
        jsonEncode({'authToken': jwt, 'refreshToken': ''}),
        jsonEncode(42),
      ]) {
        final api = fakeAuthApi(200, body);
        expect(api.refreshTokens('x'),
            failsWith(ApiFailure.unexpectedResponse),
            reason: body);
      }
    });
  });

  group('AuthApi.logout', () {
    test('posts the refresh token and accepts 204', () async {
      final requests = <http.Request>[];
      final api = fakeAuthApi(204, '', requests: requests);

      await api.logout('refresh-token');

      expect(requests.single.url.toString(), '$testBaseUrl/api/auth/v1/logout');
      expect(jsonDecode(requests.single.body),
          {'refreshToken': 'refresh-token'});
    });

    test('no connection is a network failure', () {
      final api = AuthApi(
        baseUrl: testBaseUrl,
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(api.logout('r'), failsWith(ApiFailure.network));
    });
  });
}
