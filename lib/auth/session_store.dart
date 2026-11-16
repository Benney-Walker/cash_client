import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_session.dart';

/// Keeps the signed-in session across app restarts.
///
/// The spec keeps a collector signed in until they log out or the backend
/// ends the session, so the tokens have to survive the app being closed.
/// The password is never stored.
abstract interface class SessionStore {
  Future<AuthSession?> read();
  Future<void> save(AuthSession session);
  Future<void> clear();
}

/// [SessionStore] backed by the Android Keystore (and the iOS Keychain),
/// through flutter_secure_storage. Tokens are bearer credentials for a
/// financial system, so they don't go in plain shared preferences.
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  // One key for the whole session, so a save never leaves a half-written
  // mix of old and new tokens.
  static const _key = 'auth_session';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthSession?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      final session =
          json is Map<String, dynamic> ? AuthSession.fromJson(json) : null;
      if (session == null) await clear();
      return session;
    } on FormatException {
      await clear();
      return null;
    }
  }

  @override
  Future<void> save(AuthSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
