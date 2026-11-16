import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';

/// The installed app's version (shown on the sign-in screen) and the
/// backend this build talks to.
class AppInfo {
  const AppInfo({
    required this.version,
    required this.buildNumber,
    required this.apiBaseUrl,
  });

  /// Reads the version from the installed app, so it always matches the
  /// build rather than a value someone had to remember to update.
  static Future<AppInfo> load() async {
    String version = '';
    String buildNumber = '';
    try {
      final package = await PackageInfo.fromPlatform();
      version = package.version;
      buildNumber = package.buildNumber;
    } catch (_) {
      // Shown as "Unknown" rather than stopping the app from starting.
    }
    return AppInfo(
      version: version,
      buildNumber: buildNumber,
      apiBaseUrl: AppConfig.apiBaseUrl,
    );
  }

  final String version;
  final String buildNumber;
  final String apiBaseUrl;

  /// For example "1.0.0 (build 1)".
  String get versionLabel {
    if (version.isEmpty) return 'Unknown';
    if (buildNumber.isEmpty) return version;
    return '$version (build $buildNumber)';
  }

  String get serverLabel =>
      apiBaseUrl.isEmpty ? 'Not set for this build' : apiBaseUrl;
}
