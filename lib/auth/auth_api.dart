import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_exception.dart';
import '../api/endpoint.dart';
import 'auth_session.dart';

/// What a refresh returns: a new access token, and the refresh token to use
/// next time (the one sent is used up).
class TokenPair {
  const TokenPair({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

/// Calls the backend's public authentication endpoints. These take no
/// bearer token, so they use a plain client rather than
/// `AuthenticatedClient`.
class AuthApi {
  AuthApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.refreshTimeout = const Duration(seconds: 10),
  })  : _baseUrl = baseUrl.trim(),
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// Shorter than [timeout], so that when a refresh response is lost the
  /// session manager's retry still lands inside the backend's 30-second
  /// grace for it.
  final Duration refreshTimeout;

  /// `POST /api/auth/v1/collector-login`.
  ///
  /// Collectors have their own sign-in endpoint (backend, 14 Nov 2026). It
  /// answers 401 ([ApiFailure.unauthorized]) for a wrong staff ID or
  /// password or an inactive account, and 403 ([ApiFailure.forbidden]) for
  /// a valid account that isn't a collector. Throws [ApiException].
  Future<AuthSession> login({
    required String staffId,
    required String password,
  }) async {
    final response = await _post(
      '/api/auth/v1/collector-login',
      {'staffId': staffId, 'password': password},
    );
    final json = _jsonObject(response.body);
    final session =
        json == null ? null : AuthSession.fromLoginResponse(staffId, json);
    if (session == null) {
      throw const ApiException(ApiFailure.unexpectedResponse, statusCode: 200);
    }
    return session;
  }

  /// `POST /api/auth/v1/refresh-collector-token`. Only collector refresh
  /// tokens are accepted here.
  ///
  /// Refresh tokens rotate (backend, 15 Nov 2026): the response is
  /// `{ authToken, refreshToken }`, and the refresh token sent is used up.
  /// Spending it again ends the whole session, except within 30 seconds of
  /// a refresh whose response was lost, so the caller must keep the new one
  /// (see [SessionManager]).
  ///
  /// The backend answers 401 ([ApiFailure.unauthorized]) when the refresh
  /// token has expired, is used up or revoked, the account is no longer
  /// active, or it isn't a collector's. Throws [ApiException].
  Future<TokenPair> refreshTokens(String refreshToken) async {
    final response = await _post(
      '/api/auth/v1/refresh-collector-token',
      {'refreshToken': refreshToken},
      timeout: refreshTimeout,
    );
    final json = _jsonObject(response.body);
    final accessToken = json?['authToken'];
    final nextRefreshToken = json?['refreshToken'];
    if (accessToken is! String ||
        !_jwtShape.hasMatch(accessToken.trim()) ||
        nextRefreshToken is! String ||
        nextRefreshToken.trim().isEmpty) {
      throw const ApiException(ApiFailure.unexpectedResponse, statusCode: 200);
    }
    return TokenPair(
      accessToken: accessToken.trim(),
      refreshToken: nextRefreshToken.trim(),
    );
  }

  /// `POST /api/auth/v1/logout`: the backend ends this phone's session, so
  /// its tokens stop working at once (backend, 15 Nov 2026). Always 204,
  /// whether or not the token was known. Throws [ApiException].
  Future<void> logout(String refreshToken) async {
    await _post('/api/auth/v1/logout', {'refreshToken': refreshToken});
  }

  // The backend's access tokens are signed JWTs: three base64url parts
  // joined by dots. Checking the shape catches a proxy error page or other
  // stray body before it's saved and sent as a bearer token.
  static final _jwtShape =
      RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$');

  static Map<String, dynamic>? _jsonObject(String body) {
    try {
      final json = jsonDecode(body);
      return json is Map<String, dynamic> ? json : null;
    } on FormatException {
      return null;
    }
  }

  /// Sends a JSON body and returns the 2xx response. Any other status
  /// becomes an [ApiException] built from the backend's standard error body.
  Future<http.Response> _post(
    String path,
    Map<String, Object?> body, {
    Duration? timeout,
  }) async {
    final uri = _endpoint(path);
    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout ?? this.timeout);
    } on TimeoutException {
      throw const ApiException(ApiFailure.network);
    } on http.ClientException {
      // Covers socket and DNS errors on every platform http supports.
      throw const ApiException(ApiFailure.network);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException.fromResponse(response.statusCode, response.body);
    }
    return response;
  }

  Uri _endpoint(String path) => apiUri(_baseUrl, path);
}
