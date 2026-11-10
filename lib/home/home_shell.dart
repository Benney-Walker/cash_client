import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
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
    required this.onSignOut,
  });

  final AuthSession session;
  final ThemeController theme;
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(
            staffName: widget.session.staffName,
            onSeeAll: () => _select(_history),
          ),
          const HistoryScreen(),
          SettingsScreen(
            theme: widget.theme,
            staffId: widget.session.staffId,
            staffName: widget.session.staffName,
            onSignOut: widget.onSignOut,
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
