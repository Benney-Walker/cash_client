import 'package:cash_client/collector/collector_models.dart';
import 'package:cash_client/collector/member_cache.dart';
import 'package:cash_client/collector/member_directory.dart';
import 'package:cash_client/collector/member_picker_screen.dart';
import 'package:cash_client/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fakes.dart';

void main() {
  final savedAt = DateTime(2026, 11, 15, 8, 12);
  CollectorMember? chosen;

  Future<void> pumpPicker(
    WidgetTester tester, {
    required FakeCollectorBackend backend,
    MemoryMemberCache? cache,
  }) async {
    chosen = null;
    final directory = MemberDirectory(
      api: backend.api,
      cache: cache ?? MemoryMemberCache(),
      now: () => savedAt,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MemberPickerScreen(
          directory: directory,
          onMemberChosen: (_, member) => chosen = member,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the downloaded branch list with account types',
      (tester) async {
    await pumpPicker(tester, backend: FakeCollectorBackend.working());

    expect(find.text('Ama Owusu'), findsOneWidget);
    expect(find.text('Savings · Shares'), findsOneWidget);
    expect(find.text('Yaw Boateng'), findsOneWidget);
    expect(find.text('Savings'), findsOneWidget);
    expect(find.byKey(const Key('picker.savedAt')), findsOneWidget);
  });

  testWidgets('search narrows the list by name or account number',
      (tester) async {
    await pumpPicker(tester, backend: FakeCollectorBackend.working());

    await tester.enterText(find.byKey(const Key('picker.search')), '9911');
    await tester.pump();

    expect(find.text('Yaw Boateng'), findsOneWidget);
    expect(find.text('Ama Owusu'), findsNothing);

    await tester.enterText(find.byKey(const Key('picker.search')), 'zzz');
    await tester.pump();
    expect(find.text('No member matches that search.'), findsOneWidget);
  });

  testWidgets('tapping a member chooses them', (tester) async {
    await pumpPicker(tester, backend: FakeCollectorBackend.working());

    await tester.tap(find.text('Ama Owusu'));

    expect(chosen, amaOwusu);
  });

  testWidgets('offline, the saved list is shown with a notice',
      (tester) async {
    await pumpPicker(
      tester,
      backend: FakeCollectorBackend(
        (_) => throw http.ClientException('no connection'),
      ),
      cache: MemoryMemberCache(
        SavedMembers(members: const [amaOwusu], savedAt: savedAt),
      ),
    );

    expect(find.text('Ama Owusu'), findsOneWidget);
    expect(find.byKey(const Key('picker.stale')), findsOneWidget);
    expect(find.textContaining("Couldn't update the list"), findsOneWidget);
  });

  testWidgets('offline with nothing saved offers a retry', (tester) async {
    var online = false;
    final backend = FakeCollectorBackend((request) {
      if (!online) throw http.ClientException('no connection');
      return http.Response(membersBody(const [amaOwusu]), 200);
    });
    await pumpPicker(tester, backend: backend);

    expect(find.text("Couldn't load your branch's members"), findsOneWidget);

    online = true;
    await tester.tap(find.byKey(const Key('picker.retry')));
    await tester.pumpAndSettle();

    expect(find.text('Ama Owusu'), findsOneWidget);
  });

  testWidgets('members with the same name show their account numbers',
      (tester) async {
    const otherAma = CollectorMember(
      name: 'Ama Owusu',
      accounts: [
        MemberAccount(accountNumber: '1009999999', type: PaymentType.savings),
      ],
    );
    await pumpPicker(
      tester,
      backend: FakeCollectorBackend.working(members: const [amaOwusu, otherAma]),
    );

    expect(find.text('Savings 1002345678 · Shares 3002345678'), findsOneWidget);
    expect(find.text('Savings 1009999999'), findsOneWidget);
  });

  testWidgets('an empty branch says so', (tester) async {
    await pumpPicker(
      tester,
      backend: FakeCollectorBackend.working(members: const []),
    );

    expect(find.text('No members in your branch yet'), findsOneWidget);
  });

  test('saved time reads as a time today, or a date otherwise', () {
    final now = DateTime(2026, 11, 15, 12);
    expect(describeSavedAt(DateTime(2026, 11, 15, 8, 5), now: now), '08:05');
    expect(describeSavedAt(DateTime(2026, 11, 14, 17, 30), now: now),
        '14 Nov, 17:30');
  });
}
