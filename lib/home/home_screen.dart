import 'package:flutter/material.dart';

import '../common/names.dart';
import '../theme/app_status_colors.dart';

/// The collector's home: today's total, the main actions, and the most
/// recent records.
///
/// The backend endpoints for recording and listing collections don't exist
/// yet, so the totals show an empty day and the actions explain that
/// they're not available. The buttons stay enabled on purpose: a disabled
/// button gives no reason, a message does.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.staffName,
    required this.onSeeAll,
    this.now = DateTime.now,
  });

  /// As the backend returns it, which is upper case.
  final String staffName;

  /// Opens the full history.
  final VoidCallback onSeeAll;

  /// For the greeting; replaceable in tests.
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              greetingFor(now()),
              style: textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            Text(
              displayName(staffName),
              key: const Key('home.staffName'),
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            const _TodayCard(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('home.recordDeposit'),
                    style: _compactButton,
                    onPressed: () => _notAvailable(
                      context,
                      "Recording deposits isn't available yet.",
                    ),
                    icon: const Icon(Icons.add),
                    label: const _ButtonLabel('Record deposit'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('home.withdrawal'),
                    style: _compactButton,
                    onPressed: () => _notAvailable(
                      context,
                      "Withdrawal requests aren't available yet.",
                    ),
                    icon: const Icon(Icons.north_east),
                    label: const _ButtonLabel('Withdrawal'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('home.submitDay'),
              onPressed: () => _notAvailable(
                context,
                "Submitting the day's collections isn't available yet.",
              ),
              icon: const Icon(Icons.send_outlined),
              label: const Text("Submit today's collections"),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Text('Recent', style: textTheme.titleMedium)),
                TextButton(
                  key: const Key('home.seeAll'),
                  onPressed: onSeeAll,
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const _EmptyRecent(),
          ],
        ),
      ),
    );
  }

  // Two buttons share a row, so they use less side padding than the theme
  // default to keep "Record deposit" on one line on a 360dp phone.
  static const _compactButton = ButtonStyle(
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
  );

  static void _notAvailable(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$message It needs a backend update first.'),
        ),
      );
  }
}

/// "Good morning", "Good afternoon" or "Good evening" for the phone's time.
String greetingFor(DateTime time) {
  if (time.hour < 12) return 'Good morning';
  if (time.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

class _ButtonLabel extends StatelessWidget {
  const _ButtonLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
}

/// Today's total, on the hero gradient. Until the backend can report the
/// day's records, it shows an empty day.
class _TodayCard extends StatelessWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final secondary = textTheme.bodySmall?.copyWith(
      color: status.onHeroSecondary,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: status.heroGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Today's collections", style: secondary),
            const SizedBox(height: 4),
            Text(
              'GH₵ 0.00',
              key: const Key('home.todayTotal'),
              style: textTheme.headlineMedium?.copyWith(
                color: status.onHero,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text('No records yet today', style: secondary),
          ],
        ),
      ),
    );
  }
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 32, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              'No collections recorded today',
              key: const Key('home.recentEmpty'),
              style: textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Deposits you record will show here.',
              style: textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
