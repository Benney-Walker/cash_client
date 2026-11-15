import 'collector_api.dart';
import 'collector_models.dart';
import 'member_cache.dart';

/// The branch member list: the saved copy straight away, and a fresh one
/// from the backend when there's a connection.
class MemberDirectory {
  MemberDirectory({
    required CollectorApi api,
    required MemberCache cache,
    DateTime Function()? now,
  })  : _api = api,
        _cache = cache,
        _now = now ?? DateTime.now;

  final CollectorApi _api;
  final MemberCache _cache;
  final DateTime Function() _now;

  /// The list saved on the phone, or null if there isn't one yet.
  Future<SavedMembers?> saved() async {
    try {
      return await _cache.read();
    } catch (_) {
      // A damaged or unreadable local list is no worse than none: the
      // picker downloads a fresh one.
      return null;
    }
  }

  /// Downloads the list and saves it. Throws the API's [ApiException] when
  /// it can't; the saved copy is left as it was.
  Future<SavedMembers> refresh() async {
    final members = await _api.fetchMembers();
    final savedAt = _now();
    try {
      await _cache.save(members, savedAt);
    } catch (_) {
      // Still usable for this session even if it couldn't be stored.
    }
    return SavedMembers(members: members, savedAt: savedAt);
  }

  Future<void> clear() async {
    try {
      await _cache.clear();
    } catch (_) {
      // Nothing more to do; the next sign-in replaces the list anyway.
    }
  }
}
