import 'package:flutter_test/flutter_test.dart';
import 'package:nazorat_aat/features/home/domain/entities/location_point.dart';
import 'package:nazorat_aat/features/home/domain/repositories/location_repository.dart';
import 'package:nazorat_aat/features/home/domain/usecases/get_current_location_usecase.dart';
import 'package:nazorat_aat/features/home/domain/usecases/watch_location_usecase.dart';
import 'package:nazorat_aat/features/home/presentation/bloc/map_bloc.dart';

final _point = LocationPoint(
  latitude: 41.311151,
  longitude: 69.279737,
  accuracy: 8,
  timestamp: DateTime.utc(2026, 10, 7, 12),
);

/// Hand written rather than generated: the bloc only ever asks this for a
/// position, and a fake that answers differently on the first call is the
/// whole point of these tests.
class _FakeLocationRepository implements LocationRepository {
  _FakeLocationRepository({
    this.lastKnown,
    this.failures = 0,
    this.alwaysFails = false,
    this.timesOut = false,
  });

  final LocationPoint? lastKnown;

  /// How many of the first [getCurrentLocation] calls answer with a block.
  final int failures;
  final bool alwaysFails;

  /// The other kind of failure: not something the inspector can fix, just a
  /// fix that never arrived in time.
  final bool timesOut;

  var calls = 0;

  @override
  Future<LocationPoint> getCurrentLocation() async {
    calls++;
    if (timesOut) throw Exception('locationTimeoutError');
    if (alwaysFails || calls <= failures) {
      throw const LocationUnavailable(
        LocationBlock.serviceDisabled,
        'locationServiceDisabledError',
      );
    }
    return _point;
  }

  @override
  Stream<LocationPoint> watchLocation() => const Stream.empty();

  @override
  Future<LocationPoint?> lastKnownLocation() async => lastKnown;

  @override
  Future<bool> isServiceEnabled() async => true;

  /// Never emits: the service switch firing would add a retry of its own and
  /// hide what these tests are measuring.
  @override
  Stream<bool> watchServiceEnabled() => const Stream.empty();

  @override
  Future<bool> hasOnlyApproximateAccuracy() async => false;

  @override
  Future<void> openDeviceLocationSettings() async {}

  @override
  Future<void> openAppSettings() async {}
}

MapBloc _blocFor(_FakeLocationRepository repository) => MapBloc(
  GetCurrentLocationUseCase(repository),
  WatchLocationUseCase(repository),
  repository,
);

void main() {
  group('startup', () {
    // The bug this guards: a cold start can report the location service as
    // disabled for a moment, and the map was replaced by a full-screen error
    // page for that moment on a phone whose location was on the whole time.
    test('a block on the first read never reaches the screen', () async {
      final repository = _FakeLocationRepository(failures: 1);
      final bloc = _blocFor(repository);
      final seen = <MapState>[];
      final subscription = bloc.stream.listen(seen.add);

      bloc.add(const MapLocationStarted());
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(seen.whereType<MapLocationBlocked>(), isEmpty);
      expect(seen.whereType<MapLocationFailure>(), isEmpty);
      expect(bloc.state, isA<MapLocationLoaded>());
      expect(repository.calls, 2, reason: 'the quiet retry should have run');

      await subscription.cancel();
      await bloc.close();
    });

    test('the spinner is what shows while it settles', () async {
      final repository = _FakeLocationRepository(failures: 1);
      final bloc = _blocFor(repository);
      final seen = <MapState>[];
      final subscription = bloc.stream.listen(seen.add);

      bloc.add(const MapLocationStarted());
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(seen.last, isA<MapLocationLoading>());

      await subscription.cancel();
      await bloc.close();
    });

    // The retry is one chance, not a loop: location really being off has to
    // reach the inspector, who is the only one who can fix it.
    test('a block that persists is surfaced', () async {
      final repository = _FakeLocationRepository(alwaysFails: true);
      final bloc = _blocFor(repository);

      bloc.add(const MapLocationStarted());
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(bloc.state, isA<MapLocationBlocked>());
      expect(
        (bloc.state as MapLocationBlocked).reason,
        LocationBlock.serviceDisabled,
      );

      await bloc.close();
    });

    // A remembered fix means the map can be drawn, so the banner handles the
    // block and there is nothing to flash.
    test('a remembered position is shown at once, with no retry', () async {
      final repository = _FakeLocationRepository(
        lastKnown: _point,
        alwaysFails: true,
      );
      final bloc = _blocFor(repository);

      bloc.add(const MapLocationStarted());
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(bloc.state, isA<MapLocationBlocked>());
      expect((bloc.state as MapLocationBlocked).lastKnown, _point);

      await bloc.close();
    });
  });

  group('a fix that never arrives', () {
    // Indoors the platform can spend the whole timeout refining an accuracy it
    // will never reach. Taking the map away at that point is the worst of both
    // worlds: the remembered position was good enough to work from.
    test('a remembered position stays on screen', () async {
      final repository = _FakeLocationRepository(
        lastKnown: _point,
        timesOut: true,
      );
      final bloc = _blocFor(repository);
      final seen = <MapState>[];
      final subscription = bloc.stream.listen(seen.add);

      bloc.add(const MapLocationStarted());
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(seen.whereType<MapLocationFailure>(), isEmpty);
      expect(bloc.state, isA<MapLocationLoaded>());
      expect((bloc.state as MapLocationLoaded).isStale, isTrue);

      await subscription.cancel();
      await bloc.close();
    });

    test('with nothing remembered it is still reported', () async {
      final repository = _FakeLocationRepository(timesOut: true);
      final bloc = _blocFor(repository);

      bloc.add(const MapLocationStarted());
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(bloc.state, isA<MapLocationFailure>());

      await bloc.close();
    });
  });

  group('position stream errors', () {
    test('a map already on screen survives one', () async {
      final repository = _FakeLocationRepository();
      final bloc = _blocFor(repository);

      bloc.add(const MapLocationStarted());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(bloc.state, isA<MapLocationLoaded>());

      bloc.add(const MapLocationError('stream died'));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        bloc.state,
        isA<MapLocationLoaded>(),
        reason: 'a transient stream fault must not take the fields away',
      );

      await bloc.close();
    });

    test('with nothing on screen it is reported', () async {
      final repository = _FakeLocationRepository();
      final bloc = _blocFor(repository);

      bloc.add(const MapLocationError('stream died'));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(bloc.state, isA<MapLocationFailure>());

      await bloc.close();
    });
  });
}
