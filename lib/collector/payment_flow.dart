import 'package:flutter/material.dart';

import '../outbox/outbox.dart';
import '../outbox/outbox_store.dart';
import 'confirm_payment_screen.dart';
import 'correct_payment.dart';
import 'member_directory.dart';
import 'member_picker_screen.dart';
import 'payment_saved_screen.dart';
import 'record_payment_screen.dart';

/// Opens the record-payment flow (design P1): choose member → type and
/// amount → confirm → saved on the phone, held 5 minutes for corrections
/// (design C1), then sent.
///
/// [beforeSave] runs with the payment's idempotency key when the collector
/// taps Record payment, before it's saved: the app takes the payment's
/// location point there (D34). If it throws, the payment isn't saved and
/// the confirm screen shows why (`LocationUnavailable`'s message).
///
/// [onSaved] runs once a payment is in the outbox, so the sync can arrange
/// to send it when its 5 minutes are up.
///
/// The screens are pushed on top of the tabs, so if the session ends part
/// way through, the app's auth gate closes them all.
void startPaymentFlow(
  BuildContext context, {
  required MemberDirectory directory,
  required Outbox outbox,
  Future<void> Function(String idempotencyKey)? beforeSave,
  void Function(OutboxPayment payment)? onSaved,
}) {
  final navigator = Navigator.of(context);

  void goHome() => navigator.popUntil((route) => route.isFirst);

  Future<OutboxPayment> save(PaymentDraft draft, String key) async {
    await beforeSave?.call(key);
    final saved = await outbox.add(draft, idempotencyKey: key);
    onSaved?.call(saved);
    return saved;
  }

  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => MemberPickerScreen(
        directory: directory,
        onMemberChosen: (context, member) => navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => RecordPaymentScreen(
              member: member,
              onContinue: (context, draft) => navigator.push(
                MaterialPageRoute<void>(
                  builder: (_) => ConfirmPaymentScreen(
                    draft: draft,
                    save: save,
                    // The saved screen replaces the whole flow, so going
                    // back can't reach the confirm screen and record the
                    // payment again.
                    onSaved: (context, saved) => navigator.pushAndRemoveUntil(
                      MaterialPageRoute<void>(
                        builder: (_) => PaymentSavedScreen(
                          payment: saved,
                          outbox: outbox,
                          onCorrect: (payment) => openCorrection(
                            navigator.context,
                            payment: payment,
                            outbox: outbox,
                            directory: directory,
                          ),
                          onDone: goHome,
                        ),
                      ),
                      (route) => route.isFirst,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
