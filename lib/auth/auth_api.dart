import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_exception.dart';
import 'auth_session.dart';

/// Calls the backend's public authentication endpoints. These take no
/// bearer token, so they use a plain client rather than
/// `AuthenticatedClient`.
class AuthApi {
  AuthApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  })  : _baseUrl = baseUrl.trim(),
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

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

  /// `POST /api/auth/v1/refresh-collector-token`. Returns a new access
  /// token. Only collector refresh tokens are accepted here.
  ///
  /// The backend answers with the bare token as the response body, not a
  /// JSON object (contract checked 14 Nov 2026). Because the app asks for
  /// JSON, Spring may also send it as a JSON string in quotes, so both are
  /// accepted.
  ///
  /// The backend answers 401 ([ApiFailure.unauthorized]) when the refresh
  /// token has expired or is invalid, the account is no longer active, or
  /// it isn't a collector's. It doesn't issue a new refresh token, so once
  /// that one expires the collector has to sign in again.
  Future<String> refreshAccessToken(String refreshToken) async {
    final response = await _post(
      '/api/auth/v1/refresh-collector-token',
      {'refreshToken': refreshToken},
    );
    final accessToken = _bareToken(response.body);
    if (accessToken == null) {
      throw const ApiException(ApiFailure.unexpectedResponse, statusCode: 200);
    }
    return accessToken;
  }

  // The backend's tokens are signed JWTs: three base64url parts joined by
  // dots. Checking the shape catches a proxy error page or other stray body
  // before it's saved and sent as a bearer token.
  static final _jwtShape =
      RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$');

  /// The token in a bare-token body (`abc.def.ghi` or `"abc.def.ghi"`), or
  /// null if the body isn't one.
  static String? _bareToken(String body) {
    var text = body.trim();
    if (text.startsWith('"')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is! String) return null;
        text = decoded.trim();
      } on FormatException {
        return null;
      }
    }
    return _jwtShape.hasMatch(text) ? text : null;
  }

  static Map<String, dynamic>? _jsonObject(String body) {
    try {
      final json = jsonDecode(body);
      return json is Map<String, dynamic> ? json : null;
    } on FormatException {
      return null;
    }
  }

  /// Sends a JSON body and returns a 200 response. Any other status becomes
  /// an [ApiException] built from the backend's standard error body.
  Future<http.Response> _post(
    String path,
    Map<String, Object?> body,
  ) async {
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
          .timeout(timeout);
    } on TimeoutException {
      throw const ApiException(ApiFailure.network);
    } on http.ClientException {
      // Covers socket and DNS errors on every platform http supports.
      throw const ApiException(ApiFailure.network);
    }

    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response.statusCode, response.body);
    }
    return response;
  }

  Uri _endpoint(String path) {
    if (_baseUrl.isEmpty) {
      throw const ApiException(ApiFailure.notConfigured);
    }
    final base = Uri.tryParse(_baseUrl);
    if (base == null || !base.hasScheme || base.host.isEmpty) {
      throw const ApiException(ApiFailure.notConfigured);
    }
    // Tolerate a base URL with or without a trailing slash, or with a path
    // prefix such as a reverse-proxy mount point.
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$prefix$path');
  }
}
