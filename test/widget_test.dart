import 'package:cash_client/auth/session_manager.dart';
import 'package:cash_client/main.dart';
import 'package:cash_client/theme/app_status_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  Future<SessionManager> pumpApp(
    WidgetTester tester, {
    MemorySessionStore? store,
    FakeRefreshApi? backend,
  }) async {
    final sessions = SessionManager(
      api: (backend ?? FakeRefreshApi(FakeRefreshApi.issues('new'))).api,
      store: store ?? MemorySessionStore(),
    );
    await tester.pumpWidget(CashClientApp(sessions: sessions));
    await sessions.restore();
    await tester.pumpAndSettle();
    return sessions;
  }

  testWidgets('opens at sign-in when no session is stored', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('login.submit')), findsOneWidget);
  });

  testWidgets('a stored collector session skips sign-in', (tester) async {
    await pumpApp(tester, store: MemorySessionStore(collectorSession));
    expect(find.text('Signed in as KOFI MENSAH'), findsOneWidget);
  });

  testWidgets('signing out returns to sign-in without a notice',
      (tester) async {
    final store = MemorySessionStore(collectorSession);
    await pumpApp(tester, store: store);

    await tester.tap(find.byKey(const Key('home.signOut')));
    await tester.pumpAndSettle();

    expect(store.session, isNull);
    expect(find.byKey(const Key('login.submit')), findsOneWidget);
    expect(find.byKey(const Key('login.notice')), findsNothing);
  });

  testWidgets('when the backend ends the session, the app returns to sign-in '
      'and says why', (tester) async {
    final backend = FakeRefreshApi(FakeRefreshApi.refuses());
    final sessions = await pumpApp(
      tester,
      store: MemorySessionStore(collectorSession),
      backend: backend,
    );
    expect(find.text('Signed in as KOFI MENSAH'), findsOneWidget);

    // What the authenticated client does when a request's refresh is refused.
    await expectLater(sessions.refreshAccessToken(), throwsException);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login.submit')), findsOneWidget);
    expect(find.byKey(const Key('login.notice')), findsOneWidget);
  });

  testWidgets('follows the device into dark mode', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await pumpApp(tester);

    final context = tester.element(find.byKey(const Key('login.submit')));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(AppStatusColors.of(context).success, AppStatusColors.dark.success);
  });

  testWidgets('uses the light theme on a light device', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await pumpApp(tester);

    final context = tester.element(find.byKey(const Key('login.submit')));
    expect(Theme.of(context).brightness, Brightness.light);
    expect(
        AppStatusColors.of(context).success, AppStatusColors.light.success);
  });
}
