import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/gradient_wash.dart';
import '../theme/app_gradients.dart';
import '../theme/app_status_colors.dart';
import 'collector_models.dart';

/// Shown once the backend has saved the payment.
///
/// The payment is PENDING for its 10-minute correction window; the member's
/// balance and SMS follow when it closes (decision D39). The countdown runs
/// on the phone's monotonic clock from the window length the server sent,
/// so a wrong phone clock can't shorten or stretch it.
class PaymentSavedScreen extends StatefulWidget {
  const PaymentSavedScreen({
    super.key,
    required this.payment,
    required this.onDone,
  });

  final CollectorPayment payment;
  final VoidCallback onDone;

  @override
  State<PaymentSavedScreen> createState() => _PaymentSavedScreenState();
}

class _PaymentSavedScreenState extends State<PaymentSavedScreen> {
  final _clock = Stopwatch()..start();
  Timer? _ticker;

  Duration get _left {
    final left = widget.payment.correctionWindow - _clock.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  @override
  void initState() {
    super.initState();
    if (_left > Duration.zero) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (_left == Duration.zero) _ticker?.cancel();
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payment = widget.payment;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;
    final gradients = AppGradients.of(context);
    final status = AppStatusColors.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final left = _left;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: PopScope(
        // Back goes home, not to the confirm screen, so the same payment
        // can't be sent again by accident.
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
                      Icon(Icons.check_circle_outline,
                          size: 44, color: gradients.panelText),
                      const SizedBox(height: 8),
                      Text(
                        'Payment saved',
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
                      child: _PendingChip(left: left, status: status),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "The member's balance is updated and they get an SMS "
                      'when the 10 minutes are up.',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Account ${payment.accountNumber}',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
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

/// PENDING is a warning status: an icon and a label, never colour alone.
class _PendingChip extends StatelessWidget {
  const _PendingChip({required this.left, required this.status});

  final Duration left;
  final AppStatusColors status;

  @override
  Widget build(BuildContext context) {
    final label = left > Duration.zero
        ? 'Pending · ${formatCountdown(left)} left'
        : 'Pending · being applied';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: status.warningContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 16, color: status.warning),
            const SizedBox(width: 6),
            Text(
              label,
              key: const Key('saved.pending'),
              style: TextStyle(
                color: status.warning,
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

/// "9:58".
String formatCountdown(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
