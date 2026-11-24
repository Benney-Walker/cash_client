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
  ///
  /// [createdAt] is when the collector recorded it on the phone and
  /// [updatedAt] its last correction there (the same if never corrected).
  /// The backend applies the payment as soon as it arrives (backend,
  /// 23 Nov 2026): the app sends it only after its 5 minutes on the phone.
  Future<CollectorPayment> recordPayment({
    required String idempotencyKey,
    required PaymentType type,
    required String accountNumber,
    required Cedis amount,
    required DateTime createdAt,
    required DateTime updatedAt,
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
        ',"createdAt":${jsonEncode(backendLocalTime(createdAt))}'
        ',"updatedAt":${jsonEncode(backendLocalTime(updatedAt))}'
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

  /// `GET /api/collector/v1/payments`: today's payments with totals.
  Future<CollectorDaySummary> fetchDaySummary() async {
    final response = await _send(
      () => _client.get(
        apiUri(_baseUrl, '/api/collector/v1/payments'),
        headers: const {'Accept': 'application/json'},
      ),
    );
    return CollectorDaySummary.fromJson(_decode(response.body)) ??
        (throw _unexpected());
  }

  /// `POST /api/collector/v1/submissions`: closes the day (decision D35).
  ///
  /// Covers every payment not yet handed in; no more payments can be
  /// recorded until it's approved. Refused with 409 while a payment is in
  /// its 10-minute window (the message says when the collector can submit).
  /// Sending it again while waiting returns the same submission, so a retry
  /// after a lost response is safe.
  Future<DaySubmission> submitDay() async {
    final response = await _send(
      () => _client.post(
        apiUri(_baseUrl, '/api/collector/v1/submissions'),
        headers: const {'Accept': 'application/json'},
      ),
    );
    return DaySubmission.fromJson(_decode(response.body)) ??
        (throw _unexpected());
  }

  /// `GET /api/collector/v1/submissions?page=0&size=1`: the collector's
  /// latest submission, or null if they've never submitted.
  Future<DaySubmission?> fetchLatestSubmission() async {
    final response = await _send(
      () => _client.get(
        apiUri(
          _baseUrl,
          '/api/collector/v1/submissions',
          const {'page': '0', 'size': '1'},
        ),
        headers: const {'Accept': 'application/json'},
      ),
    );
    final json = _decode(response.body);
    final content = json is Map<String, dynamic> ? json['content'] : null;
    if (content is! List) throw _unexpected();
    if (content.isEmpty) return null;
    return DaySubmission.fromJson(content.first) ?? (throw _unexpected());
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

/// [time] as the backend's `LocalDateTime` text, such as
/// `2026-11-15T10:00:00`.
///
/// The backend's clock runs on Africa/Accra time, which is UTC all year
/// (Ghana has no daylight saving), so the UTC wall time is exact whatever
/// time zone the phone is set to.
String backendLocalTime(DateTime time) {
  final t = time.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// True when the backend looked at a payment and turned it down, as opposed
/// to the request not getting through (no connection, a timeout, a server
/// fault, an ended session). Sending it again unchanged would get the same
/// answer until someone at the office fixes the cause.
bool isRefusal(Object error) {
  if (error is! ApiException) return false;
  return switch (error.failure) {
    ApiFailure.validation ||
    ApiFailure.forbidden ||
    ApiFailure.notFound ||
    ApiFailure.conflict =>
      true,
    ApiFailure.unexpectedResponse =>
      (error.statusCode ?? 0) >= 400 && (error.statusCode ?? 0) < 500,
    _ => false,
  };
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
