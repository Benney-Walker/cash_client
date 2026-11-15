import 'package:flutter/material.dart';

import '../common/gradient_button.dart';
import '../theme/app_gradients.dart';
import '../theme/app_status_colors.dart';
import 'collector_api.dart';
import 'collector_models.dart';
import 'idempotency.dart';
import 'record_payment_screen.dart';

/// The check before anything is sent: member, account and amount.
///
/// Paying into the wrong account is the costliest mistake a collector can
/// make, so the payment is only sent from here.
class ConfirmPaymentScreen extends StatefulWidget {
  const ConfirmPaymentScreen({
    super.key,
    required this.draft,
    required this.api,
    required this.onSaved,
  });

  final PaymentDraft draft;
  final CollectorApi api;
  final void Function(BuildContext context, CollectorPayment payment) onSaved;

  @override
  State<ConfirmPaymentScreen> createState() => _ConfirmPaymentScreenState();
}

class _ConfirmPaymentScreenState extends State<ConfirmPaymentScreen> {
  // One key for this payment, made when the screen opens and reused on every
  // retry, so a request that reached the backend before a connection dropped
  // isn't recorded twice. Editing goes back a screen and makes a new
  // payment, with a new key.
  final String _idempotencyKey = newIdempotencyKey();

  bool _sending = false;
  String? _error;

  Future<void> _record() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final draft = widget.draft;
      final payment = await widget.api.recordPayment(
        idempotencyKey: _idempotencyKey,
        type: draft.type,
        accountNumber: draft.account.accountNumber,
        amount: draft.amount,
        description: draft.note,
      );
      if (!mounted) return;
      widget.onSaved(context, payment);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = collectorErrorMessage(
          error,
          // The request may or may not have reached the backend. Retrying
          // with the same key is safe either way.
          networkMessage: "Couldn't confirm the payment was saved. Check "
              "your connection and tap Record payment again. It won't be "
              'recorded twice.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final gradients = AppGradients.of(context);
    final secondary =
        textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm payment')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Member', style: secondary),
                  Text(
                    draft.member.name,
                    key: const Key('confirm.memberName'),
                    style: textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(draft.type.description, style: secondary),
                  Text(
                    'Account ${draft.account.accountNumber}',
                    key: const Key('confirm.account'),
                    style: textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  Text('Amount', style: secondary),
                  Text(
                    draft.amount.format(),
                    key: const Key('confirm.amount'),
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (draft.note != null) ...[
                    const SizedBox(height: 12),
                    Text('Note', style: secondary),
                    Text(draft.note!, style: textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 20),
          GradientButton(
            key: const Key('confirm.record'),
            // Stays enabled while sending so the spinner sits on the full
            // gradient; _record ignores repeat taps.
            onPressed: _record,
            child: _sending
                ? SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: gradients.onButton,
                      semanticsLabel: 'Recording payment',
                    ),
                  )
                : const Text('Record payment'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('confirm.edit'),
            onPressed: _sending ? null : () => Navigator.of(context).pop(),
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

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
              Icon(Icons.error_outline, color: status.danger, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  key: const Key('confirm.error'),
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
