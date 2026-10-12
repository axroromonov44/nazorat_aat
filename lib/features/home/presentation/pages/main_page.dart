import 'dart:async';
import 'package:animated_bottom_navigation_bar/animated_bottom_navigation_bar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/update/update_prompt.dart';
import '../../../../core/utils/haptic.dart';
import '../../../auth/presentation/bloc/profile_cubit.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import '../../../weather/presentation/pages/weather_page.dart';
import 'home_page.dart';

const _weatherTab = 0;
const _mapTab = 1;
const _settingsTab = 2;

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _tabIndex = _weatherTab;
  final _visited = {_weatherTab};
  final _isDrawingNotifier = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    unawaited(context.read<ProfileCubit>().refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(promptForUpdateIfNeeded(context));
    });
  }

  @override
  void dispose() {
    _isDrawingNotifier.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index == _tabIndex) return;
    hapticSelect();
    setState(() {
      _tabIndex = index;
      _visited.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navActiveIndex = switch (_tabIndex) {
      _weatherTab => 0,
      _settingsTab => 1,
      _ => -1,
    };

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _visited.contains(_weatherTab)
              ? const WeatherPage()
              : const SizedBox.shrink(),
          _visited.contains(_mapTab)
              ? HomePage(isDrawing: _isDrawingNotifier)
              : const SizedBox.shrink(),
          _visited.contains(_settingsTab)
              ? const ProfilePage()
              : const SizedBox.shrink(),
        ],
      ),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _isDrawingNotifier,
        builder: (context, isDrawing, child) =>
            isDrawing ? const SizedBox.shrink() : child!,
        child: FloatingActionButton(
          onPressed: () => _selectTab(_mapTab),
          backgroundColor: kGreen,
          foregroundColor: Colors.white,
          tooltip: 'mapTitle'.tr(),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: const Icon(Icons.map_outlined),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: _isDrawingNotifier,
        builder: (context, isDrawing, child) =>
            isDrawing ? const SizedBox.shrink() : child!,
        child: AnimatedBottomNavigationBar.builder(
          itemCount: 2,
          tabBuilder: (index, isActive) => _NavItem(
            icon: index == 0 ? Icons.cloud_outlined : Icons.settings_outlined,
            label: (index == 0 ? 'bottomNavWeather' : 'bottomNavSettings').tr(),
            isActive: isActive,
            isDark: isDark,
          ),
          activeIndex: navActiveIndex,
          gapLocation: GapLocation.center,
          notchSmoothness: NotchSmoothness.defaultEdge,
          backgroundColor: isDark ? const Color(0xFF1E1E20) : Colors.white,
          onTap: (index) => _selectTab(index == 0 ? _weatherTab : _settingsTab),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? kGreen
        : (isDark ? Colors.white54 : Colors.grey.shade500);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
