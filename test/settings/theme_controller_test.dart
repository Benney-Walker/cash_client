import 'package:cash_client/settings/theme_controller.dart';
import 'package:cash_client/settings/theme_mode_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// A store whose read always fails, like unreadable preferences.
class _BrokenStore implements ThemeModeStore {
  @override
  Future<ThemeMode?> read() async => throw StateError('unreadable');

  @override
  Future<void> save(ThemeMode mode) async {}
}

void main() {
  test('follows the phone until a choice is saved', () async {
    final theme = ThemeController(MemoryThemeModeStore());

    await theme.load();

    expect(theme.mode, ThemeMode.system);
  });

  test('loads the saved choice', () async {
    final theme = ThemeController(MemoryThemeModeStore(ThemeMode.dark));

    await theme.load();

    expect(theme.mode, ThemeMode.dark);
  });

  test('an unreadable store falls back to following the phone', () async {
    final theme = ThemeController(_BrokenStore());

    await theme.load();

    expect(theme.mode, ThemeMode.system);
  });

  test('setMode applies, notifies and saves', () async {
    final store = MemoryThemeModeStore();
    final theme = ThemeController(store);
    var notified = 0;
    theme.addListener(() => notified++);

    await theme.setMode(ThemeMode.light);

    expect(theme.mode, ThemeMode.light);
    expect(notified, 1);
    expect(store.mode, ThemeMode.light);
  });

  test('choosing the current mode again does nothing', () async {
    final theme = ThemeController(MemoryThemeModeStore());
    var notified = 0;
    theme.addListener(() => notified++);

    await theme.setMode(ThemeMode.system);

    expect(notified, 0);
  });

  test('a failed save still applies the choice for now', () async {
    final store = MemoryThemeModeStore()..failSaves = true;
    final theme = ThemeController(store);

    await theme.setMode(ThemeMode.dark);

    expect(theme.mode, ThemeMode.dark);
    expect(store.mode, isNull);
  });

  test('stored names map back to modes, and unknown ones are ignored', () {
    for (final mode in ThemeMode.values) {
      expect(themeModeFromName(mode.name), mode);
    }
    expect(themeModeFromName(null), isNull);
    expect(themeModeFromName('sepia'), isNull);
  });
}
