import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/connectivity/connectivity_cubit.dart';
import 'core/connectivity/no_internet_banner.dart';
import 'core/di/injection.dart';
import 'core/download/app_download_overlay.dart';
import 'core/roles/role_controller.dart';
import 'core/roles/role_scope.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_cubit.dart';
import 'features/auth/presentation/bloc/profile_cubit.dart';
import 'features/sync/presentation/bloc/sync_bloc.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => getIt<ThemeCubit>()),
      BlocProvider(create: (_) => getIt<ConnectivityCubit>()),
      BlocProvider(create: (_) => getIt<ProfileCubit>()),
      BlocProvider(create: (_) => getIt<SyncBloc>()..add(const SyncStarted())),
    ],
    // Above the router: the shell asks for the signed-in inspector's module
    // while it builds, and routes live below MaterialApp.
    child: RoleScope(
      controller: getIt<RoleController>(),
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) => MaterialApp.router(
          onGenerateTitle: (ctx) => 'appTitle'.tr(),
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          routerConfig: getIt<AppRouter>().router,
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final isTablet = mq.size.shortestSide >= 600;
            return MediaQuery(
              data: isTablet
                  ? mq.copyWith(textScaler: const TextScaler.linear(1.2))
                  : mq,
              child: AppDownloadOverlay(
                child: NoInternetBanner(
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
