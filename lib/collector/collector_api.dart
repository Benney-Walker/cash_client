import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_exception.dart';
import '../api/endpoint.dart';
import '../common/money.dart';
import 'collector_models.dart';

/// Calls the backend's collector endpoints (`/api/collector/**`, COLLECTOR
/// only). [client] should be the app's `AuthenticatedClient`, which adds the
/// token and refreshes it when it expires.
class CollectorApi {
  CollectorApi({
    required String baseUrl,
    required http.Client client,
    this.timeout = const Duration(seconds: 20),
  })  : _baseUrl = baseUrl,
        _client = client;

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// `GET /api/collector/v1/members`: active members in the collector's
  /// branch with their savings and shares accounts.
  Future<List<CollectorMember>> fetchMembers() async {
    final response = await _send(
      () => _client.get(
        apiUri(_baseUrl, '/api/collector/v1/members'),
        headers: const {'Accept': 'application/json'},
      ),
    );
    final json = _decode(response.body);
    if (json is! List) throw _unexpected();
    final members = <CollectorMember>[];
    for (final entry in json) {
      final member = CollectorMember.fromJson(entry);
      if (member == null) throw _unexpected();
      members.add(member);
    }
    return members;
  }

  /// `POST /api/collector/v1/payments`. Saved as PENDING for its 10-minute
  /// correction window.
  ///
  /// Send the same [idempotencyKey] again to retry after a failure: if the
  /// first request did reach the backend, it returns that payment instead
  /// of recording a second one.
  Future<CollectorPayment> recordPayment({
    required String idempotencyKey,
    required PaymentType type,
    required String accountNumber,
    required Cedis amount,
    String? description,
  }) async {
    final note = description?.trim();
    // The amount is written as a JSON number literal from its exact decimal
    // text. jsonEncode would go through a double, which can't hold every
    // pesewa amount exactly.
    final body = '{'
        '"idempotencyKey":${jsonEncode(idempotencyKey)},'
        '"type":${jsonEncode(type.wireName)},'
        '"accountNumber":${jsonEncode(accountNumber)},'
        '"amount":${amount.toDecimalString()}'
        '${note == null || note.isEmpty ? '' : ',"description":${jsonEncode(note)}'}'
        '}';
    final response = await _send(
      () => _client.post(
        apiUri(_baseUrl, '/api/collector/v1/payments'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: body,
      ),
    );
    final payment = CollectorPayment.fromJson(_decode(response.body));
    if (payment == null) throw _unexpected();
    return payment;
  }

  /// Runs a request and turns transport problems and non-200 answers into
  /// [ApiException]s. `AuthenticatedClient` throws its own [ApiException]
  /// when the session has ended; that passes straight through.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw const ApiException(ApiFailure.network);
    } on http.ClientException {
      throw const ApiException(ApiFailure.network);
    }
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response.statusCode, response.body);
    }
    return response;
  }

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static ApiException _unexpected() =>
      const ApiException(ApiFailure.unexpectedResponse, statusCode: 200);
}

/// What to tell the collector when a collector request fails. The backend's
/// own messages for refused payments are written for people ("This
/// member's first deposit must be made at the office"), so they're shown
/// as they are.
String collectorErrorMessage(Object error, {required String networkMessage}) {
  if (error is ApiException) {
    return switch (error.failure) {
      ApiFailure.network => networkMessage,
      ApiFailure.validation ||
      ApiFailure.forbidden ||
      ApiFailure.notFound ||
      ApiFailure.conflict =>
        error.message ?? "The server didn't accept this. Check and try again.",
      ApiFailure.unauthorized =>
        'Your session has ended. Sign in again to continue.',
      ApiFailure.server =>
        'The server had a problem. Try again in a few minutes.',
      ApiFailure.notConfigured =>
        'This build has no server address. It needs to be rebuilt with API_BASE_URL.',
      ApiFailure.unexpectedResponse =>
        "The server sent a response the app didn't understand. Try again.",
    };
  }
  return 'Something went wrong. Try again.';
}
