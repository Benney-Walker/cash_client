import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
import 'settings/app_info.dart';
import 'settings/theme_controller.dart';
import 'settings/theme_mode_store.dart';
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
  final services = AppServices(
    collectorApi: collectorApi,
    members: MemberDirectory(api: collectorApi, cache: SqliteMemberCache()),
  );

  runApp(CashClientApp(
    sessions: sessions,
    theme: theme,
    appInfo: appInfo,
    services: services,
  ));
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
    super.dispose();
  }

  void _onSessionChanged() {
    if (widget.sessions.session != null || widget.sessions.isRestoring) return;
    // The branch member list is personal data; it doesn't outlive the
    // session it was downloaded in.
    widget.services.members.clear();
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
