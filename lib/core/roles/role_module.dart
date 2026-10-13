import 'package:flutter/widgets.dart';

/// Shell-owned state a tab may need while it builds.
///
/// The map hides the navigation bar and the floating button while a field is
/// being drawn, so it needs the notifier the shell itself listens to. Further
/// shell-level state belongs here rather than in every module's tab signature.
class RoleShell {
  const RoleShell({required this.isDrawing});

  final ValueNotifier<bool> isDrawing;
}

typedef RoleTabBuilder = Widget Function(RoleShell shell);

/// One destination in the shell's navigation.
class RoleTab {
  const RoleTab({
    required this.labelKey,
    required this.icon,
    required this.build,
    this.docked = false,
  });

  /// easy_localization key for the label; has to exist in uz, ru and en.
  final String labelKey;

  final IconData icon;

  final RoleTabBuilder build;

  /// Reached through the centre floating button instead of a bar item. The bar
  /// has one notch, so at most one tab per module is docked.
  final bool docked;
}

/// One inspectorate's slice of the app.
///
/// Everything role-specific is declared by the module instead of being
/// switched on inside the shell, so a new inspectorate means a new subclass
/// plus one line in `moduleFor` — the navigation code never changes again.
///
/// Routes, capabilities and role-scoped dependency registration join this
/// contract in later steps; for now a module only composes the navigation.
abstract class RoleModule {
  const RoleModule();

  /// Destinations in shell order.
  ///
  /// The first tab is what opens after login, so it must not be docked, and at
  /// least one tab has to stay undocked for the bar to have something to show.
  /// `test/role_module_test.dart` holds both invariants.
  List<RoleTab> get tabs;
}

/// How the shell lays a module's tabs out.
///
/// The bar and the [IndexedStack] do not share an index: the docked tab sits
/// behind the notch and has no bar item, so selecting bar item 1 can mean tab
/// 2. Keeping the arithmetic here makes it testable without a widget tree.
class ShellLayout {
  ShellLayout(this.tabs)
    : dockedIndex = tabs.indexWhere((tab) => tab.docked),
      barIndices = [
        for (final (i, tab) in tabs.indexed)
          if (!tab.docked) i,
      ];

  final List<RoleTab> tabs;

  /// Tab behind the centre button, or -1 when the module docks nothing.
  final int dockedIndex;

  /// Tab index of each bar item, in bar order.
  final List<int> barIndices;

  RoleTab? get dockedTab => dockedIndex == -1 ? null : tabs[dockedIndex];

  /// Bar item standing for [tabIndex], or -1 for the docked tab — nothing in
  /// the bar is highlighted while the map is open.
  int barItemFor(int tabIndex) => barIndices.indexOf(tabIndex);

  /// Keeps a remembered index inside this module's tabs. The role resolves
  /// asynchronously, so the module can change under a session that has already
  /// picked a tab, and a stale index would overflow the stack.
  int clamp(int tabIndex) => tabIndex < tabs.length ? tabIndex : 0;
}
