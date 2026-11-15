import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/glass_card.dart';
import '../common/gradient_button.dart';
import '../common/wash_header.dart';
import '../common/names.dart';
import '../theme/app_gradients.dart';
import '../theme/app_status_colors.dart';

/// The collector's home, design H1 ("wash header"): the pale gradient wash
/// across the top with the greeting and today's total on a glass card,
/// then the actions and recent records on the plain page.
///
/// When payments are waiting on the phone or were refused, an Outbox row
/// sits above the actions (design R2) and opens the Outbox.
///
/// Record deposit opens the payment flow. Today's totals and the recent
/// list aren't connected to the backend yet, so they show an empty day;
/// Withdrawal and Submit explain that they're not available. Those buttons
/// stay enabled on purpose: a disabled button gives no reason, a message
/// does.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.staffName,
    required this.onSeeAll,
    required this.onRecordDeposit,
    this.outboxWaiting = 0,
    this.outboxRefused = 0,
    this.onOpenOutbox,
    this.now = DateTime.now,
  });

  /// As the backend returns it, which is upper case.
  final String staffName;

  /// Opens the full history.
  final VoidCallback onSeeAll;

  /// Opens the record-payment flow (savings deposit or share purchase).
  final VoidCallback onRecordDeposit;

  /// Payments on the phone the backend doesn't have yet. The Outbox row
  /// only shows when there's at least one.
  final int outboxWaiting;
  final int outboxRefused;
  final VoidCallback? onOpenOutbox;

  /// For the greeting; replaceable in tests.
  final DateTime Function() now;

  // Two buttons share a row, so they use less side padding than the theme
  // default to keep "Record deposit" on one line on a 360dp phone.
  static const _compactPadding = EdgeInsets.symmetric(horizontal: 12);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    // The wash runs under the status bar, so its icons follow the wash.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            _HomeHeader(greeting: greetingFor(now()), name: staffName),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (outboxWaiting + outboxRefused > 0) ...[
                    _OutboxRow(
                      waiting: outboxWaiting,
                      refused: outboxRefused,
                      onTap: onOpenOutbox,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: GradientButton(
                          key: const Key('home.recordDeposit'),
                          padding: _compactPadding,
                          onPressed: onRecordDeposit,
                          child: const _IconLabel(
                            icon: Icons.add,
                            label: 'Record deposit',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('home.withdrawal'),
                          style: const ButtonStyle(
                            padding: WidgetStatePropertyAll(_compactPadding),
                          ),
                          onPressed: () => _notAvailable(
                            context,
                            "Withdrawal requests aren't available yet.",
                          ),
                          child: const _IconLabel(
                            icon: Icons.north_east,
                            label: 'Withdrawal',
                          ),
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
                      Expanded(
                        child: Text('Recent', style: textTheme.titleMedium),
                      ),
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
          ],
        ),
      ),
    );
  }

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

/// The wash across the top: greeting, name and today's total.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.greeting, required this.name});

  final String greeting;
  final String name;

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);
    final textTheme = Theme.of(context).textTheme;

    return WashHeader(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // On the open wash the lighter secondary tone is readable (at
          // least 5:1); on the glass card below it isn't, so the card uses
          // panelText throughout.
          Text(
            greeting,
            style: textTheme.bodyMedium
                ?.copyWith(color: gradients.panelTextSecondary),
          ),
          Text(
            displayName(name),
            key: const Key('home.staffName'),
            style: textTheme.titleLarge?.copyWith(
              color: gradients.panelText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          const _TodayCard(),
        ],
      ),
    );
  }
}

/// Today's total on a glass card. Until the backend can report the day's
/// records, it shows an empty day.
class _TodayCard extends StatelessWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);
    final textTheme = Theme.of(context).textTheme;
    final label = textTheme.bodySmall?.copyWith(color: gradients.panelText);

    return GlassCard(
      padding: const EdgeInsets.all(14),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Today's collections", style: label),
          const SizedBox(height: 2),
          Text(
            'GH₵ 0.00',
            key: const Key('home.todayTotal'),
            style: textTheme.headlineMedium?.copyWith(
              color: gradients.panelText,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text('No records yet today', style: label),
        ],
      ),
    );
  }
}

/// "Outbox · 3 waiting · 1 refused", opening the Outbox.
class _OutboxRow extends StatelessWidget {
  const _OutboxRow({
    required this.waiting,
    required this.refused,
    required this.onTap,
  });

  final int waiting;
  final int refused;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final status = AppStatusColors.of(context);
    final secondary =
        textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: const Key('home.outbox'),
        onTap: onTap,
        leading: Icon(Icons.outbox_outlined, color: scheme.primary),
        title: const Text('Outbox'),
        subtitle: Text.rich(
          TextSpan(
            children: [
              if (waiting > 0) TextSpan(text: '$waiting waiting', style: secondary),
              if (waiting > 0 && refused > 0)
                TextSpan(text: ' · ', style: secondary),
              if (refused > 0) ...[
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(Icons.block, size: 14, color: status.danger),
                ),
                TextSpan(
                  text: ' $refused refused',
                  style: textTheme.bodyMedium?.copyWith(
                    color: status.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          key: const Key('home.outboxSummary'),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// An icon and a label that shortens with "…" instead of overflowing.
class _IconLabel extends StatelessWidget {
  const _IconLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
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
