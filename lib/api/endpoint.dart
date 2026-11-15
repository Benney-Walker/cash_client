import 'api_exception.dart';

/// Builds a backend URL from the build's `API_BASE_URL` and a path such as
/// `/api/collector/v1/members`.
///
/// Throws [ApiException] with [ApiFailure.notConfigured] when the base URL
/// is missing or isn't an absolute URL, so nothing is ever sent to a
/// half-formed address.
Uri apiUri(String baseUrl, String path, [Map<String, String>? query]) {
  final trimmed = baseUrl.trim();
  if (trimmed.isEmpty) throw const ApiException(ApiFailure.notConfigured);
  final base = Uri.tryParse(trimmed);
  if (base == null || !base.hasScheme || base.host.isEmpty) {
    throw const ApiException(ApiFailure.notConfigured);
  }
  // Tolerate a base URL with or without a trailing slash, or with a path
  // prefix such as a reverse-proxy mount point.
  final prefix = base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
  return base.replace(
    path: '$prefix$path',
    queryParameters: query == null || query.isEmpty ? null : query,
  );
}
