import 'package:cash_client/app_services.dart';
import 'package:cash_client/auth/session_manager.dart';
import 'package:cash_client/home/home_shell.dart';
import 'package:cash_client/location/location_platform.dart';
import 'package:cash_client/location/location_point.dart';
import 'package:cash_client/main.dart';
import 'package:cash_client/settings/theme_controller.dart';
import 'package:cash_client/theme/app_status_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/fakes.dart';

void main() {
  late SessionManager sessions;
  late ThemeController theme;
  late MemoryMemberCache memberCache;
  late MemoryOutboxStore outboxStore;
  late MemoryLocationStore locationStore;
  late FakeLocationPlatform location;
  late AppServices services;

  Future<void> pumpApp(
    WidgetTester tester, {
    MemorySessionStore? store,
    FakeRefreshApi? backend,
    ThemeMode? savedTheme,
    FakeCollectorBackend? collector,
    MemoryOutboxStore? outbox,
    FakeLocationPlatform? locationPlatform,
  }) async {
    memberCache = MemoryMemberCache();
    outboxStore = outbox ?? MemoryOutboxStore();
    locationStore = MemoryLocationStore();
    location = locationPlatform ?? FakeLocationPlatform();
    sessions = SessionManager(
      deviceIds: const FakeDeviceId(),
      
      api: (backend ?? FakeRefreshApi(FakeRefreshApi.issues('new.access.token'))).api,
      store: store ?? MemorySessionStore(),
    );
    services = testServices(
      backend: collector,
      cache: memberCache,
      outboxStore: outboxStore,
      staffId: () => sessions.session?.staffId,
      locationPlatform: location,
      locationStore: locationStore,
    );
    theme = ThemeController(MemoryThemeModeStore(savedTheme));
    await theme.load();
    await tester.pumpWidget(
      CashClientApp(
        sessions: sessions,
        theme: theme,
        appInfo: testAppInfo,
        services: services,
      ),
    );
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

  group('record payment', () {
    testWidgets('Record deposit opens the member picker with the branch list',
        (tester) async {
      await pumpApp(tester, store: MemorySessionStore(collectorSession));

      await tester.tap(find.byKey(const Key('home.recordDeposit')));
      await tester.pumpAndSettle();

      expect(find.text('Choose member'), findsOneWidget);
      expect(find.text('Ama Owusu'), findsOneWidget);
      expect(find.text('Yaw Boateng'), findsOneWidget);
      // The downloaded list is saved for offline use.
      expect(memberCache.saved?.members, hasLength(2));
    });

    testWidgets('signing out clears the saved member list', (tester) async {
      await pumpApp(tester, store: MemorySessionStore(collectorSession));
      await tester.tap(find.byKey(const Key('home.recordDeposit')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tapKey(tester, 'nav.settings');
      await tapKey(tester, 'settings.signOut');

      expect(memberCache.saved, isNull);
      expect(memberCache.clears, greaterThan(0));
    });
  });

  group('offline payments', () {
    // A payment recorded a minute ago: inside its 5 minutes for the rest of
    // the test, so the sync leaves it alone.
    MemoryOutboxStore oneWaiting() => MemoryOutboxStore([
          queuedPayment(
            createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
          ),
        ]);

    testWidgets('without a connection, a payment is saved on the phone and '
        'shows in the Outbox', (tester) async {
      final collector = FakeCollectorBackend((request) {
        if (request.method == 'GET') {
          return http.Response(membersBody(const [amaOwusu]), 200);
        }
        throw http.ClientException('no connection');
      });
      await pumpApp(
        tester,
        store: MemorySessionStore(collectorSession),
        collector: collector,
      );
      expect(find.byKey(const Key('home.outbox')), findsNothing);

      await tapKey(tester, 'home.recordDeposit');
      await tester.tap(find.text('Ama Owusu'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('record.amount')), '50');
      await tapKey(tester, 'record.continue');
      await tester.tap(find.byKey(const Key('confirm.record')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Saved on this phone'), findsOneWidget);
      expect(outboxStore.all.single.amount.pesewas, 5000);

      await tester.tap(find.byKey(const Key('saved.done')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('home.outbox')), findsOneWidget);
      expect(find.text('1 waiting'), findsOneWidget);
    });

    testWidgets('signing out with unsent payments asks first and keeps them',
        (tester) async {
      final store = MemorySessionStore(collectorSession);
      await pumpApp(tester, store: store, outbox: oneWaiting());

      await tapKey(tester, 'nav.settings');
      await tapKey(tester, 'settings.signOut');
      expect(find.byKey(const Key('signOut.unsentDialog')), findsOneWidget);

      await tapKey(tester, 'signOut.cancel');
      expect(store.session, isNotNull);

      await tapKey(tester, 'settings.signOut');
      await tapKey(tester, 'signOut.confirm');
      expect(store.session, isNull);
      expect(outboxStore.all, hasLength(1));
    });

    testWidgets('tapping a refused-payment notification opens the Outbox',
        (tester) async {
      await pumpApp(
        tester,
        store: MemorySessionStore(collectorSession),
        outbox: oneWaiting(),
      );

      services.openOutboxRequest.value = true;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byKey(const Key('outbox.title')), findsOneWidget);
    });
  });

  group('daily submission', () {
    testWidgets("Submit today's collections opens the submit screen",
        (tester) async {
      await pumpApp(tester, store: MemorySessionStore(collectorSession));

      await tapKey(tester, 'home.submitDay');

      expect(find.byKey(const Key('submit.title')), findsOneWidget);
      expect(find.text('GH₵ 1,240.00'), findsOneWidget);
    });

    testWidgets('after submitting, Record deposit explains the day is closed',
        (tester) async {
      await pumpApp(tester, store: MemorySessionStore(collectorSession));

      await tapKey(tester, 'home.submitDay');
      await tapKey(tester, 'submit.button');
      await tapKey(tester, 'submit.confirm');
      expect(find.byKey(const Key('submit.waiting')), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapKey(tester, 'home.recordDeposit');

      expect(find.textContaining("You've submitted today's collections"),
          findsOneWidget);
      expect(find.byKey(const Key('picker.search')), findsNothing);
    });

    testWidgets('signing out reopens the day on this phone', (tester) async {
      await pumpApp(tester, store: MemorySessionStore(collectorSession));
      await tapKey(tester, 'home.submitDay');
      await tapKey(tester, 'submit.button');
      await tapKey(tester, 'submit.confirm');
      expect(services.dayClosure.isClosed, isTrue);

      await sessions.signOut();
      await tester.pumpAndSettle();

      expect(services.dayClosure.isClosed, isFalse);
    });
  });

  group('location (D34)', () {
    Future<void> recordFifty(WidgetTester tester) async {
      await tapKey(tester, 'home.recordDeposit');
      await tester.tap(find.text('Ama Owusu'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('record.amount')), '50');
      await tapKey(tester, 'record.continue');
      await tester.tap(find.byKey(const Key('confirm.record')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('not allowed yet: the disclosure comes first, then home',
        (tester) async {
      await pumpApp(
        tester,
        store: MemorySessionStore(collectorSession),
        locationPlatform: FakeLocationPlatform(
          accessNow: LocationAccess.denied,
          afterRequest: LocationAccess.ready,
        ),
      );
      expect(find.text('Location while you collect'), findsOneWidget);
      expect(find.byKey(const Key('home.staffName')), findsNothing);

      await tapKey(tester, 'location.turnOn');

      expect(location.requests, 1);
      expect(find.byKey(const Key('home.recordDeposit')), findsOneWidget);
      expect(services.location.isTracking, isTrue);
    });

    testWidgets('said no: the screen stays and says why; Sign out works',
        (tester) async {
      final store = MemorySessionStore(collectorSession);
      await pumpApp(
        tester,
        store: store,
        locationPlatform: FakeLocationPlatform(
          accessNow: LocationAccess.denied,
        ),
      );

      await tapKey(tester, 'location.turnOn');
      expect(find.byKey(const Key('location.notice')), findsOneWidget);

      await tapKey(tester, 'location.signOut');
      expect(store.session, isNull);
      expect(find.byKey(const Key('login.submit')), findsOneWidget);
    });

    testWidgets('said no for good: the button opens Settings',
        (tester) async {
      await pumpApp(
        tester,
        store: MemorySessionStore(collectorSession),
        locationPlatform: FakeLocationPlatform(
          accessNow: LocationAccess.deniedForever,
        ),
      );
      expect(find.text('Open settings'), findsOneWidget);

      await tapKey(tester, 'location.turnOn');

      expect(location.appSettingsOpened, 1);
    });

    testWidgets('switched off: home asks to turn it on instead of recording',
        (tester) async {
      await pumpApp(
        tester,
        store: MemorySessionStore(collectorSession),
        locationPlatform: FakeLocationPlatform(
          accessNow: LocationAccess.serviceOff,
        ),
      );
      expect(find.byKey(const Key('home.recordDeposit')), findsNothing);

      await tapKey(tester, 'home.turnOnLocation');
      expect(location.locationSettingsOpened, 1);

      // Back from Settings with location on.
      location.accessNow = LocationAccess.ready;
      location.service.add(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home.recordDeposit')), findsOneWidget);
    });

    testWidgets('a payment gets its own point, under its key', (tester) async {
      await pumpApp(tester, store: MemorySessionStore(collectorSession));

      await recordFifty(tester);

      expect(find.text('Saved on this phone'), findsOneWidget);
      final point = locationStore.points.single;
      expect(point.trigger, LocationTrigger.payment);
      expect(point.paymentKey, outboxStore.all.single.idempotencyKey);
    });

    testWidgets('no location to be had: the payment is not saved',
        (tester) async {
      await pumpApp(
        tester,
        store: MemorySessionStore(collectorSession),
        locationPlatform: FakeLocationPlatform()..fix = null,
      );

      await recordFifty(tester);

      expect(
        find.text("Can't find your location. Step outside and try again."),
        findsOneWidget,
      );
      expect(outboxStore.all, isEmpty);
    });

    testWidgets('tracking runs while signed in and stops on submitting',
        (tester) async {
      await pumpApp(tester, store: MemorySessionStore(collectorSession));
      expect(services.location.isTracking, isTrue);

      await tapKey(tester, 'home.submitDay');
      await tapKey(tester, 'submit.button');
      await tapKey(tester, 'submit.confirm');

      expect(services.dayClosure.isClosed, isTrue);
      expect(services.location.isTracking, isFalse);
    });

    testWidgets('signing out stops tracking', (tester) async {
      await pumpApp(tester, store: MemorySessionStore(collectorSession));

      await sessions.signOut();
      await tester.pumpAndSettle();

      expect(services.location.isTracking, isFalse);
    });
  });

  group("home's figures (Step 1)", () {
    testWidgets("the server's totals plus a payment just recorded",
        (tester) async {
      await pumpApp(tester, store: MemorySessionStore(collectorSession));
      // The fake server's day: GH₵ 1,040.00 savings and GH₵ 200.00 shares.
      expect(find.text('GH₵ 1,240.00'), findsOneWidget);
      expect(find.text('18 payments'), findsOneWidget);

      await tapKey(tester, 'home.recordDeposit');
      await tester.tap(find.text('Ama Owusu'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('record.amount')), '50');
      await tapKey(tester, 'record.continue');
      await tester.tap(find.byKey(const Key('confirm.record')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('saved.done')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('GH₵ 1,290.00'), findsOneWidget);
      expect(find.text('19 payments · 1 on this phone'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('home.recent.0')),
          matching: find.textContaining('Can correct'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('signing out clears them', (tester) async {
      await pumpApp(tester, store: MemorySessionStore(collectorSession));
      expect(services.today.view.hasServerFigures, isTrue);

      await sessions.signOut();
      await tester.pumpAndSettle();

      expect(services.today.view.hasServerFigures, isFalse);
    });
  });
}
