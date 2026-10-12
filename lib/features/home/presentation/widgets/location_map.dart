import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/connectivity/connectivity_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/download/app_download_controller.dart';
import '../../../../core/map/tile_cache_service.dart';
import '../../../../core/map/tile_math.dart';
import '../../../../core/map/uzbekistan_regions.dart';
import '../../../../core/utils/haptic.dart';
import '../../../../core/utils/responsive.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacings.dart';
import '../../../auth/presentation/bloc/profile_cubit.dart';
import '../../../auth/presentation/widgets/role_badge.dart';
import '../../../fields/domain/entities/field_detail.dart';
import '../../../fields/domain/entities/field_summary.dart';
import '../../../fields/domain/repositories/field_repository.dart';
import '../../../fields/presentation/bloc/fields_bloc.dart';
import '../../domain/entities/location_point.dart';
import 'field_form_sheet.dart';
import 'offline_map_download_dialog.dart';

const _tileSubdomains = ['0', '1', '2', '3'];
const _tileUrl = 'https://mt{s}.google.com/vt/lyrs=y&hl=uz&x={x}&y={y}&z={z}';

const _drawingGreen = Color(0xFF00C853);

const _radiusCircleColor = Color(0xFF2979FF);

const _regionalPaddingMeters = 3000.0;
const _regionalMinZoom = 10;
const _regionalMaxZoom = 13;

Future<PendingMapDownload?> computeRegionalMapDownload(
  BuildContext context,
) async {
  final isOnline = context.read<ConnectivityCubit>().state;
  if (!isOnline) return null;

  final languageCode = context.locale.languageCode;
  final retina = RetinaMode.isHighDensity(context);

  final fieldsBounds = await getIt<FieldRepository>().allFieldsBounds();
  if (fieldsBounds == null) return null;

  final regionalBounds = TileMath.padBounds(
    fieldsBounds,
    _regionalPaddingMeters,
  );
  final regionalRegionId = TileCacheService.assignedFieldsRegionId(
    regionalBounds,
  );
  final regionalPending = TileCacheService.shouldPromptDownload(
    regionalRegionId,
    isOnline: isOnline,
    checkFreshness: false,
  );
  if (!regionalPending) return null;

  final regionName = UzbekistanRegions.nearestTo(
    regionalBounds.center,
  ).localizedName(languageCode);

  return PendingMapDownload(
    jobs: [
      TileDownloadJob(
        regionId: regionalRegionId,
        bounds: regionalBounds,
        minZoom: _regionalMinZoom,
        maxZoom: _regionalMaxZoom,
        checkFreshness: false,
      ),
    ],
    title: 'offlineMapCityTitle'.tr(namedArgs: {'region': regionName}),
    body: 'offlineMapCityBody'.tr(namedArgs: {'region': regionName}),
    urlTemplate: _tileUrl,
    subdomains: _tileSubdomains,
    retina: retina,
  );
}

class LocationMap extends StatefulWidget {
  const LocationMap({
    super.key,
    required this.location,
    required this.drawingNotifier,
  });

  final LocationPoint location;
  final ValueNotifier<bool> drawingNotifier;

  @override
  State<LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<LocationMap>
    with TickerProviderStateMixin {
  final _mapController = MapController();
  late final AnimationController _flyController;
  late final CurvedAnimation _flyCurve;

  Animation<double>? _latAnim;
  Animation<double>? _lngAnim;
  Animation<double>? _zoomAnim;

  bool _mapReady = false;
  bool _isDrawing = false;
  bool _offlineDialogChecked = false;
  bool _introPlayed = false;
  final List<List<LatLng>> _polygons = [];
  final List<LatLng> _currentPoints = [];
  Timer? _viewportDebounce;

  bool _followUser = true;

  static const _serverFieldFill = Color(0x3300C853);
  static const _serverFieldBorder = _drawingGreen;
  static const _fieldRadiusMeters = 1000.0;
  static const _fieldMinZoom = 14;
  static const _fieldMaxZoom = 18;
  static const _regionalRadiusMeters = 30000.0;

  static const _zoomCountry = 6.0;
  static const _zoomOverview = 13.0;
  static const _zoomDetail = 17.0;
  static const _allowedZooms = [_zoomCountry, _zoomOverview, _zoomDetail];

  static const _onlineMinZoom = 3.0;
  static const _onlineMaxZoom = 19.0;

  static const _zoomGestureSources = {
    MapEventSource.multiFingerGestureStart,
    MapEventSource.onMultiFinger,
    MapEventSource.scrollWheel,
    MapEventSource.doubleTapZoomAnimationController,
  };

  Timer? _zoomGestureIdleTimer;
  bool _zoomIndicatorVisible = false;
  double _zoomIndicatorZoom = _zoomOverview;

  Future<void> _maybePromptOfflineDownload() async {
    if (_offlineDialogChecked || !mounted) return;
    _offlineDialogChecked = true;

    final center = LatLng(widget.location.latitude, widget.location.longitude);
    final isOnline = context.read<ConnectivityCubit>().state;
    if (!isOnline) return;

    final fieldsBounds = await getIt<FieldRepository>().allFieldsBounds();
    if (!mounted) return;
    final regionalBounds = fieldsBounds == null
        ? TileMath.boundsFor(center, _regionalRadiusMeters)
        : TileMath.padBounds(fieldsBounds, _regionalPaddingMeters);
    final regionalRegionId = fieldsBounds == null
        ? TileCacheService.regionalRegionId(center)
        : TileCacheService.assignedFieldsRegionId(regionalBounds);
    final regionalPending = TileCacheService.shouldPromptDownload(
      regionalRegionId,
      isOnline: isOnline,
      checkFreshness: false,
    );
    final fieldRegionId = TileCacheService.locationRegionId(center);
    final fieldPending = TileCacheService.shouldPromptDownload(
      fieldRegionId,
      isOnline: isOnline,
    );

    final jobs = [
      if (regionalPending)
        TileDownloadJob(
          regionId: regionalRegionId,
          bounds: regionalBounds,
          minZoom: _regionalMinZoom,
          maxZoom: _regionalMaxZoom,
          checkFreshness: false,
        ),
      if (fieldPending)
        TileDownloadJob(
          regionId: fieldRegionId,
          bounds: TileMath.boundsFor(center, _fieldRadiusMeters),
          minZoom: _fieldMinZoom,
          maxZoom: _fieldMaxZoom,
        ),
    ];
    if (jobs.isEmpty) return;

    final regionName = UzbekistanRegions.nearestTo(
      regionalBounds.center,
    ).localizedName(context.locale.languageCode);

    final String title;
    final String body;
    if (regionalPending && fieldPending) {
      title = 'offlineMapCombinedTitle'.tr(namedArgs: {'region': regionName});
      body = 'offlineMapCombinedBody'.tr(namedArgs: {'region': regionName});
    } else if (regionalPending) {
      title = 'offlineMapCityTitle'.tr(namedArgs: {'region': regionName});
      body = 'offlineMapCityBody'.tr(namedArgs: {'region': regionName});
    } else {
      title = 'offlineMapTitle'.tr();
      body = 'offlineMapBody'.tr();
    }

    showOfflineMapDownloadDialog(
      context,
      jobs: jobs,
      title: title,
      body: body,
      urlTemplate: _tileUrl,
      subdomains: _tileSubdomains,
      retina: RetinaMode.isHighDensity(context),
    );
  }

  Future<void> _seedMockFields() async {
    await getIt<FieldRepository>().seedMockFieldsIfEmpty(
      LatLng(widget.location.latitude, widget.location.longitude),
    );
    if (!mounted || !_mapReady) return;
    final camera = _mapController.camera;
    context.read<FieldsBloc>().add(
      FieldsViewportChanged(bounds: camera.visibleBounds, zoom: camera.zoom),
    );
  }

  void _playCityIntro() {
    if (_introPlayed || !mounted) return;
    _introPlayed = true;
    unawaited(_seedMockFields());

    Future.delayed(const Duration(milliseconds: 3500), () {
      if (!mounted || !_followUser) return;
      _flyTo(
        LatLng(widget.location.latitude, widget.location.longitude),
        zoom: _zoomDetail,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _flyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addListener(_onFlyTick);
    _flyCurve = CurvedAnimation(
      parent: _flyController,
      curve: Curves.easeInOutCubic,
    );
    TileCacheService.cacheVersion.addListener(_onCacheCleared);
  }

  void _onCacheCleared() {
    if (!mounted) return;
    _offlineDialogChecked = false;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      unawaited(_maybePromptOfflineDownload());
    });
  }

  void _onFlyTick() {
    if (_latAnim == null || !_mapReady) return;
    _mapController.move(
      LatLng(_latAnim!.value, _lngAnim!.value),
      _zoomAnim!.value,
    );
  }

  void _flyTo(LatLng target, {double? zoom}) {
    if (!_mapReady) return;
    final cam = _mapController.camera;
    _latAnim = Tween<double>(
      begin: cam.center.latitude,
      end: target.latitude,
    ).animate(_flyCurve);
    _lngAnim = Tween<double>(
      begin: cam.center.longitude,
      end: target.longitude,
    ).animate(_flyCurve);
    _zoomAnim = Tween<double>(
      begin: cam.zoom,
      end: zoom ?? cam.zoom,
    ).animate(_flyCurve);
    _flyController.forward(from: 0);
  }

  @override
  void didUpdateWidget(LocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_followUser || !_mapReady) return;
    if (oldWidget.location == widget.location) return;

    final target = LatLng(widget.location.latitude, widget.location.longitude);
    if (_distanceCalc.distance(_mapController.camera.center, target) <
        _followMinMeters) {
      return;
    }
    _flyTo(target);
  }

  @override
  void dispose() {
    TileCacheService.cacheVersion.removeListener(_onCacheCleared);
    _viewportDebounce?.cancel();
    _zoomGestureIdleTimer?.cancel();
    _flyController.dispose();
    _flyCurve.dispose();
    super.dispose();
  }

  void _onMapEvent(MapEvent event) {
    if (_zoomGestureSources.contains(event.source)) {
      _zoomGestureIdleTimer?.cancel();
      setState(() {
        _zoomIndicatorVisible = true;
        _zoomIndicatorZoom = event.camera.zoom;
      });
      _zoomGestureIdleTimer = Timer(
        const Duration(milliseconds: 180),
        () => _endZoomGesture(event.camera),
      );
      return;
    }
    final isPinchEnd =
        event is MapEventMoveEnd &&
        event.source == MapEventSource.multiFingerEnd;
    if (isPinchEnd || event is MapEventDoubleTapZoomEnd) {
      _zoomGestureIdleTimer?.cancel();
      _endZoomGesture(event.camera);
    }
  }

  double _nearestAllowedZoom(double zoom) => _allowedZooms.reduce(
    (a, b) => (zoom - a).abs() <= (zoom - b).abs() ? a : b,
  );

  double _nextAllowedZoom(double zoom) => _allowedZooms.firstWhere(
    (z) => z > zoom + 0.01,
    orElse: () => _allowedZooms.last,
  );

  double _prevAllowedZoom(double zoom) => _allowedZooms.reversed.firstWhere(
    (z) => z < zoom - 0.01,
    orElse: () => _allowedZooms.first,
  );

  void _endZoomGesture(MapCamera camera) {
    if (!mounted) return;
    setState(() => _zoomIndicatorVisible = false);
    if (context.read<ConnectivityCubit>().state) return;
    final nearest = _nearestAllowedZoom(camera.zoom);
    if ((camera.zoom - nearest).abs() > 0.01) {
      _flyTo(camera.center, zoom: nearest);
    }
  }

  String _formatZoomLevel(double zoom) {
    final rounded = (zoom * 10).round() / 10;
    if (rounded == rounded.roundToDouble()) {
      return rounded.toStringAsFixed(0);
    }
    return rounded.toStringAsFixed(1);
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    // Only a real gesture counts. Our own _flyTo also lands here, and treating
    // that as panning would switch following off the moment it was switched on.
    if (hasGesture && _followUser) {
      setState(() => _followUser = false);
    }
    _viewportDebounce?.cancel();
    _viewportDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      context.read<FieldsBloc>().add(
        FieldsViewportChanged(bounds: camera.visibleBounds, zoom: camera.zoom),
      );
    });
  }

  static const _maxRadiusMeters = 300.0;
  static const _distanceCalc = Distance();

  static const _followMinMeters = 15.0;

  void _onMapTap(TapPosition tapPos, LatLng point) {
    if (_isDrawing) {
      final userLatLng = LatLng(
        widget.location.latitude,
        widget.location.longitude,
      );
      final meters = _distanceCalc.as(LengthUnit.Meter, userLatLng, point);
      if (meters > _maxRadiusMeters) {
        final km = (meters / 1000).toStringAsFixed(1);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.location_off_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('pointTooFar'.tr(namedArgs: {'km': km})),
                  ),
                ],
              ),
              backgroundColor: kError,
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }
      setState(() => _currentPoints.add(point));
      return;
    }
    final serverFields = context.read<FieldsBloc>().state.fields;
    for (final field in serverFields) {
      if (field.points.length >= 3 && _isPointInPolygon(point, field.points)) {
        _showServerFieldDetail(field);
        return;
      }
    }
    for (int i = 0; i < _polygons.length; i++) {
      if (_polygons[i].length >= 3 && _isPointInPolygon(point, _polygons[i])) {
        _showFieldFormSheet(i);
        return;
      }
    }
  }

  void _showServerFieldDetail(FieldSummary field) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: context.isTablet
          ? BoxConstraints(maxWidth: context.sheetMaxWidth)
          : null,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ServerFieldDetailSheet(field: field),
    );
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    bool inside = false;
    final px = point.longitude;
    final py = point.latitude;
    final n = polygon.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;
      if (((yi > py) != (yj > py)) &&
          px < (xj - xi) * (py - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
    }
    return inside;
  }

  static double _metersPerPixelAtZoom0(double latitude) =>
      156543.03392 * math.cos(latitude * math.pi / 180);

  double _radiusFitZoom(double latitude) {
    final size = MediaQuery.of(context).size;
    final availablePx = math.min(size.width, size.height) * 0.8;
    final metersPerPixelNeeded = (_maxRadiusMeters * 2) / availablePx;
    final zoom =
        math.log(_metersPerPixelAtZoom0(latitude) / metersPerPixelNeeded) /
        math.ln2;
    return zoom.clamp(_zoomOverview, _zoomDetail);
  }

  void _startDrawing() {
    setState(() {
      _isDrawing = true;
      _currentPoints.clear();
    });
    widget.drawingNotifier.value = true;
    final userLatLng = LatLng(
      widget.location.latitude,
      widget.location.longitude,
    );
    final fitZoom = _radiusFitZoom(userLatLng.latitude);
    if (_mapController.camera.zoom > fitZoom + 0.01) {
      _flyTo(userLatLng, zoom: fitZoom);
    }
  }

  void _cancelDrawing() {
    setState(() {
      _isDrawing = false;
      _currentPoints.clear();
    });
    widget.drawingNotifier.value = false;
  }

  void _removeLastPoint() {
    if (_currentPoints.isEmpty) return;
    setState(() => _currentPoints.removeLast());
  }

  void _finishDrawing() {
    if (_currentPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('minPointsRequired'.tr()),
          backgroundColor: kError,
        ),
      );
      return;
    }
    final completed = List<LatLng>.from(_currentPoints);
    setState(() {
      _polygons.add(completed);
      _currentPoints.clear();
      _isDrawing = false;
    });
    widget.drawingNotifier.value = false;
  }

  void _showFieldFormSheet(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: context.isTablet
          ? BoxConstraints(maxWidth: context.sheetMaxWidth)
          : null,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FieldFormSheet(
        points: List.unmodifiable(_polygons[index]),
        onDelete: () => setState(() => _polygons.removeAt(index)),
        onRedraw: () {
          setState(() => _polygons.removeAt(index));
          _startDrawing();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final latLng = LatLng(widget.location.latitude, widget.location.longitude);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = context.watch<ConnectivityCubit>().state;
    final polygonFill = _drawingGreen.withAlpha(150);
    final polygonBorder = _drawingGreen;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: TileMath.boundsFor(latLng, _regionalRadiusMeters),
              padding: const EdgeInsets.all(24),
            ),
            minZoom: isOnline ? _onlineMinZoom : _zoomCountry,
            maxZoom: isOnline ? _onlineMaxZoom : _zoomDetail,
            onMapReady: () {
              setState(() => _mapReady = true);
              _playCityIntro();
            },
            onTap: _onMapTap,
            onPositionChanged: _onPositionChanged,
            onMapEvent: _onMapEvent,
          ),
          children: [
            TileLayer(
              urlTemplate: _tileUrl,
              subdomains: _tileSubdomains,
              userAgentPackageName: 'uz.dala.nazorati',
              maxNativeZoom: 19,
              keepBuffer: 5,
              retinaMode: RetinaMode.isHighDensity(context),
              tileDisplay: const TileDisplay.fadeIn(),
              tileProvider: TileCacheService.build(isOnline: isOnline),
            ),
            BlocBuilder<FieldsBloc, FieldsState>(
              builder: (context, state) => PolygonLayer(
                polygonCulling: true,
                simplificationTolerance: 3,
                polygons: [
                  for (final field in state.fields)
                    if (field.points.length >= 3)
                      Polygon(
                        points: field.points,
                        color: _serverFieldFill,
                        borderColor: _serverFieldBorder,
                        borderStrokeWidth: 2,
                      ),
                ],
              ),
            ),
            if (_isDrawing)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: latLng,
                    radius: _maxRadiusMeters,
                    useRadiusInMeter: true,
                    color: _radiusCircleColor.withAlpha(40),
                    borderColor: _radiusCircleColor.withAlpha(220),
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            for (final poly in _polygons)
              if (poly.length >= 2)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: poly,
                      color: polygonFill,
                      borderColor: polygonBorder,
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                ),
            if (_currentPoints.length >= 2)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: _currentPoints,
                    color: _drawingGreen.withAlpha(150),
                    borderColor: _drawingGreen,
                    borderStrokeWidth: 2.5,
                  ),
                ],
              ),
            if (_currentPoints.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (var i = 0; i < _currentPoints.length; i++)
                    Marker(
                      point: _currentPoints[i],
                      width: 28,
                      height: 28,
                      child: _CornerMarker(index: i + 1),
                    ),
                ],
              ),
            MarkerLayer(
              markers: [
                Marker(
                  point: latLng,
                  width: 48,
                  height: 48,
                  child: const _PulsingMarker(),
                ),
              ],
            ),
          ],
        ),
        if (!_isDrawing)
          Positioned(
            top: MediaQuery.of(context).padding.top + context.spaceSm,
            left: context.rs(12.0, 18.0),
            child: const _MapRoleChip(),
          ),
        if (!_isDrawing)
          Positioned(
            bottom: context.rs(32.0, 48.0) + kFloatingNavBarClearance,
            right: context.rs(16.0, 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IgnorePointer(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.bottomCenter,
                    child: _zoomIndicatorVisible
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ZoomLevelIndicator(
                              label: "${_formatZoomLevel(_zoomIndicatorZoom)}X",
                              isDark: isDark,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                _MapButton(
                  heroTag: 'zoom_in',
                  icon: Icons.add,
                  onPressed: hTap(
                    () => _flyTo(
                      _mapController.camera.center,
                      zoom: isOnline
                          ? (_mapController.camera.zoom + 1).clamp(
                              _onlineMinZoom,
                              _onlineMaxZoom,
                            )
                          : _nextAllowedZoom(_mapController.camera.zoom),
                    ),
                  )!,
                ),
                kVerticalSpace8,
                _MapButton(
                  heroTag: 'zoom_out',
                  icon: Icons.remove,
                  onPressed: hTap(
                    () => _flyTo(
                      _mapController.camera.center,
                      zoom: isOnline
                          ? (_mapController.camera.zoom - 1).clamp(
                              _onlineMinZoom,
                              _onlineMaxZoom,
                            )
                          : _prevAllowedZoom(_mapController.camera.zoom),
                    ),
                  )!,
                ),
                kVerticalSpace8,
                _MapButton(
                  heroTag: 'my_location',
                  icon: _followUser
                      ? Icons.my_location
                      : Icons.location_searching,
                  onPressed: hTap(() {
                    setState(() => _followUser = true);
                    _flyTo(latLng, zoom: _zoomDetail);
                  })!,
                ),
                kVerticalSpace8,
                _MapButton(
                  heroTag: 'draw_field',
                  icon: Icons.draw_rounded,
                  onPressed: hTap(_startDrawing)!,
                ),
              ],
            ),
          ),
        if (_isDrawing) ...[
          Positioned(
            top: MediaQuery.of(context).padding.top + context.spaceSm,
            left: context.rs(12.0, 18.0),
            child: _DrawingTopButton(
              heroTag: 'undo_draw',
              icon: _currentPoints.isEmpty
                  ? Icons.close_rounded
                  : Icons.undo_rounded,
              label: _currentPoints.isEmpty ? 'cancelAction'.tr() : 'undo'.tr(),
              enabled: true,
              isDark: isDark,
              onPressed: hTap(
                _currentPoints.isEmpty ? _cancelDrawing : _removeLastPoint,
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + context.spaceSm,
            right: context.rs(12.0, 18.0),
            child: _DrawingDoneButton(
              enabled: _currentPoints.length >= 3,
              onPressed: hTapMedium(
                _currentPoints.length >= 3 ? _finishDrawing : null,
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _DrawingBottomBar(
              pointCount: _currentPoints.length,
              onCancel: _cancelDrawing,
            ),
          ),
        ],
      ],
    );
  }
}

/// Floating pill naming the inspectorate the map belongs to.
///
/// The map itself is the same for everyone; this is what tells a user whether
/// they are looking at it as a quarantine, veterinary or SES inspector.
class _MapRoleChip extends StatelessWidget {
  const _MapRoleChip();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<ProfileCubit>().state;
    if (user == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E20) : Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: RoleBadge(role: user.inspectorRole, compact: true),
    );
  }
}

class _DrawingTopButton extends StatelessWidget {
  const _DrawingTopButton({
    required this.heroTag,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.isDark,
    required this.onPressed,
  });

  final String heroTag;
  final IconData icon;
  final String label;
  final bool enabled;
  final bool isDark;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF2A2A2A) : kWhite;
    final fg = enabled
        ? (isDark ? kGreenLight : kGreen)
        : (isDark ? Colors.white24 : Colors.black26);

    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(context.fabRadius),
          border: Border.all(color: fg, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawingDoneButton extends StatelessWidget {
  const _DrawingDoneButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  colors: [kGreen, kGreenLight],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: enabled ? null : Colors.grey.withAlpha(80),
          borderRadius: BorderRadius.circular(context.fabRadius),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: kGreen.withAlpha(80),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_rounded,
              size: 18,
              color: enabled ? Colors.white : Colors.white54,
            ),
            const SizedBox(width: 5),
            Text(
              'done'.tr(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: enabled ? Colors.white : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawingBottomBar extends StatelessWidget {
  const _DrawingBottomBar({required this.pointCount, required this.onCancel});

  final int pointCount;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // The surrounding Scaffold declares a `bottomNavigationBar`, so it strips
    // the bottom inset out of the MediaQuery it hands to its body — and while
    // drawing that bar collapses to zero height, leaving nothing to clear the
    // system navigation bar. Read the inset straight from the view instead, or
    // the cancel button ends up underneath it.
    final bottom = MediaQueryData.fromView(View.of(context)).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, bottom + 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: kGreen.withAlpha(18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kGreen.withAlpha(60)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.touch_app_rounded, color: kGreen, size: 15),
                kHorizontalSpace8,
                Text(
                  pointCount == 0
                      ? 'drawingPrompt'.tr()
                      : 'drawingPointsAdded'.tr(
                          namedArgs: {'count': pointCount.toString()},
                        ),
                  style: const TextStyle(
                    color: kGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          kVerticalSpace12,
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: hTapHeavy(onCancel),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: Text(
                'cancelAction'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: kError,
                side: const BorderSide(color: kError, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          kVerticalSpace24,
        ],
      ),
    );
  }
}

class _CornerMarker extends StatelessWidget {
  const _CornerMarker({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: kGreen,
      shape: BoxShape.circle,
      border: Border.all(color: kWhite, width: 2),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
    ),
    child: Text(
      '$index',
      style: const TextStyle(
        color: kWhite,
        fontWeight: FontWeight.bold,
        fontSize: 11,
      ),
    ),
  );
}

class _PulsingMarker extends StatefulWidget {
  const _PulsingMarker();

  @override
  State<_PulsingMarker> createState() => _PulsingMarkerState();
}

class _PulsingMarkerState extends State<_PulsingMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _scale = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeOut));
    _opacity = Tween<double>(
      begin: 0.6,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => Opacity(
          opacity: _opacity.value,
          child: Container(
            width: 48 * _scale.value,
            height: 48 * _scale.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kGreen.withAlpha(60),
              border: Border.all(color: kGreen.withAlpha(120), width: 1.5),
            ),
          ),
        ),
      ),
      Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: kGreen,
          shape: BoxShape.circle,
          border: Border.all(color: kWhite, width: 3),
          boxShadow: [
            BoxShadow(
              color: kGreen.withAlpha(120),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    ],
  );
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.heroTag,
    required this.icon,
    required this.onPressed,
  });

  final String heroTag;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF2A2A2A) : kWhite;
    final fg = isDark ? kGreenLight : kGreen;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(context.fabRadius),
      side: BorderSide(color: fg),
    );
    final child = Icon(icon, size: context.fabIconSize);

    if (context.isTablet) {
      return FloatingActionButton(
        heroTag: heroTag,
        onPressed: onPressed,
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 3,
        shape: shape,
        child: child,
      );
    }
    return FloatingActionButton.small(
      heroTag: heroTag,
      onPressed: onPressed,
      backgroundColor: bg,
      foregroundColor: fg,
      elevation: 3,
      shape: shape,
      child: child,
    );
  }
}

class _ZoomLevelIndicator extends StatelessWidget {
  const _ZoomLevelIndicator({required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF2A2A2A) : kWhite;
    final fg = isDark ? kGreenLight : kGreen;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _ServerFieldDetailSheet extends StatelessWidget {
  const _ServerFieldDetailSheet({required this.field});

  final FieldSummary field;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).padding.bottom;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 14, 20, bottom + 20),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                field.name,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                field.cropType,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FutureBuilder<FieldDetail>(
                future: getIt<FieldRepository>().getFieldDetail(field.id),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return Text(
                      'errorGeneric'.tr(),
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    );
                  }
                  return Text(
                    snapshot.data!.description,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
