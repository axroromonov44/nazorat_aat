import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:geolocator/geolocator.dart';
import '../../domain/entities/location_point.dart';
import '../../domain/repositories/location_repository.dart';

class LocationException implements Exception {
  const LocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LocationRepositoryImpl implements LocationRepository {
  static const _timeout = Duration(seconds: 30);

  /// A remembered fix older than this is not worth showing: an inspector who
  /// drove to another district would otherwise open the map on yesterday's
  /// village and believe it.
  static const _lastKnownMaxAge = Duration(hours: 6);

  LocationSettings _locationSettings({
    int distanceFilter = 0,
    Duration interval = const Duration(seconds: 2),
    LocationAccuracy accuracy = LocationAccuracy.bestForNavigation,
  }) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        forceLocationManager: true,
        distanceFilter: distanceFilter,
        // Emit on a fixed interval (not only on movement) so mock-location
        // toggling is detected almost immediately, even when standing still.
        intervalDuration: interval,
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(accuracy: accuracy, distanceFilter: distanceFilter);
    }
    return LocationSettings(accuracy: accuracy, distanceFilter: distanceFilter);
  }

  @override
  Future<LocationPoint> getCurrentLocation() async {
    await _ensurePermission();
    final position =
        await Geolocator.getCurrentPosition(
          // The first fix only has to put the map on the right field; the
          // stream below sharpens it from there. Asking for navigation-grade
          // accuracy here is asking for something indoors GPS cannot deliver —
          // the platform keeps refining and returns nothing at all, so the map
          // would sit on the timeout while a usable fix was available the
          // whole time.
          locationSettings: _locationSettings(accuracy: LocationAccuracy.high),
        ).timeout(
          _timeout,
          onTimeout: () => throw LocationException('locationTimeoutError'.tr()),
        );
    return _fromPosition(position);
  }

  @override
  Stream<LocationPoint> watchLocation() async* {
    await _ensurePermission();
    // distanceFilter: 0 + interval → continuous updates, so fake GPS appears the
    // moment it is enabled and the map returns the moment it is turned off.
    yield* Geolocator.getPositionStream(
      locationSettings: _locationSettings(distanceFilter: 0),
    ).map(_fromPosition);
  }

  @override
  Future<LocationPoint?> lastKnownLocation() async {
    // Deliberately no permission prompt here: this runs while the map is being
    // built, and a dialog at that moment would be the first thing an inspector
    // sees. The real request happens in getCurrentLocation.
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      final position = await Geolocator.getLastKnownPosition(
        forceAndroidLocationManager: true,
      );
      if (position == null) return null;
      if (DateTime.now().toUtc().difference(position.timestamp.toUtc()) >
          _lastKnownMaxAge) {
        return null;
      }
      return _fromPosition(position);
    } catch (_) {
      // Some Android builds throw instead of returning null here. A missing
      // last fix is never worth failing the map over.
      return null;
    }
  }

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Stream<bool> watchServiceEnabled() => Geolocator.getServiceStatusStream().map(
    (status) => status == ServiceStatus.enabled,
  );

  @override
  Future<bool> hasOnlyApproximateAccuracy() async {
    if (!Platform.isAndroid) return false;
    try {
      return await Geolocator.getLocationAccuracy() ==
          LocationAccuracyStatus.reduced;
    } catch (_) {
      // Not reported below Android 12; absence of the answer is not a problem.
      return false;
    }
  }

  @override
  Future<void> openDeviceLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  @override
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  Future<void> _ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationUnavailable(
        LocationBlock.serviceDisabled,
        'locationServiceDisabledError'.tr(),
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationUnavailable(
        LocationBlock.permissionForever,
        'locationPermissionDeniedError'.tr(),
      );
    }
    if (permission == LocationPermission.denied) {
      throw LocationUnavailable(
        LocationBlock.permissionDenied,
        'locationPermissionDeniedError'.tr(),
      );
    }
  }

  LocationPoint _fromPosition(Position p) => LocationPoint(
    latitude: p.latitude,
    longitude: p.longitude,
    accuracy: p.accuracy,
    timestamp: p.timestamp,
    isMocked: Platform.isAndroid && p.isMocked,
  );
}
