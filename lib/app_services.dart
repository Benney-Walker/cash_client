import 'collector/collector_api.dart';
import 'collector/member_directory.dart';

/// The backend-facing services the signed-in screens use, created once in
/// `main` and handed down, so tests can swap in fakes.
class AppServices {
  const AppServices({required this.collectorApi, required this.members});

  final CollectorApi collectorApi;
  final MemberDirectory members;
}
