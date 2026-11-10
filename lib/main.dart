import 'package:flutter/material.dart';

import 'auth/auth_api.dart';
import 'auth/auth_session.dart';
import 'auth/login_screen.dart';
import 'auth/session_manager.dart';
import 'auth/session_store.dart';
import 'config/app_config.dart';
import 'settings/settings_screen.dart';
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

  final sessions = SessionManager(
    api: AuthApi(baseUrl: AppConfig.apiBaseUrl),
    store: SecureSessionStore(),
  )..restore();

  runApp(CashClientApp(sessions: sessions, theme: theme));
}

class CashClientApp extends StatelessWidget {
  const CashClientApp({super.key, required this.sessions, required this.theme});

  final SessionManager sessions;
  final ThemeController theme;

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
        home: AuthGate(sessions: sessions, theme: theme),
      ),
    );
  }
}

/// Shows the login screen or the signed-in app, and switches between them
/// whenever the session changes, including when the backend ends it.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.sessions, required this.theme});

  final SessionManager sessions;
  final ThemeController theme;

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
    // This widget is the bottom screen, so swapping it to the login screen
    // isn't enough when other screens (settings, and later deposits) are
    // open on top. Close them, so a collector whose session ended can't
    // keep using a screen that's still showing.
    if (widget.sessions.session == null && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
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
        if (session == null) return LoginScreen(sessions: sessions);
        return _SignedInPlaceholder(
          session: session,
          onOpenSettings: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SettingsScreen(theme: widget.theme),
            ),
          ),
          onSignOut: sessions.signOut,
        );
      },
    );
  }
}

/// Stands in for the collector's home screen, which comes in a later step.
class _SignedInPlaceholder extends StatelessWidget {
  const _SignedInPlaceholder({
    required this.session,
    required this.onOpenSettings,
    required this.onSignOut,
  });

  final AuthSession session;
  final VoidCallback onOpenSettings;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Client'),
        actions: [
          IconButton(
            key: const Key('home.settings'),
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: onOpenSettings,
          ),
          IconButton(
            key: const Key('home.signOut'),
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: onSignOut,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Signed in as ${session.staffName}',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium,
          ),
        ),
      ),
    );
  }
}
