import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_exception.dart';
import 'auth_api.dart';
import 'auth_session.dart';
import 'refresh_lock.dart';
import 'session_store.dart';
import 'sign_in.dart';

/// Owns the signed-in session: restoring it at launch, signing in and out,
/// refreshing the access token, and ending the session when the backend
/// refuses it.
///
/// Widgets listen to it to switch between the login screen and the app.
class SessionManager extends ChangeNotifier {
  SessionManager({
    required AuthApi api,
    required SessionStore store,
    RefreshLock refreshLock = const NoRefreshLock(),
  })  : _api = api,
        _store = store,
        _lock = refreshLock;

  final AuthApi _api;
  final SessionStore _store;
  final RefreshLock _lock;

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
  /// The phone forgets the tokens straight away, then tells the backend to
  /// end the session (`logout`), so the tokens stop working there too. If
  /// that call can't get through (no connection), the session on the server
  /// simply runs out when its refresh token expires.
  Future<void> signOut() async {
    final refreshToken = _session?.refreshToken;
    await _clear(endedByServer: false);
    if (refreshToken != null) {
      unawaited(_api.logout(refreshToken).catchError((Object _) {}));
    }
  }

  /// The backend refused the session: the refresh token expired or was
  /// revoked, the collector was deactivated, or their day's submission was
  /// approved and the backend ended the session.
  Future<void> endSession() => _clear(endedByServer: true);

  /// Gets a new access token, and the next refresh token, and saves both.
  ///
  /// Refresh tokens are single use, and spending one twice ends the session
  /// on the backend (15 Nov 2026). So:
  /// - concurrent callers in this isolate share one refresh call;
  /// - the open app and the background sync take turns through
  ///   [RefreshLock], and each first re-reads the stored session: if the
  ///   other already refreshed, it takes those tokens instead of spending
  ///   the old one again;
  /// - when the refresh can't get through, it's retried once straight away,
  ///   so a lost response is retried inside the backend's 30-second grace.
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
    return _lock.run(() async {
      final stored = await _readStored(fallback: current);
      if (!identical(_session, current)) {
        // Signed out or in again while waiting for the lock.
        final now = _session;
        if (now == null) throw const ApiException(ApiFailure.unauthorized);
        return now.accessToken;
      }
      if (stored == null) {
        // The other isolate found the session refused and cleared it.
        await endSession();
        throw const ApiException(ApiFailure.unauthorized);
      }
      if (stored.refreshToken != current.refreshToken) {
        // The other isolate refreshed: use its tokens.
        _session = stored;
        return stored.accessToken;
      }

      try {
        final tokens = await _refreshOnce(current.refreshToken);
        // Only keep them if the collector didn't sign out (or sign in again)
        // while the refresh was in flight.
        if (identical(_session, current)) {
          final updated = current.withTokens(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
          );
          await _store.save(updated);
          _session = updated;
        }
        return tokens.accessToken;
      } on ApiException catch (e) {
        if (e.failure == ApiFailure.unauthorized &&
            identical(_session, current)) {
          await endSession();
        }
        rethrow;
      }
    });
  }

  /// One refresh, retried once at once if it didn't get through: the first
  /// may have reached the backend and only its response been lost, and the
  /// backend accepts the same token again for 30 seconds after that.
  Future<TokenPair> _refreshOnce(String refreshToken) async {
    try {
      return await _api.refreshTokens(refreshToken);
    } on ApiException catch (e) {
      if (e.failure != ApiFailure.network) rethrow;
      return _api.refreshTokens(refreshToken);
    }
  }

  /// The stored session, or [fallback] if the store can't be read (keep
  /// going with what's in memory rather than sign the collector out).
  Future<AuthSession?> _readStored({required AuthSession fallback}) async {
    try {
      return await _store.read();
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _clear({required bool endedByServer}) async {
    await _store.clear();
    _session = null;
    _endedByServer = endedByServer;
    notifyListeners();
  }
}
