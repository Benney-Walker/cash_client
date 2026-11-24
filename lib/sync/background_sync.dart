import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

import '../api/authenticated_client.dart';
import '../auth/auth_api.dart';
import '../auth/refresh_lock.dart';
import '../auth/session_manager.dart';
import '../auth/session_store.dart';
import '../collector/collector_api.dart';
import '../config/app_config.dart';
import '../location/location_store.dart';
import '../location/location_sync.dart';
import '../outbox/outbox_store.dart';
import '../storage/app_database.dart';
import 'payment_sync.dart';
import 'sync_platform.dart';
import 'sync_scheduler.dart';

/// Entry point for Android's WorkManager: syncs the outbox and the location
/// points while the app is closed (owner decision 2026-11-15).
///
/// It runs in its own isolate with nothing from the app set up, so it reads
/// the stored session and opens the database itself. When WorkManager runs
/// it inside the running app instead, it hands over to that app's
/// scheduler.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await runBackgroundSync();
    } catch (_) {
      // Whatever went wrong, the periodic task tries again later.
    }
    // Always "done": retries are the sync's own business, not WorkManager's.
    return true;
  });
}

Future<void> runBackgroundSync() async {
  final running = SyncScheduler.active;
  if (running != null) {
    await running.syncNow();
    return;
  }

  final database = AppDatabase();
  final sessions = SessionManager(
    api: AuthApi(baseUrl: AppConfig.apiBaseUrl),
    store: SecureSessionStore(),
    // The open app may be refreshing too; refresh tokens are single use.
    refreshLock: SqliteRefreshLock(database),
  );
  await sessions.restore();
  // Nobody signed in: the outbox waits for the collector's next sign-in.
  if (sessions.session == null) return;

  final client = http.Client();
  try {
    final api = CollectorApi(
      baseUrl: AppConfig.apiBaseUrl,
      client: AuthenticatedClient(client, sessions),
    );
    final sync = PaymentSync(
      store: SqliteOutboxStore(database),
      api: api,
      staffId: () => sessions.session?.staffId,
      notifier: await LocalAppNotifications.create(),
      // Points taken while the app was open but offline go first.
      locations: LocationSync(store: SqliteLocationStore(database), api: api),
    );
    await sync.run();
  } finally {
    client.close();
  }
}
