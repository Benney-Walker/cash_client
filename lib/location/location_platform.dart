import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Whether the app can take location readings.
enum LocationAccess {
  /// Permission given and location turned on.
  ready,

  /// Permission given, but location is turned off on the phone.
  serviceOff,

  /// Not allowed yet (never asked, or the collector said no once). Android
  /// can still ask.
  denied,

  /// The collector said no for good; only the phone's Settings can change
  /// it.
  deniedForever,
}

/// One reading from the phone's location.
@immutable
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
}

/// The phone's location and battery, behind an interface so tests can
/// script them.
abstract interface class LocationPlatform {
  Future<LocationAccess> access();

  /// Shows Android's location prompt if it still can, then reports the
  /// result.
  Future<LocationAccess> requestAccess();

  /// Readings about every [interval], kept going while the app is in the
  /// background by a foreground service with a notification that stays
  /// showing (owner decision 2026-11-24). Cancelling the subscription stops
  /// the service and removes the notification.
  Stream<LocationFix> trackEvery(Duration interval);

  /// A fresh reading, or an error if none comes within [timeLimit].
  Future<LocationFix> currentFix(Duration timeLimit);

  /// True when location is turned on, false when off.
  Stream<bool> serviceChanges();

  Future<int?> batteryPercent();

  Future<void> openAppSettings();

  Future<void> openLocationSettings();
}

/// [LocationPlatform] on the phone, through geolocator and battery_plus.
class DeviceLocationPlatform implements LocationPlatform {
  DeviceLocationPlatform({Battery? battery}) : _battery = battery ?? Battery();

  final Battery _battery;

  @override
  Future<LocationAccess> access() async {
    final permission = await Geolocator.checkPermission();
    switch (permission) {
      case LocationPermission.deniedForever:
        return LocationAccess.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationAccess.denied;
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        break;
    }
    return await Geolocator.isLocationServiceEnabled()
        ? LocationAccess.ready
        : LocationAccess.serviceOff;
  }

  @override
  Future<LocationAccess> requestAccess() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      await Geolocator.requestPermission();
    }
    return access();
  }

  @override
  Stream<LocationFix> trackEvery(Duration interval) {
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: interval,
        // "While using the app" permission is enough: the service is
        // started while the app is open, and keeps running when it's closed.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Penco Collector',
          notificationText: 'Recording your location while you collect',
          notificationChannelName: 'Location while collecting',
          notificationIcon:
              AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
          enableWakeLock: true,
          setOngoing: true,
        ),
      ),
    ).map(_fix);
  }

  @override
  Future<LocationFix> currentFix(Duration timeLimit) async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeLimit,
      ),
    );
    return _fix(position);
  }

  @override
  Stream<bool> serviceChanges() => Geolocator.getServiceStatusStream()
      .map((status) => status == ServiceStatus.enabled);

  @override
  Future<int?> batteryPercent() async {
    try {
      final level = await _battery.batteryLevel;
      return level < 0 || level > 100 ? null : level;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  static LocationFix _fix(Position position) => LocationFix(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy < 0 ? 0 : position.accuracy,
      );
}
