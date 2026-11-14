import 'dart:convert';

import 'package:cash_client/api/api_exception.dart';
import 'package:cash_client/api/authenticated_client.dart';
import 'package:cash_client/auth/session_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fakes.dart';

/// A protected backend endpoint that accepts only [validTokens].
class FakeProtectedApi {
  FakeProtectedApi(this.validTokens, {this.status = 200});

  Set<String> validTokens;
  int status;
  final requests = <http.Request>[];

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    final token = request.headers['Authorization']?.replaceFirst('Bearer ', '');
    if (!validTokens.contains(token)) {
      return http.Response(errorBody(401, 'Unauthorized'), 401);
    }
    return http.Response(jsonEncode({'ok': true}), status);
  });
}

void main() {
  late FakeRefreshApi refreshBackend;
  late MemorySessionStore store;
  late SessionManager sessions;

  Future<void> signIn() async {
    store = MemorySessionStore(collectorSession);
    sessions = SessionManager(api: refreshBackend.api, store: store);
    await sessions.restore();
  }

  Future<http.Response> postDeposit(http.Client client) => client.post(
        Uri.parse('$testBaseUrl/api/example'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'amount': '50.00'}),
      );

  setUp(() async {
    refreshBackend = FakeRefreshApi(FakeRefreshApi.issues('new.access.token'));
    await signIn();
  });

  test('sends the access token as a bearer token', () async {
    final backend = FakeProtectedApi({'access-token'});
    final client = AuthenticatedClient(backend.client, sessions);

    final response = await postDeposit(client);

    expect(response.statusCode, 200);
    expect(backend.requests.single.headers['Authorization'],
        'Bearer access-token');
    expect(refreshBackend.calls, 0);
  });

  test('on 401, refreshes once and replays the request with its body',
      () async {
    final backend = FakeProtectedApi({'new.access.token'});
    final client = AuthenticatedClient(backend.client, sessions);

    final response = await postDeposit(client);

    expect(response.statusCode, 200);
    expect(refreshBackend.calls, 1);
    expect(backend.requests, hasLength(2));
    final retry = backend.requests.last;
    expect(retry.headers['Authorization'], 'Bearer new.access.token');
    expect(retry.method, 'POST');
    expect(jsonDecode(retry.body), {'amount': '50.00'});
    expect(store.session?.accessToken, 'new.access.token');
  });

  test('requests that hit 401 together share one refresh', () async {
    refreshBackend = FakeRefreshApi(
      FakeRefreshApi.issues('new.access.token'),
      delay: const Duration(milliseconds: 20),
    );
    await signIn();
    final backend = FakeProtectedApi({'new.access.token'});
    final client = AuthenticatedClient(backend.client, sessions);

    final responses = await Future.wait([
      postDeposit(client),
      postDeposit(client),
      postDeposit(client),
    ]);

    expect(responses.map((r) => r.statusCode), everyElement(200));
    expect(refreshBackend.calls, 1);
  });

  test('a refused refresh ends the session and reports unauthorized',
      () async {
    refreshBackend.refresh = FakeRefreshApi.refuses();
    final backend = FakeProtectedApi({'new.access.token'});
    final client = AuthenticatedClient(backend.client, sessions);

    await expectLater(
      postDeposit(client),
      throwsA(isA<ApiException>()
          .having((e) => e.failure, 'failure', ApiFailure.unauthorized)),
    );
    expect(sessions.session, isNull);
    expect(sessions.sessionEndedByServer, isTrue);
    expect(store.session, isNull);
  });

  test('no connection during the refresh keeps the session', () async {
    refreshBackend.offline = true;
    final backend = FakeProtectedApi({'new.access.token'});
    final client = AuthenticatedClient(backend.client, sessions);

    await expectLater(
      postDeposit(client),
      throwsA(isA<ApiException>()
          .having((e) => e.failure, 'failure', ApiFailure.network)),
    );
    expect(sessions.session, isNotNull);
  });

  test('a fresh token that is still refused ends the session', () async {
    // The refresh works, but the backend rejects every token, as it does
    // for a collector deactivated between the two calls.
    final backend = FakeProtectedApi({});
    final client = AuthenticatedClient(backend.client, sessions);

    final response = await postDeposit(client);

    expect(response.statusCode, 401);
    expect(refreshBackend.calls, 1);
    expect(sessions.session, isNull);
    expect(sessions.sessionEndedByServer, isTrue);
  });

  test('403 is passed through without a refresh', () async {
    final backend = FakeProtectedApi({'access-token'}, status: 403);
    final client = AuthenticatedClient(backend.client, sessions);

    final response = await postDeposit(client);

    expect(response.statusCode, 403);
    expect(refreshBackend.calls, 0);
    expect(sessions.session, isNotNull);
  });

  test('with no session, nothing is sent', () async {
    await sessions.signOut();
    final backend = FakeProtectedApi({'access-token'});
    final client = AuthenticatedClient(backend.client, sessions);

    await expectLater(
      postDeposit(client),
      throwsA(isA<ApiException>()
          .having((e) => e.failure, 'failure', ApiFailure.unauthorized)),
    );
    expect(backend.requests, isEmpty);
  });
}
