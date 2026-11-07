import 'package:cash_client/auth/auth_session.dart';
import 'package:cash_client/auth/login_screen.dart';
import 'package:cash_client/auth/sign_in.dart';
import 'package:cash_client/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fakes.dart';

void main() {
  late MemorySessionStore store;
  AuthSession? signedIn;

  Future<void> pumpLogin(WidgetTester tester, SignIn signIn) async {
    signedIn = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LoginScreen(
          signIn: signIn,
          onSignedIn: (session) => signedIn = session,
        ),
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

  setUp(() => store = MemorySessionStore());

  testWidgets('empty fields are flagged and nothing is sent', (tester) async {
    final requests = <http.Request>[];
    await pumpLogin(
      tester,
      SignIn(fakeAuthApi(200, loginBody(), requests: requests), store),
    );

    await tapSubmit(tester);

    expect(find.text('Enter your staff ID'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(requests, isEmpty);
    expect(signedIn, isNull);
  });

  testWidgets('a collector is signed in', (tester) async {
    await pumpLogin(tester, SignIn(fakeAuthApi(200, loginBody()), store));

    await enterAndSubmit(tester);

    expect(signedIn?.staffName, 'KOFI MENSAH');
    expect(store.session, isNotNull);
  });

  testWidgets('wrong credentials show a message and clear the password',
      (tester) async {
    await pumpLogin(
      tester,
      SignIn(
        fakeAuthApi(401, errorBody(401, 'Invalid ID or password')),
        store,
      ),
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
    expect(signedIn, isNull);
  });

  testWidgets('a non-collector is turned away', (tester) async {
    await pumpLogin(
      tester,
      SignIn(fakeAuthApi(200, loginBody(roles: ['ADMINISTRATOR'])), store),
    );

    await enterAndSubmit(tester);

    expect(find.byKey(const Key('login.error')), findsOneWidget);
    expect(find.textContaining('desktop app'), findsOneWidget);
    expect(store.session, isNull);
    expect(signedIn, isNull);
  });

  testWidgets('the staff ID is trimmed before it is sent', (tester) async {
    await pumpLogin(tester, SignIn(fakeAuthApi(200, loginBody()), store));

    await enterAndSubmit(tester, staffId: '  STF001 ');

    expect(signedIn?.staffId, 'STF001');
  });
}
