import 'package:flutter/material.dart';

import '../app_services.dart';
import '../auth/auth_session.dart';
import '../collector/payment_flow.dart';
import '../outbox/outbox_screen.dart';
import '../settings/app_info.dart';
import '../settings/settings_screen.dart';
import '../settings/theme_controller.dart';
import 'history_screen.dart';
import 'home_screen.dart';

/// The signed-in app: Home, History and Settings behind a bottom bar.
///
/// The tabs are kept alive in an [IndexedStack], so switching tabs doesn't
/// lose a tab's scroll position.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.session,
    required this.theme,
    required this.appInfo,
    required this.services,
    required this.onSignOut,
  });

  final AuthSession session;
  final ThemeController theme;
  final AppInfo appInfo;
  final AppServices services;
  final VoidCallback onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _home = 0;
  static const _history = 1;

  int _tab = _home;

  void _select(int tab) => setState(() => _tab = tab);

  @override
  void initState() {
    super.initState();
    widget.services.openOutboxRequest.addListener(_onOpenOutboxRequest);
    // The app may have been started by tapping a notification.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onOpenOutboxRequest());
  }

  @override
  void dispose() {
    widget.services.openOutboxRequest.removeListener(_onOpenOutboxRequest);
    super.dispose();
  }

  void _onOpenOutboxRequest() {
    final request = widget.services.openOutboxRequest;
    if (!request.value || !mounted) return;
    request.value = false;
    _openOutbox();
  }

  void _openOutbox() {
    final navigator = Navigator.of(context);
    // Go back to the tabs first, so a notification tapped mid-payment
    // doesn't stack the Outbox on a half-finished flow.
    navigator.popUntil((route) => route.isFirst);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => OutboxScreen(
          outbox: widget.services.outbox,
          onSync: widget.services.sync.syncNow,
        ),
      ),
    );
  }

  void _recordDeposit() {
    final services = widget.services;
    startPaymentFlow(
      context,
      directory: services.members,
      api: services.collectorApi,
      saveOffline: (draft, key) async {
        final queued = await services.outbox.add(draft, idempotencyKey: key);
        services.sync.paymentQueued(queued);
        return queued;
      },
    );
  }

  /// Unsent payments stay on the phone and go after the collector signs in
  /// again (owner decision 2026-11-15), but they should know before they go.
  Future<void> _signOut() async {
    final outbox = widget.services.outbox;
    await outbox.refresh();
    final unsent = outbox.items.length;
    if (unsent == 0) {
      widget.onSignOut();
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('signOut.unsentDialog'),
        title: const Text('Payments not sent yet'),
        content: Text(
          unsent == 1
              ? "1 payment hasn't reached the server. It stays on this phone "
                  'and is sent after you sign in again.'
              : "$unsent payments haven't reached the server. They stay on "
                  'this phone and are sent after you sign in again.',
        ),
        actions: [
          TextButton(
            key: const Key('signOut.cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('signOut.confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          ListenableBuilder(
            listenable: widget.services.outbox,
            builder: (context, _) {
              final outbox = widget.services.outbox;
              return HomeScreen(
                staffName: widget.session.staffName,
                onSeeAll: () => _select(_history),
                onRecordDeposit: _recordDeposit,
                outboxWaiting: outbox.waiting.length,
                outboxRefused: outbox.refused.length,
                onOpenOutbox: _openOutbox,
              );
            },
          ),
          const HistoryScreen(),
          SettingsScreen(
            theme: widget.theme,
            staffId: widget.session.staffId,
            staffName: widget.session.staffName,
            appInfo: widget.appInfo,
            onSignOut: _signOut,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            key: Key('nav.home'),
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            key: Key('nav.history'),
            icon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            key: Key('nav.settings'),
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
