import 'dart:async';
import 'package:animated_bottom_navigation_bar/animated_bottom_navigation_bar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/roles/role_module.dart';
import '../../../../core/roles/role_registry.dart';
import '../../../../core/update/update_prompt.dart';
import '../../../../core/utils/haptic.dart';
import '../../../auth/domain/entities/inspector_role.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/bloc/profile_cubit.dart';

/// The shell every inspector lands in after login.
///
/// It knows nothing about any inspectorate: the destinations come from the
/// signed-in user's [RoleModule], so a role with different screens needs no
/// change here.
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _tabIndex = 0;
  final _visited = {0};
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
    // Only the role decides the shell, so a selector keeps it from rebuilding
    // every time another profile field arrives from /users/me.
    return BlocSelector<ProfileCubit, User?, InspectorRole?>(
      selector: (user) => user?.inspectorRole,
      builder: (context, role) => _buildShell(context, moduleFor(role)),
    );
  }

  Widget _buildShell(BuildContext context, RoleModule module) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shell = RoleShell(isDrawing: _isDrawingNotifier);
    final layout = ShellLayout(module.tabs);
    final index = layout.clamp(_tabIndex);
    final dockedTab = layout.dockedTab;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: index,
        children: [
          for (final (i, tab) in module.tabs.indexed)
            _visited.contains(i) ? tab.build(shell) : const SizedBox.shrink(),
        ],
      ),
      floatingActionButton: dockedTab == null
          ? null
          : ValueListenableBuilder<bool>(
              valueListenable: _isDrawingNotifier,
              builder: (context, isDrawing, child) =>
                  isDrawing ? const SizedBox.shrink() : child!,
              child: FloatingActionButton(
                onPressed: () => _selectTab(layout.dockedIndex),
                backgroundColor: kGreen,
                foregroundColor: Colors.white,
                tooltip: dockedTab.labelKey.tr(),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: Icon(dockedTab.icon),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: _isDrawingNotifier,
        builder: (context, isDrawing, child) =>
            isDrawing ? const SizedBox.shrink() : child!,
        child: AnimatedBottomNavigationBar.builder(
          itemCount: layout.barIndices.length,
          tabBuilder: (barIndex, isActive) {
            final tab = module.tabs[layout.barIndices[barIndex]];
            return _NavItem(
              icon: tab.icon,
              label: tab.labelKey.tr(),
              isActive: isActive,
              isDark: isDark,
            );
          },
          activeIndex: layout.barItemFor(index),
          gapLocation: dockedTab == null
              ? GapLocation.none
              : GapLocation.center,
          notchSmoothness: NotchSmoothness.defaultEdge,
          backgroundColor: isDark ? const Color(0xFF1E1E20) : Colors.white,
          onTap: (barIndex) => _selectTab(layout.barIndices[barIndex]),
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
