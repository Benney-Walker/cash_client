import 'package:cash_client/outbox/outbox.dart';
import 'package:cash_client/outbox/outbox_screen.dart';
import 'package:cash_client/outbox/outbox_store.dart';
import 'package:cash_client/sync/payment_sync.dart';
import 'package:cash_client/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  final now = DateTime.utc(2026, 11, 15, 10, 30);

  Future<Outbox> pumpOutbox(
    WidgetTester tester,
    MemoryOutboxStore store, {
    Future<SyncReport> Function()? onSync,
    void Function(OutboxPayment payment)? onCorrect,
  }) async {
    final outbox =
        Outbox(store: store, staffId: () => 'STF001', now: () => now);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: OutboxScreen(
        outbox: outbox,
        onSync: onSync ?? () async => SyncReport.nothing,
        onCorrect: onCorrect,
      ),
    ));
    await tester.pump();
    return outbox;
  }

  testWidgets('refused payments come first with the backend reason',
      (tester) async {
    final store = MemoryOutboxStore([
      queuedPayment(
        key: 'w',
        memberName: 'Yaw Boateng',
        createdAt: now.subtract(const Duration(minutes: 2)),
      ),
      queuedPayment(
        key: 'r',
        createdAt: now.subtract(const Duration(minutes: 30)),
        refusalReason: "This member's first deposit must be made at the office",
      ),
    ]);
    await pumpOutbox(tester, store);

    expect(find.text('Refused (1) · report to your admin'), findsOneWidget);
    expect(
      find.text("This member's first deposit must be made at the office"),
      findsOneWidget,
    );
    expect(find.text('On this phone (1)'), findsOneWidget);
    // Recorded 2 minutes ago: 3 minutes left to correct.
    expect(find.text('Can correct · 3:00'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('outbox.refused.0'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('outbox.waiting.0'))).dy),
    );
  });

  testWidgets('a due payment waits for a connection', (tester) async {
    final store = MemoryOutboxStore([
      queuedPayment(createdAt: now.subtract(const Duration(minutes: 12))),
    ]);
    await pumpOutbox(tester, store, onCorrect: (_) {});

    expect(find.text('Sends when online'), findsOneWidget);
    // Try again belongs to refused payments only, and the 5 minutes to
    // correct are over.
    expect(find.byKey(const Key('outbox.tryAgain')), findsNothing);
    expect(find.byKey(const Key('outbox.correct.0')), findsNothing);
  });

  testWidgets('a payment in its 5 minutes can be corrected from here',
      (tester) async {
    final store = MemoryOutboxStore([
      queuedPayment(createdAt: now.subtract(const Duration(minutes: 1))),
    ]);
    OutboxPayment? corrected;
    await pumpOutbox(tester, store, onCorrect: (p) => corrected = p);

    await tester.tap(find.byKey(const Key('outbox.correct.0')));

    expect(corrected?.idempotencyKey, 'key-1');
  });

  testWidgets('a refused payment has no Correct, only Try again',
      (tester) async {
    final store = MemoryOutboxStore([
      queuedPayment(
        createdAt: now.subtract(const Duration(minutes: 1)),
        refusalReason: 'Account 1002345678 is not active',
      ),
    ]);
    await pumpOutbox(tester, store, onCorrect: (_) {});

    expect(find.text('Correct'), findsNothing);
    expect(find.byKey(const Key('outbox.tryAgain')), findsOneWidget);
  });

  testWidgets('Try again runs a sync and says what happened', (tester) async {
    final store = MemoryOutboxStore([
      queuedPayment(
        createdAt: now.subtract(const Duration(minutes: 30)),
        refusalReason: 'Account 1002345678 is not active',
      ),
    ]);
    var syncs = 0;
    await pumpOutbox(
      tester,
      store,
      onSync: () async {
        syncs++;
        return const SyncReport(offline: true);
      },
    );

    await tester.tap(find.byKey(const Key('outbox.tryAgain')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(syncs, 1);
    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
  });

  testWidgets('an empty outbox says everything has been sent',
      (tester) async {
    await pumpOutbox(tester, MemoryOutboxStore());

    expect(find.byKey(const Key('outbox.empty')), findsOneWidget);
  });
}
