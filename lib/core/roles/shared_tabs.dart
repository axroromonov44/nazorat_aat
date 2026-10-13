import 'package:flutter/material.dart';

import '../../features/home/presentation/pages/home_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/weather/presentation/pages/weather_page.dart';
import 'role_module.dart';

/// Tabs every inspectorate gets. A module spreads these into its own list and
/// puts its inspectorate's screens around them.
///
/// Weather, the map and the profile are shared because they answer the same
/// question for every inspector: where am I, what is the sky doing, and who am
/// I signed in as.
const RoleTab weatherTab = RoleTab(
  labelKey: 'bottomNavWeather',
  icon: Icons.cloud_outlined,
  build: _buildWeather,
);

/// The map lives behind the centre button, hence [RoleTab.docked].
const RoleTab mapTab = RoleTab(
  labelKey: 'mapTitle',
  icon: Icons.map_outlined,
  build: _buildMap,
  docked: true,
);

const RoleTab settingsTab = RoleTab(
  labelKey: 'bottomNavSettings',
  icon: Icons.settings_outlined,
  build: _buildSettings,
);

// Top-level functions rather than closures: a function reference is a constant
// expression, so the tabs above stay const.
Widget _buildWeather(RoleShell shell) => const WeatherPage();

Widget _buildMap(RoleShell shell) => HomePage(isDrawing: shell.isDrawing);

Widget _buildSettings(RoleShell shell) => const ProfilePage();
