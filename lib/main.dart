import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

import 'api/authenticated_client.dart';
import 'app_services.dart';
import 'auth/auth_api.dart';
import 'auth/login_screen.dart';
import 'auth/session_manager.dart';
import 'auth/session_store.dart';
import 'collector/collector_api.dart';
import 'collector/member_cache.dart';
import 'collector/member_directory.dart';
import 'config/app_config.dart';
import 'home/home_shell.dart';
import 'outbox/outbox.dart';
import 'outbox/outbox_store.dart';
import 'settings/app_info.dart';
import 'settings/theme_controller.dart';
import 'settings/theme_mode_store.dart';
import 'storage/app_database.dart';
import 'sync/background_sync.dart';
import 'sync/payment_sync.dart';
import 'sync/sync_platform.dart';
import 'sync/sync_scheduler.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Secure storage and preferences use platform channels, which need the
  // binding first.
  WidgetsFlutterBinding.ensureInitialized();

  // Read the light/dark choice before the first frame so the app doesn't
  // open in one theme and switch to the other.
  final theme = ThemeController(PrefsThemeModeStore());
  await theme.load();
  final appInfo = await AppInfo.load();

  final sessions = SessionManager(
    api: AuthApi(baseUrl: AppConfig.apiBaseUrl),
    store: SecureSessionStore(),
  )..restore();

  // Every protected call goes through the authenticated client, which adds
  // the collector's token and refreshes it when it expires.
  final collectorApi = CollectorApi(
    baseUrl: AppConfig.apiBaseUrl,
    client: AuthenticatedClient(http.Client(), sessions),
  );
  final database = AppDatabase();
  String? staffId() => sessions.session?.staffId;
  final outboxStore = SqliteOutboxStore(database);
  final outbox = Outbox(store: outboxStore, staffId: staffId);

  // Tapping a refused-payment notification opens the Outbox.
  final openOutbox = ValueNotifier<bool>(false);
  final notifications = await _notifications(() => openOutbox.value = true);

  final services = AppServices(
    collectorApi: collectorApi,
    members: MemberDirectory(
      api: collectorApi,
      cache: SqliteMemberCache(database),
    ),
    outbox: outbox,
    sync: SyncScheduler(
      sync: PaymentSync(
        store: outboxStore,
        api: collectorApi,
        staffId: staffId,
        notifier: notifications,
      ),
      outbox: outbox,
      connectivity: ConnectivityPlusWatcher(),
      background: const WorkmanagerScheduler(),
      notifications: notifications,
    ),
    openOutboxRequest: openOutbox,
  );

  // Sends the outbox while the app is closed.
  try {
    await Workmanager().initialize(backgroundSyncDispatcher);
  } catch (_) {
    // The app still syncs while it's open.
  }

  runApp(CashClientApp(
    sessions: sessions,
    theme: theme,
    appInfo: appInfo,
    services: services,
  ));
}

/// The notifications plugin, or a stand-in that does nothing if it can't
/// start, so a notification problem never stops the app opening.
Future<AppNotifications> _notifications(void Function() onOpenOutbox) async {
  try {
    final notifications =
        await LocalAppNotifications.create(onOpenOutbox: onOpenOutbox);
    if (await notifications.launchedFromNotification()) onOpenOutbox();
    return notifications;
  } catch (_) {
    return const _NoNotifications();
  }
}

class _NoNotifications implements AppNotifications {
  const _NoNotifications();

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> refused(List<OutboxPayment> payments) async {}
}

class CashClientApp extends StatelessWidget {
  const CashClientApp({
    super.key,
    required this.sessions,
    required this.theme,
    required this.appInfo,
    required this.services,
  });

  final SessionManager sessions;
  final ThemeController theme;
  final AppInfo appInfo;
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) => MaterialApp(
        title: 'Cash Client',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: theme.mode,
        home: AuthGate(
          sessions: sessions,
          theme: theme,
          appInfo: appInfo,
          services: services,
        ),
      ),
    );
  }
}

/// Shows the login screen or the signed-in app, and switches between them
/// whenever the session changes, including when the backend ends it.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.sessions,
    required this.theme,
    required this.appInfo,
    required this.services,
  });

  final SessionManager sessions;
  final ThemeController theme;
  final AppInfo appInfo;
  final AppServices services;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    widget.sessions.addListener(_onSessionChanged);
    // In case the session was restored before this widget existed.
    if (!widget.sessions.isRestoring && widget.sessions.session != null) {
      widget.services.sync.start();
    }
  }

  @override
  void didUpdateWidget(AuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessions != widget.sessions) {
      oldWidget.sessions.removeListener(_onSessionChanged);
      widget.sessions.addListener(_onSessionChanged);
    }
  }

  @override
  void dispose() {
    widget.sessions.removeListener(_onSessionChanged);
    widget.services.sync.stop();
    super.dispose();
  }

  void _onSessionChanged() {
    final services = widget.services;
    if (widget.sessions.isRestoring) return;
    if (widget.sessions.session != null) {
      // Signed in: send anything waiting in the outbox, now and whenever a
      // chance comes up.
      services.sync.start();
      return;
    }
    // Signed out or ended by the backend. The outbox stays on the phone for
    // the collector's next sign-in (owner decision 2026-11-15), but nothing
    // is sent without a session.
    services.sync.stop();
    // The branch member list is personal data; it doesn't outlive the
    // session it was downloaded in.
    services.members.clear();
    // This widget is the bottom screen, so swapping it to the login screen
    // isn't enough when other screens (such as the payment screens) are
    // open on top. Close them, so a collector whose session ended can't
    // keep using a screen that's still showing.
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.sessions,
      builder: (context, _) {
        final sessions = widget.sessions;
        if (sessions.isRestoring) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final session = sessions.session;
        if (session == null) {
          return LoginScreen(sessions: sessions, appInfo: widget.appInfo);
        }
        return HomeShell(
          session: session,
          theme: widget.theme,
          appInfo: widget.appInfo,
          services: widget.services,
          onSignOut: sessions.signOut,
        );
      },
    );
  }
}
