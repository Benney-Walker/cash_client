import 'package:flutter/foundation.dart';

/// The signed-in collector, as returned by the backend's login endpoint.
@immutable
class AuthSession {
  const AuthSession({
    required this.staffId,
    required this.staffName,
    required this.roles,
    required this.accessToken,
    required this.refreshToken,
    this.deviceId,
  });

  /// What the collector typed to sign in. The login response doesn't echo
  /// it back, so it's kept from the request.
  final String staffId;
  final String staffName;
  final List<String> roles;
  final String accessToken;
  final String refreshToken;

  /// The phone's device ID sent at sign-in. The backend binds the session to
  /// it, so every refresh sends it again. Null for a session saved before
  /// the app sent one (13 Nov–24 Nov 2026 builds); those refresh without it.
  final String? deviceId;

  /// Only collectors may use this app. The value matches the backend's
  /// `Roles.COLLECTOR` enum.
  bool get isCollector => roles.contains('COLLECTOR');

  /// Parses the login response body. Returns null if a required field is
  /// missing or has the wrong type.
  static AuthSession? fromLoginResponse(
    String staffId,
    Map<String, dynamic> json, {
    String? deviceId,
  }) {
    final staffName = json['staffName'];
    final roles = json['roles'];
    final accessToken = json['authToken'];
    final refreshToken = json['refreshToken'];
    if (staffName is! String ||
        roles is! List ||
        accessToken is! String ||
        accessToken.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty) {
      return null;
    }
    return AuthSession(
      staffId: staffId,
      staffName: staffName,
      roles: List.unmodifiable(roles.whereType<String>()),
      accessToken: accessToken,
      refreshToken: refreshToken,
      deviceId: deviceId,
    );
  }

  /// The same session with the tokens from a refresh. Refresh tokens
  /// rotate, so both change.
  AuthSession withTokens({
    required String accessToken,
    required String refreshToken,
  }) =>
      AuthSession(
        staffId: staffId,
        staffName: staffName,
        roles: roles,
        accessToken: accessToken,
        refreshToken: refreshToken,
        deviceId: deviceId,
      );

  Map<String, dynamic> toJson() => {
        'staffId': staffId,
        'staffName': staffName,
        'roles': roles,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        if (deviceId != null) 'deviceId': deviceId,
      };

  /// Reads what [toJson] wrote. Returns null for anything malformed, so a
  /// damaged stored session sends the collector back to sign in.
  static AuthSession? fromJson(Map<String, dynamic> json) {
    final staffId = json['staffId'];
    final staffName = json['staffName'];
    final roles = json['roles'];
    final accessToken = json['accessToken'];
    final refreshToken = json['refreshToken'];
    final deviceId = json['deviceId'];
    if (staffId is! String ||
        staffName is! String ||
        roles is! List ||
        accessToken is! String ||
        refreshToken is! String ||
        (deviceId != null && deviceId is! String)) {
      return null;
    }
    return AuthSession(
      staffId: staffId,
      staffName: staffName,
      roles: List.unmodifiable(roles.whereType<String>()),
      accessToken: accessToken,
      refreshToken: refreshToken,
      deviceId: deviceId as String?,
    );
  }
}
