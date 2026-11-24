import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_exception.dart';
import '../api/endpoint.dart';
import '../common/money.dart';
import '../location/location_point.dart';
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

  /// `POST /api/collector/v1/payments`. Applied as soon as it arrives
  /// (COMPLETED or FAILED).
  ///
  /// Send the same [idempotencyKey] again to retry after a failure: if the
  /// first request did reach the backend, it returns that payment instead
  /// of recording a second one.
  ///
  /// [createdAt] is when the collector recorded it on the phone and
  /// [updatedAt] its last correction there (the same if never corrected).
  /// The backend applies the payment as soon as it arrives (backend,
  /// 23 Nov 2026): the app sends it only after its 5 minutes on the phone.
  /// It's refused (409) unless a location point taken within 15 minutes of
  /// [createdAt] reached the backend first, so [sendLocations] goes first.
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

  /// `GET /api/collector/v1/payments`: a day's payments with totals, today
  /// unless [day] is given (its date, in Accra time, which is UTC).
  Future<CollectorDaySummary> fetchDaySummary({DateTime? day}) async {
    final response = await _send(
      () => _client.get(
        apiUri(
          _baseUrl,
          '/api/collector/v1/payments',
          day == null ? null : {'date': backendDate(day)},
        ),
        headers: const {'Accept': 'application/json'},
      ),
    );
    return CollectorDaySummary.fromJson(_decode(response.body)) ??
        (throw _unexpected());
  }

  /// `POST /api/collector/v1/submissions`: closes the day (decision D35).
  ///
  /// Covers every payment not yet handed in; no more payments can be
  /// recorded until it's approved. The app sends every payment on the phone
  /// first (backend, 23 Nov 2026). Sending it again while waiting returns the same submission, so a retry
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

  /// `POST /api/collector/v1/locations`: up to 500 location points (owner
  /// decisions 2026-11-23, D34). A point sent again is stored once, so a
  /// retry after a lost response is safe.
  Future<LocationBatchResult> sendLocations(List<LocationPoint> points) async {
    assert(points.isNotEmpty && points.length <= 500);
    final body = jsonEncode({
      'points': [
        for (final point in points)
          {
            'latitude': point.latitude,
            'longitude': point.longitude,
            'accuracyMeters': point.accuracyMeters,
            if (point.batteryPercent != null)
              'batteryPercent': point.batteryPercent,
            'trigger': point.trigger.wireName,
            if (point.paymentKey != null)
              'paymentIdempotencyKey': point.paymentKey,
            'recordedAt': backendLocalTime(point.recordedAt),
          },
      ],
    });
    final response = await _send(
      () => _client.post(
        apiUri(_baseUrl, '/api/collector/v1/locations'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: body,
      ),
    );
    final json = _decode(response.body);
    final stored = json is Map<String, dynamic> ? json['stored'] : null;
    final duplicates = json is Map<String, dynamic> ? json['duplicates'] : null;
    if (stored is! int || duplicates is! int) throw _unexpected();
    return LocationBatchResult(stored: stored, duplicates: duplicates);
  }

  /// `GET /api/collector/v1/submissions?page=0&size=[size]`: the
  /// collector's latest submissions, newest first.
  Future<List<DaySubmission>> fetchSubmissions({int size = 10}) async {
    final response = await _send(
      () => _client.get(
        apiUri(
          _baseUrl,
          '/api/collector/v1/submissions',
          {'page': '0', 'size': '$size'},
        ),
        headers: const {'Accept': 'application/json'},
      ),
    );
    final json = _decode(response.body);
    final content = json is Map<String, dynamic> ? json['content'] : null;
    if (content is! List) throw _unexpected();
    return [
      for (final entry in content)
        DaySubmission.fromJson(entry) ?? (throw _unexpected()),
    ];
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

/// [day]'s date as the backend's `LocalDate` text, such as `2026-11-15`,
/// in Accra time (UTC).
String backendDate(DateTime day) {
  final t = day.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}';
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
