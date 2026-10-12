import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/home/presentation/pages/main_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../constants/app_colors.dart';
import '../storage/secure_storage_service.dart';
import 'navigation_service.dart';

class AppRouter {
  AppRouter(this._storageService);

  final SecureStorageService _storageService;

  late final GoRouter router = GoRouter(
    navigatorKey: NavigationService.navigatorKey,
    initialLocation: '/splash',
    redirect: _redirect,
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashPage(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/home', builder: (context, state) => const MainPage()),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfilePage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
    ],
  );

  Future<String?> _redirect(BuildContext context, GoRouterState state) async {
    if (state.matchedLocation == '/splash') {
      final results = await Future.wait([
        _storageService.hasValidToken(),
        Future<void>.delayed(const Duration(milliseconds: 1500)),
      ]);
      FlutterNativeSplash.remove();
      final hasToken = results[0] as bool;
      return hasToken ? '/home' : '/login';
    }
    return null;
  }
}

class _SplashPage extends StatefulWidget {
  const _SplashPage();

  @override
  State<_SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<_SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1F0D) : kGreen;
    final textColor = kWhite;
    final subColor = kWhite.withAlpha(180);

    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Matches the native splash exactly (a white circle with the
                // mark inside), so the handover from the OS splash to Flutter
                // is seamless instead of a square logo popping onto a circle.
                Container(
                  width: 140,
                  height: 140,
                  decoration: const BoxDecoration(
                    color: kWhite,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(26),
                  child: Image.asset(
                    'assets/images/splash_icon.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'appTitle'.tr(),
                  style: TextStyle(
                    color: textColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'appTagline'.tr(),
                  style: TextStyle(
                    color: subColor,
                    fontSize: 14,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 64),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: subColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
