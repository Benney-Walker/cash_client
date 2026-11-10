import 'package:flutter/material.dart';

import 'theme_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.theme});

  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text('Appearance', style: textTheme.titleMedium),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: theme,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<ThemeMode>(
                  key: const Key('settings.themeMode'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {theme.mode},
                  onSelectionChanged: (selection) =>
                      theme.setMode(selection.single),
                ),
                const SizedBox(height: 12),
                Text(
                  _describe(theme.mode),
                  key: const Key('settings.themeModeHint'),
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _describe(ThemeMode mode) => switch (mode) {
        ThemeMode.system => "Matches your phone's light or dark setting.",
        ThemeMode.light => 'Always light. Easiest to read in bright sunlight.',
        ThemeMode.dark => 'Always dark.',
      };
}
