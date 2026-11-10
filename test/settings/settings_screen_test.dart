import 'package:cash_client/settings/settings_screen.dart';
import 'package:cash_client/settings/theme_controller.dart';
import 'package:cash_client/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late MemoryThemeModeStore store;
  late ThemeController theme;
  late int signOuts;

  Future<void> pumpSettings(WidgetTester tester, {ThemeMode? saved}) async {
    store = MemoryThemeModeStore(saved);
    theme = ThemeController(store);
    signOuts = 0;
    await theme.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SettingsScreen(
          theme: theme,
          staffId: 'STF001',
          staffName: 'KOFI MENSAH',
          onSignOut: () => signOuts++,
        ),
      ),
    );
  }

  SegmentedButton<ThemeMode> picker(WidgetTester tester) =>
      tester.widget(find.byKey(const Key('settings.themeMode')));

  testWidgets('shows the three choices with the current one selected',
      (tester) async {
    await pumpSettings(tester);

    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(picker(tester).selected, {ThemeMode.system});
    expect(find.textContaining("phone's light or dark"), findsOneWidget);
  });

  testWidgets('shows a saved choice as selected', (tester) async {
    await pumpSettings(tester, saved: ThemeMode.light);

    expect(picker(tester).selected, {ThemeMode.light});
    expect(find.textContaining('Always light'), findsOneWidget);
  });

  testWidgets('choosing dark applies and saves it', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(theme.mode, ThemeMode.dark);
    expect(store.mode, ThemeMode.dark);
    expect(picker(tester).selected, {ThemeMode.dark});
    expect(find.text('Always dark.'), findsOneWidget);
  });

  testWidgets('each choice is at least 48dp tall', (tester) async {
    await pumpSettings(tester);

    for (final label in ['System', 'Light', 'Dark']) {
      final segment = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(tester.getSize(segment.first).height,
          greaterThanOrEqualTo(AppTheme.minTouchTarget));
    }
  });

  testWidgets('shows who is signed in, in normal case', (tester) async {
    await pumpSettings(tester);

    expect(find.text('Kofi Mensah'), findsOneWidget);
    expect(find.text('Staff ID STF001'), findsOneWidget);
  });

  testWidgets('sign out calls back', (tester) async {
    await pumpSettings(tester);
    final signOut = find.byKey(const Key('settings.signOut'));

    await tester.ensureVisible(signOut);
    await tester.tap(signOut);

    expect(signOuts, 1);
  });
}
