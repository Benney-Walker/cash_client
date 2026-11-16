import 'package:cash_client/settings/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppInfo info({
    String version = '1.2.0',
    String buildNumber = '7',
    String apiBaseUrl = 'https://api.test.example',
  }) =>
      AppInfo(
        version: version,
        buildNumber: buildNumber,
        apiBaseUrl: apiBaseUrl,
      );

  test('shows the version with its build number', () {
    expect(info().versionLabel, '1.2.0 (build 7)');
  });

  test('leaves out a missing build number', () {
    expect(info(buildNumber: '').versionLabel, '1.2.0');
  });

  test('says Unknown when the version could not be read', () {
    expect(info(version: '', buildNumber: '').versionLabel, 'Unknown');
  });

  test('shows the server address, or says it is not set', () {
    expect(info().serverLabel, 'https://api.test.example');
    expect(info(apiBaseUrl: '').serverLabel, 'Not set for this build');
  });
}
