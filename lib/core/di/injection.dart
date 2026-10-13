import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import '../../features/auth/data/datasources/auth_remote_datasource.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/gov_login_usecase.dart';
import '../../features/auth/domain/usecases/karantin_login_usecase.dart';
import '../../features/auth/domain/usecases/login_usecase.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/bloc/profile_cubit.dart';
import '../../features/fields/data/datasources/field_remote_datasource.dart';
import '../../features/fields/data/field_spatial_index.dart';
import '../../features/fields/data/repositories/field_repository_impl.dart';
import '../../features/fields/domain/repositories/field_repository.dart';
import '../../features/fields/presentation/bloc/fields_bloc.dart';
import '../../features/home/data/repositories/location_repository_impl.dart';
import '../../features/home/domain/repositories/location_repository.dart';
import '../../features/home/domain/usecases/get_current_location_usecase.dart';
import '../../features/home/domain/usecases/watch_location_usecase.dart';
import '../../features/home/presentation/bloc/map_bloc.dart';
import '../../features/reference/data/datasources/reference_remote_datasource.dart';
import '../../features/reference/data/repositories/reference_repository_impl.dart';
import '../../features/reference/domain/repositories/reference_repository.dart';
import '../../features/reference/presentation/bloc/reference_cubit.dart';
import '../../features/sync/presentation/bloc/sync_bloc.dart';
import '../connectivity/connectivity_cubit.dart';
import '../constants/storage_keys.dart';
import '../download/app_download_controller.dart';
import '../network/dio_service.dart';
import '../theme/theme_cubit.dart';
import '../notifications/push_service.dart';
import '../update/remote_config_service.dart';
import '../update/shorebird_update_service.dart';
import '../roles/role_controller.dart';
import '../router/app_router.dart';
import '../storage/hive_service.dart';
import '../storage/map_object_database.dart';
import '../storage/map_object_store.dart';
import '../storage/offline_sync_service.dart';
import '../storage/secure_storage_service.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  const secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  getIt.registerLazySingleton<FlutterSecureStorage>(() => secureStorage);
  getIt.registerLazySingleton<Connectivity>(() => Connectivity());

  getIt.registerLazySingleton<SecureStorageService>(
    () => SecureStorageService(getIt()),
  );
  final hiveService = await HiveService.create();
  getIt.registerSingleton<HiveService>(hiveService);

  // Map objects live in SQLite, not Hive: a province-sized download is tens of
  // thousands of polygons and only the ones under the viewport belong in
  // memory. Hive keeps what it is good at - tokens, FCM state, settings, the
  // offline queue.
  getIt.registerSingleton<MapObjectStore>(
    MapObjectStore(await MapObjectDatabase.open()),
  );
  getIt.registerLazySingleton<OfflineSyncService>(
    () => OfflineSyncService(getIt(), getIt()),
  );

  if (hiveService.userBox.get(StorageKeys.installMarker) != true) {
    await getIt<SecureStorageService>().clearTokens();
    await hiveService.userBox.put(StorageKeys.installMarker, true);
  }

  getIt.registerLazySingleton<DioService>(
    () => DioService(getIt<SecureStorageService>()),
  );

  // Registered before AppRouter, which resolves the role into it during the
  // splash redirect so the shell never builds without one.
  getIt.registerLazySingleton<RoleController>(() => RoleController());

  getIt.registerLazySingleton<AppRouter>(
    () => AppRouter(getIt(), getIt(), getIt()),
  );

  getIt.registerLazySingleton<ThemeCubit>(() => ThemeCubit(getIt()));

  getIt.registerLazySingleton<PushService>(() => PushService());

  getIt.registerLazySingleton<RemoteConfigService>(() => RemoteConfigService());

  getIt.registerLazySingleton<ShorebirdUpdateService>(
    () => ShorebirdUpdateService(),
  );

  getIt.registerLazySingleton<ConnectivityCubit>(
    () => ConnectivityCubit(getIt()),
  );

  getIt.registerLazySingleton<AuthRemoteDataSource>(
    () => AuthRemoteDataSource(getIt()),
  );
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(getIt(), getIt(), getIt()),
  );
  getIt.registerLazySingleton<LoginUseCase>(() => LoginUseCase(getIt()));
  getIt.registerLazySingleton<GovLoginUseCase>(() => GovLoginUseCase(getIt()));
  getIt.registerLazySingleton<KarantinLoginUseCase>(
    () => KarantinLoginUseCase(getIt()),
  );
  getIt.registerFactory<AuthBloc>(() => AuthBloc(getIt(), getIt(), getIt()));
  getIt.registerLazySingleton<ProfileCubit>(
    () => ProfileCubit(getIt(), getIt(), getIt()),
  );

  getIt.registerLazySingleton<LocationRepository>(
    () => LocationRepositoryImpl(),
  );
  getIt.registerLazySingleton<GetCurrentLocationUseCase>(
    () => GetCurrentLocationUseCase(getIt()),
  );
  getIt.registerLazySingleton<WatchLocationUseCase>(
    () => WatchLocationUseCase(getIt()),
  );
  getIt.registerFactory<MapBloc>(() => MapBloc(getIt(), getIt(), getIt()));

  getIt.registerLazySingleton<FieldRemoteDataSource>(
    () => FieldRemoteDataSource(getIt()),
  );
  final fieldSpatialIndex = FieldSpatialIndex();
  getIt.registerSingleton<FieldSpatialIndex>(fieldSpatialIndex);
  getIt.registerSingleton<FieldRepository>(
    FieldRepositoryImpl(
      getIt<FieldRemoteDataSource>(),
      getIt<HiveService>(),
      fieldSpatialIndex,
      getIt<MapObjectStore>(),
    ),
  );
  getIt.registerFactory<FieldsBloc>(() => FieldsBloc(getIt()));

  getIt.registerLazySingleton<ReferenceRemoteDataSource>(
    () => ReferenceRemoteDataSource(),
  );
  getIt.registerLazySingleton<ReferenceRepository>(
    () => ReferenceRepositoryImpl(getIt(), getIt()),
  );
  getIt.registerFactory<ReferenceCubit>(() => ReferenceCubit(getIt()));

  getIt.registerSingleton<SyncBloc>(
    SyncBloc(getIt<OfflineSyncService>(), getIt<DioService>()),
  );

  getIt.registerLazySingleton<AppDownloadController>(
    () => AppDownloadController(),
  );
}
