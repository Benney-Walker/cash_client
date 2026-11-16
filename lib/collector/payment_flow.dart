import 'package:flutter/material.dart';

import '../outbox/outbox_store.dart';
import 'collector_api.dart';
import 'confirm_payment_screen.dart';
import 'member_directory.dart';
import 'member_picker_screen.dart';
import 'payment_saved_screen.dart';
import 'record_payment_screen.dart';

/// Opens the record-payment flow (design P1): choose member → type and
/// amount → confirm → saved (by the backend, or on the phone when there's
/// no connection).
///
/// The screens are pushed on top of the tabs, so if the session ends part
/// way through, the app's auth gate closes them all.
void startPaymentFlow(
  BuildContext context, {
  required MemberDirectory directory,
  required CollectorApi api,
  required Future<OutboxPayment> Function(PaymentDraft draft, String key)
      saveOffline,
}) {
  final navigator = Navigator.of(context);

  void goHome() => navigator.popUntil((route) => route.isFirst);

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
                    api: api,
                    // The saved screen replaces the whole flow, so going
                    // back can't reach the confirm screen and send the
                    // payment again.
                    onSaved: (context, payment) => navigator.pushAndRemoveUntil(
                      MaterialPageRoute<void>(
                        builder: (_) => PaymentSavedScreen(
                          payment: payment,
                          onDone: goHome,
                        ),
                      ),
                      (route) => route.isFirst,
                    ),
                    saveOffline: saveOffline,
                    onSavedOffline: (context, queued) =>
                        navigator.pushAndRemoveUntil(
                      MaterialPageRoute<void>(
                        builder: (_) => PaymentSavedScreen.queued(
                          payment: queued,
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
