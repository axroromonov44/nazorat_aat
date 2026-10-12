import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/observability/diagnostics_log.dart';
import '../../domain/entities/location_point.dart';
import '../../domain/repositories/location_repository.dart';
import '../../domain/usecases/get_current_location_usecase.dart';
import '../../domain/usecases/watch_location_usecase.dart';

part 'map_event.dart';
part 'map_state.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  MapBloc(
    this._getCurrentLocationUseCase,
    this._watchLocationUseCase,
    this._locationRepository,
  ) : super(const MapInitial()) {
    on<MapLocationStarted>(_onLocationStarted);
    on<MapLocationRetried>(_onLocationStarted);
    on<MapLocationUpdated>(_onLocationUpdated);
    on<MapLocationError>(_onLocationError);
    on<MapServiceStatusChanged>(_onServiceStatusChanged);
  }

  final GetCurrentLocationUseCase _getCurrentLocationUseCase;
  final WatchLocationUseCase _watchLocationUseCase;
  final LocationRepository _locationRepository;

  static const _tag = 'map';

  StreamSubscription<LocationPoint>? _locationSubscription;
  StreamSubscription<bool>? _serviceSubscription;

  /// A cold start can report the location service as disabled for a moment
  /// before the platform settles, and the first permission read can land in
  /// the same gap. Surfacing that straight away replaced the whole map with an
  /// error page for an instant on a phone whose location had been on the whole
  /// time, so the first such answer buys one quiet retry instead.
  static const _settleDelay = Duration(milliseconds: 1200);
  bool _settleRetryUsed = false;

  Future<void> _onLocationStarted(
    MapEvent event,
    Emitter<MapState> emit,
  ) async {
    // Watching the switch is what lets the map heal by itself. Subscribing once
    // and keeping it is deliberate: it has to survive the failure below, which
    // is the case it exists for.
    _serviceSubscription ??= _locationRepository.watchServiceEnabled().listen(
      (enabled) => add(MapServiceStatusChanged(enabled: enabled)),
    );

    // A remembered fix draws the map now, instead of after a cold GPS lock that
    // can take a minute in the open and never arrive indoors.
    final remembered = await _locationRepository.lastKnownLocation();
    if (remembered != null && state is! MapLocationLoaded) {
      emit(MapLocationLoaded(remembered, isStale: true));
    } else if (remembered == null) {
      emit(const MapLocationLoading());
    }

    try {
      final location = await _getCurrentLocationUseCase();
      emit(
        location.isMocked
            ? const MapFakeGpsDetected()
            : MapLocationLoaded(location),
      );

      await _startWatching();
    } on LocationUnavailable catch (e) {
      // Nothing on screen to fall back on and the platform has not had a
      // chance to settle: wait and ask once more rather than flashing an error
      // page. The state stays MapLocationLoading, so the inspector sees the
      // spinner continue instead of the map being taken away.
      if (remembered == null && !_settleRetryUsed) {
        _settleRetryUsed = true;
        DiagnosticsLog.info(_tag, 'location blocked at startup, retrying once');
        await Future<void>.delayed(_settleDelay);
        if (isClosed) return;
        add(const MapLocationRetried());
        return;
      }
      DiagnosticsLog.warn(_tag, 'location blocked: ${e.reason.name}');
      emit(
        MapLocationBlocked(
          reason: e.reason,
          message: e.message,
          lastKnown: remembered,
        ),
      );
    } catch (e) {
      DiagnosticsLog.error(_tag, 'location failed', error: e);
      // A remembered fix on screen beats an error page. In the field the first
      // precise fix is often late and sometimes never comes, and the inspector
      // can work from a slightly stale position — but not from a page that
      // took the map away. The stream still runs, so the map corrects itself
      // the moment the platform produces a fix.
      if (remembered != null) {
        emit(MapLocationLoaded(remembered, isStale: true));
        await _startWatching();
        return;
      }
      emit(MapLocationFailure(e.toString()));
    }
  }

  Future<void> _startWatching() async {
    await _locationSubscription?.cancel();
    _locationSubscription = _watchLocationUseCase().listen(
      (loc) => add(MapLocationUpdated(loc)),
      onError: (Object e) => add(MapLocationError(e.toString())),
    );
  }

  void _onLocationUpdated(MapLocationUpdated event, Emitter<MapState> emit) =>
      emit(
        event.location.isMocked
            ? const MapFakeGpsDetected()
            : MapLocationLoaded(event.location),
      );

  void _onLocationError(MapLocationError event, Emitter<MapState> emit) {
    // The position stream fails transiently in the field all the time. Taking
    // the map down for it would cost the inspector the fields they are reading
    // over a fault that is usually gone by the next emission, so a position
    // already on screen is kept and only the log records it.
    final current = state;
    DiagnosticsLog.warn(_tag, 'position stream error', error: event.message);
    if (current is MapLocationLoaded) return;
    emit(MapLocationFailure(event.message));
  }

  Future<void> _onServiceStatusChanged(
    MapServiceStatusChanged event,
    Emitter<MapState> emit,
  ) async {
    if (event.enabled) {
      add(const MapLocationRetried());
      return;
    }

    // Keep whatever position is on screen. Losing the map because the switch
    // was flipped would throw away the fields an offline inspector is reading.
    final current = state;
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    emit(
      MapLocationBlocked(
        reason: LocationBlock.serviceDisabled,
        message: 'locationServiceDisabledError',
        lastKnown: switch (current) {
          MapLocationLoaded(:final location) => location,
          MapLocationBlocked(:final lastKnown) => lastKnown,
          _ => null,
        },
      ),
    );
  }

  @override
  Future<void> close() {
    _locationSubscription?.cancel();
    _serviceSubscription?.cancel();
    return super.close();
  }
}
