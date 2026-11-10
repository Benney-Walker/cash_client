import 'package:cash_client/auth/session_manager.dart';
import 'package:cash_client/main.dart';
import 'package:cash_client/settings/theme_controller.dart';
import 'package:cash_client/theme/app_status_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late SessionManager sessions;
  late ThemeController theme;

  Future<void> pumpApp(
    WidgetTester tester, {
    MemorySessionStore? store,
    FakeRefreshApi? backend,
    ThemeMode? savedTheme,
  }) async {
    sessions = SessionManager(
      api: (backend ?? FakeRefreshApi(FakeRefreshApi.issues('new'))).api,
      store: store ?? MemorySessionStore(),
    );
    theme = ThemeController(MemoryThemeModeStore(savedTheme));
    await theme.load();
    await tester.pumpWidget(CashClientApp(sessions: sessions, theme: theme));
    await sessions.restore();
    await tester.pumpAndSettle();
  }

  Brightness brightnessAt(WidgetTester tester, Finder finder) =>
      Theme.of(tester.element(finder)).brightness;

  void setDeviceBrightness(WidgetTester tester, Brightness brightness) {
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  group('sign-in', () {
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

    testWidgets('when the backend ends the session, the app returns to '
        'sign-in and says why', (tester) async {
      await pumpApp(
        tester,
        store: MemorySessionStore(collectorSession),
        backend: FakeRefreshApi(FakeRefreshApi.refuses()),
      );
      expect(find.text('Signed in as KOFI MENSAH'), findsOneWidget);

      // What the authenticated client does when a refresh is refused.
      await expectLater(sessions.refreshAccessToken(), throwsException);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login.submit')), findsOneWidget);
      expect(find.byKey(const Key('login.notice')), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('opens from the home screen', (tester) async {
      await pumpApp(tester, store: MemorySessionStore(collectorSession));

      await tester.tap(find.byKey(const Key('home.settings')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings.themeMode')), findsOneWidget);
    });

    testWidgets('choosing dark switches the whole app, even on a light phone',
        (tester) async {
      setDeviceBrightness(tester, Brightness.light);
      await pumpApp(tester, store: MemorySessionStore(collectorSession));
      await tester.tap(find.byKey(const Key('home.settings')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(brightnessAt(tester, find.byKey(const Key('settings.themeMode'))),
          Brightness.dark);
    });

    testWidgets('a session that ends while settings is open closes it',
        (tester) async {
      await pumpApp(
        tester,
        store: MemorySessionStore(collectorSession),
        backend: FakeRefreshApi(FakeRefreshApi.refuses()),
      );
      await tester.tap(find.byKey(const Key('home.settings')));
      await tester.pumpAndSettle();

      await expectLater(sessions.refreshAccessToken(), throwsException);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings.themeMode')), findsNothing);
      expect(find.byKey(const Key('login.notice')), findsOneWidget);
    });
  });

  group('theme', () {
    testWidgets('follows the device into dark mode by default',
        (tester) async {
      setDeviceBrightness(tester, Brightness.dark);
      await pumpApp(tester);

      final submit = find.byKey(const Key('login.submit'));
      expect(brightnessAt(tester, submit), Brightness.dark);
      expect(AppStatusColors.of(tester.element(submit)).success,
          AppStatusColors.dark.success);
    });

    testWidgets('uses the light theme on a light device by default',
        (tester) async {
      setDeviceBrightness(tester, Brightness.light);
      await pumpApp(tester);

      final submit = find.byKey(const Key('login.submit'));
      expect(brightnessAt(tester, submit), Brightness.light);
      expect(AppStatusColors.of(tester.element(submit)).success,
          AppStatusColors.light.success);
    });

    testWidgets('a saved light choice wins over a dark phone',
        (tester) async {
      setDeviceBrightness(tester, Brightness.dark);
      await pumpApp(tester, savedTheme: ThemeMode.light);

      expect(brightnessAt(tester, find.byKey(const Key('login.submit'))),
          Brightness.light);
    });
  });
}
