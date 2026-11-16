/// Build-time settings, passed with `--dart-define`.
///
/// ```
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
/// ```
///
/// `10.0.2.2` is how the Android emulator reaches the computer running it.
/// Release builds must use an `https://` address.
abstract final class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
}
