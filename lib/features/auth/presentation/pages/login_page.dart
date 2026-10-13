import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/locale/language_switcher.dart';
import '../../../../core/roles/role_controller.dart';
import '../../../../core/theme/theme_cubit.dart';
import '../../../../core/utils/responsive.dart';
import '../../../sync/presentation/bloc/sync_bloc.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/login_form.dart';
import '../widgets/login_metrics.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocProvider(create: (_) => getIt<AuthBloc>(), child: const _LoginView());
}

class _LoginView extends StatelessWidget {
  const _LoginView();

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeCubit>().state == ThemeMode.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          // A login does not pass through the splash, so the role is handed
          // over here — before /home builds, which is where the shell reads it.
          getIt<RoleController>().update(state.user.inspectorRole);
          context.read<SyncBloc>().add(const SyncTriggered());
          context.go('/home');
        }
        if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: kError),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        color: isDark ? const Color(0xFF121212) : kBackground,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            actions: [
              const LanguageSwitcher(),
              const SizedBox(width: 8),
              _ThemeToggle(isDark: isDark),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            // Size the column to the room it actually has: on short Android
            // phones everything shrinks just enough to fit above the fold,
            // while taller screens keep the original proportions. The scroll
            // view stays as a safety net (long translations, big system font,
            // on-screen keyboard).
            child: LayoutBuilder(
              builder: (context, constraints) {
                final metrics = LoginMetrics.forHeight(
                  constraints.maxHeight,
                  isTablet: context.isTablet,
                );
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: context.contentMaxWidth,
                    ),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(metrics.pagePadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Image.asset(
                            'assets/images/nazorat_logo.png',
                            height: metrics.logoHeight,
                          ),
                          SizedBox(height: metrics.logoGap),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 300),
                            style:
                                (Theme.of(context).textTheme.headlineMedium ??
                                        const TextStyle())
                                    .copyWith(
                                      fontSize: metrics.titleSize,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                            child: Text(
                              'appTitle'.tr(),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          SizedBox(height: metrics.titleGap),
                          LoginForm(metrics: metrics),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.read<ThemeCubit>().toggle(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isDark ? kGreen.withAlpha(40) : kGreen.withAlpha(20),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark ? kGreenLight.withAlpha(120) : kGreen.withAlpha(100),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: !isDark ? kGreen : Colors.transparent,
                shape: BoxShape.circle,
                boxShadow: !isDark
                    ? [BoxShadow(color: kGreen.withAlpha(80), blurRadius: 6)]
                    : null,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.wb_sunny_rounded,
                  key: const ValueKey('sun'),
                  size: 16,
                  color: !isDark ? Colors.white : kTextSecondary,
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark ? kGreen : Colors.transparent,
                shape: BoxShape.circle,
                boxShadow: isDark
                    ? [BoxShadow(color: kGreen.withAlpha(80), blurRadius: 6)]
                    : null,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.nightlight_round,
                  key: const ValueKey('moon'),
                  size: 16,
                  color: isDark ? Colors.white : kTextSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
