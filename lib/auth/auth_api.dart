import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_exception.dart';
import 'auth_session.dart';

/// Calls the backend's staff authentication endpoints.
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
    final uri = _endpoint('/api/auth/v1/login');
    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'staffId': staffId, 'password': password}),
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

    final Object? json;
    try {
      json = jsonDecode(response.body);
    } on FormatException {
      throw const ApiException(ApiFailure.unexpectedResponse, statusCode: 200);
    }
    final session = json is Map<String, dynamic>
        ? AuthSession.fromLoginResponse(staffId, json)
        : null;
    if (session == null) {
      throw const ApiException(ApiFailure.unexpectedResponse, statusCode: 200);
    }
    return session;
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
