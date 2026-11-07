import 'package:flutter/material.dart';

import 'auth/auth_api.dart';
import 'auth/auth_session.dart';
import 'auth/login_screen.dart';
import 'auth/session_store.dart';
import 'auth/sign_in.dart';
import 'config/app_config.dart';
import 'theme/app_theme.dart';

void main() {
  // Secure storage uses a platform channel, which needs the binding first.
  WidgetsFlutterBinding.ensureInitialized();
  final store = SecureSessionStore();
  runApp(
    CashClientApp(
      sessionStore: store,
      signIn: SignIn(AuthApi(baseUrl: AppConfig.apiBaseUrl), store),
    ),
  );
}

class CashClientApp extends StatelessWidget {
  const CashClientApp({
    super.key,
    required this.sessionStore,
    required this.signIn,
  });

  final SessionStore sessionStore;
  final SignIn signIn;

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
      home: AuthGate(sessionStore: sessionStore, signIn: signIn),
    );
  }
}

/// Shows the login screen or the signed-in app, depending on whether a
/// session is stored on the device.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.sessionStore, required this.signIn});

  final SessionStore sessionStore;
  final SignIn signIn;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  AuthSession? _session;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    AuthSession? session;
    try {
      session = await widget.sessionStore.read();
    } catch (_) {
      // If the stored session can't be read (for example after the device's
      // keys changed), the only safe outcome is to sign in again.
      session = null;
    }
    // A stored session from a non-collector shouldn't exist, because SignIn
    // never saves one. Guard anyway rather than trust the device.
    if (session != null && !session.isCollector) session = null;
    if (!mounted) return;
    setState(() {
      _session = session;
      _loading = false;
    });
  }

  Future<void> _signOut() async {
    // The backend has no logout endpoint yet, so signing out means
    // forgetting the tokens on this device.
    await widget.sessionStore.clear();
    if (!mounted) return;
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final session = _session;
    if (session == null) {
      return LoginScreen(
        signIn: widget.signIn,
        onSignedIn: (signedIn) => setState(() => _session = signedIn),
      );
    }
    return _SignedInPlaceholder(session: session, onSignOut: _signOut);
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
