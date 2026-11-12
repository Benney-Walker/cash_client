import 'package:cash_client/auth/auth_api.dart';
import 'package:cash_client/auth/login_screen.dart';
import 'package:cash_client/auth/session_manager.dart';
import 'package:cash_client/common/gradient_button.dart';
import 'package:cash_client/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fakes.dart';

void main() {
  late MemorySessionStore store;
  late SessionManager sessions;

  Future<void> pumpLogin(WidgetTester tester, AuthApi api) async {
    store = MemorySessionStore();
    sessions = SessionManager(api: api, store: store);
    await sessions.restore();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LoginScreen(sessions: sessions, appInfo: testAppInfo),
      ),
    );
  }

  // The test surface is short, so scroll the button into view first.
  Future<void> tapSubmit(WidgetTester tester) async {
    final submit = find.byKey(const Key('login.submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
  }

  Future<void> enterAndSubmit(
    WidgetTester tester, {
    String staffId = 'STF001',
    String password = 'secret',
  }) async {
    await tester.enterText(find.byKey(const Key('login.staffId')), staffId);
    await tester.enterText(find.byKey(const Key('login.password')), password);
    await tapSubmit(tester);
  }

  testWidgets('empty fields are flagged and nothing is sent', (tester) async {
    final requests = <http.Request>[];
    await pumpLogin(tester, fakeAuthApi(200, loginBody(), requests: requests));

    await tapSubmit(tester);

    expect(find.text('Enter your staff ID'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(requests, isEmpty);
    expect(sessions.session, isNull);
  });

  testWidgets('a collector is signed in', (tester) async {
    await pumpLogin(tester, fakeAuthApi(200, loginBody()));

    await enterAndSubmit(tester);

    expect(sessions.session?.staffName, 'KOFI MENSAH');
    expect(store.session, isNotNull);
  });

  testWidgets('wrong credentials show a message and clear the password',
      (tester) async {
    await pumpLogin(
      tester,
      fakeAuthApi(401, errorBody(401, 'Invalid ID or password')),
    );

    await enterAndSubmit(tester, password: 'wrong');

    expect(find.text('Wrong staff ID or password.'), findsOneWidget);
    final password = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('login.password')),
        matching: find.byType(EditableText),
      ),
    );
    expect(password.controller.text, isEmpty);
    expect(sessions.session, isNull);
  });

  testWidgets('a non-collector is turned away', (tester) async {
    await pumpLogin(
      tester,
      fakeAuthApi(200, loginBody(roles: ['ADMINISTRATOR'])),
    );

    await enterAndSubmit(tester);

    expect(find.byKey(const Key('login.error')), findsOneWidget);
    expect(find.textContaining('desktop app'), findsOneWidget);
    expect(store.session, isNull);
    expect(sessions.session, isNull);
  });

  testWidgets('the staff ID is trimmed before it is sent', (tester) async {
    await pumpLogin(tester, fakeAuthApi(200, loginBody()));

    await enterAndSubmit(tester, staffId: '  STF001 ');

    expect(sessions.session?.staffId, 'STF001');
  });

  testWidgets('no session-ended notice on a normal start', (tester) async {
    await pumpLogin(tester, fakeAuthApi(200, loginBody()));

    expect(find.byKey(const Key('login.notice')), findsNothing);
  });

  testWidgets('shows the app version and the glass labels', (tester) async {
    await pumpLogin(tester, fakeAuthApi(200, loginBody()));

    expect(find.text('Version 1.0.0 (build 1) · Powered by Bynex Labs'),
        findsOneWidget);
    expect(find.text('Collectors only'), findsOneWidget);
    expect(find.text('Protected'), findsOneWidget);
  });

  testWidgets('the sign-in button is the gradient primary button',
      (tester) async {
    await pumpLogin(tester, fakeAuthApi(200, loginBody()));

    expect(
      find.descendant(
        of: find.byKey(const Key('login.submit')),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
    );
    expect(tester.widget(find.byKey(const Key('login.submit'))),
        isA<GradientButton>());
  });

  testWidgets('fits a 360dp phone without overflow, in both themes',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    for (final theme in [AppTheme.light, AppTheme.dark]) {
      store = MemorySessionStore();
      sessions = SessionManager(api: fakeAuthApi(200, loginBody()), store: store);
      await sessions.restore();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: LoginScreen(sessions: sessions, appInfo: testAppInfo),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
