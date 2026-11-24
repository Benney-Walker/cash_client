import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/gradient_button.dart';
import '../common/wash_header.dart';
import '../theme/app_gradients.dart';
import '../theme/app_status_colors.dart';
import 'location_platform.dart';
import 'location_tracker.dart';

/// Design L1: shown after sign-in while location isn't allowed, before
/// Android's own prompt. It says what's recorded, who sees it and when it
/// stops (Google Play asks for this before an app tracks location in the
/// background), then asks.
///
/// Payments can't be recorded without location (owner decision
/// 2026-11-24), so the way past this screen is allowing it; the other way
/// out is signing out.
class LocationDisclosureScreen extends StatefulWidget {
  const LocationDisclosureScreen({
    super.key,
    required this.tracker,
    required this.onSignOut,
  });

  final LocationTracker tracker;
  final VoidCallback onSignOut;

  @override
  State<LocationDisclosureScreen> createState() =>
      _LocationDisclosureScreenState();
}

class _LocationDisclosureScreenState extends State<LocationDisclosureScreen> {
  bool _asking = false;

  /// Set after the collector says no to Android's prompt.
  bool _refused = false;

  Future<void> _turnOn() async {
    if (_asking) return;
    final tracker = widget.tracker;
    setState(() => _asking = true);
    if (tracker.access == LocationAccess.deniedForever) {
      // Android won't ask again; only Settings can change it. Coming back
      // to the app re-checks.
      await tracker.fixAccess();
    } else {
      final access = await tracker.requestAccess();
      _refused = access == LocationAccess.denied ||
          access == LocationAccess.deniedForever;
    }
    if (mounted) setState(() => _asking = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final gradients = AppGradients.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final blocked = widget.tracker.access == LocationAccess.deniedForever;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WashHeader(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 40,
                      color: gradients.panelText,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Location while you collect',
                      key: const Key('location.title'),
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge?.copyWith(
                        color: gradients.panelText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                children: [
                  const _Point(
                    icon: Icons.schedule,
                    text: "Your location is recorded every 5 minutes while "
                        "you're signed in, and with each payment, even when "
                        'the app is closed.',
                  ),
                  const _Point(
                    icon: Icons.apartment_outlined,
                    text: 'Your branch sees it with your payments.',
                  ),
                  const _Point(
                    icon: Icons.battery_std_outlined,
                    text: "Your phone's battery level goes with it.",
                  ),
                  const _Point(
                    icon: Icons.stop_circle_outlined,
                    text: "It stops when you submit the day's collections or "
                        'sign out.',
                  ),
                  const _Point(
                    icon: Icons.notifications_none,
                    text: 'A notification shows while it runs.',
                  ),
                  if (blocked || _refused) ...[
                    const SizedBox(height: 8),
                    _Notice(
                      text: blocked
                          ? 'Location is blocked for this app. Open Settings, '
                              'tap Permissions, then Location, and choose '
                              'Allow only while using the app.'
                          : "Location wasn't allowed. Payments can't be "
                              'recorded without it.',
                    ),
                  ],
                ],
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GradientButton(
                    key: const Key('location.turnOn'),
                    onPressed: _turnOn,
                    child: Text(blocked ? 'Open settings' : 'Turn on location'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('location.signOut'),
                    onPressed: _asking ? null : widget.onSignOut,
                    child: const Text('Sign out'),
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

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: status.dangerContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.location_off_outlined, color: status.danger, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  key: const Key('location.notice'),
                  style: TextStyle(color: status.danger),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
