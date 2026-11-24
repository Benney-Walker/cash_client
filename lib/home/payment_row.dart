import 'package:flutter/material.dart';

import '../collector/payment_saved_screen.dart';
import '../common/names.dart';
import '../theme/app_status_colors.dart';
import 'today.dart';

/// "10:42", in the phone's time (Ghana is UTC).
String clockTime(DateTime time) {
  final t = time.toLocal();
  return '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}

/// A payment in a list (home's Recent, History): the member's initials and
/// name, Savings or Shares, the account and time, the amount, and where it
/// stands. A failed payment can show the server's reason beneath.
class PaymentRow extends StatelessWidget {
  const PaymentRow({
    super.key,
    required this.payment,
    required this.now,
    this.onTap,
    this.showFailureReason = false,
  });

  final RecentPayment payment;
  final DateTime now;
  final VoidCallback? onTap;

  /// History shows why a payment failed; home keeps rows to one size.
  final bool showFailureReason;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final phone = payment.phonePayment;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            ExcludeSemantics(
              child: CircleAvatar(
                radius: 18,
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  initials(payment.memberName),
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName(payment.memberName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyLarge,
                  ),
                  Text(
                    '${payment.type.label} · ${payment.accountNumber} · '
                    '${clockTime(payment.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (showFailureReason &&
                      payment.state == RecentState.failed &&
                      payment.failureReason != null)
                    Text(
                      payment.failureReason!,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppStatusColors.of(context).danger,
                      ),
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
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                if (phone != null)
                  OutboxStatusChip(payment: phone, now: now)
                else
                  ServerStatusChip(state: payment.state),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Where a payment the server has stands: icon and word, never colour
/// alone.
class ServerStatusChip extends StatelessWidget {
  const ServerStatusChip({required this.state});

  final RecentState state;

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final (IconData icon, String label, Color fg, Color bg) = switch (state) {
      RecentState.completed => (
          Icons.check_circle_outline,
          'Completed',
          status.success,
          status.successContainer,
        ),
      RecentState.failed => (
          Icons.cancel_outlined,
          'Failed',
          status.danger,
          status.dangerContainer,
        ),
      _ => (
          Icons.cloud_done_outlined,
          'Received',
          status.neutral,
          status.neutralContainer,
        ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 3),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
