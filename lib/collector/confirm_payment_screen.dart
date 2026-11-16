import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../common/gradient_button.dart';
import '../outbox/outbox_store.dart';
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
///
/// Without a connection, the payment is saved on the phone instead and sent
/// later (app spec 2.3). When the backend refuses it, its reason is shown
/// here word for word and nothing is saved.
class ConfirmPaymentScreen extends StatefulWidget {
  const ConfirmPaymentScreen({
    super.key,
    required this.draft,
    required this.api,
    required this.onSaved,
    required this.saveOffline,
    required this.onSavedOffline,
  });

  final PaymentDraft draft;
  final CollectorApi api;
  final void Function(BuildContext context, CollectorPayment payment) onSaved;

  /// Keeps the payment in the outbox, with this screen's idempotency key.
  final Future<OutboxPayment> Function(PaymentDraft draft, String key)
      saveOffline;
  final void Function(BuildContext context, OutboxPayment payment)
      onSavedOffline;

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
      if (_couldNotReachBackend(error)) {
        await _keepOnPhone();
        return;
      }
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = collectorErrorMessage(
          error,
          networkMessage: "Couldn't reach the server. Try again.",
        );
      });
    }
  }

  /// No connection, a timeout or a server fault. The request may or may not
  /// have reached the backend; either way it's saved on the phone with the
  /// same key, so the sync either gets the saved payment back or records
  /// it, never both.
  static bool _couldNotReachBackend(Object error) =>
      error is ApiException &&
      (error.failure == ApiFailure.network ||
          error.failure == ApiFailure.server);

  Future<void> _keepOnPhone() async {
    try {
      final queued = await widget.saveOffline(widget.draft, _idempotencyKey);
      if (!mounted) return;
      widget.onSavedOffline(context, queued);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = "The server couldn't be reached and the payment couldn't "
            "be saved on this phone. Tap Record payment to try again. It "
            "won't be recorded twice.";
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
