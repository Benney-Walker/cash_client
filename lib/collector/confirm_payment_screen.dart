import 'package:flutter/material.dart';

import '../common/gradient_button.dart';
import '../location/location_tracker.dart';
import '../outbox/outbox_store.dart';
import '../theme/app_gradients.dart';
import '../theme/app_status_colors.dart';
import 'idempotency.dart';
import 'record_payment_screen.dart';

/// The check before the payment is kept: member, account and amount.
///
/// Paying into the wrong account is the costliest mistake a collector can
/// make, so the payment is only recorded from here. It's saved on the phone
/// and held for 5 minutes, when it can still be corrected, then sent (owner
/// decision 2026-11-23); the backend's answer, including any refusal, comes
/// then, through the Outbox. Recording also takes the payment's location
/// point, which can take up to 20 seconds; without a location the payment
/// isn't saved and the reason shows here.
class ConfirmPaymentScreen extends StatefulWidget {
  const ConfirmPaymentScreen({
    super.key,
    required this.draft,
    required this.save,
    required this.onSaved,
  });

  final PaymentDraft draft;

  /// Keeps the payment in the outbox under this screen's idempotency key.
  final Future<OutboxPayment> Function(PaymentDraft draft, String key) save;
  final void Function(BuildContext context, OutboxPayment payment) onSaved;

  @override
  State<ConfirmPaymentScreen> createState() => _ConfirmPaymentScreenState();
}

class _ConfirmPaymentScreenState extends State<ConfirmPaymentScreen> {
  // One key for this payment, made when the screen opens: it goes with
  // every send, so the backend never records the payment twice. Saving the
  // same key twice keeps one copy. Editing goes back a screen and makes a
  // new payment, with a new key.
  final String _idempotencyKey = newIdempotencyKey();

  bool _saving = false;
  String? _error;

  Future<void> _record() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.save(widget.draft, _idempotencyKey);
      if (!mounted) return;
      widget.onSaved(context, saved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // No location: nothing was saved, and the message says what to do.
        _error = error is LocationUnavailable
            ? error.message
            : "The payment couldn't be saved on this phone. Tap Record "
                "payment to try again. It won't be recorded twice.";
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
            // Stays enabled while saving so the spinner sits on the full
            // gradient; _record ignores repeat taps.
            onPressed: _record,
            child: _saving
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
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
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
