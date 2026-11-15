import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../collector/payment_saved_screen.dart';
import '../common/wash_header.dart';
import '../sync/payment_sync.dart';
import '../theme/app_gradients.dart';
import '../theme/app_status_colors.dart';
import 'outbox.dart';
import 'outbox_store.dart';

/// Payments that haven't reached the backend yet, design R2 ("Outbox
/// screen", owner decision 2026-11-15): refused payments first, with the
/// backend's reason, then waiting ones with their 10-minute countdown.
///
/// Refused payments are retried on every sync automatically; Try again
/// runs a sync now. They can't be changed or removed here (owner decision
/// 2026-11-15): the admin sorts out the cause.
class OutboxScreen extends StatefulWidget {
  const OutboxScreen({super.key, required this.outbox, required this.onSync});

  final Outbox outbox;
  final Future<SyncReport> Function() onSync;

  @override
  State<OutboxScreen> createState() => _OutboxScreenState();
}

class _OutboxScreenState extends State<OutboxScreen> {
  Timer? _ticker;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    widget.outbox.refresh();
    // The countdowns need a rebuild every second.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.outbox.waiting.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _tryAgain() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final report = await widget.onSync();
    if (!mounted) return;
    setState(() => _syncing = false);
    final refusedLeft = widget.outbox.refused.length;
    final String message;
    if (report.offline) {
      message = "Couldn't reach the server. The app tries again when "
          "you're online.";
    } else if (refusedLeft > 0) {
      message = report.sent > 0
          ? '${_payments(report.sent)} sent. ${_payments(refusedLeft)} still '
              'refused. Report it to your admin.'
          : 'Still refused. Report it to your admin.';
    } else if (report.sent > 0) {
      message = '${_payments(report.sent)} sent.';
    } else {
      message = 'Nothing is ready to send yet.';
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String _payments(int n) => n == 1 ? '1 payment' : '$n payments';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: ListenableBuilder(
          listenable: widget.outbox,
          builder: (context, _) {
            final outbox = widget.outbox;
            final now = outbox.now();
            final refused = outbox.refused;
            final waiting = outbox.waiting;
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                const _OutboxHeader(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (outbox.isEmpty) const _EmptyOutbox(),
                      if (refused.isNotEmpty) ...[
                        _SectionLabel.refused(count: refused.length),
                        const SizedBox(height: 8),
                        for (final (i, p) in refused.indexed)
                          _RefusedRow(key: Key('outbox.refused.$i'), payment: p),
                        const SizedBox(height: 4),
                        OutlinedButton.icon(
                          key: const Key('outbox.tryAgain'),
                          onPressed: _tryAgain,
                          icon: _syncing
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    semanticsLabel: 'Sending',
                                  ),
                                )
                              : const Icon(Icons.refresh),
                          label: const Text('Try again now'),
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (waiting.isNotEmpty) ...[
                        _SectionLabel.waiting(count: waiting.length),
                        const SizedBox(height: 8),
                        for (final (i, p) in waiting.indexed)
                          _WaitingRow(
                            key: Key('outbox.waiting.$i'),
                            payment: p,
                            now: now,
                          ),
                      ],
                      if (!outbox.isEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Payments are sent when their 10 minutes are up and '
                          "the phone is online, even when the app is closed. "
                          'Refused payments are tried again each time.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OutboxHeader extends StatelessWidget {
  const _OutboxHeader();

  @override
  Widget build(BuildContext context) {
    final gradients = AppGradients.of(context);
    final textTheme = Theme.of(context).textTheme;

    return WashHeader(
      child: Row(
        children: [
          BackButton(color: gradients.panelText),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Outbox',
                  key: const Key('outbox.title'),
                  style: textTheme.titleLarge?.copyWith(
                    color: gradients.panelText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  "Payments the server doesn't have yet",
                  style: textTheme.bodyMedium
                      ?.copyWith(color: gradients.panelTextSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel.refused({required this.count})
      : _refused = true;
  const _SectionLabel.waiting({required this.count})
      : _refused = false;

  final int count;
  final bool _refused;

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final color = _refused ? status.danger : status.warning;
    return Row(
      children: [
        Icon(_refused ? Icons.block : Icons.schedule, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _refused
                ? 'Refused ($count) · report to your admin'
                : 'Waiting to send ($count)',
            key: Key(_refused ? 'outbox.refusedLabel' : 'outbox.waitingLabel'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

/// Member, type and amount: the first line of every outbox row.
class _PaymentLine extends StatelessWidget {
  const _PaymentLine({required this.payment, this.trailing});

  final OutboxPayment payment;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(payment.memberName, style: textTheme.titleSmall),
              Text(
                '${payment.type.label} · ${payment.accountNumber}',
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              payment.amount.format(),
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (trailing != null) ...[const SizedBox(height: 4), trailing!],
          ],
        ),
      ],
    );
  }
}

class _RefusedRow extends StatelessWidget {
  const _RefusedRow({super.key, required this.payment});

  final OutboxPayment payment;

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final refusedAt = payment.refusedAt;
    final triedAt = payment.lastTriedAt;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PaymentLine(payment: payment),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.block, size: 16, color: status.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    payment.refusalReason!,
                    style: textTheme.bodyMedium?.copyWith(color: status.danger),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                'Recorded ${clockTime(payment.recordedAt)}',
                if (refusedAt != null) 'refused ${clockTime(refusedAt)}',
                if (triedAt != null && triedAt != refusedAt)
                  'last tried ${clockTime(triedAt)}',
              ].join(' · '),
              style:
                  textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaitingRow extends StatelessWidget {
  const _WaitingRow({super.key, required this.payment, required this.now});

  final OutboxPayment payment;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final left = payment.timeLeft(now);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _PaymentLine(
          payment: payment,
          trailing: DecoratedBox(
            decoration: BoxDecoration(
              color: status.warningContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    left > Duration.zero ? Icons.schedule : Icons.cloud_off,
                    size: 14,
                    color: status.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    outboxStatusLabel(left),
                    style: TextStyle(
                      color: status.warning,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyOutbox extends StatelessWidget {
  const _EmptyOutbox();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          children: [
            Icon(Icons.cloud_done_outlined,
                size: 32, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              'Everything has been sent',
              key: const Key('outbox.empty'),
              style: textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Payments saved on this phone without a connection show here '
              'until the server has them.',
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

/// "09:42" in the phone's time zone.
String clockTime(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}';
}
