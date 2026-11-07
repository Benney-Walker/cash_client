import 'package:cash_client/api/api_exception.dart';
import 'package:cash_client/auth/sign_in.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  test('a collector is signed in and the session is saved', () async {
    final store = MemorySessionStore();
    final signIn = SignIn(fakeAuthApi(200, loginBody()), store);

    final session = await signIn(staffId: 'STF001', password: 'x');

    expect(session.isCollector, isTrue);
    expect(store.session?.accessToken, 'access-token');
  });

  test('a collector who also has another role is allowed', () async {
    final store = MemorySessionStore();
    final signIn = SignIn(
      fakeAuthApi(200, loginBody(roles: ['AGENT', 'COLLECTOR'])),
      store,
    );

    await signIn(staffId: 'STF001', password: 'x');

    expect(store.session, isNotNull);
  });

  test("a non-collector is refused and their tokens aren't saved", () async {
    final store = MemorySessionStore();
    final signIn = SignIn(fakeAuthApi(200, loginBody(roles: ['AGENT'])), store);

    await expectLater(
      signIn(staffId: 'STF002', password: 'x'),
      throwsA(isA<NotCollectorException>()),
    );
    expect(store.saves, 0);
    expect(store.session, isNull);
  });

  test('a failed login saves nothing', () async {
    final store = MemorySessionStore();
    final signIn = SignIn(
      fakeAuthApi(401, errorBody(401, 'Invalid ID or password')),
      store,
    );

    await expectLater(
      signIn(staffId: 'STF001', password: 'wrong'),
      throwsA(isA<ApiException>()),
    );
    expect(store.saves, 0);
  });

  test('every failure has a message for the collector', () {
    for (final failure in ApiFailure.values) {
      expect(signInErrorMessage(ApiException(failure)), isNotEmpty);
    }
    expect(signInErrorMessage(const NotCollectorException()),
        contains('collectors'));
    expect(signInErrorMessage(StateError('x')), isNotEmpty);
  });
}
