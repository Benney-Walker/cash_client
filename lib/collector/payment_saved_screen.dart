import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/gradient_wash.dart';
import '../outbox/outbox.dart';
import '../outbox/outbox_store.dart';
import '../theme/app_gradients.dart';
import '../theme/app_status_colors.dart';

/// Shown once a payment is confirmed (design C1, owner decision
/// 2026-11-24): it's saved on the phone and held for 5 minutes.
///
/// During those minutes Correct reopens the filled-in payment form; there's
/// no cancelling (owner decision 2026-11-24). Then the payment is sent once
/// there's a connection. The screen follows the payment in the outbox, so a
/// correction shows here at once, and once the server has it the chip says
/// so: success only after the backend confirms it.
class PaymentSavedScreen extends StatefulWidget {
  const PaymentSavedScreen({
    super.key,
    required this.payment,
    required this.outbox,
    required this.onCorrect,
    required this.onDone,
  });

  /// The payment as it was saved; the outbox holds its latest version.
  final OutboxPayment payment;
  final Outbox outbox;
  final void Function(OutboxPayment payment) onCorrect;
  final VoidCallback onDone;

  @override
  State<PaymentSavedScreen> createState() => _PaymentSavedScreenState();
}

class _PaymentSavedScreenState extends State<PaymentSavedScreen> {
  Timer? _ticker;
  late OutboxPayment _payment = widget.payment;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    widget.outbox.addListener(_follow);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.outbox.removeListener(_follow);
    _ticker?.cancel();
    super.dispose();
  }

  void _follow() {
    final latest = widget.outbox.find(widget.payment.idempotencyKey);
    setState(() {
      if (latest != null) {
        _payment = latest;
        _sent = false;
      } else {
        // Gone from the outbox: the backend has it.
        _sent = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;
    final gradients = AppGradients.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final payment = _payment;
    final now = widget.outbox.now();
    final left = payment.timeLeft(now);
    final correctable = !_sent && payment.isCorrectable(now);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: PopScope(
        // Back goes home, not to the confirm screen, so the same payment
        // can't be recorded again by accident.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) widget.onDone();
        },
        child: Scaffold(
          body: ListView(
            padding: EdgeInsets.zero,
            children: [
              GradientWash(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(24)),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    MediaQuery.paddingOf(context).top + 32,
                    16,
                    28,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.phone_android_outlined,
                        size: 44,
                        color: gradients.panelText,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Saved on this phone',
                        key: const Key('saved.title'),
                        style: textTheme.titleLarge?.copyWith(
                          color: gradients.panelText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        payment.amount.format(),
                        key: const Key('saved.amount'),
                        style: textTheme.headlineMedium?.copyWith(
                          color: gradients.panelText,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        '${payment.type.description} · ${payment.memberName}',
                        key: const Key('saved.line'),
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium
                            ?.copyWith(color: gradients.panelTextSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _sent
                          ? const OutboxStatusChip.sent()
                          : OutboxStatusChip(payment: payment, now: now),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _sent
                          ? "The server has the payment. The member's balance "
                              'is updated and they get an SMS.'
                          : "It's kept on this phone for 5 minutes so you can "
                              "correct it, then sent once you're online. The "
                              "member's balance and SMS follow when the "
                              'server has it. You can follow it in Outbox on '
                              'the home screen.',
                      key: const Key('saved.explanation'),
                      style: textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Account ${payment.accountNumber}',
                      key: const Key('saved.account'),
                      style: textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    if (correctable) ...[
                      OutlinedButton(
                        key: const Key('saved.correct'),
                        onPressed: () => widget.onCorrect(payment),
                        child: Text(
                          'Correct · ${formatCountdown(left)} left',
                          style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    OutlinedButton(
                      key: const Key('saved.done'),
                      onPressed: widget.onDone,
                      child: const Text('Done'),
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

/// A payment's state on the phone, as an icon and a label, never colour
/// alone: "Can correct · 4:12" in its 5 minutes, "Sends when online" after,
/// "Refused" once the server turned it down, "Sent" once it has it.
class OutboxStatusChip extends StatelessWidget {
  const OutboxStatusChip({super.key, required this.payment, required this.now})
      : _sent = false;

  const OutboxStatusChip.sent({super.key})
      : payment = null,
        now = null,
        _sent = true;

  final OutboxPayment? payment;
  final DateTime? now;
  final bool _sent;

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final payment = this.payment;
    final IconData icon;
    final String label;
    final Color fg;
    final Color bg;
    if (_sent || payment == null) {
      icon = Icons.cloud_done_outlined;
      label = 'Sent';
      fg = status.success;
      bg = status.successContainer;
    } else if (payment.isRefused) {
      icon = Icons.block;
      label = 'Refused';
      fg = status.danger;
      bg = status.dangerContainer;
    } else {
      final at = now ?? DateTime.now();
      icon = payment.isCorrectable(at)
          ? Icons.schedule
          : Icons.cloud_upload_outlined;
      label = outboxStatusLabel(payment.timeLeft(at));
      fg = status.warning;
      bg = status.warningContainer;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              key: const Key('saved.status'),
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A held payment's status: "Can correct · 4:12" inside its 5 minutes,
/// then "Sends when online".
String outboxStatusLabel(Duration left) => left > Duration.zero
    ? 'Can correct · ${formatCountdown(left)}'
    : 'Sends when online';

/// "4:58".
String formatCountdown(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
