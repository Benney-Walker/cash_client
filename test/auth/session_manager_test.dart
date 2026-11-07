import 'package:cash_client/api/api_exception.dart';
import 'package:cash_client/auth/auth_session.dart';
import 'package:cash_client/auth/session_manager.dart';
import 'package:cash_client/auth/sign_in.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  group('restore', () {
    test('picks up a stored collector session', () async {
      final sessions = SessionManager(
        api: fakeAuthApi(200, loginBody()),
        store: MemorySessionStore(collectorSession),
      );
      expect(sessions.isRestoring, isTrue);

      await sessions.restore();

      expect(sessions.isRestoring, isFalse);
      expect(sessions.session?.staffId, 'STF001');
    });

    test('discards a stored session without the collector role', () async {
      final store = MemorySessionStore(const AuthSession(
        staffId: 'ADM1',
        staffName: 'ADMIN',
        roles: ['ADMINISTRATOR'],
        accessToken: 'a',
        refreshToken: 'r',
      ));
      final sessions =
          SessionManager(api: fakeAuthApi(200, loginBody()), store: store);

      await sessions.restore();

      expect(sessions.session, isNull);
      expect(store.session, isNull);
    });
  });

  group('signIn', () {
    test('a collector is signed in and the session is saved', () async {
      final store = MemorySessionStore();
      final sessions =
          SessionManager(api: fakeAuthApi(200, loginBody()), store: store);

      await sessions.signIn(staffId: 'STF001', password: 'x');

      expect(sessions.session?.isCollector, isTrue);
      expect(store.session?.accessToken, 'access-token');
    });

    test('a collector who also has another role is allowed', () async {
      final sessions = SessionManager(
        api: fakeAuthApi(200, loginBody(roles: ['AGENT', 'COLLECTOR'])),
        store: MemorySessionStore(),
      );

      await sessions.signIn(staffId: 'STF001', password: 'x');

      expect(sessions.session, isNotNull);
    });

    test("a non-collector is refused and their tokens aren't saved",
        () async {
      final store = MemorySessionStore();
      final sessions = SessionManager(
        api: fakeAuthApi(200, loginBody(roles: ['AGENT'])),
        store: store,
      );

      await expectLater(
        sessions.signIn(staffId: 'STF002', password: 'x'),
        throwsA(isA<NotCollectorException>()),
      );
      expect(store.saves, 0);
      expect(sessions.session, isNull);
    });

    test('a failed login saves nothing', () async {
      final store = MemorySessionStore();
      final sessions = SessionManager(
        api: fakeAuthApi(401, errorBody(401, 'Invalid ID or password')),
        store: store,
      );

      await expectLater(
        sessions.signIn(staffId: 'STF001', password: 'wrong'),
        throwsA(isA<ApiException>()),
      );
      expect(store.saves, 0);
    });
  });

  test('signing out clears the session without the "ended" flag', () async {
    final store = MemorySessionStore(collectorSession);
    final sessions =
        SessionManager(api: fakeAuthApi(200, loginBody()), store: store);
    await sessions.restore();

    await sessions.signOut();

    expect(sessions.session, isNull);
    expect(store.session, isNull);
    expect(sessions.sessionEndedByServer, isFalse);
  });

  group('refreshAccessToken', () {
    Future<(SessionManager, MemorySessionStore)> signedIn(
      FakeRefreshApi backend,
    ) async {
      final store = MemorySessionStore(collectorSession);
      final sessions = SessionManager(api: backend.api, store: store);
      await sessions.restore();
      return (sessions, store);
    }

    test('saves and returns the new access token', () async {
      final backend = FakeRefreshApi(FakeRefreshApi.issues('new-access'));
      final (sessions, store) = await signedIn(backend);

      final token = await sessions.refreshAccessToken();

      expect(token, 'new-access');
      expect(sessions.session?.accessToken, 'new-access');
      expect(store.session?.accessToken, 'new-access');
      // The refresh token is kept: the backend doesn't issue a new one.
      expect(store.session?.refreshToken, 'refresh-token');
    });

    test('overlapping callers share one refresh call', () async {
      final backend = FakeRefreshApi(
        FakeRefreshApi.issues('new-access'),
        delay: const Duration(milliseconds: 20),
      );
      final (sessions, _) = await signedIn(backend);

      final tokens = await Future.wait([
        sessions.refreshAccessToken(),
        sessions.refreshAccessToken(),
        sessions.refreshAccessToken(),
      ]);

      expect(tokens, everyElement('new-access'));
      expect(backend.calls, 1);
    });

    test('a refused refresh ends the session', () async {
      final backend = FakeRefreshApi(FakeRefreshApi.refuses());
      final (sessions, store) = await signedIn(backend);

      await expectLater(
        sessions.refreshAccessToken(),
        throwsA(isA<ApiException>()
            .having((e) => e.failure, 'failure', ApiFailure.unauthorized)),
      );
      expect(sessions.session, isNull);
      expect(store.session, isNull);
      expect(sessions.sessionEndedByServer, isTrue);
    });

    test('being offline keeps the session', () async {
      final backend = FakeRefreshApi(FakeRefreshApi.issues('unused'))
        ..offline = true;
      final (sessions, store) = await signedIn(backend);

      await expectLater(
        sessions.refreshAccessToken(),
        throwsA(isA<ApiException>()
            .having((e) => e.failure, 'failure', ApiFailure.network)),
      );
      expect(sessions.session, isNotNull);
      expect(store.session, isNotNull);
    });
  });

  test('every failure has a sign-in message', () {
    for (final failure in ApiFailure.values) {
      expect(signInErrorMessage(ApiException(failure)), isNotEmpty);
    }
    expect(signInErrorMessage(const NotCollectorException()),
        contains('collectors'));
    expect(signInErrorMessage(StateError('x')), isNotEmpty);
  });
}
