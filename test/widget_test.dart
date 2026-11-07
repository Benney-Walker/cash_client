import 'package:cash_client/auth/sign_in.dart';
import 'package:cash_client/main.dart';
import 'package:cash_client/theme/app_status_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  Future<MemorySessionStore> pumpApp(
    WidgetTester tester, {
    MemorySessionStore? store,
  }) async {
    final sessionStore = store ?? MemorySessionStore();
    await tester.pumpWidget(
      CashClientApp(
        sessionStore: sessionStore,
        signIn: SignIn(fakeAuthApi(200, loginBody()), sessionStore),
      ),
    );
    await tester.pumpAndSettle();
    return sessionStore;
  }

  testWidgets('opens at sign-in when no session is stored', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('login.submit')), findsOneWidget);
  });

  testWidgets('a stored collector session skips sign-in', (tester) async {
    await pumpApp(tester, store: MemorySessionStore(collectorSession));
    expect(find.text('Signed in as KOFI MENSAH'), findsOneWidget);
  });

  testWidgets('signing out clears the session and returns to sign-in',
      (tester) async {
    final store =
        await pumpApp(tester, store: MemorySessionStore(collectorSession));

    await tester.tap(find.byKey(const Key('home.signOut')));
    await tester.pumpAndSettle();

    expect(store.session, isNull);
    expect(find.byKey(const Key('login.submit')), findsOneWidget);
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
