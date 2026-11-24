import 'package:cash_client/app_services.dart';
import 'package:cash_client/collector/collector_models.dart';
import 'package:cash_client/collector/confirm_payment_screen.dart';
import 'package:cash_client/collector/payment_flow.dart';
import 'package:cash_client/collector/payment_saved_screen.dart';
import 'package:cash_client/collector/record_payment_screen.dart';
import 'package:cash_client/common/money.dart';
import 'package:cash_client/outbox/outbox.dart';
import 'package:cash_client/outbox/outbox_store.dart';
import 'package:cash_client/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Future<void> tapKey(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  group('record payment screen', () {
    PaymentDraft? draft;

    Future<void> pumpForm(WidgetTester tester, CollectorMember member) async {
      draft = null;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RecordPaymentScreen(
            member: member,
            onContinue: (_, d) => draft = d,
          ),
        ),
      );
    }

    testWidgets('starts on savings and shows the account number',
        (tester) async {
      await pumpForm(tester, amaOwusu);

      expect(find.text('Ama Owusu'), findsOneWidget);
      expect(find.text('Savings deposit · account 1002345678'), findsOneWidget);
    });

    testWidgets('switching to shares uses the shares account', (tester) async {
      await pumpForm(tester, amaOwusu);

      await tester.tap(find.text('Shares'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('record.amount')), '20');
      await tapKey(tester, 'record.continue');

      expect(draft?.type, PaymentType.shares);
      expect(draft?.account.accountNumber, '3002345678');
      expect(draft?.amount, const Cedis.pesewas(2000));
    });

    testWidgets('a member with only savings gets no shares choice',
        (tester) async {
      await pumpForm(tester, yawBoateng);

      expect(find.text('Shares'), findsNothing);
      expect(find.text('Savings'), findsOneWidget);
    });

    testWidgets('the amount is required and must be more than zero',
        (tester) async {
      await pumpForm(tester, amaOwusu);

      await tapKey(tester, 'record.continue');
      expect(find.text('Enter the amount'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('record.amount')), '0.00');
      await tapKey(tester, 'record.continue');
      expect(find.text('The amount must be more than GH₵ 0.00'), findsOneWidget);
      expect(draft, isNull);
    });

    testWidgets('only cedis and pesewas can be typed', (tester) async {
      await pumpForm(tester, amaOwusu);

      await tester.enterText(find.byKey(const Key('record.amount')), '12.345');
      await tester.pump();

      final field = tester.widget<EditableText>(find.descendant(
        of: find.byKey(const Key('record.amount')),
        matching: find.byType(EditableText),
      ));
      expect(field.controller.text, isNot('12.345'));
    });

    testWidgets('continue passes the amount and trimmed note', (tester) async {
      await pumpForm(tester, amaOwusu);

      await tester.enterText(find.byKey(const Key('record.amount')), '50.5');
      await tester.enterText(find.byKey(const Key('record.note')), ' Paid in coins ');
      await tapKey(tester, 'record.continue');

      expect(draft?.amount, const Cedis.pesewas(5050));
      expect(draft?.note, 'Paid in coins');
      expect(draft?.type, PaymentType.savings);
    });
  });

  group('confirm screen', () {
    const draft = PaymentDraft(
      member: amaOwusu,
      account:
          MemberAccount(accountNumber: '1002345678', type: PaymentType.savings),
      amount: Cedis.pesewas(5050),
    );

    testWidgets('shows member, account and amount, and keeps nothing yet',
        (tester) async {
      var saves = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: ConfirmPaymentScreen(
          draft: draft,
          save: (_, _) async {
            saves++;
            return queuedPayment(createdAt: DateTime.utc(2026, 11, 15, 10));
          },
          onSaved: (_, _) {},
        ),
      ));

      expect(find.text('Ama Owusu'), findsOneWidget);
      expect(find.text('Account 1002345678'), findsOneWidget);
      expect(find.text('GH₵ 50.50'), findsOneWidget);
      expect(saves, 0);
    });

    testWidgets('Record payment saves it on the phone under one key',
        (tester) async {
      String? savedKey;
      OutboxPayment? saved;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: ConfirmPaymentScreen(
          draft: draft,
          save: (d, key) async {
            savedKey = key;
            return queuedPayment(
              key: key,
              createdAt: DateTime.utc(2026, 11, 15, 10),
            );
          },
          onSaved: (_, p) => saved = p,
        ),
      ));

      await tapKey(tester, 'confirm.record');

      expect(savedKey, isNotNull);
      expect(saved?.idempotencyKey, savedKey);
    });

    testWidgets('if saving fails, trying again uses the same key',
        (tester) async {
      final keys = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: ConfirmPaymentScreen(
          draft: draft,
          save: (_, key) async {
            keys.add(key);
            throw StateError('disk full');
          },
          onSaved: (_, _) {},
        ),
      ));

      await tapKey(tester, 'confirm.record');
      expect(find.textContaining("couldn't be saved on this phone"),
          findsOneWidget);
      await tapKey(tester, 'confirm.record');

      expect(keys, hasLength(2));
      expect(keys.toSet(), hasLength(1));
    });
  });

  group('saved screen', () {
    final recorded = DateTime.utc(2026, 11, 15, 10);
    late MemoryOutboxStore store;

    Future<Outbox> pumpSaved(
      WidgetTester tester, {
      required DateTime now,
      void Function(OutboxPayment)? onCorrect,
    }) async {
      final payment = queuedPayment(createdAt: recorded);
      store = MemoryOutboxStore([payment]);
      final outbox = Outbox(
        store: store,
        staffId: () => 'STF001',
        now: () => now,
      );
      await outbox.refresh();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: PaymentSavedScreen(
          payment: payment,
          outbox: outbox,
          onCorrect: onCorrect ?? (_) {},
          onDone: () {},
        ),
      ));
      return outbox;
    }

    testWidgets('holds the payment 5 minutes with Correct', (tester) async {
      OutboxPayment? corrected;
      await pumpSaved(
        tester,
        now: recorded.add(const Duration(minutes: 1, seconds: 30)),
        onCorrect: (p) => corrected = p,
      );

      expect(find.text('Saved on this phone'), findsOneWidget);
      expect(find.text('GH₵ 50.00'), findsOneWidget);
      expect(find.text('Can correct · 3:30'), findsOneWidget);
      expect(find.byKey(const Key('saved.cancel')), findsNothing);

      await tester.tap(find.byKey(const Key('saved.correct')));
      expect(corrected?.idempotencyKey, 'key-1');
    });

    testWidgets('after the 5 minutes there is nothing left to correct',
        (tester) async {
      await pumpSaved(tester, now: recorded.add(const Duration(minutes: 6)));

      expect(find.text('Sends when online'), findsOneWidget);
      expect(find.byKey(const Key('saved.correct')), findsNothing);
    });

    testWidgets('once the server has it, the screen says Sent',
        (tester) async {
      final outbox =
          await pumpSaved(tester, now: recorded.add(const Duration(minutes: 6)));
      // The sync removed it from the outbox.
      await store.remove('key-1');
      await outbox.refresh();
      await tester.pump();

      expect(find.text('Sent'), findsOneWidget);
    });

    test('countdown reads minutes and seconds', () {
      expect(formatCountdown(const Duration(minutes: 4, seconds: 58)), '4:58');
      expect(formatCountdown(const Duration(seconds: 5)), '0:05');
    });
  });

  group('the whole flow', () {
    Future<AppServices> pumpFlow(WidgetTester tester) async {
      final services = testServices();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => startPaymentFlow(
                  context,
                  directory: services.members,
                  outbox: services.outbox,
                ),
                child: const Text('Home'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ama Owusu'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('record.amount')), '50');
      await tapKey(tester, 'record.continue');
      expect(find.text('Confirm payment'), findsOneWidget);
      await tapKey(tester, 'confirm.record');
      return services;
    }

    testWidgets('choose, enter, confirm: held on the phone, nothing sent',
        (tester) async {
      final services = await pumpFlow(tester);

      expect(find.text('Saved on this phone'), findsOneWidget);
      expect(services.outbox.items.single.amount, const Cedis.pesewas(5000));

      // Back from the saved screen goes home, never to the confirm screen.
      await tapKey(tester, 'saved.done');
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Confirm payment'), findsNothing);
    });

    testWidgets('a correction moves it to shares and changes the amount',
        (tester) async {
      final services = await pumpFlow(tester);

      await tapKey(tester, 'saved.correct');
      expect(find.text('Correct payment'), findsOneWidget);
      expect(find.byKey(const Key('record.note')), findsNothing);
      expect(find.byKey(const Key('correct.timeLeft')), findsOneWidget);

      await tester.tap(find.text('Shares'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('record.amount')), '60');
      await tapKey(tester, 'record.continue');

      expect(find.text('Correction saved.'), findsOneWidget);
      expect(find.text('GH₵ 60.00'), findsOneWidget);
      final held = services.outbox.items.single;
      expect(held.type, PaymentType.shares);
      expect(held.accountNumber, '3002345678');
      expect(held.amount, const Cedis.pesewas(6000));
      expect(held.updatedAt.isAfter(held.createdAt) ||
          held.updatedAt == held.createdAt, isTrue);
    });
  });
}
