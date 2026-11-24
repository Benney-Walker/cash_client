import 'package:flutter/services.dart';

/// The phone's own device ID, which the backend uses to keep each collector
/// to one registered phone (owner decision 2026-11-23, D36): sent as
/// `deviceId` at collector sign-in and with every refresh.
///
/// It's read once, at sign-in, and saved with the session, so the
/// background sync (which runs without the app's screens) can refresh too.
abstract interface class DeviceIdSource {
  /// Throws [DeviceIdUnavailable] when the phone doesn't give one.
  Future<String> read();
}

class DeviceIdUnavailable implements Exception {
  const DeviceIdUnavailable();
}

/// Android's `Settings.Secure.ANDROID_ID`, read in `MainActivity.kt`.
class AndroidDeviceId implements DeviceIdSource {
  const AndroidDeviceId();

  static const _channel = MethodChannel('com.bynexlabs.cash_client/device');

  @override
  Future<String> read() async {
    try {
      final id = await _channel.invokeMethod<String>('androidId');
      if (id == null || id.trim().isEmpty) throw const DeviceIdUnavailable();
      return id.trim();
    } on PlatformException {
      throw const DeviceIdUnavailable();
    } on MissingPluginException {
      throw const DeviceIdUnavailable();
    }
  }
}
