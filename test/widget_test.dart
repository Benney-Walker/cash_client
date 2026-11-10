import 'package:cash_client/auth/session_manager.dart';
import 'package:cash_client/home/home_shell.dart';
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

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  void setDeviceBrightness(WidgetTester tester, Brightness brightness) {
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  group('sign-in', () {
    testWidgets('opens at sign-in when no session is stored', (tester) async {
      await pumpApp(tester);
      expect(find.byKey(const Key('login.submit')), findsOneWidget);
    });

    testWidgets('a stored collector session opens on the home tab',
        (tester) async {
      await pumpApp(tester, store: MemorySessionStore(collectorSession));
      expect(find.byKey(const Key('home.staffName')), findsOneWidget);
      expect(find.text('Kofi Mensah'), findsOneWidget);
    });

    testWidgets('signing out from settings returns to sign-in without a '
        'notice', (tester) async {
      final store = MemorySessionStore(collectorSession);
      await pumpApp(tester, store: store);

      await tapKey(tester, 'nav.settings');
      await tapKey(tester, 'settings.signOut');

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
      expect(find.byKey(const Key('home.staffName')), findsOneWidget);

      // What the authenticated client does when a refresh is refused.
      await expectLater(sessions.refreshAccessToken(), throwsException);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login.submit')), findsOneWidget);
      expect(find.byKey(const Key('login.notice')), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('the bottom bar switches between home, history and settings',
        (tester) async {
      await pumpApp(tester, store: MemorySessionStore(collectorSession));

      await tapKey(tester, 'nav.history');
      expect(find.byKey(const Key('history.empty')), findsOneWidget);
      expect(find.byKey(const Key('home.staffName')), findsNothing);

      await tapKey(tester, 'nav.settings');
      expect(find.byKey(const Key('settings.themeMode')), findsOneWidget);

      await tapKey(tester, 'nav.home');
      expect(find.byKey(const Key('home.staffName')), findsOneWidget);
    });

    testWidgets('See all on home opens the history tab', (tester) async {
      await pumpApp(tester, store: MemorySessionStore(collectorSession));

      await tapKey(tester, 'home.seeAll');

      expect(find.byKey(const Key('history.empty')), findsOneWidget);
    });

    testWidgets('a session that ends closes screens opened on top of home',
        (tester) async {
      await pumpApp(
        tester,
        store: MemorySessionStore(collectorSession),
        backend: FakeRefreshApi(FakeRefreshApi.refuses()),
      );
      // Stands in for a later screen, such as recording a deposit.
      Navigator.of(tester.element(find.byType(HomeShell))).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Pushed screen')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pushed screen'), findsOneWidget);

      await expectLater(sessions.refreshAccessToken(), throwsException);
      await tester.pumpAndSettle();

      expect(find.text('Pushed screen'), findsNothing);
      expect(find.byKey(const Key('login.notice')), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('choosing dark switches the whole app, even on a light phone',
        (tester) async {
      setDeviceBrightness(tester, Brightness.light);
      await pumpApp(tester, store: MemorySessionStore(collectorSession));
      await tapKey(tester, 'nav.settings');

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(brightnessAt(tester, find.byKey(const Key('settings.themeMode'))),
          Brightness.dark);
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
