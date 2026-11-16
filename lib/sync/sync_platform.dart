import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../outbox/outbox_store.dart';
import 'payment_sync.dart';

/// Asks Android to run the sync while the app is closed.
abstract interface class BackgroundScheduler {
  /// A sync about every 15 minutes (Android's shortest interval) whenever
  /// there's a connection. Safe to call on every launch.
  Future<void> ensurePeriodic();

  /// A sync once [delay] has passed and there's a connection, for the
  /// payment [idempotencyKey] whose 10 minutes end then.
  Future<void> scheduleOnce(String idempotencyKey, Duration delay);
}

/// Says when the phone gets a network connection.
abstract interface class ConnectivityWatcher {
  /// True when a network is available. It doesn't prove the backend can be
  /// reached; the sync finds that out.
  Stream<bool> get changes;
}

/// The notification side of the app: refused-payment notifications and
/// what happens when one is tapped.
abstract interface class AppNotifications implements RefusalNotifier {
  /// Asks for Android 13's notification permission. Called when the first
  /// payment is saved on the phone, which is when it starts to matter.
  Future<void> requestPermission();
}

const backgroundSyncTask = 'payment-sync';
const _periodicName = 'payment-sync-periodic';

class WorkmanagerScheduler implements BackgroundScheduler {
  const WorkmanagerScheduler();

  static final _online = Constraints(networkType: NetworkType.connected);

  @override
  Future<void> ensurePeriodic() => Workmanager().registerPeriodicTask(
        _periodicName,
        backgroundSyncTask,
        frequency: const Duration(minutes: 15),
        constraints: _online,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );

  @override
  Future<void> scheduleOnce(String idempotencyKey, Duration delay) =>
      Workmanager().registerOneOffTask(
        'payment-due-$idempotencyKey',
        backgroundSyncTask,
        initialDelay: delay,
        constraints: _online,
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );
}

class ConnectivityPlusWatcher implements ConnectivityWatcher {
  ConnectivityPlusWatcher([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Stream<bool> get changes => _connectivity.onConnectivityChanged.map(
        (results) => results.any((r) => r != ConnectivityResult.none),
      );
}

/// Payload on refused-payment notifications; tapping one opens the Outbox.
const outboxPayload = 'outbox';

/// Refused-payment notifications through flutter_local_notifications.
class LocalAppNotifications implements AppNotifications {
  LocalAppNotifications._(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channel = AndroidNotificationDetails(
    'refused_payments',
    'Refused payments',
    channelDescription:
        'Payments the server refused, to report to your admin.',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.error,
  );

  // One notification at a time, replaced by the latest; the Outbox lists
  // every refused payment.
  static const _id = 1001;

  /// Sets the plugin up. [onOpenOutbox] runs when the collector taps a
  /// notification while the app is running; it isn't needed in the
  /// background sync.
  static Future<LocalAppNotifications> create({
    void Function()? onOpenOutbox,
  }) async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: onOpenOutbox == null
          ? null
          : (response) {
              if (response.payload == outboxPayload) onOpenOutbox();
            },
    );
    return LocalAppNotifications._(plugin);
  }

  /// True when the app was started by tapping a refused-payment
  /// notification.
  Future<bool> launchedFromNotification() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    return (details?.didNotificationLaunchApp ?? false) &&
        details?.notificationResponse?.payload == outboxPayload;
  }

  @override
  Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  @override
  Future<void> refused(List<OutboxPayment> payments) async {
    if (payments.isEmpty) return;
    final String title;
    final String body;
    if (payments.length == 1) {
      final p = payments.single;
      title = 'Payment refused';
      body = '${p.amount.format()} for ${p.memberName} was refused. '
          'Report it to your admin. Open Outbox to see why.';
    } else {
      title = '${payments.length} payments refused';
      body = 'Report them to your admin. Open Outbox to see why.';
    }
    await _plugin.show(
      id: _id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: _channel),
      payload: outboxPayload,
    );
  }
}
