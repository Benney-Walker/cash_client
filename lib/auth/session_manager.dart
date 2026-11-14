import 'package:flutter/foundation.dart';

import '../api/api_exception.dart';
import 'auth_api.dart';
import 'auth_session.dart';
import 'session_store.dart';
import 'sign_in.dart';

/// Owns the signed-in session: restoring it at launch, signing in and out,
/// refreshing the access token, and ending the session when the backend
/// refuses it.
///
/// Widgets listen to it to switch between the login screen and the app.
class SessionManager extends ChangeNotifier {
  SessionManager({required AuthApi api, required SessionStore store})
      : _api = api,
        _store = store;

  final AuthApi _api;
  final SessionStore _store;

  AuthSession? _session;
  bool _restoring = true;
  bool _endedByServer = false;
  Future<String>? _refreshing;

  AuthSession? get session => _session;

  /// True until [restore] has finished reading the stored session.
  bool get isRestoring => _restoring;

  /// True when the backend refused the session, as opposed to the collector
  /// signing out. The login screen uses it to explain why they're there.
  bool get sessionEndedByServer => _endedByServer;

  Future<void> restore() async {
    AuthSession? stored;
    try {
      stored = await _store.read();
    } catch (_) {
      // If the stored session can't be read (for example after the device's
      // keys changed), the only safe outcome is to sign in again.
      stored = null;
    }
    // SignIn never saves a non-collector, but don't trust the device.
    if (stored != null && !stored.isCollector) {
      await _store.clear();
      stored = null;
    }
    _session = stored;
    _restoring = false;
    notifyListeners();
  }

  /// Signs a collector in and keeps the session.
  ///
  /// Throws [ApiException] when the login call fails; the collector sign-in
  /// endpoint already refuses other roles with a 403. The role is checked
  /// here too, as a second line: anything without the COLLECTOR role throws
  /// [NotCollectorException] and its tokens are never saved.
  Future<void> signIn({
    required String staffId,
    required String password,
  }) async {
    final session = await _api.login(staffId: staffId, password: password);
    if (!session.isCollector) throw const NotCollectorException();
    await _store.save(session);
    _session = session;
    _endedByServer = false;
    notifyListeners();
  }

  /// The collector chose to sign out.
  ///
  /// The backend has no logout endpoint yet, so this forgets the tokens on
  /// the phone; they stay valid until they expire.
  Future<void> signOut() => _clear(endedByServer: false);

  /// The backend refused the session: the refresh token expired, the
  /// collector was deactivated, or (later) their day's submission was
  /// approved and the backend ended the session.
  Future<void> endSession() => _clear(endedByServer: true);

  /// Gets a new access token and saves it.
  ///
  /// Concurrent callers share one refresh call: when several requests hit a
  /// 401 together, the backend is asked once.
  ///
  /// Throws [ApiException]. A 401 from the refresh endpoint ends the session
  /// before it's rethrown. Other failures, such as no connection, leave the
  /// session alone so the collector isn't signed out for being offline.
  Future<String> refreshAccessToken() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String> _refresh() async {
    final current = _session;
    if (current == null) throw const ApiException(ApiFailure.unauthorized);
    try {
      final accessToken = await _api.refreshAccessToken(current.refreshToken);
      // Only keep it if the collector didn't sign out (or sign in again)
      // while the refresh was in flight.
      if (identical(_session, current)) {
        final updated = current.withAccessToken(accessToken);
        await _store.save(updated);
        _session = updated;
      }
      return accessToken;
    } on ApiException catch (e) {
      if (e.failure == ApiFailure.unauthorized && identical(_session, current)) {
        await endSession();
      }
      rethrow;
    }
  }

  Future<void> _clear({required bool endedByServer}) async {
    await _store.clear();
    _session = null;
    _endedByServer = endedByServer;
    notifyListeners();
  }
}
