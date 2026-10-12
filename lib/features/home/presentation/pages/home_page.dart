import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/haptic.dart';
import '../../../../core/utils/responsive.dart';
import '../../../fields/presentation/bloc/fields_bloc.dart';
import '../../../reference/domain/repositories/reference_repository.dart';
import '../../domain/repositories/location_repository.dart';
import '../bloc/map_bloc.dart';
import '../widgets/app_download_dialog.dart';
import '../widgets/location_map.dart';
import '../widgets/location_status_banner.dart';
import 'fake_gps_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.isDrawing});

  final ValueNotifier<bool> isDrawing;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => getIt<MapBloc>()..add(const MapLocationStarted()),
      ),
      BlocProvider(create: (_) => getIt<FieldsBloc>()),
    ],
    child: _HomeView(isDrawing: isDrawing),
  );
}

class _HomeView extends StatefulWidget {
  const _HomeView({required this.isDrawing});

  final ValueNotifier<bool> isDrawing;

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  @override
  void initState() {
    super.initState();
    unawaited(_maybeOfferDownloads());
  }

  Future<void> _maybeOfferDownloads() async {
    final includeCatalog = !getIt<ReferenceRepository>().isCatalogCached();
    if (!mounted) return;
    final mapDownload = await computeRegionalMapDownload(context);
    if (!mounted || (!includeCatalog && mapDownload == null)) return;

    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    await showAppDownloadDialog(
      context,
      includeCatalog: includeCatalog,
      mapDownload: mapDownload,
    );
  }

  Future<void> _resolveLocationBlock(LocationBlock reason) async {
    final repository = getIt<LocationRepository>();
    if (reason == LocationBlock.serviceDisabled) {
      await repository.openDeviceLocationSettings();
    } else {
      await repository.openAppSettings();
    }
    if (!mounted) return;
    context.read<MapBloc>().add(const MapLocationRetried());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<MapBloc, MapState>(
        builder: (context, state) => switch (state) {
          MapInitial() => const SizedBox.expand(),
          MapLocationLoading() => const _LoadingView(),
          MapLocationLoaded(:final location) => LocationMap(
            location: location,
            drawingNotifier: widget.isDrawing,
          ),
          MapLocationBlocked(:final reason, :final lastKnown, :final message) =>
            lastKnown == null
                ? _ErrorView(message: message.tr())
                : Stack(
                    children: [
                      LocationMap(
                        location: lastKnown,
                        drawingNotifier: widget.isDrawing,
                      ),
                      Align(
                        alignment: Alignment.topCenter,
                        child: LocationStatusBanner(
                          reason: reason,
                          onPressed: () => _resolveLocationBlock(reason),
                        ),
                      ),
                    ],
                  ),
          MapFakeGpsDetected() => const FakeGpsPage(),
          MapLocationFailure(:final message) => _ErrorView(message: message),
        },
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(color: kGreen));
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(context.spaceLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_off, size: context.iconLg, color: kGreen),
          SizedBox(height: context.spaceMd),
          Text(message, textAlign: TextAlign.center),
          SizedBox(height: context.spaceMd),
          ElevatedButton(
            onPressed: hTap(
              () => context.read<MapBloc>().add(const MapLocationStarted()),
            ),
            child: Text('retry'.tr()),
          ),
        ],
      ),
    ),
  );
}
