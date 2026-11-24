import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/glass_card.dart';
import '../common/gradient_button.dart';
import '../common/wash_header.dart';
import '../common/names.dart';
import '../theme/app_gradients.dart';
import '../theme/app_status_colors.dart';
import 'payment_row.dart';
import 'today.dart';

export 'payment_row.dart' show clockTime;

/// The collector's home, design H1 ("wash header"): the pale gradient wash
/// across the top with the greeting and today's total on a glass card,
/// then the actions and recent records on the plain page.
///
/// When payments are waiting on the phone or were refused, an Outbox row
/// sits above the actions (design R2) and opens the Outbox.
///
/// Record deposit opens the payment flow and Submit today's collections the
/// Submit today screen.
///
/// Today's figures and the 5 latest payments come from [today] (design T1,
/// owner decisions 2026-11-24): the server's day summary plus the payments
/// still on the phone. Pulling down refreshes them.
///
/// While location is off or not allowed, Record deposit becomes "Turn on
/// location to record" (design H-B): payments need a location point (D34,
/// owner decision 2026-11-24).
///
/// There's no Withdrawal button: collector withdrawal requests were removed
/// (owner decision 2026-11-15). Members withdraw at a branch office.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.staffName,
    required this.onSeeAll,
    required this.onRecordDeposit,
    required this.onSubmitDay,
    this.outboxWaiting = 0,
    this.outboxRefused = 0,
    this.onOpenOutbox,
    this.locationOff = false,
    this.onTurnOnLocation,
    this.today = TodayView.empty,
    this.onRefresh,
    this.now = DateTime.now,
  });

  /// As the backend returns it, which is upper case.
  final String staffName;

  /// Opens the full history.
  final VoidCallback onSeeAll;

  /// Opens the record-payment flow (savings deposit or share purchase).
  final VoidCallback onRecordDeposit;
  final VoidCallback onSubmitDay;

  /// Payments on the phone the backend doesn't have yet. The Outbox row
  /// only shows when there's at least one.
  final int outboxWaiting;
  final int outboxRefused;
  final VoidCallback? onOpenOutbox;

  /// Location is off or not allowed, so payments can't be recorded.
  final bool locationOff;
  final VoidCallback? onTurnOnLocation;

  /// Today's figures and recent payments.
  final TodayView today;

  /// Pull to refresh; null turns it off.
  final Future<void> Function()? onRefresh;

  /// For the greeting; replaceable in tests.
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    // The wash runs under the status bar, so its icons follow the wash.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: _MaybeRefresh(
          onRefresh: onRefresh,
          child: ListView(
            // So pull-to-refresh works even when the page doesn't scroll.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              _HomeHeader(
                greeting: greetingFor(now()),
                name: staffName,
                today: today,
              ),
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
                    if (locationOff) ...[
                      GradientButton(
                        key: const Key('home.turnOnLocation'),
                        onPressed: onTurnOnLocation,
                        child: const _IconLabel(
                          icon: Icons.location_on_outlined,
                          label: 'Turn on location to record',
                        ),
                      ),
                      const SizedBox(height: 6),
                      const _LocationOff(),
                    ] else
                      GradientButton(
                        key: const Key('home.recordDeposit'),
                        onPressed: onRecordDeposit,
                        child: const _IconLabel(
                          icon: Icons.add,
                          label: 'Record deposit',
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('home.submitDay'),
                      onPressed: onSubmitDay,
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
                    if (today.recent.isEmpty)
                      const _EmptyRecent()
                    else
                      _RecentList(
                        payments: today.recent,
                        onOpenOutbox: onOpenOutbox,
                        now: now,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
  const _HomeHeader({
    required this.greeting,
    required this.name,
    required this.today,
  });

  final String greeting;
  final String name;
  final TodayView today;

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
          _TodayCard(today: today),
        ],
      ),
    );
  }
}

/// Today's figures on a glass card (design T1): total, savings and shares,
/// how many payments and how many are still on the phone. All text uses the
/// panel's main colour: the secondary tone is too faint on the glass.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.today});

  final TodayView today;

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);
    final textTheme = Theme.of(context).textTheme;
    final label = textTheme.bodySmall?.copyWith(color: gradients.panelText);
    final figure = label?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final updated = todayUpdatedLabel(today);

    return GlassCard(
      padding: const EdgeInsets.all(14),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Today's collections", style: label),
          const SizedBox(height: 2),
          Text(
            today.total.format(),
            key: const Key('home.todayTotal'),
            style: textTheme.headlineMedium?.copyWith(
              color: gradients.panelText,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 16,
            runSpacing: 2,
            children: [
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Savings '),
                  TextSpan(text: today.savings.format(), style: figure),
                ]),
                key: const Key('home.todaySavings'),
                style: label,
              ),
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Shares '),
                  TextSpan(text: today.shares.format(), style: figure),
                ]),
                key: const Key('home.todayShares'),
                style: label,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            todayCountLabel(today),
            key: const Key('home.todayCount'),
            style: label,
          ),
          if (updated != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.cloud_off_outlined,
                    size: 14, color: gradients.panelText),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    updated,
                    key: const Key('home.todayUpdated'),
                    style: label,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "14 payments · 2 on this phone", or "No records yet today".
String todayCountLabel(TodayView today) {
  if (today.count == 0) return 'No records yet today';
  final payments = today.count == 1 ? '1 payment' : '${today.count} payments';
  return today.onPhone == 0
      ? payments
      : '$payments · ${today.onPhone} on this phone';
}

/// Shown only when the server's figures couldn't be downloaded: when they
/// date from, or that only the phone's payments are counted.
String? todayUpdatedLabel(TodayView today) {
  final why = switch (today.problem) {
    TodayProblem.none => null,
    TodayProblem.offline => 'offline',
    TodayProblem.failed => "couldn't update",
  };
  if (why == null) return null;
  final at = today.updatedAt;
  if (at == null) return 'Only payments on this phone · $why';
  return 'Updated ${clockTime(at)} · $why';
}

/// Pull-to-refresh around [child] when there's something to refresh.
class _MaybeRefresh extends StatelessWidget {
  const _MaybeRefresh({required this.onRefresh, required this.child});

  final Future<void> Function()? onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final refresh = onRefresh;
    if (refresh == null) return child;
    return RefreshIndicator(onRefresh: refresh, child: child);
  }
}

/// Home's latest payments (design T1): initials, member, type, account and
/// time, the amount, and where it stands. A payment still on the phone
/// counts down its 5 minutes and opens the Outbox when tapped.
class _RecentList extends StatefulWidget {
  const _RecentList({
    required this.payments,
    required this.onOpenOutbox,
    required this.now,
  });

  final List<RecentPayment> payments;
  final VoidCallback? onOpenOutbox;
  final DateTime Function() now;

  @override
  State<_RecentList> createState() => _RecentListState();
}

class _RecentListState extends State<_RecentList> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_RecentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  /// Ticks every second only while a countdown is showing.
  void _syncTicker() {
    final now = widget.now();
    final counting = widget.payments.any(
      (p) => p.phonePayment?.isCorrectable(now) ?? false,
    );
    if (counting && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        _syncTicker();
      });
    } else if (!counting) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now();
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < widget.payments.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 60),
            PaymentRow(
              key: Key('home.recent.$i'),
              payment: widget.payments[i],
              now: now,
              onTap: widget.payments[i].phonePayment == null
                  ? null
                  : widget.onOpenOutbox,
            ),
          ],
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

/// The line under "Turn on location to record": icon and words, never
/// colour alone.
class _LocationOff extends StatelessWidget {
  const _LocationOff();

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Row(
      key: const Key('home.locationOff'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.location_off_outlined, size: 16, color: status.danger),
        const SizedBox(width: 6),
        Text(
          "Location is off. Payments can't be recorded.",
          style: textTheme.bodySmall?.copyWith(color: status.danger),
        ),
      ],
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
