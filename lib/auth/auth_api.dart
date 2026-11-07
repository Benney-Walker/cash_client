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

  /// `POST /api/auth/v1/login`.
  ///
  /// Throws [ApiException]. Any staff member can sign in here; checking that
  /// they're a collector is the caller's job, because the backend accepts
  /// every role.
  Future<AuthSession> login({
    required String staffId,
    required String password,
  }) async {
    final json = await _post(
      '/api/auth/v1/login',
      {'staffId': staffId, 'password': password},
    );
    final session = AuthSession.fromLoginResponse(staffId, json);
    if (session == null) {
      throw const ApiException(ApiFailure.unexpectedResponse, statusCode: 200);
    }
    return session;
  }

  /// `POST /api/auth/v1/refresh-token`. Returns a new access token.
  ///
  /// The backend answers 401 ([ApiFailure.unauthorized]) when the refresh
  /// token has expired or is invalid, or the staff member is no longer
  /// active. It doesn't issue a new refresh token, so once that one expires
  /// the collector has to sign in again.
  Future<String> refreshAccessToken(String refreshToken) async {
    final json = await _post(
      '/api/auth/v1/refresh-token',
      {'refreshToken': refreshToken},
    );
    final accessToken = json['authToken'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw const ApiException(ApiFailure.unexpectedResponse, statusCode: 200);
    }
    return accessToken;
  }

  Future<Map<String, dynamic>> _post(
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
    try {
      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic>) return json;
    } on FormatException {
      // Falls through to the unexpected-response error below.
    }
    throw const ApiException(ApiFailure.unexpectedResponse, statusCode: 200);
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
