import '../api/api_exception.dart';
import 'auth_api.dart';
import 'auth_session.dart';
import 'session_store.dart';

/// Thrown when someone without the COLLECTOR role signs in. Administrators
/// and agents use the desktop app.
class NotCollectorException implements Exception {
  const NotCollectorException();
}

/// Signs a collector in and keeps the session.
///
/// A non-collector's tokens are thrown away, not stored. The backend still
/// enforces permissions on every endpoint; this check only keeps the wrong
/// people out of an app that isn't built for them.
class SignIn {
  SignIn(this._api, this._store);

  final AuthApi _api;
  final SessionStore _store;

  Future<AuthSession> call({
    required String staffId,
    required String password,
  }) async {
    final session = await _api.login(staffId: staffId, password: password);
    if (!session.isCollector) throw const NotCollectorException();
    await _store.save(session);
    return session;
  }
}

/// What to tell the collector when sign-in fails.
String signInErrorMessage(Object error) {
  if (error is NotCollectorException) {
    return 'This app is for collectors. Administrators and agents use the desktop app.';
  }
  if (error is ApiException) {
    return switch (error.failure) {
      ApiFailure.invalidCredentials => 'Wrong staff ID or password.',
      ApiFailure.network =>
        "Couldn't reach the server. Check your connection and try again.",
      ApiFailure.validation =>
        error.message ?? 'Check your staff ID and password.',
      ApiFailure.server =>
        'The server had a problem. Try again in a few minutes.',
      ApiFailure.notConfigured =>
        "This build has no server address. It needs to be rebuilt with API_BASE_URL.",
      ApiFailure.unexpectedResponse =>
        "The server sent a response the app didn't understand. Try again.",
    };
  }
  return 'Something went wrong. Try again.';
}
