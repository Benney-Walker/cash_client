import 'dart:convert';

/// Why a call to the backend failed, in terms the UI can act on.
enum ApiFailure {
  /// The app was built without `API_BASE_URL`.
  notConfigured,

  /// No connection, DNS failure, timeout and the like.
  network,

  /// 401 from the login endpoint: wrong staff ID or password, or an
  /// inactive account. The backend deliberately doesn't say which.
  invalidCredentials,

  /// 400: the backend rejected the request's fields.
  validation,

  /// 5xx.
  server,

  /// A response the app doesn't understand.
  unexpectedResponse,
}

class ApiException implements Exception {
  const ApiException(this.failure, {this.message, this.statusCode});

  final ApiFailure failure;

  /// The backend's own `message`, when it sent one.
  final String? message;
  final int? statusCode;

  /// Reads the backend's standard error body:
  /// `{timestamp, status, error, message, path}`, plus `errors` (a map of
  /// field to message) for validation failures.
  factory ApiException.fromResponse(int statusCode, String body) {
    final failure = switch (statusCode) {
      400 => ApiFailure.validation,
      401 => ApiFailure.invalidCredentials,
      >= 500 => ApiFailure.server,
      _ => ApiFailure.unexpectedResponse,
    };
    return ApiException(
      failure,
      message: _messageFrom(body),
      statusCode: statusCode,
    );
  }

  static String? _messageFrom(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;
      // Field errors are more useful than the generic "Validation failed".
      final errors = json['errors'];
      if (errors is Map && errors.isNotEmpty) {
        return errors.values.whereType<String>().join('\n');
      }
      final message = json['message'];
      return message is String && message.isNotEmpty ? message : null;
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() =>
      'ApiException($failure, status: $statusCode, message: $message)';
}
