import 'package:cash_client/api/api_exception.dart';
import 'package:cash_client/collector/member_cache.dart';
import 'package:cash_client/collector/member_directory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/fakes.dart';

void main() {
  final savedAt = DateTime(2026, 11, 15, 8, 12);

  test('refresh downloads the list and saves it', () async {
    final cache = MemoryMemberCache();
    final directory = MemberDirectory(
      api: FakeCollectorBackend.working().api,
      cache: cache,
      now: () => savedAt,
    );

    final fresh = await directory.refresh();

    expect(fresh.members, hasLength(2));
    expect(cache.saved?.members, hasLength(2));
    expect(cache.saved?.savedAt, savedAt);
  });

  test('a failed refresh leaves the saved list alone', () async {
    final cache = MemoryMemberCache(
      SavedMembers(members: const [amaOwusu], savedAt: savedAt),
    );
    final directory = MemberDirectory(
      api: FakeCollectorBackend(
        (_) => http.Response(errorBody(500, 'Down'), 500),
      ).api,
      cache: cache,
    );

    await expectLater(directory.refresh(), throwsA(isA<ApiException>()));
    expect((await directory.saved())?.members, [amaOwusu]);
  });

  test('clear forgets the list', () async {
    final cache = MemoryMemberCache(
      SavedMembers(members: const [amaOwusu], savedAt: savedAt),
    );
    final directory =
        MemberDirectory(api: FakeCollectorBackend.working().api, cache: cache);

    await directory.clear();

    expect(await directory.saved(), isNull);
  });

  test('search matches names and account numbers', () {
    const members = [amaOwusu, yawBoateng];
    expect(searchMembers(members, ''), members);
    expect(searchMembers(members, 'ama'), [amaOwusu]);
    expect(searchMembers(members, 'BOAT'), [yawBoateng]);
    expect(searchMembers(members, '9911'), [yawBoateng]);
    expect(searchMembers(members, '3002345678'), [amaOwusu]);
    expect(searchMembers(members, 'kwesi'), isEmpty);
  });
}
