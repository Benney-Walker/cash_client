import 'package:flutter/material.dart';

import 'theme_mode_store.dart';

/// The app's light/dark choice: follow the phone, always light, or always
/// dark. The app rebuilds its theme by listening to this.
class ThemeController extends ChangeNotifier {
  ThemeController(this._store);

  final ThemeModeStore _store;
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  /// Reads the saved choice. Called before the first frame, so the app
  /// doesn't flash the wrong theme at launch.
  Future<void> load() async {
    ThemeMode? saved;
    try {
      saved = await _store.read();
    } catch (_) {
      // An unreadable preference isn't worth stopping the app for; it
      // falls back to following the phone.
      saved = null;
    }
    if (saved != null && saved != _mode) {
      _mode = saved;
      notifyListeners();
    }
  }

  /// Applies [mode] straight away and saves it.
  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      await _store.save(mode);
    } catch (_) {
      // The choice still applies until the app closes; it just won't be
      // remembered. Not worth interrupting the collector over.
    }
  }
}
