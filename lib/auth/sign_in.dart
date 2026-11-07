import '../api/api_exception.dart';

/// Thrown when someone without the COLLECTOR role signs in. Administrators
/// and agents use the desktop app.
class NotCollectorException implements Exception {
  const NotCollectorException();
}

/// What to tell the collector when sign-in fails.
String signInErrorMessage(Object error) {
  if (error is NotCollectorException) {
    return 'This app is for collectors. Administrators and agents use the desktop app.';
  }
  if (error is ApiException) {
    return switch (error.failure) {
      ApiFailure.unauthorized => 'Wrong staff ID or password.',
      ApiFailure.forbidden => "Your account can't sign in to this app.",
      ApiFailure.network =>
        "Couldn't reach the server. Check your connection and try again.",
      ApiFailure.validation =>
        error.message ?? 'Check your staff ID and password.',
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
