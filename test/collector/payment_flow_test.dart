import 'dart:convert';

import 'package:cash_client/collector/collector_models.dart';
import 'package:cash_client/collector/confirm_payment_screen.dart';
import 'package:cash_client/collector/payment_flow.dart';
import 'package:cash_client/collector/payment_saved_screen.dart';
import 'package:cash_client/collector/record_payment_screen.dart';
import 'package:cash_client/common/money.dart';
import 'package:cash_client/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

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

    testWidgets('shows member, account and amount before sending',
        (tester) async {
      final backend = FakeCollectorBackend.working();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: ConfirmPaymentScreen(
          draft: draft,
          api: backend.api,
          onSaved: (_, _) {},
        ),
      ));

      expect(find.text('Ama Owusu'), findsOneWidget);
      expect(find.text('Account 1002345678'), findsOneWidget);
      expect(find.text('GH₵ 50.50'), findsOneWidget);
      expect(backend.paymentRequests, isEmpty);
    });

    testWidgets('a refused payment shows the backend reason', (tester) async {
      final backend = FakeCollectorBackend(
        (_) => http.Response(errorBody(403, "This member isn't in your branch"), 403),
      );
      CollectorPayment? saved;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: ConfirmPaymentScreen(
          draft: draft,
          api: backend.api,
          onSaved: (_, p) => saved = p,
        ),
      ));

      await tapKey(tester, 'confirm.record');

      expect(find.text("This member isn't in your branch"), findsOneWidget);
      expect(saved, isNull);
    });

    testWidgets('after a dropped connection, retrying reuses the same key',
        (tester) async {
      var dropped = true;
      final backend = FakeCollectorBackend((request) {
        if (dropped) throw http.ClientException('reset');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          paymentBody(idempotencyKey: body['idempotencyKey'] as String),
          200,
        );
      });
      CollectorPayment? saved;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: ConfirmPaymentScreen(
          draft: draft,
          api: backend.api,
          onSaved: (_, p) => saved = p,
        ),
      ));

      await tapKey(tester, 'confirm.record');
      expect(find.textContaining("won't be recorded twice"), findsOneWidget);

      dropped = false;
      await tapKey(tester, 'confirm.record');

      expect(saved, isNotNull);
      final keys = [
        for (final r in backend.requests)
          (jsonDecode(r.body) as Map<String, dynamic>)['idempotencyKey'],
      ];
      expect(keys, hasLength(2));
      expect(keys.toSet(), hasLength(1));
    });
  });

  group('saved screen', () {
    final payment = CollectorPayment.fromJson(
      jsonDecode(paymentBody(idempotencyKey: 'k')),
    )!;

    testWidgets('counts down the correction window', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: PaymentSavedScreen(payment: payment, onDone: () {}),
      ));

      expect(find.text('Payment saved'), findsOneWidget);
      expect(find.text('GH₵ 50.00'), findsOneWidget);
      expect(find.textContaining('Pending · 10:00 left'), findsOneWidget);
    });

    test('countdown reads minutes and seconds', () {
      expect(formatCountdown(const Duration(minutes: 9, seconds: 58)), '9:58');
      expect(formatCountdown(const Duration(seconds: 5)), '0:05');
    });
  });

  testWidgets('the whole flow: choose, enter, confirm, saved, done',
      (tester) async {
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
                api: services.collectorApi,
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

    // The saved screen's countdown ticks every second, so pumpAndSettle
    // would run through the whole 10 minutes; step with fixed pumps instead.
    await tester.tap(find.byKey(const Key('confirm.record')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Payment saved'), findsOneWidget);

    // Back from the saved screen goes home, never to the confirm screen.
    await tester.tap(find.byKey(const Key('saved.done')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Confirm payment'), findsNothing);
  });
}
