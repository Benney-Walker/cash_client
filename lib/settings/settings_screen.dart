import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/glass_card.dart';
import '../common/initials_avatar.dart';
import '../common/names.dart';
import '../common/wash_header.dart';
import '../theme/app_gradients.dart';
import 'app_info.dart';
import 'theme_controller.dart';

/// Settings, design S1 ("profile header"): the wash header with the
/// collector's initials, name and staff ID on a glass card, then the
/// Appearance and About cards and Sign out on the plain page.
///
/// There's no primary action here, so no gradient button; Sign out is
/// outlined.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.theme,
    required this.staffId,
    required this.staffName,
    required this.appInfo,
    required this.onSignOut,
  });

  final ThemeController theme;
  final String staffId;

  /// As the backend returns it, which is upper case.
  final String staffName;

  /// For the About card.
  final AppInfo appInfo;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // The wash runs under the status bar, so its icons follow the wash.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            _ProfileHeader(staffId: staffId, staffName: staffName),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AppearanceCard(theme: theme),
                  const SizedBox(height: 12),
                  _AboutCard(appInfo: appInfo),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    key: const Key('settings.signOut'),
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.staffId, required this.staffName});

  final String staffId;
  final String staffName;

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);
    final textTheme = Theme.of(context).textTheme;

    return WashHeader(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Settings',
              style: textTheme.titleLarge?.copyWith(
                color: gradients.panelText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          GlassCard(
            padding: const EdgeInsets.all(12),
            radius: 16,
            child: Row(
              children: [
                InitialsAvatar(name: staffName),
                const SizedBox(width: 12),
                Expanded(
                  // Everything on the glass uses panelText; see GlassCard.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName(staffName),
                        key: const Key('settings.staffName'),
                        style: textTheme.titleMedium?.copyWith(
                          color: gradients.panelText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Staff ID $staffId · Collector',
                        key: const Key('settings.staffId'),
                        style: textTheme.bodySmall
                            ?.copyWith(color: gradients.panelText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({required this.theme});

  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListenableBuilder(
          listenable: theme,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Appearance', style: textTheme.titleMedium),
              const SizedBox(height: 12),
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
              const SizedBox(height: 10),
              Text(
                _describe(theme.mode),
                key: const Key('settings.themeModeHint'),
                style: textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _describe(ThemeMode mode) => switch (mode) {
        ThemeMode.system => "Matches your phone's light or dark setting.",
        ThemeMode.light => 'Always light. Easiest to read in bright sunlight.',
        ThemeMode.dark => 'Always dark.',
      };
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.appInfo});

  final AppInfo appInfo;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('About', style: textTheme.titleMedium),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Version',
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                Text(
                  appInfo.versionLabel,
                  key: const Key('settings.version'),
                  style: textTheme.bodyMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
