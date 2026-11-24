import 'dart:async';

import 'package:flutter/material.dart';

import '../outbox/outbox.dart';
import '../outbox/outbox_store.dart';
import '../theme/app_status_colors.dart';
import 'collector_models.dart';
import 'member_directory.dart';
import 'payment_saved_screen.dart';
import 'record_payment_screen.dart';

/// Opens the correction for a payment still in its 5 minutes (design C1,
/// owner decision 2026-11-24): the Record payment form, filled in, where
/// the collector can change the amount or move it to the member's other
/// account. The note stays as it was, and the 5 minutes don't restart.
///
/// The member's accounts come from the branch list saved on the phone; if
/// the member isn't in it any more, only the amount can change.
Future<void> openCorrection(
  BuildContext context, {
  required OutboxPayment payment,
  required Outbox outbox,
  required MemberDirectory directory,
}) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final member = await _memberFor(payment, directory);
  if (!payment.isCorrectable(outbox.now())) {
    messenger.showSnackBar(const SnackBar(content: Text(_tooLate)));
    return;
  }
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => _CorrectPaymentScreen(
        payment: payment,
        member: member,
        outbox: outbox,
        onDone: (message) {
          navigator.pop();
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(message)));
        },
      ),
    ),
  );
}

const _tooLate = "The 5 minutes are up, so this payment can't be changed. "
    "It's sent as it was.";

Future<CollectorMember> _memberFor(
  OutboxPayment payment,
  MemberDirectory directory,
) async {
  final saved = await directory.saved();
  for (final member in saved?.members ?? const <CollectorMember>[]) {
    if (member.accounts.any((a) => a.accountNumber == payment.accountNumber)) {
      return member;
    }
  }
  return CollectorMember(
    name: payment.memberName,
    accounts: [
      MemberAccount(accountNumber: payment.accountNumber, type: payment.type),
    ],
  );
}

class _CorrectPaymentScreen extends StatefulWidget {
  const _CorrectPaymentScreen({
    required this.payment,
    required this.member,
    required this.outbox,
    required this.onDone,
  });

  final OutboxPayment payment;
  final CollectorMember member;
  final Outbox outbox;
  final void Function(String message) onDone;

  @override
  State<_CorrectPaymentScreen> createState() => _CorrectPaymentScreenState();
}

class _CorrectPaymentScreenState extends State<_CorrectPaymentScreen> {
  Timer? _ticker;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _save(PaymentDraft draft) async {
    if (_saving) return;
    _saving = true;
    final payment = widget.payment;
    final unchanged = draft.account.accountNumber == payment.accountNumber &&
        draft.amount == payment.amount;
    if (unchanged) {
      widget.onDone('Nothing changed.');
      return;
    }
    bool saved;
    try {
      saved = await widget.outbox.correct(
        payment.idempotencyKey,
        account: draft.account,
        amount: draft.amount,
      );
    } catch (_) {
      saved = false;
    }
    if (!mounted) return;
    widget.onDone(saved ? 'Correction saved.' : _tooLate);
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.payment.timeLeft(widget.outbox.now());
    final status = AppStatusColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return RecordPaymentScreen(
      member: widget.member,
      title: 'Correct payment',
      actionLabel: 'Save correction',
      showNote: false,
      initialType: widget.payment.type,
      initialAmount: widget.payment.amount,
      banner: Row(
        children: [
          Icon(Icons.schedule, size: 18, color: status.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              left > Duration.zero
                  ? '${formatCountdown(left)} left to correct'
                  : "The 5 minutes are up: it's sent as it was",
              key: const Key('correct.timeLeft'),
              style: textTheme.bodyMedium?.copyWith(
                color: status.warning,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
      onContinue: (_, draft) => _save(draft),
    );
  }
}
