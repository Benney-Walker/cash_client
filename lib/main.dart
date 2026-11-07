import 'package:flutter/material.dart';

import 'auth/auth_api.dart';
import 'auth/auth_session.dart';
import 'auth/login_screen.dart';
import 'auth/session_manager.dart';
import 'auth/session_store.dart';
import 'config/app_config.dart';
import 'theme/app_theme.dart';

void main() {
  // Secure storage uses a platform channel, which needs the binding first.
  WidgetsFlutterBinding.ensureInitialized();
  final sessions = SessionManager(
    api: AuthApi(baseUrl: AppConfig.apiBaseUrl),
    store: SecureSessionStore(),
  )..restore();
  runApp(CashClientApp(sessions: sessions));
}

class CashClientApp extends StatelessWidget {
  const CashClientApp({super.key, required this.sessions});

  final SessionManager sessions;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cash Client',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Follows the phone's setting. An in-app choice comes with the
      // settings screen.
      themeMode: ThemeMode.system,
      home: AuthGate(sessions: sessions),
    );
  }
}

/// Shows the login screen or the signed-in app, and switches between them
/// whenever the session changes, including when the backend ends it.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.sessions});

  final SessionManager sessions;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sessions,
      builder: (context, _) {
        if (sessions.isRestoring) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final session = sessions.session;
        if (session == null) return LoginScreen(sessions: sessions);
        return _SignedInPlaceholder(
          session: session,
          onSignOut: sessions.signOut,
        );
      },
    );
  }
}

/// Stands in for the collector's home screen, which comes in a later step.
class _SignedInPlaceholder extends StatelessWidget {
  const _SignedInPlaceholder({required this.session, required this.onSignOut});

  final AuthSession session;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Client'),
        actions: [
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
